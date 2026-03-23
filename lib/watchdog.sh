#!/usr/bin/env bash
# Watchdog for BashClaw gateway + heartbeat loops (Termux-friendly)
# Compatible with bash 3.2+

: "${WATCHDOG_CHECK_INTERVAL:=5}"
: "${WATCHDOG_RESTART_BACKOFF_BASE:=2}"
: "${WATCHDOG_RESTART_BACKOFF_MAX:=60}"
: "${WATCHDOG_FAIL_WINDOW:=300}"
: "${WATCHDOG_FAIL_THRESHOLD:=5}"
: "${WATCHDOG_COOLDOWN_SECONDS:=300}"
: "${WATCHDOG_STABLE_RESET_SECONDS:=600}"

_watchdog_dir() {
  printf '%s/watchdog' "${BASHCLAW_STATE_DIR:?BASHCLAW_STATE_DIR not set}"
}

_watchdog_pid_file() {
  printf '%s/watchdog.pid' "${BASHCLAW_STATE_DIR:?BASHCLAW_STATE_DIR not set}"
}

_watchdog_state_file() {
  printf '%s/state' "${BASHCLAW_STATE_DIR:?BASHCLAW_STATE_DIR not set}/watchdog"
}

_watchdog_log_file() {
  printf '%s/logs/watchdog.log' "${BASHCLAW_STATE_DIR:?BASHCLAW_STATE_DIR not set}"
}

_watchdog_gateway_log_file() {
  printf '%s/logs/gateway.log' "${BASHCLAW_STATE_DIR:?BASHCLAW_STATE_DIR not set}"
}

_watchdog_hb_pid_file() {
  local agent_id="$1"
  printf '%s/heartbeat_%s.pid' "$(_watchdog_dir)" "$agent_id"
}

_watchdog_load_env() {
  local env_file="${BASHCLAW_STATE_DIR:?}/.env"
  if [[ -f "$env_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      if [[ "$line" =~ ^[A-Za-z_][A-Za-z_0-9]*= ]]; then
        export "$line"
      fi
    done < "$env_file"
  fi
}

_watchdog_apply_env_defaults() {
  : "${WATCHDOG_CHECK_INTERVAL:=5}"
  : "${WATCHDOG_RESTART_BACKOFF_BASE:=2}"
  : "${WATCHDOG_RESTART_BACKOFF_MAX:=60}"
  : "${WATCHDOG_FAIL_WINDOW:=300}"
  : "${WATCHDOG_FAIL_THRESHOLD:=5}"
  : "${WATCHDOG_COOLDOWN_SECONDS:=300}"
  : "${WATCHDOG_STABLE_RESET_SECONDS:=600}"
}

_watchdog_state_load() {
  local state_file
  state_file="$(_watchdog_state_file)"

  watchdog_failures=0
  watchdog_last_fail_ts=0
  watchdog_last_start_ts=0
  watchdog_cooldown_until=0

  if [[ -f "$state_file" ]]; then
    local line key val
    while IFS='=' read -r key val; do
      case "$key" in
        failures) watchdog_failures="${val:-0}" ;;
        last_fail_ts) watchdog_last_fail_ts="${val:-0}" ;;
        last_start_ts) watchdog_last_start_ts="${val:-0}" ;;
        cooldown_until) watchdog_cooldown_until="${val:-0}" ;;
      esac
    done < "$state_file"
  fi
}

_watchdog_state_save() {
  local state_file
  state_file="$(_watchdog_state_file)"
  printf 'failures=%s\nlast_fail_ts=%s\nlast_start_ts=%s\ncooldown_until=%s\n' \
    "${watchdog_failures:-0}" \
    "${watchdog_last_fail_ts:-0}" \
    "${watchdog_last_start_ts:-0}" \
    "${watchdog_cooldown_until:-0}" \
    > "$state_file"
}

_watchdog_calc_backoff() {
  local failures="${1:-1}"
  local backoff="$WATCHDOG_RESTART_BACKOFF_BASE"
  local i=1
  while (( i < failures )); do
    backoff=$((backoff * 2))
    if (( backoff > WATCHDOG_RESTART_BACKOFF_MAX )); then
      backoff="$WATCHDOG_RESTART_BACKOFF_MAX"
      break
    fi
    i=$((i + 1))
  done
  printf '%s' "$backoff"
}

