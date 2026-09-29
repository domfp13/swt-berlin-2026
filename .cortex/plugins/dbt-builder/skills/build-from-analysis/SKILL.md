---
name: build-from-analysis
description: "Generate a dbt project of stg_* and mart_* models from a data-analyzer analysis.json contract, then deploy and build it natively in Snowflake using the dbt-projects-on-snowflake skill. Reuses an existing dbt/ folder (dbt_project.yml, profiles.yml, _*.yml, tests/, models) and generates only the missing files, so it is safe to re-run and pairs with remove-transformations. Triggers: build dbt from analysis, generate dbt pipeline, create dbt transformations, dbt from analysis.json, build stg and mart models, scaffold dbt project from schema analysis, rebuild dbt models, redeploy dbt project, rerun dbt build."
---

# Build dbt Transformations from Analysis

Turn the analysis contract for `$ARGUMENTS` (`DB.SCHEMA`) into a dbt project, deploy it into Snowflake, and run `dbt build`.

`dbt/` may already contain a scaffold. That can be a committed `dbt_project.yml`, `profiles.yml`, `_*.yml` files, and `tests/`, left after `/dbt-builder:remove-transformations` deleted the model SQL. It can also be a complete earlier build. Keep what is there and generate only what is missing. Running this again redeploys and rebuilds the same project, so the two commands can alternate.

This skill **writes the models**. Deploying, executing, and dropping are delegated to the bundled **`dbt-projects-on-snowflake`** skill. Load it with the `skill` tool and read its `deploy/SKILL.md`, `execute/SKILL.md`, and `references/profiles-yml.md` before running any `snow dbt` command. Do not reinvent that syntax.

## Inputs

- `$ARGUMENTS`: `DB.SCHEMA`. If empty, ask with `ask_user_question`.
- Contract: `<workspace-root>/.cortex/analysis/<DB>/<SCHEMA>/analysis.json` (`contract_version` must be `1.0`).
  - If the file is missing, **stop** and tell the user to run `/data-analyzer:analyze-schema <DB>.<SCHEMA>` first. Do not profile the schema yourself.

## Fixed conventions

| Setting | Value |
|---|---|
| dbt project folder | `<workspace-root>/dbt/`. Existing files are kept; only missing files are generated (Step 2). |
| dbt project name | lowercase `<DB>` with non-alphanumerics as `_` (e.g. `swt_berlin_2026`) |
| DBT PROJECT object | `<DB>.<SCHEMA>.<DB>_DBT` with `_2026`-style suffixes kept (e.g. `SWT_BERLIN_2026.PUBLIC.SWT_BERLIN_2026_DBT`) |
| Target schema | `<SCHEMA>`. Every model lands in the same schema as the sources. Never set `+schema`. |
| Model prefixes | `stg_` (views) and `mart_` (tables) **only**. Any other prefix is an error. |
| Role / warehouse | `SYSADMIN` / the current warehouse (`SELECT CURRENT_WAREHOUSE()`) |
| Snowflake CLI connection | the `snow connection list` entry whose `account` matches the active account (`SELECT CURRENT_ORGANIZATION_NAME() \|\| '-' \|\| CURRENT_ACCOUNT_NAME()`). Always pass `-c <name>`; the default connection may point elsewhere. |
| Packages | none. Use only built-in tests (`unique`, `not_null`, `accepted_values`, `relationships`) so no `dbt deps` or external access integration is needed. |
| dbt version | pin `1.11.11` (check with `SELECT SYSTEM$SUPPORTED_DBT_VERSIONS()`; use the newest dbt Core 1.x listed) |

## Step 1: Read the contract

Load `analysis.json`. Build three lists:
- `facts`, `dimensions`, `standalone` from `tables[].role`
- `rels`: relationships with `confidence = "high"` (ignore medium and low for tests; mention them in the report)
- For each dimension, whether it is **snowflaked**: it has an outgoing relationship to another dimension (e.g. `RAW_PRODUCTS -> RAW_PRODUCT_CATEGORIES`).

