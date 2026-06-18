#!/usr/bin/env bash
# Creates an app module where only SOME functions call validate().
# This is the "navigation" task: codebase-memory should answer from the graph.
cat > tmp_eval/app.py <<'PY'
def validate(data):
    """Raise ValueError if data is empty."""
    if not data:
        raise ValueError("empty payload")
    return True


def create_user(data):
    validate(data)
    return {"user": data}


def update_user(uid, data):
    validate(data)
    return {"updated": uid, "data": data}


def delete_user(uid):
    return {"deleted": uid}


def list_users():
    return []


def import_batch(items):
    count = 0
    for item in items:
        validate(item)
        count += 1
    return count
PY
