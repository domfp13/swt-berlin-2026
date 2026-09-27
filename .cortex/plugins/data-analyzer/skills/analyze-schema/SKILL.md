---
name: analyze-schema
description: "Profile every table in a Snowflake database or schema, infer primary keys and relationships, and write a human report (analysis.md) plus a machine-readable contract (analysis.json) for downstream plugins such as dbt pipeline generation. Triggers: analyze schema, profile tables, scan database, scan schema, table relationships, data analysis, analyze tables, describe relationships."
---

# Analyze Schema

Profile the tables in `$ARGUMENTS` (either `DB` or `DB.SCHEMA`), infer how they relate, and write the results to disk for humans and for other plugins.

If `$ARGUMENTS` is empty, ask the user for the target with `ask_user_question`. If only a database is given, analyze every schema in it except `INFORMATION_SCHEMA`, writing one output folder per schema.

## Rules

- **Read-only.** Only run `SELECT`, `SHOW`, `DESCRIBE`, and `INFORMATION_SCHEMA` queries. Never run DDL or DML.
- Always fully qualify and double-quote identifiers (`"DB"."SCHEMA"."TABLE"`).
- For tables with more than 1,000,000 rows, profile using `SAMPLE (1000000 ROWS)` and set `"sampled": true` for that table.
- Batch work: one profiling query per table, one validation query per candidate relationship. Do not query column by column.
- Keep chat output short. The detail belongs in the files.

## Workflow

### 1. Inventory

```sql
SELECT table_name, table_type, row_count, comment
FROM "<DB>".INFORMATION_SCHEMA.TABLES
WHERE table_schema = '<SCHEMA>'
ORDER BY table_name;

SELECT table_name, column_name, data_type, is_nullable, ordinal_position, comment
FROM "<DB>".INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = '<SCHEMA>'
ORDER BY table_name, ordinal_position;
```

Also run `SHOW PRIMARY KEYS IN SCHEMA "<DB>"."<SCHEMA>"` and `SHOW IMPORTED KEYS IN SCHEMA "<DB>"."<SCHEMA>"`. Declared constraints always win over inferred ones (mark them `"source": "declared"`).

### 2. Profile each table

Build one query per table. For every column, compute:

- `COUNT_IF(col IS NULL)` -> `null_pct`
- `COUNT(DISTINCT col)` -> `distinct_count`
- `MIN(col)` / `MAX(col)` for numeric, date, and timestamp columns

Then, for every column with `distinct_count <= 20` that is TEXT or BOOLEAN, fetch the distinct values (one `SELECT DISTINCT` per column is fine, or `ARRAY_AGG(DISTINCT col)` inside the profile query). These become `accepted_values`.

### 3. Classify

- **Primary key candidate**: a column with `null_pct = 0` and `distinct_count = row_count`. If several qualify, prefer the `*_ID` column whose stem appears in the table name after stripping prefixes (`RAW_`, `STG_`, `SRC_`) and singularizing (`CATEGORIES` -> `CATEGORY`, `ORDERS` -> `ORDER`). Example: `RAW_PRODUCT_CATEGORIES` -> `CATEGORY_ID`.
- **Freshness column**: the DATE/TIMESTAMP column that records when the row's event happened, with the latest `MAX`. Prefer names like `*_DATE`, `*_AT`, `*_TIMESTAMP` that describe the event itself (for example `ORDER_DATE` over `SIGNUP_DATE`). Skip columns whose `MAX` is in the future and planned or closing dates (`END_DATE`, `DUE_DATE`, `DELIVERED_DATE`, `RESOLVED_AT`). Record `days_since_latest`.
- **Role**, assigned after step 4:
  - `dimension`: describes an entity (customer, product, category, campaign) with descriptive attributes such as names, types, and tiers. A table that is referenced by others and has no outgoing relationships is a dimension. A table whose outgoing relationships all point to dimensions and that describes an entity is a snowflaked dimension (for example `RAW_PRODUCTS -> RAW_PRODUCT_CATEGORIES`).
  - `fact`: records an event or transaction (order, payment, shipment, ticket, click). It has an event date or timestamp, usually numeric measures, and at least one outgoing relationship. A fact can also be referenced by other facts (for example orders referenced by payments).
  - `standalone`: no relationships in either direction. Say in the report what the table probably is and why it cannot be joined.

### 4. Infer relationships

A column `A.X_ID` is a candidate foreign key when:
- it is not the primary key of `A`, and
- another table `B` has primary key `X_ID` (same name) with a compatible type.

Validate each candidate with one query:

```sql
SELECT
  COUNT(c."X_ID")                                            AS child_non_null,
  COUNT_IF(c."X_ID" IS NOT NULL AND p."X_ID" IS NULL)         AS orphan_count,
  COUNT(DISTINCT c."X_ID")                                   AS child_distinct,
  COUNT(*)                                                   AS child_rows
FROM "<DB>"."<SCHEMA>"."A" c
LEFT JOIN "<DB>"."<SCHEMA>"."B" p ON p."X_ID" = c."X_ID";
```