Entity name = table name with the `RAW_`, `SRC_`, or `STG_` prefix removed, lowercased (`RAW_ORDERS` -> `orders`).

## Step 2: Take stock of `dbt/`

Existing files may have been reviewed or hand-tuned. Regenerating them would throw that work away, and every run would produce a different diff. Glob `<workspace-root>/dbt/` and decide per file:

| File | Exists | Missing |
|---|---|---|
| `dbt_project.yml`, `profiles.yml` | Keep. Check `name` and `profile` equal `<project_name>`, and `profiles.yml` targets `<DB>` / `<SCHEMA>` with no forbidden fields. On a mismatch, show it and ask before changing anything. | Generate |
| `models/staging/_sources.yml`, `models/staging/_stg_models.yml`, `models/marts/_mart_models.yml` | Keep. They are the spec for the SQL: collect every model, column, rename, and `is_*` flag they declare. For a contract table they lack, append an entry; don't rewrite existing ones. | Generate |
| `tests/assert_*.sql` | Keep. Collect the models and columns each one references; the SQL must provide them. | Generate |
| `models/staging/stg_*.sql`, `models/marts/mart_*.sql` | Keep. | Generate |

If a YAML entry has no contract table, report it and leave it alone. If nothing is missing, skip Step 3; the run just redeploys and rebuilds.

Before generating, tell the user in one line which files you are reusing and which you will generate.

## Step 3: Generate the missing files

Generate only the files Step 2 marked missing. When YAML for a model already exists, follow it: output exactly the columns, renames, and flags it documents, in contract column order. The templates below fill in everything else. Keep SQL lowercase and readable; one CTE per input.

### `dbt/dbt_project.yml`

```yaml
name: '<project_name>'
version: '1.0.0'
config-version: 2
profile: '<project_name>'

model-paths: ["models"]
test-paths: ["tests"]

models:
  <project_name>:
    staging:
      +materialized: view
      +tags: ["staging"]
    marts:
      +materialized: table
      +tags: ["marts"]
```

### `dbt/profiles.yml`

Follow `dbt-projects-on-snowflake/references/profiles-yml.md`: it must live inside `dbt/`, and must **not** contain `password`, `authenticator`, `private_key_path`, or `token`.

```yaml
<project_name>:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: ""
      user: ""
      role: SYSADMIN
      database: <DB>
      warehouse: <WAREHOUSE>
      schema: <SCHEMA>
      threads: 4
```

### `dbt/models/staging/_sources.yml`

One source named `raw` with `database: <DB>` and `schema: <SCHEMA>`, and one table entry per contract table (`name: <entity>`, `identifier: <TABLE_NAME>`). Copy the contract's `grain` into `description`. Add freshness **only for `fact` tables** that have `freshness` set; dimensions and standalone tables change slowly, and freshness on them would error for no reason:

```yaml
config:
  loaded_at_field: "cast(<freshness.column> as timestamp_ntz)"   # TIMESTAMP_LTZ: convert_timezone('UTC', col)::timestamp_ntz
  freshness:
    warn_after: {count: 2, period: day}
    error_after: {count: 14, period: day}
```

Do not put tests on sources; test the staging models instead.

### `dbt/models/staging/stg_<entity>.sql` (one per contract table, standalone included)

```sql
with source as (
    select * from {{ source('raw', '<entity>') }}
)

select
    <every column, explicit, in contract order>
from source
```

