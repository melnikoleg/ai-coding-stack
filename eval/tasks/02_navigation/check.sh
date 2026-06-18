#!/usr/bin/env bash
# Checks the model's free-text answer (captured in tmp_eval/_response.txt).
# Correct callers of validate(): create_user, update_user, import_batch.
# Non-callers: delete_user, list_users.
python3 - <<'PY'
import sys, re

try:
    resp = open("tmp_eval/_response.txt").read().lower()
except FileNotFoundError:
    print("no response captured")
    sys.exit(1)

required = ["create_user", "update_user", "import_batch"]
missing = [f for f in required if f not in resp]
if missing:
    print("missing required callers:", missing)
    sys.exit(1)

# False positives: these do NOT call validate. We allow them to appear only in a
# negating context ("does not call", "delete_user ... do not"); a naive mention
# as a caller is a failure. Check a window on BOTH sides of the occurrence.
NEG = re.compile(r"(not|n't|does not|doesn't|do not|don't|never|exclud|without|no\b)")
for f in ["delete_user", "list_users"]:
    for m in re.finditer(re.escape(f), resp):
        window = resp[max(0, m.start() - 40): m.end() + 40]
        if not NEG.search(window):
            # mentioned without a negation nearby -> likely listed as a caller
            print(f"false positive: {f} listed as a caller")
            sys.exit(1)

sys.exit(0)
PY