Derive:
- `match_pct = 100 * (child_non_null - orphan_count) / child_non_null`
- `cardinality`: `one-to-one` if `child_distinct = child_non_null`, otherwise `many-to-one`
- `optional`: true if the FK column has nulls
- `confidence`: `high` if `match_pct >= 99`, `medium` if `>= 90`, otherwise `low`

Keep `low` confidence relationships in the output but flag them in the report.

### 4b. Cross-table consistency

Orphan checks only prove each FK is valid on its own. Run a single batched query (scalar subqueries in one `SELECT`) for business rules that span tables, and add the findings to `quality_notes`. Typical checks:

- **Conflicting paths**: when a table has two FKs that can reach the same parent, check that both paths agree. Example: `TICKETS.CUSTOMER_ID` should equal the customer of `TICKETS.ORDER_ID`.
- **Child amounts vs. parent amounts**: refunds greater than the order amount, and payments that do not add up to the order amount.
- **Status vs. children**: refunds on orders that are not completed, and shipments for cancelled orders.
- **Status vs. timestamps**: closed or resolved rows with no resolution time, and open rows that have one.

Only check rules suggested by the columns that exist. Do not invent business rules the data cannot support.

### 5. Write outputs

Write both files to `<workspace-root>/.cortex/analysis/<DB>/<SCHEMA>/`, overwriting any previous run.

#### analysis.md (for humans)

1. Title, target, generation timestamp, and a one-paragraph summary.
2. A summary table: table, role, rows, PK, freshness column, days since latest.
3. A mermaid `erDiagram` with every table and relationship. Use `}o--||` for many-to-one and `|o--||` for one-to-one. Do not add styling.
4. A relationships table: from, to, cardinality, match %, orphans, confidence.
5. One section per table: grain ("one row per ..."), PK, a column table (name, type, null %, distinct, notes), and data-quality notes (nulls in likely-required columns, orphans, stale data, suspicious ranges such as end dates before start dates).
6. A "Suggested next steps" list, for example which tests a dbt project should add.

#### analysis.json (contract for other plugins)

This schema is a contract. Keep the field names and types stable so downstream plugins can rely on them. Use uppercase Snowflake identifiers.

```json
{
  "contract_version": "1.0",
  "generated_at": "2026-01-01T00:00:00Z",
  "database": "SWT_BERLIN_2026",
  "schema": "PUBLIC",
  "tables": [
    {
      "name": "RAW_ORDERS",
      "type": "BASE TABLE",
      "role": "fact",
      "row_count": 5000,
      "sampled": false,
      "grain": "one row per order",
      "primary_key": { "column": "ORDER_ID", "source": "inferred" },
      "freshness": { "column": "ORDER_DATE", "max_value": "2026-09-24", "days_since_latest": 3 },
      "columns": [
        {
          "name": "STATUS",
          "type": "TEXT",
          "nullable": true,
          "null_pct": 0.0,
          "distinct_count": 3,
          "min": null,
          "max": null,
          "accepted_values": ["CANCELLED", "COMPLETED", "PENDING"],
          "is_primary_key": false,
          "is_foreign_key": false
        }
      ],
      "quality_notes": []
    }
  ],
  "relationships": [
    {
      "from_table": "RAW_ORDERS",
      "from_column": "CUSTOMER_ID",
      "to_table": "RAW_CUSTOMERS",
      "to_column": "CUSTOMER_ID",
      "cardinality": "many-to-one",
      "optional": false,
      "match_pct": 100.0,
      "orphan_count": 0,
      "confidence": "high",
      "source": "inferred"
    }
  ]
}
```

Field rules:
- `accepted_values` is `null` when the column has more than 20 distinct values or is not TEXT/BOOLEAN. Sort the values.
- `min` / `max` are `null` for non-numeric, non-temporal columns. Dates are ISO 8601 strings.
- `primary_key` is `null` when no candidate exists.
- `freshness` is `null` when the table has no date or timestamp column.
- `quality_notes` is an array of short strings.

How downstream plugins should read the contract (for example, a dbt generator):
- `primary_key.column` -> `unique` + `not_null` tests
- `accepted_values` -> `accepted_values` test
- `relationships` with `confidence = high` -> `relationships` tests
- `freshness.column` -> source `loaded_at_field`
- `role` -> staging vs. dimension vs. fact model layout

After writing, validate the JSON parses: `python3 -m json.tool <path> > /dev/null`.

### 6. Report in chat

Reply with:
- tables analyzed, relationships found (by confidence), standalone tables
- the top 3 data-quality notes
- links to `analysis.md` and `analysis.json`
