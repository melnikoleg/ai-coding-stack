#!/usr/bin/env bash
# arch-doc installer: sets up a self-updating ARCHITECTURE.md in a target
# project, powered by the codebase-memory MCP server.
#
# Usage: ./install.sh [--no-rules] [target-project-dir]
# Run it from (or point it at) the project that should get the doc.
set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")
STACK_REPO="https://github.com/melnikoleg/ai-coding-stack.git"

log() { printf '\033[1;34m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '\033[1;33m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2; }
err() { printf '\033[1;31m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }; }
have() { command -v "$1" >/dev/null 2>&1; }

WITH_RULES=1
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --no-rules) WITH_RULES=0 ;;
    -h|--help) printf 'Usage: %s [--no-rules] [target-project-dir]\n' "$SCRIPT_NAME"; exit 0 ;;
    *) TARGET="$arg" ;;
  esac
done
TARGET=${TARGET:-$(pwd)}

need git
need python3

if ! git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  err "$TARGET is not inside a git repository. arch-doc needs git to track staleness."
  exit 1
fi

if ! have codebase-memory-mcp; then
  warn "codebase-memory-mcp is not on PATH. Installed files are inert without it;"
  warn "  install the stack first: ./install-ai-coding-stack.sh (or see README)."
fi
have claude || warn "claude CLI not found; the /architecture command and Stop hook only work in Claude Code."

# Locate templates next to this script; fall back to a shallow clone when the
# script was piped (curl | bash) and has no directory of its own.
TMP_CLONE=""
cleanup() { if [ -n "$TMP_CLONE" ]; then rm -rf "$TMP_CLONE"; fi; }
trap cleanup EXIT
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)
if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/templates" ]; then
  TEMPLATES="$SCRIPT_DIR/templates"
else
  log "templates/ not found next to the script; fetching $STACK_REPO"
  TMP_CLONE=$(mktemp -d)
  git clone --depth 1 "$STACK_REPO" "$TMP_CLONE/stack" >/dev/null 2>&1 \
    || { err "Could not clone $STACK_REPO to locate templates"; exit 1; }
  TEMPLATES="$TMP_CLONE/stack/arch-doc/templates"
fi
[ -d "$TEMPLATES" ] || { err "Template directory not found: $TEMPLATES"; exit 1; }

install_files() {
  log "Installing Claude Code command and hooks into $TARGET/.claude/"
  install -D -m 0644 "$TEMPLATES/architecture.md" "$TARGET/.claude/commands/architecture.md"
  install -D -m 0755 "$TEMPLATES/arch-doc-stop-hook.sh" "$TARGET/.claude/hooks/arch-doc-stop-hook.sh"
  install -D -m 0755 "$TEMPLATES/arch-doc-state.sh" "$TARGET/.claude/hooks/arch-doc-state.sh"
}

# Append the Stop hook to .claude/settings.json without touching anything
# else. Unlike the main installer's MCP merge, a malformed settings.json is
# never clobbered — hand-edited hook configs are too costly to lose.
merge_settings_hook() {
  local settings="$TARGET/.claude/settings.json" rc=0
  log "Registering Stop hook in $settings"
  python3 - "$settings" <<'PY' || rc=$?
import json, os, sys
path = sys.argv[1]
HOOK_MARK = "arch-doc-stop-hook.sh"
entry = {
    "hooks": [
        {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/arch-doc-stop-hook.sh",
        }
    ]
}
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()
    if raw.strip():
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            sys.stderr.write(
                "refusing to touch malformed %s (%s); add the Stop hook manually\n" % (path, e)
            )
            sys.exit(3)
    else:
        data = {}
else:
    data = {}
if not isinstance(data, dict):
    sys.stderr.write("refusing to touch %s: top level is not an object\n" % path)
    sys.exit(3)
stop = data.setdefault("hooks", {}).setdefault("Stop", [])
for item in stop:
    for hook in item.get("hooks", []) if isinstance(item, dict) else []:
        if HOOK_MARK in str(hook.get("command", "")):
            print("already registered")
            sys.exit(0)
stop.append(entry)
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("registered")
PY
  if [ "$rc" -eq 3 ]; then
    warn "Stop hook NOT registered; fix $settings and re-run, or add it manually:"
    warn '  {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/arch-doc-stop-hook.sh"}]}]}}'
  elif [ "$rc" -ne 0 ]; then
    warn "settings.json merge failed (exit $rc)"
  fi
}

# Project-scope MCP registration so the /architecture command is guaranteed to
# see the codebase-memory tools regardless of global config paths.
merge_project_mcp() {
  local bin_path mcp_json="$TARGET/.mcp.json" rc=0
  bin_path=$(command -v codebase-memory-mcp || true)
  if [ -z "$bin_path" ]; then
    warn "Skipping $mcp_json merge (codebase-memory-mcp not on PATH)"
    return 0
  fi
  log "Registering codebase-memory in $mcp_json"
  python3 - "$mcp_json" "$bin_path" <<'PY' || rc=$?
import json, os, sys
path, command = sys.argv[1:3]
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()
    if raw.strip():
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            sys.stderr.write(
                "refusing to touch malformed %s (%s); register codebase-memory manually\n" % (path, e)
            )
            sys.exit(3)
    else:
        data = {}
else:
    data = {}
if not isinstance(data, dict):
    sys.stderr.write("refusing to touch %s: top level is not an object\n" % path)
    sys.exit(3)
data.setdefault("mcpServers", {})["codebase-memory"] = {
    "command": command,
    "args": [],
    "transport": "stdio",
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
  if [ "$rc" -eq 3 ]; then
    warn "codebase-memory NOT registered in $mcp_json; fix the file and re-run"
  fi
  return 0
}

# Rule files so Cursor / Windsurf / Cline agents also keep the doc fresh
# (they cannot run the Stop hook, but can follow the same procedure).
copy_editor_rules() {
  local dest
  for dest in ".cursor/rules/arch-doc.mdc" ".windsurf/rules/arch-doc.md" ".clinerules/arch-doc.md"; do
    if [ -e "$TARGET/$dest" ]; then
      warn "$dest exists; left as-is"
    else
      install -D -m 0644 "$TEMPLATES/arch-doc.rules.md" "$TARGET/$dest"
      log "arch-doc rules -> $dest"
    fi
  done
}

install_files
merge_settings_hook
merge_project_mcp
if [ "$WITH_RULES" -eq 1 ]; then
  copy_editor_rules
else
  log "Skipping editor rule files (--no-rules)"
fi

log "Done. In Claude Code, run /architecture once to create ARCHITECTURE.md;"
log "the Stop hook keeps it fresh automatically after sessions that change code."
log "Commit or gitignore the new .claude/ files per your team's policy."
