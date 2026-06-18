#!/usr/bin/env bash
# Verifies overrides are respected after the fix.
python3 - <<'PY'
import sys
sys.path.insert(0, "tmp_eval")
from config import get_timeout

assert get_timeout({"timeout": 60}) == 60, "override 60 not respected"
assert get_timeout({"timeout": 5}) == 5, "override 5 not respected"
assert get_timeout() == 30, "default broke"
assert get_timeout({}) == 30, "empty overrides should fall back to default"
PY
