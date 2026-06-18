# AI coding stack installer

This installer sets up:
- RTK
- agora-code
- codebase-memory-mcp
- MCP config stubs for Cursor, Claude, and GitHub Copilot
- Claude Code skill plugins:
  - [ponytail](https://github.com/DietrichGebert/ponytail) — "lazy senior dev" mode that pushes agents toward minimal, necessary code
  - [caveman](https://github.com/juliusbrussee/caveman) — compresses agent output to cut tokens

## Run

```bash
chmod +x ./install-ai-coding-stack.sh
./install-ai-coding-stack.sh
```

## Notes

- Run the script from the repository where you want `agora-code` hooks installed.
- On macOS/Linux, RTK global hook mode should be available.
- `codebase-memory-mcp` config is written as `mcpServers.codebase-memory` in JSON config files.
- You may still need to restart Cursor / Claude / VS Code after install.
- GitHub Copilot MCP support depends on your editor build and extension version.
- The `ponytail` and `caveman` skills are installed as Claude Code plugins via the `claude plugin` CLI, so the `claude` command must be on your `PATH`. If it isn't, the script prints the manual install commands and continues.
- After install, run `/reload-plugins` (or restart Claude Code) to activate the skills.
