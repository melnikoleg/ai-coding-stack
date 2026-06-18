#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")
WORKDIR=$(pwd)
HOME_BIN="$HOME/.local/bin"
mkdir -p "$HOME_BIN"
export PATH="$HOME_BIN:$PATH"

log() { printf '[1;34m[%s][0m %s
' "$SCRIPT_NAME" "$*"; }
warn() { printf '[1;33m[%s][0m %s
' "$SCRIPT_NAME" "$*" >&2; }
err() { printf '[1;31m[%s][0m %s
' "$SCRIPT_NAME" "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }; }
have() { command -v "$1" >/dev/null 2>&1; }

OS=$(uname -s)
ARCH=$(uname -m)
case "$OS" in
  Darwin) PLATFORM="macos" ;;
  Linux) PLATFORM="linux" ;;
  *) err "Unsupported OS: $OS"; exit 1 ;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH_NORM="x86_64" ;;
  arm64|aarch64) ARCH_NORM="arm64" ;;
  *) err "Unsupported architecture: $ARCH"; exit 1 ;;
esac

need curl
need tar
need python3

json_merge_mcp_server() {
  python3 - "$@" <<'PY2'
import json, os, sys
path, server_name, command, args_json = sys.argv[1:5]
args = json.loads(args_json)
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            data = {}
else:
    data = {}
if not isinstance(data, dict):
    data = {}
root = data.setdefault('mcpServers', {})
root[server_name] = {
    'command': command,
    'args': args,
    'transport': 'stdio'
}
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('
')
PY2
}

install_rtk() {
  if have rtk && rtk --version >/dev/null 2>&1; then
    log "RTK already installed: $(rtk --version 2>/dev/null || true)"
    return
  fi
  log "Installing RTK"
  curl -fsSL https://www.rtk-ai.app/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  if ! have rtk; then
    warn "RTK installer finished but 'rtk' is not on PATH. Expected in $HOME/.local/bin"
  fi
}

install_agora_code() {
  log "Installing agora-code via pipx/pip"
  if have pipx; then
    pipx install --force git+https://github.com/thebnbrkr/agora-code.git || pipx upgrade agora-code || true
  else
    python3 -m pip install --user --upgrade pip >/dev/null 2>&1 || true
    python3 -m pip install --user --upgrade git+https://github.com/thebnbrkr/agora-code.git
  fi
}

download_codebase_memory() {
  local api url tmp asset_pattern
  if have codebase-memory-mcp; then
    log "codebase-memory-mcp already installed"
    return
  fi
  log "Installing codebase-memory-mcp binary from latest GitHub release"
  api=$(curl -fsSL https://api.github.com/repos/DeusData/codebase-memory-mcp/releases/latest)
  case "$PLATFORM/$ARCH_NORM" in
    macos/x86_64) asset_pattern='darwin.*x86_64|macos.*x86_64|apple.*x86_64' ;;
    macos/arm64) asset_pattern='darwin.*arm64|darwin.*aarch64|macos.*arm64|apple.*arm64' ;;
    linux/x86_64) asset_pattern='linux.*x86_64|linux.*amd64' ;;
    linux/arm64) asset_pattern='linux.*arm64|linux.*aarch64' ;;
  esac
  url=$(printf '%s' "$api" | python3 -c "import json,re,sys; data=json.load(sys.stdin); rx=re.compile(r'$asset_pattern', re.I); [print(a.get('browser_download_url','')) for a in data.get('assets',[]) if rx.search(a.get('name',''))][:1]")
  url=$(printf '%s' "$url" | head -n 1)
  if [ -z "$url" ]; then
    warn "Could not auto-detect a release asset for $PLATFORM/$ARCH_NORM. Falling back to cargo if available."
    if have cargo; then
      cargo install codebase-memory-mcp
      return
    fi
    err "No suitable codebase-memory-mcp binary found automatically. Install manually from releases: https://github.com/DeusData/codebase-memory-mcp/releases"
    exit 1
  fi
  tmp=$(mktemp -d)
  curl -fL "$url" -o "$tmp/asset"
  if file "$tmp/asset" | grep -qi 'gzip compressed'; then
    tar -xzf "$tmp/asset" -C "$tmp"
  elif file "$tmp/asset" | grep -qi 'Zip archive'; then
    need unzip
    unzip -q "$tmp/asset" -d "$tmp"
  else
    chmod +x "$tmp/asset"
    cp "$tmp/asset" "$HOME_BIN/codebase-memory-mcp"
  fi
  if [ ! -f "$HOME_BIN/codebase-memory-mcp" ]; then
    find "$tmp" -type f \( -name 'codebase-memory-mcp' -o -name 'codebase-memory-mcp-*' \) | while read -r f; do
      if [ -x "$f" ]; then cp "$f" "$HOME_BIN/codebase-memory-mcp"; break; fi
    done
  fi
  chmod +x "$HOME_BIN/codebase-memory-mcp"
  rm -rf "$tmp"
}

