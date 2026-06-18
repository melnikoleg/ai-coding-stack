# Eval harness: does the stack actually help?

A small A/B benchmark to measure whether the AI coding stack (RTK +
codebase-memory-mcp + ponytail + caveman) reduces **cost/tokens** without
hurting **task quality**. It measures both axes — savings are meaningless if
quality drops.

## Design

A **2×2 factorial** over the two things the stack changes (MCP server on/off ×
skills+hooks on/off), so you can attribute effects, not just see a yes/no:

| condition      | codebase-memory (MCP) | RTK + ponytail + caveman | how it's run |
|----------------|:---:|:---:|---|
| `baseline`     | ✗ | ✗ | `claude --bare --strict-mcp-config` |
| `skills_hooks` | ✗ | ✓ | `claude --strict-mcp-config` |
| `mcp_only`     | ✓ | ✗ | `claude --bare --mcp-config <file>` |
| `full`         | ✓ | ✓ | `claude` (stack as installed) |

Each condition runs every task **N times** (default 3) because agent runs are
non-deterministic — the report uses **medians**, not single runs.

### Tasks (`tasks/<name>/`)

Each task is `prompt.txt` + `setup.sh` (writes scratch code into `tmp_eval/`) +
`check.sh` (objective pass/fail). They cover the cases where the stack should
help and one where it can backfire:

- **01_bugfix** — fix a `TypeError`. Baseline sanity check.
- **02_navigation** — "which functions call `validate`?" Free-text answer graded
  against the known-correct set. This is where `codebase-memory` should shine.
- **03_feature** — add a `parse_csv` function matching existing style.
- **04_trap** — the real bug lives in a helper's body, invisible to
  signature/AST summaries. Detects quality regressions from lossy compression.

## Run

```bash
# 1. Point the harness at your codebase-memory binary
cp mcp/codebase-memory.json.example mcp/codebase-memory.json
$EDITOR mcp/codebase-memory.json          # set the absolute "command" path

# 2. Run everything (4 tasks × 4 conditions × 3 repeats)
./harness.sh

# Variations
REPEATS=5 ./harness.sh                     # more repeats = tighter medians
SKIP_MCP=1 ./harness.sh                    # only baseline + skills_hooks
FORCE=1 ./harness.sh                       # ignore cached results, rerun all
./harness.sh 04_trap full 1                # one specific run

# Re-print the report / export CSV without re-running
python3 parse_results.py --csv
```

## Output

Per run: `results/<task>__<condition>__<repeat>.json` — the raw
`claude --output-format json` payload plus a `_bench` block (`wall_ms`,
`check_passed`, exit codes).

The report shows per-condition medians (pass%, cost, turns, tokens, wall),
per-task pass rates, and **contrasts** (e.g. `full − baseline` as a %). Negative
Δ means the tool *saved* cost/tokens.

## Reading the result

The stack "helps" for a tool only if, on **your** representative tasks, it gives
a meaningful cost/token reduction (rule of thumb **≥15–20%** to beat noise)
**with no drop in pass rate** and no rise in turns (re-reads). Watch for:

- **Net effect on short tasks** — skill instructions + MCP tool schemas are a
  fixed per-turn input-token tax; on small tasks it can exceed the savings.
- **Caching** — toggling tools changes the system prompt and invalidates the
  prompt cache; compare `cache_read` vs `cache_create`, run repeats back-to-back.
- **04_trap pass rate** — if `mcp_only`/`full` regress here vs `baseline`,
  lossy code summaries are hurting correctness.
- **Self-reported numbers** (RTK %, `/caveman-stats`, ponytail LOC) — use only
  for attribution; the report's end-to-end `total_cost_usd`/tokens are truth.

## Caveats

- Exact token field names in the JSON output should be confirmed on a live run;
  `parse_results.py` already handles both snake_case and camelCase.
- `--bare` disables hooks/skills/plugins/MCP/auto-memory/CLAUDE.md; per-feature
  ablation uses `--strict-mcp-config` and `--mcp-config`.
- Memory value is cross-session — extend with a two-session scenario (use
  `--resume`) if you want to measure persistence specifically.
