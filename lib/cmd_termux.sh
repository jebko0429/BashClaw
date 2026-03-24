#!/usr/bin/env bash
# Termux-specific CLI command

cmd_termux() {
  local subcommand="${1:-doctor}"
  shift || true

  case "$subcommand" in
    enable)
      cmd_termux_enable "$@"
      ;;
    doctor)
      cmd_termux_doctor "$@"
      ;;
    status)
      cmd_termux_status "$@"
      ;;
    recipes)
      cmd_termux_recipes "$@"
      ;;
    operator)
      cmd_termux_operator "$@"
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

cmd_termux_enable() {
  local setup_storage="false"
  local install_boot="false"
  local send_notification="false"
  local arg

  while [[ $# -gt 0 ]]; do
    arg="$1"
    shift || true
    case "$arg" in
      --setup-storage)
        setup_storage="true"
        ;;
      --install-boot)
        install_boot="true"
        ;;
      --notify)
        send_notification="true"
        ;;
      -h|--help|help)
        cat <<'EOF'
Usage: bashclaw termux enable [--setup-storage] [--install-boot] [--notify]

Options:
  --setup-storage  Run termux-setup-storage when shared storage is not linked
  --install-boot   Install the BashClaw Termux boot script
  --notify         Send a completion notification when Termux API is available
EOF
        return 0
        ;;
      *)
        log_error "Unknown termux enable option: $arg"
        return 1
        ;;
    esac
  done

  if ! platform_is_termux; then
    printf 'Termux enable requires a Termux runtime.\n'
    return 1
  fi

  local created=0
  local config_created=0
  local storage_attempted="false"
  local boot_installed="false"
  local path

  printf '=== BashClaw Termux enable ===\n'

  for path in \
    "$BASHCLAW_STATE_DIR" \
    "${BASHCLAW_STATE_DIR}/agents" \
    "${BASHCLAW_STATE_DIR}/cache" \
    "${BASHCLAW_STATE_DIR}/config" \
    "${BASHCLAW_STATE_DIR}/cron" \
    "${BASHCLAW_STATE_DIR}/logs" \
    "${BASHCLAW_STATE_DIR}/memory" \
    "${BASHCLAW_STATE_DIR}/sessions"; do
    if [[ ! -d "$path" ]]; then
      mkdir -p "$path"
      created=$((created + 1))
    fi
  done

  path="$(platform_temp_base 2>/dev/null || true)"
  if [[ -n "$path" && ! -d "$path" ]]; then
    mkdir -p "$path"
    created=$((created + 1))
  fi

  if [[ ! -f "$(config_path)" ]]; then
    config_init_default
    config_created=1
  fi

  if [[ "$setup_storage" == "true" ]] && [[ ! -e "$(platform_termux_shared_storage)" ]]; then
    if is_command_available termux-setup-storage; then
      termux-setup-storage >/dev/null 2>&1 || true
      storage_attempted="true"
    else
      printf '[WARN] termux-setup-storage not available\n'
    fi
  fi

  if [[ "$install_boot" == "true" ]]; then
    _daemon_install_termux "${BASHCLAW_ROOT}/bashclaw" "${BASHCLAW_STATE_DIR}/logs/watchdog.log"
    boot_installed="true"
  fi

  if [[ "$send_notification" == "true" ]] && platform_termux_api_available termux-notification; then
    termux-notification --title "BashClaw" --content "Termux enable complete" >/dev/null 2>&1 || true
  fi

  printf 'State dir:      %s\n' "$BASHCLAW_STATE_DIR"
  printf 'Temp base:      %s\n' "$(platform_temp_base 2>/dev/null || printf 'unavailable')"
  printf 'Created paths:  %s\n' "$created"
  printf 'Config:         %s\n' "$(if [[ "$config_created" -eq 1 ]]; then printf 'created'; else printf 'existing'; fi)"
  printf 'Storage setup:  %s\n' "$(if [[ "$storage_attempted" == "true" ]]; then printf 'requested'; else printf 'not requested'; fi)"
  printf 'Boot script:    %s\n' "$(if [[ "$boot_installed" == "true" ]]; then printf 'installed'; else printf 'not requested'; fi)"
  printf '\n'

  cmd_termux_doctor
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
  printf 'Boot dir:       %s\n' "$(platform_termux_boot_dir)"
  printf 'Boot ready:     %s\n' "$(_termux_bool "$(platform_termux_boot_ready && printf yes || printf no)")"
  printf 'Service mode:   %s\n' "$(platform_termux_service_strategy)"
  printf 'Operator mode:  %s\n' "$(config_get '.termux.operatorMode' 'false')"
}

