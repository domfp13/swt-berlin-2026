---
name: remove-transformations
description: "Remove the dbt transformations built by dbt-builder: drop every STG_* view/table, every MART_* table/view, and the DBT PROJECT object in a schema, leaving the RAW_ source tables untouched. Triggers: remove dbt transformations, drop dbt models, tear down dbt, clean up stg and mart tables, reset dbt pipeline, undo dbt build."
---

# Remove dbt Transformations

Undo `/dbt-builder:build-from-analysis` for `$ARGUMENTS` (`DB.SCHEMA`). This drops the Snowflake objects only. Local `dbt/` files are left alone; git handles those.

If `$ARGUMENTS` is empty, ask with `ask_user_question`.

## Rules

- Only objects whose name starts with `STG_` or `MART_`, plus the project object `<DB>.<SCHEMA>.<DB>_DBT` (the name used by build-from-analysis), may be dropped.
- Drop each object **by its exact, fully qualified, quoted name**, one statement per object. Never use wildcards, `DROP SCHEMA`, `DROP DATABASE`, or `CREATE OR REPLACE`.
- Never touch `RAW_*` or any other object. The plugin's guard hook blocks destructive SQL on `RAW_*`. If it blocks a statement here, something is wrong: stop and report it; do not work around it.
- `DROP DBT PROJECT` does **not** drop the tables it built, which is why the models are dropped explicitly.

## Step 1: Inventory

```sql
SELECT table_name, table_type
FROM "<DB>".INFORMATION_SCHEMA.TABLES
WHERE table_schema = '<SCHEMA>'
  AND (table_name LIKE 'STG\\_%' ESCAPE '\\' OR table_name LIKE 'MART\\_%' ESCAPE '\\')
ORDER BY table_type, table_name;

SHOW DBT PROJECTS LIKE '<DB>_DBT' IN SCHEMA "<DB>"."<SCHEMA>";

SELECT COUNT(*) AS raw_tables
FROM "<DB>".INFORMATION_SCHEMA.TABLES
WHERE table_schema = '<SCHEMA>' AND table_name LIKE 'RAW\\_%' ESCAPE '\\';
```

Snowflake `LIKE` has no default escape character, so the explicit `ESCAPE '\\'` is required. It makes `_` literal, so `STG_%` does not match a name like `STGX...`. Without `ESCAPE`, the pattern matches nothing. Remember the `raw_tables` count for Step 4.

If nothing matches, say so and stop.

## Step 2: Confirm (mandatory)

Show a short table in chat: counts of views and tables, the object names, and the project object if present. State that `RAW_` tables are not affected. Then call `ask_user_question` with the options **Remove them** and **Cancel**. Do nothing on Cancel.

## Step 3: Drop

For each object from Step 1:

```sql
DROP VIEW IF EXISTS "<DB>"."<SCHEMA>"."<NAME>";    -- table_type = VIEW
DROP TABLE IF EXISTS "<DB>"."<SCHEMA>"."<NAME>";   -- table_type = BASE TABLE
```

Then, if the project exists:

```sql
DROP DBT PROJECT IF EXISTS "<DB>"."<SCHEMA>"."<DB>_DBT";
```

Also drop the SQL-fallback stage if build-from-analysis created it:

```sql
DROP STAGE IF EXISTS "<DB>"."<SCHEMA>"."DBT_BUILDER_STAGE";
```

If a statement fails, report the error and the statement, continue with the rest, and list any failures at the end.

## Step 4: Verify and report

Re-run the Step 1 queries. Confirm that there are 0 `STG_`/`MART_` objects, no project object, and that the `RAW_` table count is unchanged from Step 1.

Reply with the number of views, tables, and project objects dropped, the RAW_ count before and after, and how to rebuild: `/dbt-builder:build-from-analysis <DB>.<SCHEMA>`.
