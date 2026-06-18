#!/usr/bin/env bash
# Verifies count_words works correctly after the fix.
python3 - <<'PY'
import sys
sys.path.insert(0, "tmp_eval")
from utils import count_words

r = count_words("hello world hello")
assert r.get("hello") == 2, f"expected hello=2, got {r.get('hello')}"
assert r.get("world") == 1, f"expected world=1, got {r.get('world')}"

r2 = count_words("")
assert r2 == {}, f"expected empty dict for empty string, got {r2}"

r3 = count_words("a A a")
assert r3.get("a") == 3, f"expected a=3 (case-insensitive), got {r3}"
PY
