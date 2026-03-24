#!/usr/bin/env bash
# Agent CLI command for BashClaw

_cmd_agent_color() {
  local name="$1"
  if [[ ! -t 1 || "${TERM:-}" == "dumb" ]]; then
    return 0
  fi

  case "$name" in
    reset) printf '\033[0m' ;;
    bold) printf '\033[1m' ;;
    dim) printf '\033[2m' ;;
    cyan) printf '\033[36m' ;;
    blue) printf '\033[34m' ;;
    green) printf '\033[32m' ;;
    yellow) printf '\033[33m' ;;
    red) printf '\033[31m' ;;
    *) ;;
  esac
}

_cmd_agent_compact_mode() {
  if platform_is_termux; then
    return 0
  fi

  local cols="${COLUMNS:-0}"
  if [[ "$cols" =~ ^[0-9]+$ ]] && (( cols > 0 && cols < 90 )); then
    return 0
  fi

  return 1
}

_cmd_agent_notify_completion() {
  local response="$1"
  [[ -z "$response" ]] && return 0
  platform_is_termux || return 0
  platform_termux_api_available termux-notification || return 0

  local enabled
  enabled="$(config_get '.termux.notifyOnAgentResponse' 'false')"
  [[ "$enabled" == 'true' ]] || return 0

  local summary="$response"
  summary="$(printf '%s' "$summary" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g')"
  summary="${summary:0:120}"
  termux-notification --title 'BashClaw reply ready' --content "$summary" >/dev/null 2>&1 || true
}

_cmd_agent_print_banner() {
  local agent_id="$1"
  local channel="$2"
  local sender="$3"
  local model provider sess_file msg_count
  model="$(agent_resolve_model "$agent_id")"
  provider="$(agent_resolve_provider "$model")"
  sess_file="$(session_file "$agent_id" "$channel" "$sender")"
  msg_count="$(session_count "$sess_file" 2>/dev/null || printf '0')"

  if _cmd_agent_compact_mode; then
    printf '%sBashClaw%s  %s | %s (%s) | %s msgs\n' \
      "$(_cmd_agent_color bold)" \
      "$(_cmd_agent_color reset)" \
      "$agent_id" \
      "$model" \
      "$provider" \
      "$msg_count"
    printf '%sCommands:%s /reset /history /status /model /quit\n\n' "$(_cmd_agent_color cyan)" "$(_cmd_agent_color reset)"
    return
  fi

  printf '%sBashClaw Chat%s\n' "$(_cmd_agent_color bold)" "$(_cmd_agent_color reset)"
  printf '%sagent%s   %s\n' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)" "$agent_id"
  printf '%smodel%s   %s (%s)\n' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)" "$model" "$provider"
  printf '%schannel%s %s\n' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)" "$channel"
  printf '%ssender%s  %s\n' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)" "$sender"
  printf '%ssession%s %s messages\n' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)" "$msg_count"
  printf '\n'
  printf '%sCommands:%s /reset  /history  /status  /model  /quit\n\n' "$(_cmd_agent_color cyan)" "$(_cmd_agent_color reset)"
}

_cmd_agent_prompt() {
  printf '%sYou%s › ' "$(_cmd_agent_color blue)" "$(_cmd_agent_color reset)"
}

_cmd_agent_print_rule() {
  printf '%s----------------------------------------%s\n' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)"
}

_cmd_agent_print_response() {
  local response="$1"
  _cmd_agent_print_rule
  if [[ -n "$response" ]]; then
    printf '%sAgent%s\n%s\n\n' "$(_cmd_agent_color green)" "$(_cmd_agent_color reset)" "$response"
  else
    printf '%sAgent%s\n%s[no response]%s\n\n' \
      "$(_cmd_agent_color green)" \
      "$(_cmd_agent_color reset)" \
      "$(_cmd_agent_color dim)" \
      "$(_cmd_agent_color reset)"
  fi
}

_cmd_agent_print_status() {
  local agent_id="$1"
  local channel="$2"
  local sender="$3"
  local model provider sess_file msg_count
  model="$(agent_resolve_model "$agent_id")"
  provider="$(agent_resolve_provider "$model")"
  sess_file="$(session_file "$agent_id" "$channel" "$sender")"
  msg_count="$(session_count "$sess_file")"

  _cmd_agent_print_rule
  printf '%sStatus%s\n' "$(_cmd_agent_color yellow)" "$(_cmd_agent_color reset)"
  printf '  agent      %s\n' "$agent_id"
  printf '  model      %s (%s)\n' "$model" "$provider"
  printf '  channel    %s\n' "$channel"
  printf '  sender     %s\n' "$sender"
  printf '  messages   %s\n\n' "$msg_count"
}

_cmd_agent_print_history() {
  local sess_file="$1"
  local history count
  history="$(session_load "$sess_file")"
  count="$(printf '%s' "$history" | jq 'length')"

  _cmd_agent_print_rule
  printf '%sHistory%s  %s messages\n' "$(_cmd_agent_color yellow)" "$(_cmd_agent_color reset)" "$count"
  printf '%s' "$history" | jq -r '.[] | "\(.role): \(.content // .tool_name // "[tool]")"' 2>/dev/null | tail -20
  printf '\n\n'
}