watchdog_is_running() {
  local pid_file
  pid_file="$(_watchdog_pid_file)"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file" 2>/dev/null)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

watchdog_start_daemon() {
  local port="${1:-}"
  local heartbeat_enabled="${2:-true}"

  if watchdog_is_running; then
    log_warn "watchdog already running"
    return 1
  fi

  local log_file
  log_file="$(_watchdog_log_file)"
  ensure_dir "$(dirname "$log_file")"

  nohup bash -c "
    export BASHCLAW_STATE_DIR='${BASHCLAW_STATE_DIR}'
    export LOG_FILE='${log_file}'
    source '${BASHCLAW_ROOT}/bashclaw'
    watchdog_run '${port}' '${heartbeat_enabled}'
  " >> "$log_file" 2>&1 &

  log_info "watchdog started (pid=$!, log=$log_file)"
}

watchdog_run() {
  local port="${1:-}"
  local heartbeat_enabled="${2:-true}"

  ensure_state_dir
  ensure_dir "$(_watchdog_dir)"
  _watchdog_load_env
  _watchdog_apply_env_defaults

  local pid_file
  pid_file="$(_watchdog_pid_file)"
  if watchdog_is_running; then
    log_error "watchdog already running"
    return 1
  fi
  printf '%s' "$$" > "$pid_file"

  trap 'watchdog_stop_children; rm -f "$pid_file"; exit 0' INT TERM

  watchdog_cleanup_orphans
  if [[ "$heartbeat_enabled" == "true" ]]; then
    watchdog_start_heartbeats
  fi

  while true; do
    _watchdog_state_load
    local now
    now="$(timestamp_s)"

    if ! watchdog_gateway_running; then
      if (( watchdog_cooldown_until > now )); then
        local remaining=$((watchdog_cooldown_until - now))
        log_warn "watchdog: cooldown active, retrying in ${remaining}s"
        sleep "$remaining"
        continue
      fi

      if (( watchdog_last_fail_ts > 0 )) && (( now - watchdog_last_fail_ts <= WATCHDOG_FAIL_WINDOW )); then
        watchdog_failures=$((watchdog_failures + 1))
      else
        watchdog_failures=1
      fi
      watchdog_last_fail_ts="$now"

      if (( watchdog_failures >= WATCHDOG_FAIL_THRESHOLD )); then
        watchdog_cooldown_until=$((now + WATCHDOG_COOLDOWN_SECONDS))
        watchdog_failures=0
        _watchdog_state_save
        log_warn "watchdog: too many failures, cooling down for ${WATCHDOG_COOLDOWN_SECONDS}s"
        sleep "$WATCHDOG_COOLDOWN_SECONDS"
        continue
      fi

      local backoff
      backoff="$(_watchdog_calc_backoff "$watchdog_failures")"
      log_warn "watchdog: gateway not running, restarting in ${backoff}s"
      sleep "$backoff"
      watchdog_start_gateway "$port"
      watchdog_last_start_ts="$(timestamp_s)"
      _watchdog_state_save
    else
      if (( watchdog_last_start_ts == 0 )); then
        watchdog_last_start_ts="$now"
        _watchdog_state_save
      elif (( now - watchdog_last_start_ts >= WATCHDOG_STABLE_RESET_SECONDS )); then
        watchdog_failures=0
        watchdog_last_fail_ts=0
        watchdog_cooldown_until=0
        _watchdog_state_save
      fi
    fi
    sleep "$WATCHDOG_CHECK_INTERVAL"
  done
}

watchdog_gateway_running() {
  local pid_file="${BASHCLAW_STATE_DIR:?}/gateway.pid"
  if [[ ! -f "$pid_file" ]]; then
    return 1
  fi
  local pid
  pid="$(cat "$pid_file" 2>/dev/null)"
  if [[ -z "$pid" ]]; then
    rm -f "$pid_file"
    return 1
  fi
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  rm -f "$pid_file"
  return 1
}

watchdog_start_gateway() {
  local port="${1:-}"
  local log_file
  log_file="$(_watchdog_gateway_log_file)"
  ensure_dir "$(dirname "$log_file")"

  local port_arg=""
  if [[ -n "$port" ]]; then
    port_arg="--port ${port}"
  fi

  bash "${BASHCLAW_ROOT}/bashclaw" gateway ${port_arg} >> "$log_file" 2>&1 &
  log_info "watchdog: spawned gateway (pid=$!)"
}

watchdog_start_heartbeats() {
  require_command jq "watchdog heartbeats require jq"

  local agents_raw
  agents_raw="$(config_get_raw '.agents.list // []')"
  local agent_ids
  agent_ids="$(printf '%s' "$agents_raw" | jq -r '.[].id // empty')"

  if [[ -z "$agent_ids" ]]; then
    agent_ids="$(config_get '.agents.defaultId' 'main')"
  fi

  local agent_id
  for agent_id in $agent_ids; do
    local hb_pid_file
    hb_pid_file="$(_watchdog_hb_pid_file "$agent_id")"
    if [[ -f "$hb_pid_file" ]]; then
      local existing_pid
      existing_pid="$(cat "$hb_pid_file" 2>/dev/null)"
      if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        continue
      fi
      rm -f "$hb_pid_file"
    fi
    heartbeat_loop "$agent_id" &
    printf '%s' "$!" > "$hb_pid_file"
    log_info "watchdog: heartbeat loop started for agent=$agent_id (pid=$!)"
  done
}

watchdog_stop_children() {
  watchdog_stop_heartbeats

  watchdog_stop_gateway
}

watchdog_stop_gateway() {
  local pid_file="${BASHCLAW_STATE_DIR:?}/gateway.pid"
  if [[ ! -f "$pid_file" ]]; then
    return 0
  fi
  local pid
  pid="$(cat "$pid_file" 2>/dev/null)"
  if [[ -z "$pid" ]]; then
    rm -f "$pid_file"
    return 0
  fi
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    local waited=0
    while kill -0 "$pid" 2>/dev/null && (( waited < 10 )); do
      sleep 1
      waited=$((waited + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  rm -f "$pid_file"
}

watchdog_stop_heartbeats() {
  local f
  for f in "$(_watchdog_dir)"/heartbeat_*.pid; do
    [[ -f "$f" ]] || continue
    local pid
    pid="$(cat "$f" 2>/dev/null)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
    rm -f "$f"
  done
}

watchdog_cleanup_orphans() {
  watchdog_stop_heartbeats
  if watchdog_gateway_running; then
    return 0
  fi
  rm -f "${BASHCLAW_STATE_DIR:?}/gateway.pid"
}

watchdog_stop() {
  local pid_file
  pid_file="$(_watchdog_pid_file)"

  if [[ ! -f "$pid_file" ]]; then
    log_warn "watchdog not running"
    return 1
  fi

  local pid
  pid="$(cat "$pid_file" 2>/dev/null)"
  if [[ -z "$pid" ]]; then
    rm -f "$pid_file"
    log_warn "watchdog PID file empty"
    return 1
  fi

  if kill -0 "$pid" 2>/dev/null; then
    log_info "Stopping watchdog (pid=$pid)..."
    kill -TERM "$pid" 2>/dev/null || true
    local waited=0
    while kill -0 "$pid" 2>/dev/null && (( waited < 10 )); do
      sleep 1
      waited=$((waited + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
  fi

  rm -f "$pid_file"
  watchdog_stop_children
  log_info "watchdog stopped"
}

watchdog_status() {
  if watchdog_is_running; then
    local pid
    pid="$(cat "$(_watchdog_pid_file)" 2>/dev/null)"
    printf 'Watchdog: running (pid=%s)\n' "$pid"
  else
    printf 'Watchdog: stopped\n'
  fi

  if watchdog_gateway_running; then
    local gw_pid
    gw_pid="$(cat "${BASHCLAW_STATE_DIR:?}/gateway.pid" 2>/dev/null)"
    printf 'Gateway:  running (pid=%s)\n' "$gw_pid"
  else
    printf 'Gateway:  stopped\n'
  fi
}

watchdog_logs() {
  local follow="${1:-false}"
  local lines="${2:-50}"
  local log_file
  log_file="$(_watchdog_log_file)"

  if [[ ! -f "$log_file" ]]; then
    printf 'No log file found: %s\n' "$log_file"
    return 1
  fi

  if [[ "$follow" == "true" ]]; then
    tail -n "$lines" -f "$log_file"
  else
    tail -n "$lines" "$log_file"
  fi
}
