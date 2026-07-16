# arch-doc — self-updating ARCHITECTURE.md

A standalone component of the AI coding stack: it gives any project a
generated `ARCHITECTURE.md` built from the
[codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)
knowledge graph, and keeps that document fresh automatically.

## What it installs (into the target project)

| File | Purpose |
| --- | --- |
| `.claude/commands/architecture.md` | `/architecture` slash command: full or incremental (re)generation of the doc from graph data (`get_architecture`, `search_graph`, `query_graph`, plus `detect_changes` on server versions that have it) |
| `.claude/hooks/arch-doc-stop-hook.sh` | Claude Code Stop hook: at the end of a session that edited source files, blocks once with instructions to update the stale doc incrementally |
| `.claude/hooks/arch-doc-state.sh` | Shared helper that fingerprints the current source state (used by the marker and the hook) |
| `.claude/settings.json` | Gets the Stop hook appended (existing content is preserved; a malformed file is never overwritten) |
| `.mcp.json` | Gets a project-scope `codebase-memory` server entry so the tools are always visible to Claude Code |
| `.cursor/rules/arch-doc.mdc`, `.windsurf/rules/arch-doc.md`, `.clinerules/arch-doc.md` | Rule files so Cursor/Windsurf/Cline agents follow the same update procedure (skip with `--no-rules`; existing files are left as-is) |

## Install

Prerequisites: `git`, `python3`, and ideally `codebase-memory-mcp` on PATH
(installed by the main `install-ai-coding-stack.sh`, or via
`npm install -g codebase-memory-mcp` / `pip install codebase-memory-mcp`;
without it the files are installed but inert).

```bash
# from a clone of this repo, inside your project:
/path/to/ai-coding-stack/arch-doc/install.sh

# or point it at the project:
./arch-doc/install.sh ~/work/my-project

# or straight from GitHub (the script fetches its templates itself):
curl -fsSL https://raw.githubusercontent.com/melnikoleg/ai-coding-stack/main/arch-doc/install.sh | bash
```

Then, in Claude Code inside the project, run `/architecture` once to create
the document. Re-running the installer upgrades the managed files in place
(they carry a "managed by ai-coding-stack/arch-doc" header).

## How self-updating works

The first line of the generated document is a marker:

```
<!-- arch-doc commit=<sha> state=<hash> -->
```

`state` is a hash of the diff (committed + working tree) of
architecture-relevant sources against the marker's base commit; markdown
files, `docs/`, `.claude/` and lockfiles are excluded, so doc-only churn
never counts as staleness.

At the end of each Claude Code session, the Stop hook — cheap, git-only, no
MCP calls — checks, in order: the session actually edited files (read-only
sessions are never interrupted); the doc exists and has a valid marker (the
hook maintains a doc, it never demands creating one); the current source
state differs from the marker. Only then does it block the stop once, telling
the agent to map the diff since the marker's commit to affected symbols
(`detect_changes` where available, else `git diff` + `search_graph`
`file_pattern`), patch only the affected sections, and write a fresh marker. Loop safety: `stop_hook_active`
guarantees at most one block per stop cycle, and any internal hook failure
falls through to "allow".

`/architecture` uses the same marker: with a valid one it updates
incrementally; without one (or with `/architecture full`, or after a
rebase/squash removed the base commit) it regenerates from scratch.

## Document contents

Overview, languages & packages, module map (Louvain clusters from the graph),
key entry points, HTTP routes, a mermaid module-dependency diagram, and
dead-code candidates — all derived from `codebase-memory` tools, capped for
large repos (25 diagram nodes, 30 dead-code rows, 15 entry points).

## Uninstall

```bash
rm -f .claude/commands/architecture.md \
      .claude/hooks/arch-doc-stop-hook.sh \
      .claude/hooks/arch-doc-state.sh \
      .cursor/rules/arch-doc.mdc .windsurf/rules/arch-doc.md .clinerules/arch-doc.md
```

Then remove the `arch-doc-stop-hook.sh` entry from `hooks.Stop` in
`.claude/settings.json` (and, if unwanted, the `codebase-memory` entry from
`.mcp.json`). `ARCHITECTURE.md` itself is yours to keep or delete.
