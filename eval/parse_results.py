#!/usr/bin/env python3
"""
Aggregate eval results and print a summary report.

Usage:
    python3 parse_results.py [results_dir]   # default: ./results
    python3 parse_results.py --csv           # also write results.csv
"""
import json
import os
import sys
import statistics
from pathlib import Path
from collections import defaultdict

RESULTS_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else Path(__file__).parent / "results"
WRITE_CSV = "--csv" in sys.argv

CONDITION_ORDER = ["baseline", "skills_hooks", "mcp_only", "full"]
CONDITION_LABELS = {
    "baseline":    "baseline    (nothing)",
    "skills_hooks": "skills+hooks (no MCP)",
    "mcp_only":    "mcp_only    (no skills/hooks)",
    "full":        "full        (all tools)",
}

# Contrasts: (a, b) → "b minus a" — positive means b is WORSE (costs more)
CONTRASTS = [
    ("baseline",     "skills_hooks", "RTK + skills effect (no MCP)"),
    ("baseline",     "mcp_only",     "codebase-memory effect (no skills)"),
    ("baseline",     "full",         "full stack net effect"),
    ("skills_hooks", "full",         "codebase-memory on top of skills"),
    ("mcp_only",     "full",         "skills on top of MCP"),
]


def extract_usage(data: dict) -> dict:
    u = data.get("usage") or {}
    # Handle both snake_case and camelCase field names
    def get(keys, default=0):
        for k in keys:
            v = u.get(k)
            if v is not None:
                return int(v)
        return default

    inp  = get(["input_tokens",            "inputTokens"])
    out  = get(["output_tokens",           "outputTokens"])
    cr   = get(["cache_read_input_tokens", "cacheReadInputTokens"])
    cc   = get(["cache_creation_input_tokens", "cacheCreationInputTokens"])

    # model_usage may carry per-model breakdown
    for mu in (data.get("modelUsage") or {}).values():
        if isinstance(mu, dict):
            inp += get(["input_tokens",  "inputTokens"],  0)
            out += get(["output_tokens", "outputTokens"], 0)

    return {"input": inp, "output": out, "cache_read": cr, "cache_create": cc,
            "total": inp + out + cr + cc}


def load_results(results_dir: Path) -> list[dict]:
    rows = []
    for p in sorted(results_dir.glob("*.json")):
        if p.name.startswith("."):
            continue
        try:
            data = json.loads(p.read_text())
        except json.JSONDecodeError:
            print(f"[warn] could not parse {p.name}", file=sys.stderr)
            continue

        bench = data.get("_bench", {})
        if not bench:
            continue

        usage = extract_usage(data)
        rows.append({
            "file":         p.name,
            "task":         bench.get("task", "?"),
            "condition":    bench.get("condition", "?"),
            "repeat":       bench.get("repeat", 0),
            "wall_ms":      bench.get("wall_ms", 0),
            "check_passed": bench.get("check_passed", False),
            "claude_exit":  bench.get("claude_exit", -1),
            "cost_usd":     data.get("total_cost_usd") or 0.0,
            "turns":        data.get("num_turns") or 0,
            "tokens_in":    usage["input"],
            "tokens_out":   usage["output"],
            "cache_read":   usage["cache_read"],
            "cache_create": usage["cache_create"],
            "tokens_total": usage["total"],
            "error":        "error" in data,
        })
    return rows


def median(values):
    return statistics.median(values) if values else float("nan")


def pct_change(a, b):
    if a == 0:
        return float("nan")
    return (b - a) / a * 100


def summarize(rows: list[dict]) -> dict:
    by_cond = defaultdict(list)
    for r in rows:
        by_cond[r["condition"]].append(r)
    return by_cond


def fmt(v, fmt_str):
    try:
        return format(v, fmt_str)
    except (ValueError, TypeError):
        return "n/a"