cmd_agent() {
  local message="" agent_id="main" channel="default" sender="" interactive=false verbose=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--message) message="$2"; shift 2 ;;
      -a|--agent) agent_id="$2"; shift 2 ;;
      -c|--channel) channel="$2"; shift 2 ;;
      -s|--sender) sender="$2"; shift 2 ;;
      -i|--interactive) interactive=true; shift ;;
      -v|--verbose) verbose=true; shift ;;
      -h|--help) _cmd_agent_usage; return 0 ;;
      *) message="$*"; break ;;
    esac
  done

  if [[ "$verbose" == "true" ]]; then
    LOG_LEVEL="debug"
  fi

  if [[ "$interactive" == "true" ]]; then
    cmd_agent_interactive "$agent_id" "$channel" "$sender"
    return $?
  fi

  if [[ -z "$message" ]]; then
    log_error "Message is required. Use -m 'message' or -i for interactive mode."
    _cmd_agent_usage
    return 1
  fi

  local response
  response="$(engine_run "$agent_id" "$message" "$channel" "$sender")"
  _cmd_agent_notify_completion "$response"
  if [[ -n "$response" ]]; then
    printf '%s\n' "$response"
  fi
}

cmd_agent_interactive() {
  local agent_id="${1:-main}"
  local channel="${2:-default}"
  local sender="${3:-cli}"

  log_info "Interactive mode: agent=$agent_id channel=$channel"
  local sess_file
  sess_file="$(session_file "$agent_id" "$channel" "$sender")"
  _cmd_agent_print_banner "$agent_id" "$channel" "$sender"

  local _use_readline=false
  local _history_file="${BASHCLAW_STATE_DIR}/history"
  if (echo "" | read -e 2>/dev/null); then
    _use_readline=true
    if [[ -f "$_history_file" ]]; then
      history -r "$_history_file" 2>/dev/null || true
    fi
  fi

  while true; do
    local input
    if [[ "$_use_readline" == "true" ]]; then
      if ! IFS= read -e -r -p "$(_cmd_agent_prompt)" input; then
        printf '\n'
        break
      fi
    else
      _cmd_agent_prompt
      if ! IFS= read -r input; then
        printf '\n'
        break
      fi
    fi

    input="$(trim "$input")"
    if [[ -z "$input" ]]; then
      continue
    fi

    if [[ "$_use_readline" == "true" ]]; then
      history -s "$input" 2>/dev/null || true
      history -a "$_history_file" 2>/dev/null || true
    fi

    # Handle slash commands
    case "$input" in
      /reset)
        session_clear "$sess_file"
        _cmd_agent_print_rule
        printf '%sSession reset.%s\n\n' "$(_cmd_agent_color yellow)" "$(_cmd_agent_color reset)"
        continue
        ;;
      /history)
        _cmd_agent_print_history "$sess_file"
        continue
        ;;
      /status)
        _cmd_agent_print_status "$agent_id" "$channel" "$sender"
        continue
        ;;
      /model)
        _cmd_agent_print_rule
        printf '%sCurrent model:%s %s\n\n' "$(_cmd_agent_color yellow)" "$(_cmd_agent_color reset)" "${AGENT_MODEL_OVERRIDE:-$(agent_resolve_model "$agent_id")}"
        continue
        ;;
      /model\ *)
        local new_model
        new_model="${input#/model }"
        new_model="$(trim "$new_model")"
        if [[ -z "$new_model" ]]; then
          _cmd_agent_print_rule
          printf '%sUsage:%s /model <model_id>\n\n' "$(_cmd_agent_color red)" "$(_cmd_agent_color reset)"
          continue
        fi
        export AGENT_MODEL_OVERRIDE="$new_model"
        _cmd_agent_print_rule
        printf '%sModel override set:%s %s\n\n' "$(_cmd_agent_color green)" "$(_cmd_agent_color reset)" "$new_model"
        continue
        ;;
      /quit|/exit|/q)
        printf '%sGoodbye.%s\n' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)"
        break
        ;;
      /*)
        _cmd_agent_print_rule
        printf '%sUnknown command:%s %s\n\n' "$(_cmd_agent_color red)" "$(_cmd_agent_color reset)" "$input"
        continue
        ;;
    esac

    local response
    response="$(engine_run "$agent_id" "$input" "$channel" "$sender")"
    _cmd_agent_notify_completion "$response"
    _cmd_agent_print_response "$response"
  done
}

_cmd_agent_usage() {
  cat <<'EOF'
Usage: bashclaw agent [options] [message]

Options:
  -m, --message TEXT    Message to send to the agent
  -a, --agent ID        Agent ID (default: main)
  -c, --channel NAME    Channel context (default: default)
  -s, --sender ID       Sender identifier
  -i, --interactive     Start interactive REPL mode
  -v, --verbose         Enable debug logging
  -h, --help            Show this help

Interactive commands:
  /reset    Clear session history
  /history  Show recent session history
  /status   Show agent status
  /quit     Exit interactive mode
EOF
}
