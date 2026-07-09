#!/usr/bin/env bash
# managed by ai-coding-stack/arch-doc — edits are overwritten on reinstall
#
# Claude Code Stop hook: if this session edited source files and
# ARCHITECTURE.md is stale relative to its marker, block the stop once with
# instructions to update the doc incrementally. Any internal failure must
# allow the stop — never break the user's session.
set -u
trap 'exit 0' ERR

input=$(cat)

# Safe: every value is shell-quoted by python's shlex.quote.
eval "$(printf '%s' "$input" | python3 -c '
import json, shlex, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
print("stop_hook_active=%s" % shlex.quote(str(data.get("stop_hook_active", False)).lower()))
print("transcript_path=%s" % shlex.quote(str(data.get("transcript_path", ""))))
print("hook_cwd=%s" % shlex.quote(str(data.get("cwd", ""))))
')"

# Loop prevention: we already blocked once during this stop cycle.
if [ "$stop_hook_active" = "true" ]; then exit 0; fi

if [ -n "$hook_cwd" ]; then cd "$hook_cwd"; fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then exit 0; fi

# Opt-in: the hook only maintains an existing doc; creation is an explicit
# /architecture run.
doc="ARCHITECTURE.md"
if [ ! -f "$doc" ]; then exit 0; fi
marker=$(head -n 1 "$doc")
case "$marker" in
  '<!-- arch-doc commit='*' state='*' -->') ;;
  *) exit 0 ;;
esac
marker_commit=$(printf '%s' "$marker" | sed -n 's/.*commit=\([0-9a-f]*\).*/\1/p')
marker_state=$(printf '%s' "$marker" | sed -n 's/.*state=\([0-9a-f]*\).*/\1/p')
if [ -z "$marker_commit" ] || [ -z "$marker_state" ]; then exit 0; fi

# Only act when this session actually modified files; read-only sessions are
# never blocked even if the repo is stale from external edits.
if [ ! -f "$transcript_path" ]; then exit 0; fi
if ! grep -qE '"name"[[:space:]]*:[[:space:]]*"(Edit|Write|MultiEdit|NotebookEdit)"' "$transcript_path"; then exit 0; fi

state_helper=$(dirname "$0")/arch-doc-state.sh
if [ ! -x "$state_helper" ]; then exit 0; fi

if git cat-file -e "${marker_commit}^{commit}" 2>/dev/null; then
  current=$("$state_helper" "$marker_commit")
  current_state=${current##*state=}
  if [ "$current_state" = "$marker_state" ]; then exit 0; fi
  reason="ARCHITECTURE.md is out of date: source files changed since its base commit ${marker_commit}. Update it now, incrementally: (1) call the codebase-memory MCP tool index_repository for this project, then map changes to affected symbols — via detect_changes with base=${marker_commit} if that tool exists, otherwise via 'git diff --name-only ${marker_commit}' plus search_graph file_pattern per changed source file; (2) update only the affected sections of ARCHITECTURE.md following the procedure in .claude/commands/architecture.md (regenerate the mermaid diagram only if module imports changed); (3) replace the first line of ARCHITECTURE.md with the fresh marker printed by running: bash .claude/hooks/arch-doc-state.sh (no arguments). Do not modify any other files. If the codebase-memory tools are unavailable, tell the user instead of guessing."
else
  reason="ARCHITECTURE.md is out of date and its base commit ${marker_commit} no longer exists (likely rebase or squash). Do a full regeneration following .claude/commands/architecture.md, then replace the first line of ARCHITECTURE.md with the fresh marker printed by running: bash .claude/hooks/arch-doc-state.sh (no arguments). Do not modify any other files."
fi

python3 - "$reason" <<'PY'
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}))
PY
exit 0
