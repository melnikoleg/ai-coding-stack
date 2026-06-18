#!/usr/bin/env bash
# Creates a small Python module with a TypeError bug (missing default in dict.get).
cat > tmp_eval/utils.py <<'PY'
def count_words(text):
    """Return a dict mapping each word to its frequency in text."""
    words = text.lower().split()
    counts = {}
    for word in words:
        counts[word] = counts.get(word) + 1  # BUG: get() returns None for new keys
    return counts
PY
