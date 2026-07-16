# AI coding stack installer

This installer sets up:
- RTK
- agora-code
- codebase-memory-mcp
- MCP config stubs for Cursor, Claude, and GitHub Copilot
- Editor skills (Claude Code + Cursor / Windsurf / Cline / Copilot):
  - [ponytail](https://github.com/DietrichGebert/ponytail) — "lazy senior dev" mode that pushes agents toward minimal, necessary code
  - [caveman](https://github.com/juliusbrussee/caveman) — compresses agent output to cut tokens

## Run

```bash
chmod +x ./install-ai-coding-stack.sh
./install-ai-coding-stack.sh
```

## arch-doc: self-updating ARCHITECTURE.md

A standalone add-on (not part of the main installer) that gives a project a
generated `ARCHITECTURE.md` built from the `codebase-memory` knowledge graph,
plus a `/architecture` Claude Code command and a Stop hook that keeps the
document fresh after sessions that change code. Install it per project:

```bash
./arch-doc/install.sh ~/work/my-project
```

See [arch-doc/README.md](arch-doc/README.md) for details.

## Notes

- Run the script from the repository where you want `agora-code` hooks installed.
- On macOS/Linux, RTK global hook mode should be available.
- `codebase-memory-mcp` config is written as `mcpServers.codebase-memory` in JSON config files.
- You may still need to restart Cursor / Claude / VS Code after install.
- GitHub Copilot MCP support depends on your editor build and extension version.
- `caveman` is installed via its official installer (`--with-init`), which auto-detects every supported editor (Claude Code, Cursor, Windsurf, Copilot, ...): it installs the plugin for plugin-capable agents and writes per-repo rule files for IDE editors into the repo you run the script from. Needs Node >=18; without it the script falls back to Claude Code only via `claude plugin`.
- `ponytail` is installed for Claude Code via `claude plugin`. It has no multi-editor installer, so for Cursor / Windsurf / Cline its rule files are copied into the repo you run the script from (`.cursor/rules/`, `.windsurf/rules/`, `.clinerules/`), and `.github/copilot-instructions.md` is added for Copilot if absent (an existing one is left untouched). Needs `git`.
- After install, run `/reload-plugins` (or restart your editor) to activate the skills.