def print_report(rows: list[dict]):
    if not rows:
        print("No result files found in", RESULTS_DIR)
        return

    tasks = sorted({r["task"] for r in rows})
    conditions = [c for c in CONDITION_ORDER if c in {r["condition"] for r in rows}]

    print("\n" + "=" * 72)
    print("  EVAL REPORT")
    print(f"  {len(rows)} runs  |  {len(tasks)} tasks  |  {len(conditions)} conditions")
    print("=" * 72)

    by_cond = summarize(rows)

    # ── Per-condition summary ──────────────────────────────────────────────
    print("\n── PER-CONDITION SUMMARY (medians across all tasks × repeats) ──────\n")
    col = "{:<28} {:>6} {:>9} {:>8} {:>9} {:>7} {:>6}"
    print(col.format("condition", "pass%", "cost_usd", "turns", "tok_in", "tok_out", "wall_s"))
    print("-" * 72)
    for cond in conditions:
        rs = by_cond[cond]
        pass_pct    = sum(1 for r in rs if r["check_passed"]) / len(rs) * 100
        cost        = median([r["cost_usd"]     for r in rs])
        turns       = median([r["turns"]        for r in rs])
        tok_in      = median([r["tokens_in"]    for r in rs])
        tok_out     = median([r["tokens_out"]   for r in rs])
        wall_s      = median([r["wall_ms"]      for r in rs]) / 1000
        label       = CONDITION_LABELS.get(cond, cond)
        print(col.format(
            label[:28],
            fmt(pass_pct, ".0f") + "%",
            fmt(cost,  ".5f"),
            fmt(turns, ".1f"),
            fmt(tok_in,  ".0f"),
            fmt(tok_out, ".0f"),
            fmt(wall_s,  ".1f"),
        ))

    # ── Per-task breakdown ─────────────────────────────────────────────────
    print("\n── PER-TASK PASS RATE ───────────────────────────────────────────────\n")
    task_col = "{:<20}" + " {:>12}" * len(conditions)
    print(task_col.format("task", *[c[:12] for c in conditions]))
    print("-" * (20 + 13 * len(conditions)))
    for task in tasks:
        cells = []
        for cond in conditions:
            rs = [r for r in rows if r["task"] == task and r["condition"] == cond]
            if not rs:
                cells.append("   —")
            else:
                n_pass = sum(1 for r in rs if r["check_passed"])
                cells.append(f"{n_pass}/{len(rs)}")
        print(task_col.format(task[:20], *cells))

    # ── Contrasts ─────────────────────────────────────────────────────────
    print("\n── CONTRASTS (negative = tool SAVES cost/tokens vs reference) ───────\n")
    avail = set(conditions)
    contrast_col = "{:<40} {:>10} {:>10} {:>10}"
    print(contrast_col.format("contrast", "Δcost%", "Δtok_in%", "Δwall%"))
    print("-" * 72)
    for ref_cond, tgt_cond, label in CONTRASTS:
        if ref_cond not in avail or tgt_cond not in avail:
            continue
        ref = by_cond[ref_cond]
        tgt = by_cond[tgt_cond]
        m_cost_ref  = median([r["cost_usd"]    for r in ref])
        m_cost_tgt  = median([r["cost_usd"]    for r in tgt])
        m_tin_ref   = median([r["tokens_in"]   for r in ref])
        m_tin_tgt   = median([r["tokens_in"]   for r in tgt])
        m_wall_ref  = median([r["wall_ms"]      for r in ref])
        m_wall_tgt  = median([r["wall_ms"]      for r in tgt])
        print(contrast_col.format(
            label[:40],
            fmt(pct_change(m_cost_ref, m_cost_tgt),  "+.1f") + "%",
            fmt(pct_change(m_tin_ref,  m_tin_tgt),   "+.1f") + "%",
            fmt(pct_change(m_wall_ref, m_wall_tgt),  "+.1f") + "%",
        ))

    # ── Error summary ──────────────────────────────────────────────────────
    errors = [r for r in rows if r["error"] or r["claude_exit"] != 0]
    if errors:
        print(f"\n── ERRORS ({len(errors)} runs had non-zero exit or parse failure) ───────\n")
        for r in errors:
            print(f"  {r['file']:<50}  exit={r['claude_exit']}  error={r['error']}")

    print("\n" + "=" * 72 + "\n")


def write_csv(rows: list[dict], path: Path):
    import csv
    if not rows:
        return
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"CSV written to {path}")


if __name__ == "__main__":
    rows = load_results(RESULTS_DIR)
    print_report(rows)
    if WRITE_CSV:
        write_csv(rows, RESULTS_DIR.parent / "results.csv")
