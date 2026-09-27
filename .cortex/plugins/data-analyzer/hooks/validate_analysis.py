#!/usr/bin/env python3
"""PostToolUse hook: validate .cortex/analysis/<DB>/<SCHEMA>/analysis.json against the contract.

Reads the hook event from stdin. Ignores every file except analysis.json under .cortex/analysis/.
On contract errors, returns decision=block so the agent sees the errors and rewrites the file.
"""
import json
import os
import re
import sys

PATH_PATTERN = re.compile(r"[\\/]\.cortex[\\/]analysis[\\/][^\\/]+[\\/][^\\/]+[\\/]analysis\.json$")
ROLES = {"fact", "dimension", "standalone"}
CARDINALITIES = {"many-to-one", "one-to-one"}
CONFIDENCES = {"high", "medium", "low"}
SOURCES = {"inferred", "declared"}
TOP_KEYS = {"contract_version", "generated_at", "database", "schema", "tables", "relationships"}
TABLE_KEYS = {"name", "type", "role", "row_count", "sampled", "grain", "primary_key", "freshness", "columns", "quality_notes"}
COLUMN_KEYS = {"name", "type", "nullable", "null_pct", "distinct_count", "min", "max", "accepted_values", "is_primary_key", "is_foreign_key"}
REL_KEYS = {"from_table", "from_column", "to_table", "to_column", "cardinality", "optional", "match_pct", "orphan_count", "confidence", "source"}


def validate(doc):
    errors = []
    missing = TOP_KEYS - doc.keys()
    if missing:
        return [f"missing top-level keys: {sorted(missing)}"]
    if doc["contract_version"] != "1.0":
        errors.append(f"contract_version must be '1.0', got {doc['contract_version']!r}")

    columns_by_table = {}
    for t in doc["tables"]:
        name = t.get("name", "<unnamed>")
        missing = TABLE_KEYS - t.keys()
        if missing:
            errors.append(f"{name}: missing keys {sorted(missing)}")
            continue
        if t["role"] not in ROLES:
            errors.append(f"{name}: role {t['role']!r} not in {sorted(ROLES)}")
        cols = {}
        for c in t["columns"]:
            cmissing = COLUMN_KEYS - c.keys()
            if cmissing:
                errors.append(f"{name}.{c.get('name', '?')}: missing keys {sorted(cmissing)}")
                continue
            cols[c["name"]] = c
            av = c["accepted_values"]
            if av is not None and (not isinstance(av, list) or len(av) > 20):
                errors.append(f"{name}.{c['name']}: accepted_values must be null or a list of at most 20 values")
        columns_by_table[name] = cols

        pk = t["primary_key"]
        if pk is not None:
            if pk.get("column") not in cols:
                errors.append(f"{name}: primary_key column {pk.get('column')!r} is not a column of the table")
            elif not cols[pk["column"]]["is_primary_key"]:
                errors.append(f"{name}.{pk['column']}: is the primary_key but is_primary_key is false")
            if pk.get("source") not in SOURCES:
                errors.append(f"{name}: primary_key.source must be one of {sorted(SOURCES)}")
        flagged_pks = [c for c, v in cols.items() if v["is_primary_key"]]
        if pk is None and flagged_pks:
            errors.append(f"{name}: primary_key is null but {flagged_pks} are flagged is_primary_key")

        fr = t["freshness"]
        if fr is not None and fr.get("column") not in cols:
            errors.append(f"{name}: freshness column {fr.get('column')!r} is not a column of the table")

    related = set()
    rel_fks = set()
    for r in doc["relationships"]:
        missing = REL_KEYS - r.keys()
        label = f"{r.get('from_table')}.{r.get('from_column')} -> {r.get('to_table')}.{r.get('to_column')}"
        if missing:
            errors.append(f"relationship {label}: missing keys {sorted(missing)}")
            continue
        for side in ("from", "to"):
            tbl, col = r[f"{side}_table"], r[f"{side}_column"]
            if tbl not in columns_by_table:
                errors.append(f"relationship {label}: unknown {side}_table {tbl}")
            elif col not in columns_by_table[tbl]:
                errors.append(f"relationship {label}: unknown {side}_column {col}")
        if r["cardinality"] not in CARDINALITIES:
            errors.append(f"relationship {label}: cardinality {r['cardinality']!r} not in {sorted(CARDINALITIES)}")
        if r["confidence"] not in CONFIDENCES:
            errors.append(f"relationship {label}: confidence {r['confidence']!r} not in {sorted(CONFIDENCES)}")
        if r["source"] not in SOURCES:
            errors.append(f"relationship {label}: source {r['source']!r} not in {sorted(SOURCES)}")
        related.update({r["from_table"], r["to_table"]})
        rel_fks.add((r["from_table"], r["from_column"]))

    flagged_fks = {(t, c) for t, cols in columns_by_table.items() for c, v in cols.items() if v["is_foreign_key"]}
    for t, c in sorted(flagged_fks - rel_fks):
        errors.append(f"{t}.{c}: is_foreign_key is true but no relationship uses it")
    for t, c in sorted(rel_fks - flagged_fks):
        if t in columns_by_table and c in columns_by_table[t]:
            errors.append(f"{t}.{c}: used as from_column in a relationship but is_foreign_key is false")

    for t in doc["tables"]:
        if t.get("role") == "standalone" and t.get("name") in related:
            errors.append(f"{t['name']}: role is standalone but it appears in a relationship")
        if t.get("role") in {"fact", "dimension"} and t.get("name") not in related:
            errors.append(f"{t['name']}: role is {t['role']} but it has no relationships (should be standalone)")

    return errors


def main():
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        return
    tool_input = event.get("tool_input") or {}
    path = tool_input.get("file_path") or ""
    if not PATH_PATTERN.search(path) or not os.path.isfile(path):
        return

    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
        errors = validate(doc)
    except json.JSONDecodeError as e:
        errors = [f"invalid JSON: {e}"]

    if errors:
        reason = f"analysis.json contract check FAILED ({len(errors)} errors) for {path}:\n- " + "\n- ".join(errors[:25])
        reason += "\nFix the file and write it again."
        print(json.dumps({"decision": "block", "reason": reason, "additionalContext": reason}))
    else:
        msg = f"analysis.json contract check passed: {len(doc['tables'])} tables, {len(doc['relationships'])} relationships."
        print(json.dumps({"systemMessage": msg, "additionalContext": msg}))


if __name__ == "__main__":
    main()
