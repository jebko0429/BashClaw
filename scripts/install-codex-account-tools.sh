#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/install-codex-account-tools.sh [target_bin_dir]

Installs the Codex account helper scripts from this repo into a bin directory.
If no target directory is provided, the installer picks the first writable PATH
entry, or falls back to ~/.local/bin.

Installed commands:
  start-codex
  switch-codex-account
  codex-start
EOF
}

pick_target_bin() {
  local path_entry
  IFS=':' read -r -a path_parts <<< "${PATH:-}"
  for path_entry in "${path_parts[@]}"; do
    [[ -z "$path_entry" ]] && continue
    if [[ -d "$path_entry" && -w "$path_entry" ]]; then
      printf '%s\n' "$path_entry"
      return 0
    fi
  done
  printf '%s\n' "${HOME}/.local/bin"
}

install_file() {
  local src="$1"
  local dst="$2"
  cp "$src" "$dst"
  chmod 700 "$dst"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local src_start="${REPO_ROOT}/start-codex"
  local src_switch="${REPO_ROOT}/switch-codex-account"
  local target_bin="${1:-}"

  if [[ ! -f "$src_start" || ! -f "$src_switch" ]]; then
    printf 'Error: source scripts not found in repo root.\n' >&2
    exit 1
  fi

  if [[ -z "$target_bin" ]]; then
    target_bin="$(pick_target_bin)"
  fi

  mkdir -p "$target_bin"

  install_file "$src_start" "${target_bin}/start-codex"
  install_file "$src_switch" "${target_bin}/switch-codex-account"
  install_file "$src_start" "${target_bin}/codex-start"

  printf 'Installed Codex account tools to %s\n' "$target_bin"
  printf 'Commands:\n'
  printf '  %s/start-codex\n' "$target_bin"
  printf '  %s/switch-codex-account\n' "$target_bin"
  printf '  %s/codex-start\n' "$target_bin"
}

main "$@"
