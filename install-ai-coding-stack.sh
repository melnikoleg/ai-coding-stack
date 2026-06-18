#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")
WORKDIR=$(pwd)
HOME_BIN="$HOME/.local/bin"
mkdir -p "$HOME_BIN"
export PATH="$HOME_BIN:$PATH"

log() { printf '\033[1;34m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '\033[1;33m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2; }
err() { printf '\033[1;31m[%s]\033[0m %s\n' "$SCRIPT_NAME" "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }; }
have() { command -v "$1" >/dev/null 2>&1; }
sha256_of() {
  if have sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  elif have shasum; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf ''
  fi
}

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

# Merge a single MCP server entry into a JSON config without clobbering existing
# content. root_key is the top-level object the client expects: "mcpServers" for
# Cursor and Claude Code, "servers" for VS Code / GitHub Copilot.
json_merge_mcp_server() {
  python3 - "$@" <<'PY2'
import json, os, sys
path, root_key, server_name, command, args_json = sys.argv[1:6]
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
root = data.setdefault(root_key, {})
root[server_name] = {
    'type': 'stdio',
    'command': command,
    'args': args,
}
parent = os.path.dirname(path)
if parent:
    os.makedirs(parent, exist_ok=True)
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write('\n')
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
  local api url checksum_url tmp asset_pattern releases_url version asset_name expected actual
  if have codebase-memory-mcp; then
    log "codebase-memory-mcp already installed"
    return
  fi
  # Pin a release with CODEBASE_MEMORY_VERSION=<tag> for reproducible installs.
  version="${CODEBASE_MEMORY_VERSION:-latest}"
  if [ "$version" = "latest" ]; then
    releases_url="https://api.github.com/repos/DeusData/codebase-memory-mcp/releases/latest"
    log "Installing codebase-memory-mcp from latest GitHub release (pin with CODEBASE_MEMORY_VERSION=<tag>)"
  else
    releases_url="https://api.github.com/repos/DeusData/codebase-memory-mcp/releases/tags/$version"
    log "Installing codebase-memory-mcp $version from GitHub release"
  fi
  api=$(curl -fsSL "$releases_url")
  case "$PLATFORM/$ARCH_NORM" in
    macos/x86_64) asset_pattern='darwin.*x86_64|macos.*x86_64|apple.*x86_64' ;;
    macos/arm64) asset_pattern='darwin.*arm64|darwin.*aarch64|macos.*arm64|apple.*arm64' ;;
    linux/x86_64) asset_pattern='linux.*x86_64|linux.*amd64' ;;
    linux/arm64) asset_pattern='linux.*arm64|linux.*aarch64' ;;
  esac
  url=$(printf '%s' "$api" | python3 -c "import json,re,sys; data=json.load(sys.stdin); rx=re.compile(r'$asset_pattern', re.I); print(next((a.get('browser_download_url','') for a in data.get('assets',[]) if rx.search(a.get('name','')) and not re.search(r'(checksums?|sha256|\.sig|\.asc)', a.get('name',''), re.I)), ''))")
  checksum_url=$(printf '%s' "$api" | python3 -c "import json,re,sys; data=json.load(sys.stdin); print(next((a.get('browser_download_url','') for a in data.get('assets',[]) if re.search(r'(checksums?|sha256)', a.get('name',''), re.I) and not re.search(r'(\.sig|\.asc)$', a.get('name',''), re.I)), ''))")
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
  asset_name=$(basename "$url")
  # Verify the download against the release checksums file when one is published.
  if [ -n "$checksum_url" ]; then
    log "Verifying SHA-256 for $asset_name"
    if curl -fL "$checksum_url" -o "$tmp/checksums.txt"; then
      expected=$(python3 -c "import sys
name = sys.argv[1]
want = ''
for line in open(sys.argv[2], encoding='utf-8', errors='replace'):
    parts = line.split()
    if len(parts) >= 2 and parts[-1].lstrip('*').endswith(name):
        want = parts[0]
        break
print(want)" "$asset_name" "$tmp/checksums.txt")
      actual=$(sha256_of "$tmp/asset")
      if [ -z "$actual" ]; then
        warn "No sha256 tool (sha256sum/shasum) available; skipping checksum verification"
      elif [ -z "$expected" ]; then
        warn "Release checksums file has no entry for $asset_name; skipping verification"
      elif [ "$expected" != "$actual" ]; then
        err "Checksum mismatch for $asset_name (expected $expected, got $actual). Aborting."
        rm -rf "$tmp"
        exit 1
      else
        log "Checksum verified for $asset_name"
      fi
    else
      warn "Could not download checksums file; skipping integrity verification"
    fi
  else
    warn "No checksums asset found in release; skipping integrity verification"
  fi
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
  claude_cfg="$HOME/.claude.json"
  copilot_cfg="$WORKDIR/.vscode/mcp.json"

  log "Writing MCP config for Cursor: $cursor_cfg"
  json_merge_mcp_server "$cursor_cfg" "mcpServers" "codebase-memory" "$bin_path" '[]'

  log "Writing MCP config for Claude Code (user scope): $claude_cfg"
  json_merge_mcp_server "$claude_cfg" "mcpServers" "codebase-memory" "$bin_path" '[]'

  log "Writing MCP config for VS Code / GitHub Copilot (workspace): $copilot_cfg"
  json_merge_mcp_server "$copilot_cfg" "servers" "codebase-memory" "$bin_path" '[]'
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
  local issues=0
  install_rtk
  # install_agora_code  # temporarily disabled (early-stage; overlaps codebase-memory-mcp)
  download_codebase_memory
  setup_rtk_hooks
  # setup_agora_hooks "$WORKDIR"  # temporarily disabled
  setup_mcp_configs
  install_claude_skills

  # Honest summary: only claim success when the core tools are actually present.
  have rtk || { warn "RTK is not on PATH after install"; issues=$((issues + 1)); }
  have codebase-memory-mcp || { warn "codebase-memory-mcp is not on PATH after install"; issues=$((issues + 1)); }
  have claude || warn "Claude Code CLI not found; ponytail/caveman skills were skipped"

  if [ "$issues" -gt 0 ]; then
    warn "Finished with $issues issue(s) above. The stack is only partially installed; review the warnings before relying on it."
  else
    log "Done. Restart Claude Code, Cursor, and VS Code/Copilot after installation."
  fi
}

main "$@"
