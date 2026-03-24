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
    printf '%sCommands:%s /help /edit /paste /model /set /quit\n\n' "$(_cmd_agent_color cyan)" "$(_cmd_agent_color reset)"
    return
  fi

  printf '%sBashClaw Chat%s\n' "$(_cmd_agent_color bold)" "$(_cmd_agent_color reset)"
  printf '%sagent%s   %s\n' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)" "$agent_id"
  printf '%smodel%s   %s (%s)\n' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)" "$model" "$provider"
  printf '%schannel%s %s\n' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)" "$channel"
  printf '%ssender%s  %s\n' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)" "$sender"
  printf '%ssession%s %s messages\n' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)" "$msg_count"
  printf '\n'
  printf '%sCommands:%s /help  /edit  /paste  /model  /set  /quit\n\n' "$(_cmd_agent_color cyan)" "$(_cmd_agent_color reset)"
}

_cmd_agent_current_model() {
  local agent_id="${1:-main}"
  printf '%s' "${AGENT_MODEL_OVERRIDE:-$(agent_resolve_model "$agent_id")}"
}

_cmd_agent_set_model_override() {
  local model="$1"
  case "$model" in
    reset|clear|default)
      unset AGENT_MODEL_OVERRIDE
      return
      ;;
  esac

  export AGENT_MODEL_OVERRIDE="$model"
}

_cmd_agent_resolve_model_input() {
  local raw="$1"
  local matches count resolved pretty_matches

  matches="$(_model_complete_prefix "$raw")"
  count="$(printf '%s
' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [[ "$count" == "0" ]]; then
    printf '%s' "$raw"
    return 0
  fi

  if [[ "$count" == "1" ]]; then
    resolved="$(printf '%s
' "$matches" | sed -n '1p')"
    printf '%s' "$resolved"
    return 0
  fi

  pretty_matches="$(printf '%s
' "$matches" | tr '
' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/[[:space:]]$//')"
  printf '%s----------------------------------------%s
'     "$(_cmd_agent_color dim)"     "$(_cmd_agent_color reset)" >&2
  printf '%sModel matches:%s %s

'     "$(_cmd_agent_color yellow)"     "$(_cmd_agent_color reset)"     "$pretty_matches" >&2
  return 0
}

_cmd_agent_current_provider() {
  local agent_id="${1:-main}"
  local model
  model="$(_cmd_agent_current_model "$agent_id")"
  agent_resolve_provider "$model"
}

_cmd_agent_command_list() {
  cat <<'EOF'
/help
/paste
/edit
/reset
/history
/status
/model
/models
/set
/quit
/exit
/q
EOF
}

