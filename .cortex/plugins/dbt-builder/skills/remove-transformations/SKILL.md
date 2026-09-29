---
name: remove-transformations
description: "Remove the dbt transformations built by dbt-builder: drop every STG_* view/table, every MART_* table/view, the DBT PROJECT object, and the fallback stage in a schema, and delete the generated stg_*.sql / mart_*.sql model files from the local dbt/ folder. Keeps the RAW_ source tables and the dbt scaffold (dbt_project.yml, profiles.yml, _*.yml, tests/) so build-from-analysis can regenerate just the models. Idempotent: safe to run again. Triggers: remove dbt transformations, drop dbt models, tear down dbt, clean up stg and mart tables, clean dbt models, reset dbt pipeline, reset the demo, undo dbt build."
---

# Remove dbt Transformations

Undo `/dbt-builder:build-from-analysis` for `$ARGUMENTS` (`DB.SCHEMA`), both in Snowflake and in `<workspace-root>/dbt/`. Afterwards the repo is back to its scaffold: `dbt_project.yml`, `profiles.yml`, the `_*.yml` files, `tests/`, and the folders. build-from-analysis reuses that scaffold and regenerates only the models, so the two commands can alternate indefinitely.

The command is idempotent. Anything already gone is skipped, and a run with nothing left to remove says so and stops.

If `$ARGUMENTS` is empty, ask with `ask_user_question`.

## Rules

- In Snowflake, only objects whose name starts with `STG_` or `MART_`, plus the project object `<DB>.<SCHEMA>.<DB>_DBT` and the fallback stage `<DB>.<SCHEMA>.DBT_BUILDER_STAGE` (the names used by build-from-analysis), may be dropped.
- Drop each object **by its exact, fully qualified, quoted name**, one statement per object. Never use wildcards, `DROP SCHEMA`, `DROP DATABASE`, or `CREATE OR REPLACE`.
- Never touch `RAW_*` or any other object. The plugin's guard hook blocks destructive SQL on `RAW_*`. If it blocks a statement here, something is wrong: stop and report it; do not work around it.
- `DROP DBT PROJECT` does **not** drop the tables it built, which is why the models are dropped explicitly.
- Locally, delete only model SQL files named `stg_*.sql` or `mart_*.sql` under `dbt/models/`. Keep `dbt_project.yml`, `profiles.yml`, every `_*.yml`, `tests/`, and every directory, even one that ends up empty. They are the scaffold build-from-analysis reads; deleting them would make the next build start from scratch.

## Step 1: Inventory

```sql
SELECT table_name, table_type
FROM "<DB>".INFORMATION_SCHEMA.TABLES
WHERE table_schema = '<SCHEMA>'
  AND (table_name LIKE 'STG\\_%' ESCAPE '\\' OR table_name LIKE 'MART\\_%' ESCAPE '\\')
ORDER BY table_type, table_name;

SHOW DBT PROJECTS LIKE '<DB>_DBT' IN SCHEMA "<DB>"."<SCHEMA>";

SHOW STAGES LIKE 'DBT_BUILDER_STAGE' IN SCHEMA "<DB>"."<SCHEMA>";

SELECT COUNT(*) AS raw_tables
FROM "<DB>".INFORMATION_SCHEMA.TABLES
WHERE table_schema = '<SCHEMA>' AND table_name LIKE 'RAW\\_%' ESCAPE '\\';
```

Snowflake `LIKE` has no default escape character, so the explicit `ESCAPE '\\'` is required. It makes `_` literal, so `STG_%` does not match a name like `STGX...`. Without `ESCAPE`, the pattern matches nothing. Remember the `raw_tables` count for Step 4.

If the database is reported as missing or not authorized, the active connection probably points at a different account than the one the project was built on. Report the account (`SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME()`) and stop; don't treat it as already clean.

Locally, glob `<workspace-root>/dbt/models/**/stg_*.sql` and `<workspace-root>/dbt/models/**/mart_*.sql`. Also note which scaffold files exist (`dbt_project.yml`, `profiles.yml`, `models/**/_*.yml`, `tests/*.sql`) so Step 4 can confirm they survived.

If there are no Snowflake objects and no model files, say everything is already clean and stop.

## Step 2: Confirm (mandatory)

Show a short table in chat: counts of views and tables, the object names, the project object and stage if present, and the local model files that will be deleted. State that `RAW_` tables and the scaffold files are not affected. Then call `ask_user_question` with the options **Remove them** and **Cancel**. Do nothing on Cancel.

## Step 3: Drop and delete

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

Then delete the local model files from Step 1 in one command that names each file by its exact path:

```bash
rm -- "<workspace-root>/dbt/models/staging/stg_<entity>.sql" "<workspace-root>/dbt/models/marts/mart_<entity>.sql" ...
```

Don't use wildcards, `rm -r`, or `find -delete`: an explicit list can only remove what the user just confirmed.

If a statement or delete fails, report the error and the statement, continue with the rest, and list any failures at the end.

## Step 4: Verify and report

Re-run the Step 1 queries and globs. Confirm that there are 0 `STG_`/`MART_` objects, no project object or stage, 0 `stg_*.sql`/`mart_*.sql` files, that every scaffold file from Step 1 still exists, and that the `RAW_` table count is unchanged from Step 1.

Reply with the number of views, tables, project objects, and model files removed, the RAW_ count before and after, the scaffold files kept, and how to rebuild: `/dbt-builder:build-from-analysis <DB>.<SCHEMA>` (it reuses the scaffold and regenerates only the models).
