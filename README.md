# AI coding stack installer

This installer sets up:
- RTK
- agora-code
- codebase-memory-mcp
- MCP config stubs for Cursor, Claude, and GitHub Copilot

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
