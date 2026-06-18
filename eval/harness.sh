#!/usr/bin/env bash
# Usage:
#   ./harness.sh                      # all tasks × all conditions × REPEATS (default 3)
#   ./harness.sh 01_bugfix full 2     # single run: <task> <condition> <repeat-index>
#   REPEATS=5 ./harness.sh            # override repeat count
#   FORCE=1 ./harness.sh              # re-run even if result file already exists
#   SKIP_MCP=1 ./harness.sh          # skip MCP-dependent conditions
#
# Conditions (2×2 factorial: MCP on/off × skills+hooks on/off):
#   baseline    = --bare --strict-mcp-config          (nothing at all)
#   skills_hooks = --strict-mcp-config                 (RTK+ponytail+caveman, no MCP)
#   mcp_only    = --bare --mcp-config <file>           (codebase-memory only, no hooks/skills)
#   full        = (no flags)                           (full stack as installed)
#
# Contrasts:
#   full - baseline       → net effect of the whole stack
#   full - skills_hooks   → value of codebase-memory-mcp
#   full - mcp_only       → value of RTK + skills
#   skills_hooks - baseline → value of RTK + skills (without MCP)
#   mcp_only - baseline   → value of codebase-memory (without skills)

set -Eeuo pipefail

EVAL_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$EVAL_DIR/results"
TASKS_DIR="$EVAL_DIR/tasks"
MCP_CONFIG="$EVAL_DIR/mcp/codebase-memory.json"
REPEATS="${REPEATS:-3}"
FORCE="${FORCE:-0}"
SKIP_MCP="${SKIP_MCP:-0}"

log()  { printf '\033[1;34m[harness]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[harness]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[harness]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[harness]\033[0m %s\n' "$*" >&2; }

now_ms() { python3 -c "import time; print(int(time.time()*1000))"; }

# Flags per condition. __MCP__ is replaced with the actual config path at runtime.
declare -A COND_FLAGS=(
  [baseline]="--bare --strict-mcp-config"
  [skills_hooks]="--strict-mcp-config"
  [mcp_only]="--bare --mcp-config __MCP__"
  [full]=""
)
# 1 = condition requires mcp/codebase-memory.json to exist
declare -A COND_NEEDS_MCP=(
  [baseline]=0
  [skills_hooks]=0
  [mcp_only]=1
  [full]=1
)
CONDITION_ORDER=(baseline skills_hooks mcp_only full)
TASK_ORDER=(01_bugfix 02_navigation 03_feature 04_trap)

mkdir -p "$RESULTS_DIR"

run_once() {
  local task=$1 cond=$2 repeat=$3
  local out_file="$RESULTS_DIR/${task}__${cond}__${repeat}.json"

  if [[ -f "$out_file" ]] && [[ "$FORCE" != "1" ]]; then
    warn "SKIP (cached) $task/$cond/$repeat  — set FORCE=1 to rerun"
    return
  fi

  local needs_mcp="${COND_NEEDS_MCP[$cond]}"
  if [[ "$needs_mcp" == "1" ]]; then
    if [[ "$SKIP_MCP" == "1" ]] || [[ ! -f "$MCP_CONFIG" ]]; then
      warn "SKIP $task/$cond/$repeat — MCP config missing at $MCP_CONFIG"
      warn "  Copy mcp/codebase-memory.json.example → mcp/codebase-memory.json and set the binary path"
      return
    fi
  fi

  log "RUN  task=$task  cond=$cond  repeat=$repeat"

  # Clean and set up task-specific tmp files
  rm -rf "$EVAL_DIR/tmp_eval"
  mkdir -p "$EVAL_DIR/tmp_eval"
  if ! (cd "$EVAL_DIR" && bash "tasks/$task/setup.sh"); then
    fail "setup.sh failed for $task — skipping"
    return
  fi

  local prompt; prompt=$(cat "$TASKS_DIR/$task/prompt.txt")

  # Substitute MCP config path into flags; leave empty for 'full'
  # Word splitting of $flags is intentional here (each flag is a separate arg)
  local flags="${COND_FLAGS[$cond]/__MCP__/$MCP_CONFIG}"

  local raw_out; raw_out=$(mktemp)
  local t0; t0=$(now_ms)
  local claude_exit=0

  # shellcheck disable=SC2086
  (cd "$EVAL_DIR" && claude -p "$prompt" --output-format json $flags) \
    > "$raw_out" 2>&1 || claude_exit=$?

  local wall_ms=$(( $(now_ms) - t0 ))

  # Save response text so check.sh can inspect what the model said (task 02)
  python3 - "$raw_out" > "$EVAL_DIR/tmp_eval/_response.txt" 2>/dev/null <<'PY' || true
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get("result") or d.get("content") or "")
except Exception:
    pass
PY

  # Run acceptance test
  local check_exit=0
  (cd "$EVAL_DIR" && bash "tasks/$task/check.sh") > /dev/null 2>&1 || check_exit=$?

  # Merge raw JSON output with benchmark metadata into the result file
  python3 - "$raw_out" "$task" "$cond" "$repeat" \
      "$wall_ms" "$claude_exit" "$check_exit" "$out_file" <<'PY'
import json, sys

raw_path, task, cond, repeat, wall_ms, claude_exit, check_exit, out_path = sys.argv[1:9]

try:
    with open(raw_path) as f:
        data = json.load(f)
except Exception:
    with open(raw_path) as f:
        raw = f.read()
    data = {"error": "parse_failed", "raw_output": raw[:4000]}

data["_bench"] = {
    "task":         task,
    "condition":    cond,
    "repeat":       int(repeat),
    "wall_ms":      int(wall_ms),
    "check_passed": int(check_exit) == 0,
    "claude_exit":  int(claude_exit),
}
with open(out_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  rm -f "$raw_out"

  local status_str="PASS"
  [[ "$check_exit" != "0" ]] && status_str="FAIL"
  log "  → $status_str  wall=${wall_ms}ms  claude_exit=$claude_exit"
}

main() {
  command -v claude >/dev/null 2>&1 || { fail "'claude' not on PATH — install Claude Code first"; exit 1; }

  # Single-run mode: harness.sh <task> <condition> <repeat>
  if [[ $# -eq 3 ]]; then
    run_once "$1" "$2" "$3"
    python3 "$EVAL_DIR/parse_results.py" "$RESULTS_DIR"
    return
  fi
  [[ $# -ne 0 ]] && { fail "Usage: harness.sh [task condition repeat]"; exit 1; }

  log "Starting benchmark: ${#TASK_ORDER[@]} tasks × ${#CONDITION_ORDER[@]} conditions × $REPEATS repeats"
  [[ ! -f "$MCP_CONFIG" ]] && warn "MCP config not found — mcp_only and full conditions will be skipped"

  local total=$(( ${#TASK_ORDER[@]} * ${#CONDITION_ORDER[@]} * REPEATS ))
  local done_count=0

  for task in "${TASK_ORDER[@]}"; do
    for cond in "${CONDITION_ORDER[@]}"; do
      for (( r=1; r<=REPEATS; r++ )); do
        run_once "$task" "$cond" "$r"
        done_count=$(( done_count + 1 ))
        log "Progress: $done_count / $total"
      done
    done
  done

  ok "All runs complete. Generating report..."
  python3 "$EVAL_DIR/parse_results.py" "$RESULTS_DIR"
}

main "$@"
