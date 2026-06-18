#!/usr/bin/env bash
# Verifies parse_csv was added and behaves as specified.
python3 - <<'PY'
import sys
sys.path.insert(0, "tmp_eval")
try:
    from parser import parse_csv
except ImportError:
    print("parse_csv not defined")
    sys.exit(1)

r = parse_csv("name,age\nalice,30\nbob,25")
expected = [{"name": "alice", "age": "30"}, {"name": "bob", "age": "25"}]
assert r == expected, f"got {r!r}"

# Header-only input -> empty list, must not crash.
r2 = parse_csv("name,age")
assert r2 == [], f"header-only should be [], got {r2!r}"
PY
