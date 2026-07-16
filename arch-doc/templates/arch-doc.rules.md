<!-- managed by ai-coding-stack/arch-doc — edits are overwritten on reinstall -->

# arch-doc: keep ARCHITECTURE.md fresh

This repository maintains a generated `ARCHITECTURE.md` built from the
`codebase-memory` MCP server's knowledge graph. Its first line is a marker:
`<!-- arch-doc commit=<sha> state=<hash> -->`.

After you change source files in a session:

1. Call the `codebase-memory` MCP tool `index_repository` on this project,
   then find affected symbols: `detect_changes` with `base=<marker commit>`
   if your server has it, otherwise `git diff --name-only <marker commit>`
   plus `search_graph` with `file_pattern` per changed source file.
2. Update only the affected sections of `ARCHITECTURE.md`, following the full
   procedure in `.claude/commands/architecture.md` (same file works as a
   plain instruction document for any agent).
3. Replace the first line of `ARCHITECTURE.md` with the fresh marker printed
   by running `bash .claude/hooks/arch-doc-state.sh` (no arguments).

Never hand-write architecture facts — everything in the document must come
from the graph. If the `codebase-memory` tools are unavailable, leave the
document untouched and tell the user.
