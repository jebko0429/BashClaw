#!/usr/bin/env bash
# Watchdog command for BashClaw

cmd_watchdog() {
  local subcommand="${1:-start}"
  shift 2>/dev/null || true

  case "$subcommand" in
    start)  _cmd_watchdog_start "$@" ;;
    stop)   _cmd_watchdog_stop ;;
    status) _cmd_watchdog_status ;;
    logs)   _cmd_watchdog_logs "$@" ;;
    -h|--help|help|"") _cmd_watchdog_usage ;;
    *) log_error "Unknown watchdog subcommand: $subcommand"; _cmd_watchdog_usage; return 1 ;;
  esac
}

_cmd_watchdog_start() {
  local port=""
  local daemon=false
  local heartbeat_enabled=true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -p|--port) port="$2"; shift 2 ;;
      -d|--daemon) daemon=true; shift ;;
      --no-heartbeat) heartbeat_enabled=false; shift ;;
      -h|--help) _cmd_watchdog_usage; return 0 ;;
      *) log_error "Unknown option: $1"; _cmd_watchdog_usage; return 1 ;;
    esac
  done

  if [[ "$daemon" == "true" ]]; then
    watchdog_start_daemon "$port" "$heartbeat_enabled"
  else
    watchdog_run "$port" "$heartbeat_enabled"
  fi
}

_cmd_watchdog_stop() {
  watchdog_stop
}

_cmd_watchdog_status() {
  watchdog_status
}

_cmd_watchdog_logs() {
  local follow=false
  local lines=50

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--follow) follow=true; shift ;;
      -n|--lines) lines="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  watchdog_logs "$follow" "$lines"
}

_cmd_watchdog_usage() {
  cat <<'EOF'
Usage: bashclaw watchdog <subcommand> [options]

Subcommands:
  start       Start watchdog (default)
  stop        Stop watchdog
  status      Show watchdog status
  logs        Show watchdog logs

Options (start):
  -d, --daemon         Run watchdog in background
  -p, --port PORT      Override gateway port
  --no-heartbeat       Disable heartbeat loops

Options (logs):
  -f, --follow         Follow log output
  -n, --lines N        Tail last N lines (default: 50)
EOF
}