_cmd_agent_complete_line() {
  local line="$1"
  local prefix matches count resolved pretty_matches

  if [[ "$line" == /model\ * ]]; then
    prefix="${line#/model }"
    if [[ -z "$prefix" ]]; then
      printf '%s' "$line"
      return 0
    fi
    matches="$(_model_complete_prefix "$prefix")"
  elif [[ "$line" == /* ]]; then
    matches="$(printf '%s
' "$(_cmd_agent_command_list)" | awk -v prefix="$line" 'index($0, prefix) == 1')"
  else
    printf '%s' "$line"
    return 0
  fi

  count="$(printf '%s
' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" == "0" ]]; then
    printf '%s' "$line"
    return 0
  fi

  if [[ "$count" == "1" ]]; then
    resolved="$(printf '%s
' "$matches" | sed -n '1p')"
    if [[ "$line" == /model\ * ]]; then
      printf '/model %s' "$resolved"
    else
      printf '%s' "$resolved"
    fi
    return 0
  fi

  pretty_matches="$(printf '%s
' "$matches" | tr '
' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/[[:space:]]$//')"
  printf '%sCompletion matches:%s %s
'     "$(_cmd_agent_color yellow)"     "$(_cmd_agent_color reset)"     "$pretty_matches" >&2
  printf '%s' "$line"
}

_cmd_agent_readline_complete() {
  local updated
  updated="$(_cmd_agent_complete_line "${READLINE_LINE:-}")"
  READLINE_LINE="$updated"
  READLINE_POINT="${#READLINE_LINE}"
}

_cmd_agent_enable_readline_completion() {
  bind 'set show-all-if-ambiguous on' 2>/dev/null || true
  bind 'set completion-ignore-case on' 2>/dev/null || true
  bind -x '"	":_cmd_agent_readline_complete' 2>/dev/null || true
}

_cmd_agent_prompt_label() {
  local agent_id="${1:-main}"
  local model provider
  model="$(_cmd_agent_current_model "$agent_id")"
  provider="$(_cmd_agent_current_provider "$agent_id")"
  printf 'You[%s@%s]' "$model" "$provider"
}

_cmd_agent_prompt() {
  local agent_id="${1:-main}"
  printf '%s%s%s › ' "$(_cmd_agent_color blue)" "$(_cmd_agent_prompt_label "$agent_id")" "$(_cmd_agent_color reset)"
}

_cmd_agent_collect_block_input() {
  local terminator="$1"
  local lines="" line

  while true; do
    printf '%s...%s ' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)" >&2
    if ! IFS= read -r line; then
      printf '
' >&2
      break
    fi
    if [[ "$line" == "$terminator" ]]; then
      break
    fi
    if [[ -n "$lines" ]]; then
      lines="${lines}"$'
'
    fi
    lines="${lines}${line}"
  done

  printf '%s' "$lines"
}

_cmd_agent_collect_multiline() {
  _cmd_agent_collect_block_input '/end'
}

_cmd_agent_collect_editor_input() {
  local editor="${VISUAL:-${EDITOR:-}}"
  local tmp_file content

  if [[ -z "$editor" ]]; then
    printf '%sNo editor configured.%s Set EDITOR or VISUAL first.

'       "$(_cmd_agent_color red)"       "$(_cmd_agent_color reset)" >&2
    return 1
  fi

  tmp_file="$(mktemp "${TMPDIR:-${BASHCLAW_STATE_DIR}}/bashclaw-agent-edit.XXXXXX")" || return 1
  cat > "$tmp_file" <<'EOF'
# Write your message below.
# Lines starting with # are ignored.
EOF

  if ! eval "$editor "$tmp_file""; then
    rm -f "$tmp_file"
    printf '%sEditor exited without saving input.%s

'       "$(_cmd_agent_color red)"       "$(_cmd_agent_color reset)" >&2
    return 1
  fi

  content="$(sed '/^#/d' "$tmp_file")"
  rm -f "$tmp_file"
  printf '%s' "$content"
}

_cmd_agent_print_models() {
  local prefix="${1:-}"
  local matches

  if [[ -n "$prefix" ]]; then
    matches="$(_model_complete_prefix "$prefix")"
  else
    matches="$(_model_list_ids)"
  fi

  _cmd_agent_print_rule
  printf '%sModels%s
' "$(_cmd_agent_color yellow)" "$(_cmd_agent_color reset)"
  if [[ -z "$matches" ]]; then
    printf '  [no matches]

'
    return
  fi
  printf '%s
' "$matches" | sed 's/^/  /'
  printf '
'
}

_cmd_agent_json_string() {
  jq -Rn --arg value "$1" '$value'
}

_cmd_agent_apply_setting() {
  local key="$1"
  local value="$2"
  local resolved bool_value

  case "$key" in
    notify)
      case "$value" in
        on|true|1|yes)
          bool_value='true'
          ;;
        off|false|0|no)
          bool_value='false'
          ;;
        *)
          printf 'notify expects on/off
' >&2
          return 1
          ;;
      esac
      config_set '.termux.notifyOnAgentResponse' "$bool_value"
      config_load >/dev/null 2>&1 || true
      printf 'notifyOnAgentResponse = %s' "$bool_value"
      ;;
    model|agent.model|default.model)
      resolved="$(_cmd_agent_resolve_model_input "$value")"
      if [[ -z "$resolved" ]]; then
        return 1
      fi
      config_set '.agents.defaults.model' "$(_cmd_agent_json_string "$resolved")"
      config_load >/dev/null 2>&1 || true
      printf 'default model = %s' "$resolved"
      ;;
    tools.profile)
      config_set '.agents.defaults.tools.profile' "$(_cmd_agent_json_string "$value")"
      config_load >/dev/null 2>&1 || true
      printf 'tools.profile = %s' "$value"
      ;;
    session.maxHistory|session.idleResetMinutes)
      if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s expects an integer
' "$key" >&2
        return 1
      fi
      config_set ".${key}" "$value"
      config_load >/dev/null 2>&1 || true
      printf '%s = %s' "$key" "$value"
      ;;
    *)
      printf 'unsupported setting: %s
' "$key" >&2
      return 1
      ;;
  esac
}

_cmd_agent_print_repl_help() {
  _cmd_agent_print_rule
  cat <<'EOF'
REPL commands:
  /help                 Show this help
  /edit                 Open EDITOR or VISUAL for multiline input
  /paste                Enter multiline mode until /end
  :::                   Enter block mode until :::
  /reset                Clear session history
  /history              Show recent session history
  /status               Show agent status
  /model                Show current model override or resolved model
  /model <id>           Set session model override
  /model reset          Clear session model override
  /models [prefix]      List models, optionally filtered by prefix
  /set notify on|off    Persist notifyOnAgentResponse
  /set model <id>       Persist default model in config
  /set tools.profile X  Persist default tool profile
  /set session.maxHistory N
  /set session.idleResetMinutes N
  /quit                 Exit interactive mode
EOF
  printf '
'
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
    _cmd_agent_enable_readline_completion
    if [[ -f "$_history_file" ]]; then
      history -r "$_history_file" 2>/dev/null || true
    fi
  fi

  while true; do
    local input response
    if [[ "$_use_readline" == "true" ]]; then
      if ! IFS= read -e -r -p "$(_cmd_agent_prompt "$agent_id")" input; then
        printf '
'
        break
      fi
    else
      _cmd_agent_prompt "$agent_id"
      if ! IFS= read -r input; then
        printf '
'
        break
      fi
    fi

    input="$(trim "$input")"
    if [[ -z "$input" ]]; then
      continue
    fi

    case "$input" in
      /help)
        _cmd_agent_print_repl_help
        continue
        ;;
      :::)
        _cmd_agent_print_rule
        printf '%sBlock mode:%s finish with ::: on its own line.

' "$(_cmd_agent_color yellow)" "$(_cmd_agent_color reset)"
        input="$(_cmd_agent_collect_block_input ':::')"
        input="$(trim "$input")"
        if [[ -z "$input" ]]; then
          continue
        fi
        ;;
      /paste)
        _cmd_agent_print_rule
        printf '%sPaste mode:%s finish with /end on its own line.

' "$(_cmd_agent_color yellow)" "$(_cmd_agent_color reset)"
        input="$(_cmd_agent_collect_multiline)"
        input="$(trim "$input")"
        if [[ -z "$input" ]]; then
          continue
        fi
        ;;
      /edit)
        input="$(_cmd_agent_collect_editor_input)" || continue
        input="$(trim "$input")"
        if [[ -z "$input" ]]; then
          continue
        fi
        ;;
      /reset)
        session_clear "$sess_file"
        _cmd_agent_print_rule
        printf '%sSession reset.%s

' "$(_cmd_agent_color yellow)" "$(_cmd_agent_color reset)"
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
        printf '%sCurrent model:%s %s

'           "$(_cmd_agent_color yellow)"           "$(_cmd_agent_color reset)"           "$(_cmd_agent_current_model "$agent_id")"
        continue
        ;;
      /model\ reset|/model\ clear|/model\ default)
        _cmd_agent_set_model_override reset
        _cmd_agent_print_rule
        printf '%sModel override cleared.%s

'           "$(_cmd_agent_color green)"           "$(_cmd_agent_color reset)"
        continue
        ;;
      /model\ *)
        local new_model resolved_model
        new_model="${input#/model }"
        new_model="$(trim "$new_model")"
        if [[ -z "$new_model" ]]; then
          _cmd_agent_print_rule
          printf '%sUsage:%s /model <model_id>

'             "$(_cmd_agent_color red)"             "$(_cmd_agent_color reset)"
          continue
        fi
        resolved_model="$(_cmd_agent_resolve_model_input "$new_model")"
        if [[ -z "$resolved_model" ]]; then
          continue
        fi
        _cmd_agent_set_model_override "$resolved_model"
        _cmd_agent_print_rule
        printf '%sModel override set:%s %s

'           "$(_cmd_agent_color green)"           "$(_cmd_agent_color reset)"           "$resolved_model"
        continue
        ;;
      /models)
        _cmd_agent_print_models
        continue
        ;;
      /models\ *)
        _cmd_agent_print_models "$(trim "${input#/models }")"
        continue
        ;;
      /set\ *)
        local set_args set_key set_value set_result
        set_args="$(trim "${input#/set }")"
        set_key="${set_args%% *}"
        set_value="$(trim "${set_args#"$set_key"}")"
        if [[ -z "$set_key" || -z "$set_value" ]]; then
          _cmd_agent_print_rule
          printf '%sUsage:%s /set <key> <value>

'             "$(_cmd_agent_color red)"             "$(_cmd_agent_color reset)"
          continue
        fi
        set_result="$(_cmd_agent_apply_setting "$set_key" "$set_value")" || continue
        _cmd_agent_print_rule
        printf '%sSetting updated:%s %s

'           "$(_cmd_agent_color green)"           "$(_cmd_agent_color reset)"           "$set_result"
        continue
        ;;
      /quit|/exit|/q)
        printf '%sGoodbye.%s
' "$(_cmd_agent_color dim)" "$(_cmd_agent_color reset)"
        break
        ;;
      /*)
        _cmd_agent_print_rule
        printf '%sUnknown command:%s %s

' "$(_cmd_agent_color red)" "$(_cmd_agent_color reset)" "$input"
        continue
        ;;
    esac

    if [[ "$_use_readline" == "true" ]]; then
      history -s "$input" 2>/dev/null || true
      history -a "$_history_file" 2>/dev/null || true
    fi

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
  /help                 Show REPL command help
  /edit                 Open EDITOR or VISUAL for multiline input
  /paste                Enter multiline mode until /end
  :::                   Enter block mode until :::
  /reset                Clear session history
  /history              Show recent session history
  /status               Show agent status
  /model                Show current model, set /model <id>, reset /model reset
  /models [prefix]      List models, optionally filtered by prefix
  /set <key> <value>    Persist a supported config value
  /quit                 Exit interactive mode
EOF
}
