#!/usr/bin/env bash
# managed by ai-coding-stack/arch-doc — edits are overwritten on reinstall
#
# Prints the source-state fingerprint used by the ARCHITECTURE.md marker:
#   commit=<HEAD sha> state=<16-hex hash>
#
# The hash covers committed AND working-tree changes relative to <base>
# (default HEAD), restricted to architecture-relevant paths. Run with no
# argument when writing a fresh marker; the Stop hook re-runs it with the
# marker's commit as <base> to detect staleness.
set -Eeuo pipefail

base=${1:-HEAD}

# Changes to these paths must NOT mark ARCHITECTURE.md stale.
SRC_PATHSPEC=(
  '.'
  ':(exclude)ARCHITECTURE.md'
  ':(exclude)*.md'
  ':(exclude).claude'
  ':(exclude)docs'
  ':(exclude)*.lock'
  ':(exclude)package-lock.json'
)

commit=$(git rev-parse HEAD)
state=$(
  {
    git diff "$base" --name-only -- "${SRC_PATHSPEC[@]}"
    git diff "$base" -- "${SRC_PATHSPEC[@]}"
  } | git hash-object --stdin
)
printf 'commit=%s state=%s\n' "$commit" "${state:0:16}"
