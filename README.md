# AI coding stack installer

This installer sets up a token-optimization stack for AI coding agents: it
trims the noisy parts of an agent's context (command output, code navigation,
generated code, chat output) so sessions stay cheaper and longer.

**Installed by default:**
- [RTK](https://github.com/rtk-ai/rtk) — compresses noisy CLI output (test/build/git) before it reaches the model; preserves errors, diffs, and stack traces
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) — MCP server that answers code-navigation queries from a graph index instead of re-reading files
- MCP config for Cursor, Claude Code, and VS Code / GitHub Copilot
- Claude Code skill plugins:
  - [ponytail](https://github.com/DietrichGebert/ponytail) — "lazy senior dev" mode that pushes agents toward minimal, necessary code
  - [caveman](https://github.com/juliusbrussee/caveman) — compresses agent output to cut tokens

**Currently disabled in the installer:**
- [agora-code](https://github.com/thebnbrkr/agora-code) — AST-summary file reads plus cross-session memory. Temporarily disabled because it is early-stage and overlaps `codebase-memory-mcp`. To enable it, uncomment `install_agora_code` and `setup_agora_hooks "$WORKDIR"` in `main()`.

## Run

```bash
chmod +x ./install-ai-coding-stack.sh
./install-ai-coding-stack.sh
```

Pin the `codebase-memory-mcp` release for reproducible installs (recommended):

```bash
CODEBASE_MEMORY_VERSION=v0.8.1 ./install-ai-coding-stack.sh
```

## Notes

- Run the script from the repository/workspace where you want the VS Code (Copilot) MCP config written — it is created at `<workspace>/.vscode/mcp.json`.
- The `codebase-memory-mcp` binary is downloaded from GitHub releases. When the release publishes a checksums file, the download's SHA-256 is verified and a mismatch aborts the install; otherwise a warning is printed.
- The MCP config is written as the `codebase-memory` server in:
  - Cursor: `~/.cursor/mcp.json` (under `mcpServers`)
  - Claude Code (user scope): `~/.claude.json` (under `mcpServers`)
  - VS Code / GitHub Copilot (workspace): `<workspace>/.vscode/mcp.json` (under `servers`)
- After install, verify the agent actually lists the `codebase-memory` tools before relying on them. The installer prints a warning summary if a core tool failed; `Done` is printed only on a clean install.
- On macOS/Linux, RTK global hook mode should be available.
- You may still need to restart Cursor / Claude Code / VS Code after install.
- GitHub Copilot MCP support depends on your editor build and extension version.
- The `ponytail` and `caveman` skills are installed as Claude Code plugins via the `claude plugin` CLI, so the `claude` command must be on your `PATH`. If it isn't, the script prints the manual install commands and continues.
- After install, run `/reload-plugins` (or restart Claude Code) to activate the skills.

## Security note

The RTK installer is executed via `curl | sh`, and the `codebase-memory-mcp`
binary is fetched from GitHub releases. Review
[`install.sh`](https://www.rtk-ai.app/install.sh) and pin
`CODEBASE_MEMORY_VERSION` before running in sensitive environments.