cmd_termux_recipes() {
  local recipe="${1:-}"
  local action="list"

  case "$recipe" in
    -h|--help|help)
      cat <<'EOF'
Usage: bashclaw termux recipes [recipe] [run]

Examples:
  bashclaw termux recipes
  bashclaw termux recipes battery
  bashclaw termux recipes connectivity run
EOF
      return 0
      ;;
  esac

  if [[ -z "$recipe" ]]; then
    local list_json
    list_json="$(tool_termux_recipe '{"action":"list"}')"
    printf '=== BashClaw Termux recipes ===\n'
    printf '%s' "$list_json" | jq -r '.recipes[] | "- \(.id): \(.summary)"'
    return 0
  fi

  if [[ "${2:-}" == "run" ]]; then
    action="run"
  else
    action="describe"
  fi

  local payload result
  payload="$(jq -nc --arg action "$action" --arg recipe "$recipe" '{action: $action, recipe: $recipe}')"
  result="$(tool_termux_recipe "$payload")" || return 1

  if [[ "$action" == "describe" ]]; then
    printf '=== Termux recipe: %s ===\n' "$recipe"
    printf '%s' "$result" | jq -r '"Summary: \(.summary)\nUses: \(.uses | join(", "))"'
  else
    printf '%s\n' "$result" | jq .
  fi
}

cmd_termux_operator() {
  local subcommand="${1:-status}"

  case "$subcommand" in
    enable)
      [[ -f "$(config_path)" ]] || config_init_default >/dev/null 2>&1
      config_set '.termux.operatorMode' 'true'
      config_set '.agents.defaults.tools.profile' '"termux-operator"'
      printf 'Termux operator mode enabled.\n'
      printf 'Default agent tool profile: %s\n' "$(config_get '.agents.defaults.tools.profile' 'full')"
      ;;
    disable)
      [[ -f "$(config_path)" ]] || config_init_default >/dev/null 2>&1
      config_set '.termux.operatorMode' 'false'
      config_set '.agents.defaults.tools.profile' '"full"'
      printf 'Termux operator mode disabled.\n'
      ;;
    status)
      printf 'Termux operator mode: %s\n' "$(config_get '.termux.operatorMode' 'false')"
      printf 'Default agent tool profile: %s\n' "$(config_get '.agents.defaults.tools.profile' 'full')"
      ;;
    -h|--help|help)
      cat <<'EOF'
Usage: bashclaw termux operator [enable|disable|status]
EOF
      ;;
    *)
      log_error "Unknown termux operator subcommand: $subcommand"
      return 1
      ;;
  esac
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

  printf '[INFO] Recommended service strategy: %s\n' "$(platform_termux_service_strategy)"


  printf '\n  --- Secrets (.env) ---\n'
  local env_path env_mode
  env_path="${BASHCLAW_STATE_DIR}/.env"
  if [[ -f "$env_path" ]]; then
    env_mode=$(stat -c '%a' "$env_path" 2>/dev/null || stat -f '%Lp' "$env_path" 2>/dev/null || printf 'unknown')
    if [[ "$env_mode" =~ ^[0-9]+$ ]] && (( env_mode > 640 )); then
      printf '[WARN] .env permissions are loose (%s). Recommend chmod 600 %s\n' "$env_mode" "$env_path"
      warnings=$((warnings + 1))
    else
      printf '[OK]   .env permissions: %s\n' "$env_mode"
    fi
  else
    printf '[INFO] .env not found at %s\n' "$env_path"
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
Usage: bashclaw termux <enable|doctor|status|recipes|operator|paths>

Subcommands:
  enable    Initialize Termux-native state, config, and optional boot/storage helpers
  doctor    Check Termux compatibility, temp paths, storage, and API tools
  status    Show the current Termux runtime summary
  recipes   List or run built-in Termux workflow recipes
  operator  Enable or inspect Termux operator mode
  paths     Print Termux-related path resolution
EOF
}
