#!/usr/bin/env python3
"""PreToolUse hook: block destructive SQL against RAW_ source objects.

Raw sources, staging views, and marts all share one schema, so a mistaken DROP could take out
the source data. This hook inspects SQL sent through snowflake_sql_execute (tool_input.sql) or
bash (tool_input.command, e.g. `snow sql -q ...`) and exits 2 to block the call when it would:
  - DROP / TRUNCATE / DELETE FROM an object whose name starts with RAW_
  - ALTER TABLE RAW_... DROP / RENAME / SWAP
  - DROP SCHEMA ...PUBLIC or DROP DATABASE <protected database>
CREATE OR REPLACE is deliberately allowed so the setup scripts can reseed the raw data.
"""
import json
import re
import sys

PROTECTED_PREFIX = "RAW_"
PROTECTED_SCHEMAS = {"PUBLIC"}
PROTECTED_DATABASES = {"SWT_BERLIN_2026"}

NAME = r'((?:"[^"]+"|[A-Za-z0-9_$]+)(?:\.(?:"[^"]+"|[A-Za-z0-9_$]+)){0,2})'
PATTERNS = [
    ("drop", re.compile(
        r"\bDROP\s+(?:(?:TRANSIENT|TEMPORARY|DYNAMIC|EXTERNAL|ICEBERG|MATERIALIZED|SECURE|HYBRID)\s+)*"
        r"(TABLE|VIEW|SCHEMA|DATABASE|STAGE|STREAM|TASK)\s+(?:IF\s+EXISTS\s+)?" + NAME, re.I)),
    ("truncate", re.compile(r"\bTRUNCATE\s+(?:TABLE\s+)?(?:IF\s+EXISTS\s+)?" + NAME, re.I)),
    ("delete", re.compile(r"\bDELETE\s+FROM\s+" + NAME, re.I)),
    ("alter", re.compile(r"\bALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?" + NAME + r"\s+(DROP|RENAME|SWAP)\b", re.I)),
]


def strip_comments(sql):
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    return re.sub(r"--[^\n]*", " ", sql)


def last_part(name):
    return name.split(".")[-1].strip('"').upper()


def violations(text):
    found = []
    for kind, pattern in PATTERNS:
        for m in pattern.finditer(text):
            if kind == "drop":
                obj_type, name = m.group(1).upper(), m.group(2)
                target = last_part(name)
                if obj_type == "SCHEMA" and target in PROTECTED_SCHEMAS:
                    found.append(f"DROP SCHEMA {name}: the schema holds the RAW_ source tables")
                elif obj_type == "DATABASE" and target in PROTECTED_DATABASES:
                    found.append(f"DROP DATABASE {name}: protected demo database")
                elif target.startswith(PROTECTED_PREFIX):
                    found.append(f"DROP {obj_type} {name}: RAW_ objects are source data")
            else:
                name = m.group(1)
                if last_part(name).startswith(PROTECTED_PREFIX):
                    found.append(f"{kind.upper()} on {name}: RAW_ objects are source data")
    return found


def main():
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    tool_input = event.get("tool_input") or {}
    text = tool_input.get("sql") or tool_input.get("command") or ""
    if not text:
        return 0
    found = violations(strip_comments(text))
    if not found:
        return 0
    print("Blocked by dbt-builder RAW_ guard:\n- " + "\n- ".join(found)
          + "\nOnly STG_* and MART_* objects may be dropped. Drop objects by exact name, never the raw sources.",
          file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
