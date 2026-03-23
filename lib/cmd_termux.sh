#!/usr/bin/env bash
# Termux-specific CLI command

cmd_termux() {
  local subcommand="${1:-doctor}"
  shift || true

  case "$subcommand" in
    doctor)
      cmd_termux_doctor "$@"
      ;;
    status)
      cmd_termux_status "$@"
      ;;
    paths)
      cmd_termux_paths "$@"
      ;;
    -h|--help|help)
      _cmd_termux_usage
      ;;
    *)
      log_error "Unknown termux subcommand: $subcommand"
      _cmd_termux_usage
      return 1
      ;;
  esac
}

cmd_termux_status() {
  printf '=== BashClaw Termux status ===\n'
  printf 'Termux runtime: %s\n' "$(_termux_bool "$(platform_is_termux && printf yes || printf no)")"
  printf 'Prefix:         %s\n' "$(platform_termux_prefix)"
  printf 'Home:           %s\n' "$(platform_termux_home)"
  printf 'Temp base:      %s\n' "$(platform_temp_base 2>/dev/null || printf 'unavailable')"
  printf 'State dir:      %s\n' "$BASHCLAW_STATE_DIR"
  printf 'Shared storage: %s\n' "$(platform_termux_shared_storage)"
  printf 'Downloads:      %s\n' "$(platform_termux_downloads_dir)"
}

cmd_termux_paths() {
  printf 'termux_prefix=%s\n' "$(platform_termux_prefix)"
  printf 'termux_home=%s\n' "$(platform_termux_home)"
  printf 'temp_base=%s\n' "$(platform_temp_base 2>/dev/null || printf 'unavailable')"
  printf 'shared_storage=%s\n' "$(platform_termux_shared_storage)"
  printf 'downloads=%s\n' "$(platform_termux_downloads_dir)"
  printf 'boot_dir=%s\n' "$(platform_termux_boot_dir)"
  printf 'state_dir=%s\n' "$BASHCLAW_STATE_DIR"
}

cmd_termux_doctor() {
  local issues=0
  local warnings=0
  local cmd ok path

  printf '=== BashClaw Termux doctor ===\n\n'

  if platform_is_termux; then
    printf '[OK]   Running inside a Termux-style environment\n'
  else
    printf '[WARN] This does not look like a Termux runtime\n'
    warnings=$((warnings + 1))
  fi

  path="$(platform_temp_base 2>/dev/null || true)"
  if [[ -n "$path" && -d "$path" && -w "$path" ]]; then
    printf '[OK]   Writable temp base: %s\n' "$path"
  else
    printf '[FAIL] No writable temp base detected\n'
    issues=$((issues + 1))
  fi

  if [[ -d "$BASHCLAW_STATE_DIR" && -w "$BASHCLAW_STATE_DIR" ]]; then
    printf '[OK]   Writable state dir: %s\n' "$BASHCLAW_STATE_DIR"
  elif mkdir -p "$BASHCLAW_STATE_DIR" 2>/dev/null; then
    printf '[OK]   Created state dir: %s\n' "$BASHCLAW_STATE_DIR"
  else
    printf '[FAIL] State dir is not writable: %s\n' "$BASHCLAW_STATE_DIR"
    issues=$((issues + 1))
  fi

  printf '\n  --- Termux API Commands ---\n'
  local api_cmds="termux-notification termux-toast termux-open termux-share termux-clipboard-get termux-clipboard-set termux-battery-status termux-wifi-connectioninfo termux-location termux-telephony-deviceinfo termux-camera-photo"
  for cmd in $api_cmds; do
    if platform_termux_api_available "$cmd"; then
      printf '[OK]   %s\n' "$cmd"
      ok=true
    else
      printf '[WARN] %s not available\n' "$cmd"
      warnings=$((warnings + 1))
      ok=false
    fi
  done

  printf '\n  --- Storage Paths ---\n'
  local shared_dir downloads_dir boot_dir
  shared_dir="$(platform_termux_shared_storage)"
  downloads_dir="$(platform_termux_downloads_dir)"
  boot_dir="$(platform_termux_boot_dir)"

  if [[ -e "$shared_dir" ]]; then
    printf '[OK]   Shared storage linked: %s\n' "$shared_dir"
  else
    printf '[WARN] Shared storage not linked: %s\n' "$shared_dir"
    printf '       Run: termux-setup-storage\n'
    warnings=$((warnings + 1))
  fi

  if [[ -d "$downloads_dir" ]]; then
    printf '[OK]   Downloads path available: %s\n' "$downloads_dir"
  else
    printf '[INFO] Downloads path not available yet: %s\n' "$downloads_dir"
  fi

  if [[ -d "$boot_dir" ]]; then
    printf '[OK]   Termux boot directory exists: %s\n' "$boot_dir"
  else
    printf '[INFO] Termux boot directory missing: %s\n' "$boot_dir"
  fi

  printf '\n  --- Package Tooling ---\n'
  if is_command_available pkg; then
    printf '[OK]   pkg available: %s\n' "$(command -v pkg)"
  else
    printf '[WARN] pkg command not found\n'
    warnings=$((warnings + 1))
  fi

  if is_command_available termux-info; then
    printf '[OK]   termux-info available\n'
  else
    printf '[INFO] termux-info not available\n'
  fi

  printf '\n'
  if (( issues > 0 )); then
    printf 'Termux doctor found %d issue(s) and %d warning(s)\n' "$issues" "$warnings"
    return 1
  fi

  printf 'Termux doctor passed with %d warning(s)\n' "$warnings"
  return 0
}

_termux_bool() {
  if [[ "$1" == "yes" ]]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

_cmd_termux_usage() {
  cat <<'EOF'
Usage: bashclaw termux <doctor|status|paths>

Subcommands:
  doctor   Check Termux compatibility, temp paths, storage, and API tools
  status   Show the current Termux runtime summary
  paths    Print Termux-related path resolution
EOF
}