Column rules:
- Keep column names as they are (lowercase in SQL). Rename only when the name is ambiguous across marts (for example `RAW_ORDERS.AMOUNT` -> `order_amount`, and bare `STATUS` -> `<entity_singular>_status`) and record the rename in the column description.
- `TIMESTAMP_LTZ` -> `convert_timezone('UTC', col)::timestamp_ntz`
- A `DATE` column whose name ends in `_AT` -> `col::timestamp_ntz`
- For every `quality_notes` entry that describes a row-level rule on this table's own columns, add a boolean flag column named `is_<condition>`, for example `end_date < start_date as is_end_before_start`, `cost_price > list_price as is_negative_margin`, `resolved_at < created_at as is_resolved_before_created`. Skip notes that need another table; those become singular tests.
  - If an operand can be NULL, wrap the flag in `coalesce(..., false)`. A NULL flag silently drops rows from `where not is_x` filters.
  - Compare against "now" as `convert_timezone('UTC', current_timestamp())::timestamp_ntz` (or `::date`), never a bare `current_date()`, so the result doesn't depend on the session timezone.
- Add `(status = 'COMPLETED') as is_completed`-style booleans only when the contract has `accepted_values` that clearly define a terminal state.

### `dbt/models/staging/_stg_models.yml`

For every `stg_` model, set a `description` from `grain` and the columns you output. Then add these tests:
- `primary_key.column`: `unique` and `not_null`
- each column with non-null `accepted_values`: `accepted_values`. For BOOLEAN columns use `values: [true, false]` with `quote: false`, plus `not_null`. **Skip** it when `distinct_count = row_count` or a quality note calls the column a unique label (for example `CAMPAIGN_NAME`, `CATEGORY_NAME`): the list only exists because the table is small, and the test would break on the first new row.
- an FK column on a `one-to-one` relationship also gets `unique`
- each relationship in `rels`: on the child stg model's FK column,
  ```yaml
  - relationships:
      arguments:
        to: ref('stg_<parent_entity>')
        field: <to_column>
      config:
        where: "<from_column> is not null"   # only when optional = true
  ```

Use the `arguments:` / `config:` nesting shown above; it works on both the current and the newer dbt test syntax.

### `dbt/models/marts/mart_<entity>.sql`

- **Dimension**: `mart_<entity>` selects from its `stg_` model. If it is snowflaked, left join the parent dimension's `stg_` model and add the parent's descriptive columns (names, types, tiers). Do not create a separate mart for a parent that has been folded in.
- **Fact**: `mart_<entity>` selects every column from its `stg_` model, then left joins each **many-to-one** parent dimension and adds that dimension's descriptive TEXT columns (for example `region` and `segment` from customers). If the fact points to another fact (for example payments -> orders), join the parent fact's `stg_` model only to inherit the dimension keys it has (such as `customer_id`), and never fan out.
- **Standalone**: no mart. Note it in the report.
- Add derived measures only when they are unambiguous from the columns, for example `datediff(day, shipped_date, delivered_date) as delivery_days` or `list_price - cost_price as margin_amount`. If a quality flag marks the inputs of a derived measure as invalid, return NULL for those rows, e.g. `iff(is_resolved_before_created, null, datediff(hour, created_at, resolved_at))`, so the bad rows don't distort averages.

Every mart must keep exactly the grain (row count) of its fact or dimension `stg_` model. Joins must be to the parent's primary key only.

### `dbt/models/marts/_mart_models.yml`

For every mart: `description` (grain), `config: {meta: {role: fact|dimension, source_table: <TABLE>}}`, and `unique` + `not_null` on the primary key. Relationship tests live in staging, so don't duplicate them here.

### `dbt/tests/assert_<rule>.sql` (singular tests for quality notes)

Create one per quality note that is a checkable rule, **including cross-table rules** (for example "ticket customer differs from the order's customer"). Each test returns the offending rows and starts with:

```sql
{{ config(severity='warn') }}
```

Known quality issues must **warn, not fail**. The build should succeed and show them.

## Step 4: Validate before deploying

- Every file in `models/` is named `stg_*.sql` or `mart_*.sql` (plus `_*.yml`). If not, fix the name.
- Every `ref()` points to a model that exists, and every `source()` points to a declared table.
- Every column documented in `_stg_models.yml` / `_mart_models.yml`, and every column a singular test uses, is produced by its model. This matters most when the YAML was reused: a missing column only fails at build time.
- `profiles.yml` has no forbidden fields.

