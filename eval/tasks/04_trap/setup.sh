#!/usr/bin/env bash
# The "trap": the real bug is inside _merge (writes to the wrong dict), so a
# signature-only / AST-summary view of get_timeout will not reveal it. The agent
# must read the actual body of _merge to fix it correctly.
cat > tmp_eval/config.py <<'PY'
DEFAULT_TIMEOUT = 30


def _merge(base, overrides):
    """Return base with overrides applied on top."""
    result = base.copy()
    for key, value in overrides.items():
        base[key] = value  # BUG: writes to `base`, not `result`
    return result


def get_timeout(overrides=None):
    """Return the timeout in seconds. `overrides` may supply a 'timeout' key
    that takes precedence over the default."""
    defaults = {"timeout": DEFAULT_TIMEOUT}
    if overrides is None:
        overrides = {}
    merged = _merge(defaults, overrides)
    return merged["timeout"]
PY