setup_rtk_hooks() {
  if have rtk; then
    log "Initializing RTK global hooks"
    rtk init -g || warn "RTK global init returned non-zero; you may need to run it manually"
  fi
}

setup_agora_hooks() {
  local target_repo=${1:-$WORKDIR}
  if have agora-code; then
    log "Installing agora-code hooks in $target_repo"
    (cd "$target_repo" && agora-code install-hooks --claude-code) || warn "agora-code hook install failed for Claude Code"
    (cd "$target_repo" && agora-code install-hooks --cursor) || warn "agora-code hook install failed for Cursor"
  else
    warn "agora-code not found on PATH after installation"
  fi
}

setup_mcp_configs() {
  local bin_path
  bin_path=$(command -v codebase-memory-mcp || true)
  if [ -z "$bin_path" ]; then
    warn "codebase-memory-mcp not found on PATH; skipping MCP config"
    return
  fi

  local cursor_cfg claude_cfg copilot_cfg
  cursor_cfg="$HOME/.cursor/mcp.json"
  claude_cfg="$HOME/.config/claude/mcp.json"
  copilot_cfg="$HOME/.config/github-copilot/mcp.json"

  log "Writing MCP config for Cursor: $cursor_cfg"
  json_merge_mcp_server "$cursor_cfg" "codebase-memory" "$bin_path" '[]'

  log "Writing MCP config for Claude Code/Desktop-style clients: $claude_cfg"
  json_merge_mcp_server "$claude_cfg" "codebase-memory" "$bin_path" '[]'

  log "Writing MCP config for GitHub Copilot: $copilot_cfg"
  json_merge_mcp_server "$copilot_cfg" "codebase-memory" "$bin_path" '[]'
}

add_claude_plugin() {
  local repo=$1 plugin_ref=$2
  log "Adding marketplace: $repo"
  claude plugin marketplace add "$repo" || warn "marketplace add failed for $repo (may already be registered)"
  log "Installing plugin: $plugin_ref"
  claude plugin install "$plugin_ref" || warn "plugin install failed for $plugin_ref (may already be installed)"
}

install_claude_skills() {
  if ! have claude; then
    warn "Claude Code CLI ('claude') not found on PATH; skipping skill plugins (ponytail, caveman)."
    warn "After installing Claude Code, add them manually:"
    warn "  claude plugin marketplace add DietrichGebert/ponytail && claude plugin install ponytail@ponytail"
    warn "  claude plugin marketplace add JuliusBrussee/caveman && claude plugin install caveman@caveman"
    return
  fi
  log "Installing Claude Code skill plugins (ponytail, caveman)"
  add_claude_plugin "DietrichGebert/ponytail" "ponytail@ponytail"
  add_claude_plugin "JuliusBrussee/caveman" "caveman@caveman"
}

main() {
  log "Detected platform: $PLATFORM / $ARCH_NORM"
  install_rtk
  # install_agora_code  # temporarily disabled
  download_codebase_memory
  setup_rtk_hooks
  # setup_agora_hooks "$WORKDIR"  # temporarily disabled
  setup_mcp_configs
  install_claude_skills
  log "Done. Restart Claude Code, Cursor, and VS Code/Copilot after installation."
}

main "$@"