## Step 5: Deploy and build (delegate to `dbt-projects-on-snowflake`)

Load `dbt-projects-on-snowflake` and follow its **DEPLOY** and **EXECUTE** sub-skills. First check the CLI can log in with `snow connection test -c <connection>`. An expired OAuth token otherwise fails midway through the deploy. If the test fails, use the SQL-only fallback below instead.

```bash
snow dbt deploy <DB>_DBT --source <workspace-root>/dbt --database <DB> --schema <SCHEMA> --dbt-version <dbt_version> -c <connection>
snow dbt execute -c <connection> --database <DB> --schema <SCHEMA> <DB>_DBT build
```

`snow dbt deploy` creates the object or updates the existing one, so re-running it is safe.

**SQL-only fallback** (use it if `snow` cannot authenticate or is unavailable; everything runs through the active connection):

```sql
CREATE STAGE IF NOT EXISTS <DB>.<SCHEMA>.DBT_BUILDER_STAGE;
REMOVE @<DB>.<SCHEMA>.DBT_BUILDER_STAGE;   -- start empty so the stage mirrors dbt/ exactly (no stale files from earlier runs)
-- PUT file://<workspace-root>/dbt/<dir>/* @<DB>.<SCHEMA>.DBT_BUILDER_STAGE/<dir>/ AUTO_COMPRESS = FALSE OVERWRITE = TRUE
--   once for the root files (dbt_project.yml, profiles.yml), then models/staging, models/marts, and tests.
--   LIST the stage afterwards and check it holds exactly the local files.
SHOW DBT PROJECTS LIKE '<DB>_DBT' IN SCHEMA <DB>.<SCHEMA>;
-- project missing:
CREATE DBT PROJECT <DB>.<SCHEMA>.<DB>_DBT FROM '@<DB>.<SCHEMA>.DBT_BUILDER_STAGE' DBT_VERSION = '<dbt_version>';
-- project exists and SHOW reports default_version = LIVE (single mutable live version):
ALTER DBT PROJECT <DB>.<SCHEMA>.<DB>_DBT DEPLOY FROM '@<DB>.<SCHEMA>.DBT_BUILDER_STAGE';
-- project exists with numbered versions (accounts without the live version):
ALTER DBT PROJECT <DB>.<SCHEMA>.<DB>_DBT ADD VERSION FROM '@<DB>.<SCHEMA>.DBT_BUILDER_STAGE';
EXECUTE DBT PROJECT <DB>.<SCHEMA>.<DB>_DBT ARGS='build';
```

If the build fails: read the error, fix the generated files, redeploy, and rebuild. If the cause is in a reused file, show the fix and ask before editing it. Do not weaken or delete a generic test to get green unless the contract itself is wrong (and say so).

After a green build, run the `dbt-verify` subagent (read-only: no local dbt-core, Snowflake SELECTs only) and fix anything it reports as a correctness issue before reporting success.

## Step 6: Verify and report

```sql
SELECT table_name, table_type, row_count
FROM <DB>.INFORMATION_SCHEMA.TABLES
WHERE table_schema = '<SCHEMA>' AND (table_name LIKE 'STG\\_%' ESCAPE '\\' OR table_name LIKE 'MART\\_%' ESCAPE '\\')
ORDER BY table_name;
```

Check that each mart's row count equals its source table's `row_count` in the contract.

Reply briefly with:
- files reused vs generated
- models built (count of stg and mart), and tests passed / warned / failed
- the warnings (these are the known data-quality issues)
- anything skipped (standalone tables, low-confidence relationships)
- how to undo: `/dbt-builder:remove-transformations <DB>.<SCHEMA>` (drops the objects and the generated model files, keeps the scaffold)
