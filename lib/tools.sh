#!/usr/bin/env bash
# Tool system for BashClaw
# Compatible with bash 3.2+ (no associative arrays)
# Supports file tools, session isolation, optional tools, and elevated checks.

TOOL_WEB_FETCH_MAX_CHARS="${TOOL_WEB_FETCH_MAX_CHARS:-102400}"
TOOL_SHELL_TIMEOUT="${TOOL_SHELL_TIMEOUT:-30}"
TOOL_READ_FILE_MAX_LINES="${TOOL_READ_FILE_MAX_LINES:-2000}"
TOOL_LIST_FILES_MAX="${TOOL_LIST_FILES_MAX:-500}"

# ---- Tool Profiles ----
# Named presets of tool sets. Profile is applied first, then allow/deny modify it.

tools_resolve_profile() {
  local profile_name="${1:-full}"
  case "$profile_name" in
    minimal)
      echo "web_fetch web_search memory session_status"
      ;;
    coding)
      echo "web_fetch web_search memory session_status shell read_file write_file list_files file_search"
      ;;
    messaging)
      echo "web_fetch web_search memory session_status message agent_message agents_list"
      ;;
    termux-operator)
      echo "memory read_file write_file list_files file_search termux_notify termux_clipboard termux_battery termux_wifi termux_location termux_telephony termux_camera termux_open termux_sensor termux_brightness termux_volume termux_torch termux_vibrate termux_wakelock termux_recipe"
      ;;
    full|"")
      _tool_list
      ;;
    *)
      _tool_list
      ;;
  esac
}

# ---- Tool Registry (function-based for bash 3.2 compat) ----

_tool_handler() {
  case "$1" in
    web_fetch)      echo "tool_web_fetch" ;;
    web_search)     echo "tool_web_search" ;;
    shell)          echo "tool_shell" ;;
    memory)         echo "tool_memory" ;;
    cron)           echo "tool_cron" ;;
    message)        echo "tool_message" ;;
    agents_list)    echo "tool_agents_list" ;;
    session_status) echo "tool_session_status" ;;
    sessions_list)  echo "tool_sessions_list" ;;
    agent_message)  echo "tool_agent_message" ;;
    read_file)      echo "tool_read_file" ;;
    write_file)     echo "tool_write_file" ;;
    list_files)     echo "tool_list_files" ;;
    file_search)    echo "tool_file_search" ;;
    termux_notify)  echo "tool_termux_notify" ;;
    termux_clipboard) echo "tool_termux_clipboard" ;;
    termux_battery) echo "tool_termux_battery" ;;
    termux_wifi)    echo "tool_termux_wifi" ;;
    termux_location) echo "tool_termux_location" ;;
    termux_telephony) echo "tool_termux_telephony" ;;
    termux_camera)  echo "tool_termux_camera" ;;
    termux_open)    echo "tool_termux_open" ;;
    termux_sensor)   echo "tool_termux_sensor" ;;
    termux_brightness) echo "tool_termux_brightness" ;;
    termux_volume)   echo "tool_termux_volume" ;;
    termux_torch)    echo "tool_termux_torch" ;;
    termux_vibrate)  echo "tool_termux_vibrate" ;;
    termux_wakelock) echo "tool_termux_wakelock" ;;
    termux_recipe)  echo "tool_termux_recipe" ;;
    spawn)          echo "tool_spawn" ;;
    spawn_status)   echo "tool_spawn_status" ;;
    *)
      # Check plugin-registered tools as fallback
      local plugin_handler
      plugin_handler="$(plugin_tool_handler "$1" 2>/dev/null)"
      if [[ -n "$plugin_handler" ]]; then
        echo "$plugin_handler"
      fi
      ;;
  esac
}

_tool_list() {
  echo "web_fetch web_search shell memory cron message agents_list session_status sessions_list agent_message read_file write_file list_files file_search termux_notify termux_clipboard termux_battery termux_wifi termux_location termux_telephony termux_camera termux_open termux_sensor termux_brightness termux_volume termux_torch termux_vibrate termux_wakelock termux_recipe spawn spawn_status"
}

# Tool optional flag registry (tools that default to disabled unless explicitly allowed).
# Returns 0 if the tool is optional, 1 otherwise.
_tool_is_optional() {
  case "$1" in
    shell|write_file)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# Elevated operations that require authorization.
# Returns the elevation level: "none", "elevated", "dangerous"
_tool_elevation_level() {
  case "$1" in
    shell)      echo "elevated" ;;
    write_file) echo "elevated" ;;
    *)          echo "none" ;;
  esac
}

# ---- SSRF private IP patterns ----

_ssrf_is_private_pattern() {
  local addr="$1"
  case "$addr" in
    10.*)            return 0 ;;
    172.1[6-9].*)    return 0 ;;
    172.2[0-9].*)    return 0 ;;
    172.3[01].*)     return 0 ;;
    192.168.*)       return 0 ;;
    127.*)           return 0 ;;
    0.*)             return 0 ;;
    169.254.*)       return 0 ;;
    localhost)       return 0 ;;
    metadata.google.internal) return 0 ;;
    ::1)             return 0 ;;
    fe80:*)          return 0 ;;
    fc*)             return 0 ;;
    fd*)             return 0 ;;
    *)               return 1 ;;
  esac
}

# ---- Dangerous shell patterns ----

_shell_is_dangerous() {
  local cmd="$1"
  case "$cmd" in
    *"rm -rf /"*)       return 0 ;;
    *"rm -rf /*"*)      return 0 ;;
    *"mkfs"*)           return 0 ;;
    *"dd if="*)         return 0 ;;
    *"> /dev/sd"*)      return 0 ;;
    *"chmod -R 777 /"*) return 0 ;;
    *":(){:|:&};:"*)    return 0 ;;
    *)                  return 1 ;;
  esac
}

# ---- Tool Dispatch ----

# Execute a tool with optional session isolation and security checks.
# Usage: tool_execute TOOL_NAME TOOL_INPUT [SESSION_KEY]
tool_execute() {
  local tool_name="$1"
  local tool_input="$2"
  local session_key="${3:-}"

  local handler
  handler="$(_tool_handler "$tool_name")"
  if [[ -z "$handler" ]]; then
    log_error "Unknown tool: $tool_name"
    printf '{"error": "unknown tool: %s"}' "$tool_name"
    return 1
  fi

  # Elevated check for dangerous tools
  local elevation
  elevation="$(_tool_elevation_level "$tool_name")"
  if [[ "$elevation" != "none" ]]; then
    if ! tools_elevated_check "$tool_name" "$session_key"; then
      log_warn "Elevated tool blocked: $tool_name session=$session_key"
      printf '{"error": "elevated tool requires authorization", "tool": "%s"}' "$tool_name"
      return 1
    fi
  fi

  # Export session context for tools that need isolation
  local prev_session_key="${BASHCLAW_TOOL_SESSION_KEY:-}"
  if [[ -n "$session_key" ]]; then
    BASHCLAW_TOOL_SESSION_KEY="$session_key"
  fi

  log_debug "Executing tool: $tool_name session=$session_key"
  local result
  result="$("$handler" "$tool_input")"
  local rc=$?

  # Restore previous session context
  BASHCLAW_TOOL_SESSION_KEY="$prev_session_key"

  printf '%s' "$result"
  return $rc
}

# Check if a tool should be included in the tool spec for a given context.
# Handles optional tools and allow/deny filtering.
# Usage: tools_is_available TOOL_NAME [ALLOW_LIST_JSON] [DENY_LIST_JSON]
tools_is_available() {
  local tool_name="${1:?tool name required}"
  local allow_json="${2:-[]}"
  local deny_json="${3:-[]}"

  require_command jq "tools_is_available requires jq"

  # Check deny list first
  if [[ "$deny_json" != "[]" ]]; then
    local in_deny
    in_deny="$(printf '%s' "$deny_json" | jq --arg t "$tool_name" '[.[] | select(. == $t)] | length')"
    if [[ "$in_deny" -gt 0 ]]; then
      return 1
    fi
  fi

  # If tool is optional, it must be explicitly in the allow list
  if _tool_is_optional "$tool_name"; then
    if [[ "$allow_json" == "[]" ]]; then
      return 1
    fi
    local in_allow
    in_allow="$(printf '%s' "$allow_json" | jq --arg t "$tool_name" '[.[] | select(. == $t)] | length')"
    if [[ "$in_allow" -eq 0 ]]; then
      return 1
    fi
  fi

  # If allow list is non-empty and tool is not optional, check it
  if [[ "$allow_json" != "[]" ]]; then
    local in_allow
    in_allow="$(printf '%s' "$allow_json" | jq --arg t "$tool_name" '[.[] | select(. == $t)] | length')"
    if [[ "$in_allow" -eq 0 ]]; then
      return 1
    fi
  fi

  return 0
}

# Check if a tool requiring elevated authorization is permitted.
# Returns 0 if allowed, 1 if blocked.
# Usage: tools_elevated_check TOOL_NAME [SESSION_KEY]
tools_elevated_check() {
  local tool_name="${1:?tool name required}"
  local session_key="${2:-}"

  local elevation
  elevation="$(_tool_elevation_level "$tool_name")"

  if [[ "$elevation" == "none" ]]; then
    return 0
  fi

  # Check if tool is explicitly allowed in config
  local elevated_allow
  elevated_allow="$(config_get_raw '.security.elevatedTools // []' 2>/dev/null)"
  if [[ -n "$elevated_allow" && "$elevated_allow" != "[]" ]]; then
    local in_allow
    in_allow="$(printf '%s' "$elevated_allow" | jq --arg t "$tool_name" '[.[] | select(. == $t)] | length' 2>/dev/null)"
    if [[ "$in_allow" -gt 0 ]]; then
      return 0
    fi
  fi

  # Check approval file for this session
  if [[ -n "$session_key" ]]; then
    local approval_dir="${BASHCLAW_STATE_DIR:?}/approvals"
    local safe_key
    safe_key="$(sanitize_key "$session_key")"
    local approval_file="${approval_dir}/${safe_key}_${tool_name}.approved"
    if [[ -f "$approval_file" ]]; then
      return 0
    fi
  fi

  # Default: elevated tools in "dangerous" category are blocked
  if [[ "$elevation" == "dangerous" ]]; then
    return 1
  fi

  # "elevated" tools are allowed by default but logged
  log_info "Elevated tool execution: $tool_name session=$session_key"
  return 0
}

# ---- Tool Descriptions ----

tools_describe_all() {
  cat <<'TOOLDESC'
Available tools:

1. web_fetch - Fetch and extract readable content from a URL.
   Parameters: url (string, required), maxChars (number, optional)

2. web_search - Search the web using Brave Search or Perplexity.
   Parameters: query (string, required), count (number, optional, 1-10)

3. shell - Execute a shell command with timeout and safety checks. [optional]
   Parameters: command (string, required), timeout (number, optional)

4. memory - File-based key-value store for persistent memory.
   Parameters: action (get|set|delete|list|search, required), key (string), value (string), query (string)

5. cron - Manage scheduled jobs.
   Parameters: action (add|remove|list, required), id (string), schedule (string), command (string)

6. message - Send a message via the configured channel handler.
   Parameters: action (send, required), channel (string), target (string), message (string, required)

7. agents_list - List all configured agents with their settings.
   Parameters: none

8. session_status - Query session info for the current agent.
   Parameters: agent_id (string), channel (string), sender (string)

9. sessions_list - List all active sessions across all agents.
   Parameters: none

10. agent_message - Send a message to another agent.
    Parameters: target_agent (string, required), message (string, required), from_agent (string, optional)

11. read_file - Read a file with optional line offset and limit.
    Parameters: path (string, required), offset (number, optional), limit (number, optional)

12. write_file - Create or overwrite a file. [optional, elevated]
    Parameters: path (string, required), content (string, required), append (boolean, optional)

13. list_files - List files in a directory with optional pattern filtering.
    Parameters: path (string, required), pattern (string, optional), recursive (boolean, optional)

14. file_search - Search for files matching a name or content pattern.
    Parameters: path (string, required), name (string, optional), content (string, optional), maxResults (number, optional)

15. termux_notify - Send a Termux notification or toast.
    Parameters: title (string), message (string, required), type (notification|toast, optional)

16. termux_clipboard - Read from or write to the Termux clipboard.
    Parameters: action (get|set, required), text (string)

17. termux_battery - Read battery status from Termux API.
    Parameters: none

18. termux_wifi - Read wifi connection details from Termux API.
    Parameters: none

19. termux_location - Read location details from Termux API.
    Parameters: provider (gps|network|passive, optional), request (once|last, optional)

20. termux_telephony - Read telephony and carrier details from Termux API.
    Parameters: none

21. termux_camera - Capture a photo with Termux API.
    Parameters: path (string, optional), cameraId (number, optional)

22. termux_open - Open or share a URL, file, or text through Android intents.
    Parameters: target (string, required), action (open|share, optional)

22. termux_sensor - Read device sensors (accelerometer, gyroscope, light, etc.).
   Parameters: sensor (string, optional), delay (number, optional)

23. termux_brightness - Get or set screen brightness.
   Parameters: brightness (number 0-255 or "auto", optional)

24. termux_volume - Get or set media volume.
   Parameters: stream (string, optional), volume (number, optional)

25. termux_torch - Control device flashlight.
   Parameters: state (on|off|toggle, optional)

26. termux_vibrate - Trigger device vibration.
   Parameters: duration (number, optional), force (boolean, optional)

27. termux_wakelock - Control device wake lock.
   Parameters: action (acquire|release|status, optional)
23. termux_recipe - Run or inspect a built-in Termux workflow recipe.
    Parameters: action (list|describe|run, optional), recipe (battery|downloads|clipboard|connectivity, optional), limit (number, optional), notify (boolean, optional)

24. spawn - Spawn a background subagent for long-running tasks.
    Parameters: task (string, required), label (string, optional)

25. spawn_status - Check status of a spawned background task.
    Parameters: task_id (string, required)
TOOLDESC
}

# Bridge-only tool descriptions for Claude CLI engine.
# Only includes BashClaw-specific tools that are exposed via CLI bridge, not native-mapped ones.
# When agent_id is provided, respects allow/deny tool filtering.
tools_describe_bridge_only() {
  local agent_id="${1:-}"

  local allow_list="[]"
  local deny_list="[]"
  if [[ -n "$agent_id" ]]; then
    local _al _dl
    _al="$(config_agent_get_raw "$agent_id" '.tools.allow // null' 2>/dev/null)"
    _dl="$(config_agent_get_raw "$agent_id" '.tools.deny // null' 2>/dev/null)"
    if [[ -n "$_al" && "$_al" != "null" ]]; then allow_list="$_al"; fi
    if [[ -n "$_dl" && "$_dl" != "null" ]]; then deny_list="$_dl"; fi
  fi

  local header="BashClaw tools (invoke via Bash: bashclaw tool <name> --param value):"
  local descs=""
  local idx=0

  _bridge_tool_desc() {
    local name="$1" desc="$2"
    if [[ -n "$agent_id" ]]; then
      if ! tools_is_available "$name" "$allow_list" "$deny_list" 2>/dev/null; then
        return
      fi
    fi
    idx=$((idx + 1))
    descs="${descs}
${idx}. ${desc}"
  }

  _bridge_tool_desc "memory" "memory - File-based key-value store for persistent memory.
   Params: --action (get|set|delete|list|search) --key <string> --value <string> --query <string>"

  _bridge_tool_desc "cron" "cron - Manage scheduled jobs.
   Params: --action (add|remove|list) --id <string> --schedule <string> --command <string>"

  _bridge_tool_desc "message" "message - Send a message via the configured channel handler.
   Params: --action send --channel <string> --target <string> --message <string>"

  _bridge_tool_desc "agents_list" "agents_list - List all configured agents with their settings.
   Params: none"

  _bridge_tool_desc "session_status" "session_status - Query session info for the current agent.
   Params: --agent_id <string> --channel <string> --sender <string>"

  _bridge_tool_desc "sessions_list" "sessions_list - List all active sessions across all agents.
   Params: none"

  _bridge_tool_desc "agent_message" "agent_message - Send a message to another agent.
   Params: --target_agent <string> --message <string> --from_agent <string>"

  _bridge_tool_desc "termux_notify" "termux_notify - Send a Termux notification or toast.
   Params: --message <string> --title <string> --type <notification|toast>"

  _bridge_tool_desc "termux_clipboard" "termux_clipboard - Read or write the Termux clipboard.
   Params: --action <get|set> --text <string>"

  _bridge_tool_desc "termux_battery" "termux_battery - Read battery status from Termux API.
   Params: none"

  _bridge_tool_desc "termux_wifi" "termux_wifi - Read wifi connection details from Termux API.
   Params: none"

  _bridge_tool_desc "termux_location" "termux_location - Read location details from Termux API.
   Params: --provider <gps|network|passive> --request <once|last>"

  _bridge_tool_desc "termux_telephony" "termux_telephony - Read telephony and carrier details from Termux API.
   Params: none"

  _bridge_tool_desc "termux_camera" "termux_camera - Capture a photo with Termux API.
   Params: --path <string> --cameraId <number>"

  _bridge_tool_desc "termux_open" "termux_open - Open or share text, files, or URLs via Android intents.
   Params: --target <string> --action <open|share>"

  _bridge_tool_desc "termux_sensor" "termux_sensor - Read device sensors (accelerometer, gyroscope, light, etc.). Params: sensor (string, optional), delay (number, optional)"
  _bridge_tool_desc "termux_brightness" "termux_brightness - Get or set screen brightness. Params: brightness (number 0-255 or "auto", optional)"
  _bridge_tool_desc "termux_volume" "termux_volume - Get or set media volume. Params: stream (string, optional), volume (number, optional)"
  _bridge_tool_desc "termux_torch" "termux_torch - Control device flashlight. Params: state (on|off|toggle, optional)"
  _bridge_tool_desc "termux_vibrate" "termux_vibrate - Trigger device vibration. Params: duration (number, optional), force (boolean, optional)"
  _bridge_tool_desc "termux_wakelock" "termux_wakelock - Control device wake lock. Params: action (acquire|release|status, optional)"
  _bridge_tool_desc "termux_recipe" "termux_recipe - Run or inspect a built-in Termux workflow recipe.
   Params: --action <list|describe|run> --recipe <battery|downloads|clipboard|connectivity> --limit <number> --notify <true|false>"

  _bridge_tool_desc "spawn" "spawn - Spawn a background subagent for long-running tasks.
   Params: --task <string> --label <string>"

  _bridge_tool_desc "spawn_status" "spawn_status - Check status of a spawned background task.
   Params: --task_id <string>"

  local footer="
You also have native file, shell, and web tools available directly (Read, Write, Bash, Glob, Grep, WebFetch, WebSearch)."

  if [[ -z "$descs" ]]; then
    printf '%s' "$footer"
  else
    printf '%s\n%s\n%s' "$header" "$descs" "$footer"
  fi
}

# ---- Tool Spec Builder (Anthropic format) ----

tools_build_spec() {
  local profile_name="${1:-}"
  require_command jq "tools_build_spec requires jq"

  # If a profile is specified, filter the full spec to only include profile tools
  local profile_tools=""
  if [[ -n "$profile_name" && "$profile_name" != "full" ]]; then
    profile_tools="$(tools_resolve_profile "$profile_name")"
  fi

  local full_spec
  full_spec="$(_tools_build_full_spec)"

  if [[ -n "$profile_tools" ]]; then
    local profile_json="[]"
    local t
    for t in $profile_tools; do
      profile_json="$(printf '%s' "$profile_json" | jq --arg t "$t" '. + [$t]')"
    done
    printf '%s' "$full_spec" | jq --argjson p "$profile_json" '[.[] | select(.name as $n | $p | index($n))]'
  else
    printf '%s' "$full_spec"
  fi
}

_tools_build_full_spec() {
  jq -nc '[
    {
      "name": "web_fetch",
      "description": "Fetch and extract readable content from a URL. Use for lightweight page access.",
      "input_schema": {
        "type": "object",
        "properties": {
          "url": {"type": "string", "description": "HTTP or HTTPS URL to fetch."},
          "maxChars": {"type": "number", "description": "Maximum characters to return."}
        },
        "required": ["url"]
      }
    },
    {
      "name": "web_search",
      "description": "Search the web. Returns titles, URLs, and snippets.",
      "input_schema": {
        "type": "object",
        "properties": {
          "query": {"type": "string", "description": "Search query string."},
          "count": {"type": "number", "description": "Number of results to return (1-10)."}
        },
        "required": ["query"]
      }
    },
    {
      "name": "shell",
      "description": "Execute a shell command with timeout and safety checks.",
      "input_schema": {
        "type": "object",
        "properties": {
          "command": {"type": "string", "description": "The shell command to execute."},
          "timeout": {"type": "number", "description": "Timeout in seconds (default 30)."}
        },
        "required": ["command"]
      }
    },
    {
      "name": "memory",
      "description": "File-based key-value store for persistent agent memory. Supports get, set, delete, list, and search actions.",
      "input_schema": {
        "type": "object",
        "properties": {
          "action": {"type": "string", "enum": ["get", "set", "delete", "list", "search"], "description": "The memory operation to perform."},
          "key": {"type": "string", "description": "The key to get, set, or delete."},
          "value": {"type": "string", "description": "The value to store (for set action)."},
          "query": {"type": "string", "description": "Search query (for search action)."}
        },
        "required": ["action"]
      }
    },
    {
      "name": "cron",
      "description": "Manage scheduled cron jobs. Supports add, remove, and list actions.",
      "input_schema": {
        "type": "object",
        "properties": {
          "action": {"type": "string", "enum": ["add", "remove", "list"], "description": "The cron operation to perform."},
          "id": {"type": "string", "description": "Job ID (for remove)."},
          "schedule": {"type": "string", "description": "Cron schedule expression (for add)."},
          "command": {"type": "string", "description": "Command to execute (for add)."},
          "agent_id": {"type": "string", "description": "Agent ID for the job."}
        },
        "required": ["action"]
      }
    },
    {
      "name": "message",
      "description": "Send a message via channel handler.",
      "input_schema": {
        "type": "object",
        "properties": {
          "action": {"type": "string", "enum": ["send"], "description": "Message action."},
          "channel": {"type": "string", "description": "Target channel (telegram, discord, slack, etc)."},
          "target": {"type": "string", "description": "Target chat/user ID."},
          "message": {"type": "string", "description": "The message text to send."}
        },
        "required": ["action", "message"]
      }
    },
    {
      "name": "agents_list",
      "description": "List all configured agents with their settings.",
      "input_schema": {
        "type": "object",
        "properties": {},
        "required": []
      }
    },
    {
      "name": "session_status",
      "description": "Query session info for a specific agent, channel, and sender.",
      "input_schema": {
        "type": "object",
        "properties": {
          "agent_id": {"type": "string", "description": "Agent ID to query."},
          "channel": {"type": "string", "description": "Channel name."},
          "sender": {"type": "string", "description": "Sender identifier."}
        },
        "required": []
      }
    },
    {
      "name": "sessions_list",
      "description": "List all active sessions across all agents.",
      "input_schema": {
        "type": "object",
        "properties": {},
        "required": []
      }
    },
    {
      "name": "agent_message",
      "description": "Send a message to another agent and get their response.",
      "input_schema": {
        "type": "object",
        "properties": {
          "target_agent": {"type": "string", "description": "The agent ID to send the message to."},
          "message": {"type": "string", "description": "The message to send."},
          "from_agent": {"type": "string", "description": "The sending agent ID (optional)."}
        },
        "required": ["target_agent", "message"]
      }
    },
    {
      "name": "read_file",
      "description": "Read a file from the filesystem with optional line offset and limit.",
      "input_schema": {
        "type": "object",
        "properties": {
          "path": {"type": "string", "description": "Absolute or relative file path to read."},
          "offset": {"type": "number", "description": "Line number to start reading from (1-based, default 1)."},
          "limit": {"type": "number", "description": "Maximum number of lines to return."}
        },
        "required": ["path"]
      }
    },
    {
      "name": "write_file",
      "description": "Create or overwrite a file on the filesystem. Requires elevated authorization.",
      "input_schema": {
        "type": "object",
        "properties": {
          "path": {"type": "string", "description": "Absolute or relative file path to write."},
          "content": {"type": "string", "description": "The content to write to the file."},
          "append": {"type": "boolean", "description": "If true, append to the file instead of overwriting."}
        },
        "required": ["path", "content"]
      }
    },
    {
      "name": "list_files",
      "description": "List files and directories at a given path.",
      "input_schema": {
        "type": "object",
        "properties": {
          "path": {"type": "string", "description": "Directory path to list."},
          "pattern": {"type": "string", "description": "Glob pattern to filter results (e.g. *.sh)."},
          "recursive": {"type": "boolean", "description": "If true, list recursively."}
        },
        "required": ["path"]
      }
    },
    {
      "name": "file_search",
      "description": "Search for files by name pattern or content match.",
      "input_schema": {
        "type": "object",
        "properties": {
          "path": {"type": "string", "description": "Directory to search in."},
          "name": {"type": "string", "description": "Filename pattern to match (glob)."},
          "content": {"type": "string", "description": "Search for files containing this text."},
          "maxResults": {"type": "number", "description": "Maximum number of results to return."}
        },
        "required": ["path"]
      }
    },
    {
      "name": "termux_notify",
      "description": "Send a Termux notification or toast when running in a Termux environment.",
      "input_schema": {
        "type": "object",
        "properties": {
          "title": {"type": "string", "description": "Notification title."},
          "message": {"type": "string", "description": "Notification body text."},
          "type": {"type": "string", "enum": ["notification", "toast"], "description": "Send a full notification or a toast."}
        },
        "required": ["message"]
      }
    },
    {
      "name": "termux_clipboard",
      "description": "Read from or write to the Termux clipboard.",
      "input_schema": {
        "type": "object",
        "properties": {
          "action": {"type": "string", "enum": ["get", "set"], "description": "Clipboard action to perform."},
          "text": {"type": "string", "description": "Clipboard text to write for set action."}
        },
        "required": ["action"]
      }
    },
    {
      "name": "termux_battery",
      "description": "Read battery status using the Termux battery API.",
      "input_schema": {
        "type": "object",
        "properties": {},
        "required": []
      }
    },
    {
      "name": "termux_wifi",
      "description": "Read wifi connection details using the Termux wifi API.",
      "input_schema": {
        "type": "object",
        "properties": {},
        "required": []
      }
    },
    {
      "name": "termux_location",
      "description": "Read device location using the Termux location API.",
      "input_schema": {
        "type": "object",
        "properties": {
          "provider": {"type": "string", "enum": ["gps", "network", "passive"], "description": "Preferred location provider."},
          "request": {"type": "string", "enum": ["once", "last"], "description": "Whether to request a fresh reading or last known location."}
        },
        "required": []
      }
    },
    {
      "name": "termux_telephony",
      "description": "Read telephony and carrier information using the Termux telephony API.",
      "input_schema": {
        "type": "object",
        "properties": {},
        "required": []
      }
    },
    {
      "name": "termux_camera",
      "description": "Capture a photo using the Termux camera API.",
      "input_schema": {
        "type": "object",
        "properties": {
          "path": {"type": "string", "description": "Output path for the captured photo. Defaults to the writable Termux temp area."},
          "cameraId": {"type": "number", "description": "Camera ID to use, such as 0 for rear or 1 for front."}
        },
        "required": []
      }
    },
    {
      "name": "termux_open",
      "description": "Open or share a URL, file path, or text using Termux Android intents.",
      "input_schema": {
        "type": "object",
        "properties": {
          "target": {"type": "string", "description": "URL, file path, or text payload."},
          "action": {"type": "string", "enum": ["open", "share"], "description": "Whether to open or share the target."}
        },
        "required": ["target"]
      }
    },
    {
      "name": "termux_recipe",
      "description": "Run or inspect built-in Termux workflow recipes for battery, downloads, clipboard, and connectivity.",
      "input_schema": {
        "type": "object",
        "properties": {
          "action": {"type": "string", "enum": ["list", "describe", "run"], "description": "Whether to list recipes, describe one, or run one."},
          "recipe": {"type": "string", "enum": ["battery", "downloads", "clipboard", "connectivity"], "description": "Recipe name to describe or run."},
          "limit": {"type": "number", "description": "Maximum number of items to return for downloads."},
          "notify": {"type": "boolean", "description": "Send a Termux notification for recipes that support it."}
        },
        "required": []
      }
    },
    {
      "name": "spawn",
      "description": "Spawn a background subagent for long-running tasks. Returns immediately with a task ID.",
      "input_schema": {
        "type": "object",
        "properties": {
          "task": {"type": "string", "description": "Task description for the subagent."},
          "label": {"type": "string", "description": "Short label for the task."}
        },
        "required": ["task"]
      }
    },
    {
      "name": "spawn_status",
      "description": "Check status of a spawned background task.",
      "input_schema": {
        "type": "object",
        "properties": {
          "task_id": {"type": "string", "description": "Task ID from spawn."}
        },
        "required": ["task_id"]
      }
    }
  ]'
}

# ---- Tool: web_fetch ----

tool_web_fetch() {
  local input="$1"
  require_command curl "web_fetch requires curl"
  require_command jq "web_fetch requires jq"

  local url max_chars
  url="$(printf '%s' "$input" | jq -r '.url // empty')"
  max_chars="$(printf '%s' "$input" | jq -r '.maxChars // empty')"
  max_chars="${max_chars:-$TOOL_WEB_FETCH_MAX_CHARS}"

  if [[ -z "$url" ]]; then
    printf '{"error": "url parameter is required"}'
    return 1
  fi

  if [[ "$url" != http://* && "$url" != https://* ]]; then
    printf '{"error": "URL must use http or https protocol"}'
    return 1
  fi

  # SSRF protection: extract hostname
  local hostname
  hostname="$(printf '%s' "$url" | sed -E 's|^https?://||' | sed -E 's|[:/].*||' | tr '[:upper:]' '[:lower:]')"

  if _ssrf_is_blocked "$hostname"; then
    printf '{"error": "SSRF blocked: request to private/internal address denied"}'
    return 1
  fi

  local response_file
  response_file="$(tmpfile "web_fetch")"

  local http_code
  http_code="$(curl -sS -L --max-redirs 5 --max-time 30 \
    -o "$response_file" -w '%{http_code}' \
    -H 'Accept: text/markdown, text/html;q=0.9, */*;q=0.1' \
    -H 'User-Agent: Mozilla/5.0 (compatible; bashclaw/1.0)' \
    "$url" 2>/dev/null)" || {
    printf '{"error": "fetch failed", "url": "%s"}' "$url"
    return 1
  }

  if [[ "$http_code" -ge 400 ]]; then
    local error_body
    error_body="$(head -c 4000 "$response_file" 2>/dev/null || true)"
    jq -nc --arg url "$url" --arg code "$http_code" --arg body "$error_body" \
      '{error: "HTTP error", status: ($code | tonumber), url: $url, detail: $body}'
    return 1
  fi

  local body
  body="$(head -c "$max_chars" "$response_file" 2>/dev/null || true)"
  local body_len
  body_len="$(file_size_bytes "$response_file")"
  local truncated="false"
  if [ "$body_len" -gt "$max_chars" ]; then
    truncated="true"
  fi

  jq -nc \
    --arg url "$url" \
    --arg status "$http_code" \
    --arg text "$body" \
    --arg trunc "$truncated" \
    --arg len "$body_len" \
    '{url: $url, status: ($status | tonumber), text: $text, truncated: ($trunc == "true"), length: ($len | tonumber)}'
}

# ---- Tool: web_search ----

tool_web_search() {
  local input="$1"
  require_command curl "web_search requires curl"
  require_command jq "web_search requires jq"

  local query count
  query="$(printf '%s' "$input" | jq -r '.query // empty')"
  count="$(printf '%s' "$input" | jq -r '.count // empty')"
  count="${count:-5}"

  if [[ -z "$query" ]]; then
    printf '{"error": "query parameter is required"}'
    return 1
  fi

  if [ "$count" -lt 1 ] 2>/dev/null; then count=1; fi
  if [ "$count" -gt 10 ] 2>/dev/null; then count=10; fi

  local api_key="${BRAVE_SEARCH_API_KEY:-}"
  if [[ -n "$api_key" ]]; then
    _web_search_brave "$query" "$count" "$api_key"
    return $?
  fi

  local perplexity_key="${PERPLEXITY_API_KEY:-}"
  if [[ -n "$perplexity_key" ]]; then
    _web_search_perplexity "$query" "$perplexity_key"
    return $?
  fi

  printf '{"error": "No search API key configured. Set BRAVE_SEARCH_API_KEY or PERPLEXITY_API_KEY."}'
  return 1
}

_web_search_brave() {
  local query="$1"
  local count="$2"
  local api_key="$3"

  local encoded_query
  encoded_query="$(url_encode "$query")"

  local response
  response="$(curl -sS --max-time 15 \
    -H "Accept: application/json" \
    -H "X-Subscription-Token: ${api_key}" \
    "https://api.search.brave.com/res/v1/web/search?q=${encoded_query}&count=${count}" 2>/dev/null)"

  if [[ $? -ne 0 || -z "$response" ]]; then
    printf '{"error": "Brave Search API request failed"}'
    return 1
  fi

  printf '%s' "$response" | jq '{
    query: .query.original,
    provider: "brave",
    results: [(.web.results // [])[:10][] | {
      title: .title,
      url: .url,
      description: .description,
      published: .age
    }]
  }'
}

_web_search_perplexity() {
  local query="$1"
  local api_key="$2"

  local base_url="${PERPLEXITY_BASE_URL:-https://api.perplexity.ai}"
  local model="${PERPLEXITY_MODEL:-sonar-pro}"

  local body
  body="$(jq -nc --arg q "$query" --arg m "$model" '{
    model: $m,
    messages: [{role: "user", content: $q}]
  }')"

  local response
  response="$(curl -sS --max-time 30 \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${api_key}" \
    -d "$body" \
    "${base_url}/chat/completions" 2>/dev/null)"

  if [[ $? -ne 0 || -z "$response" ]]; then
    printf '{"error": "Perplexity API request failed"}'
    return 1
  fi

  local safe_query
  safe_query="$(printf '%s' "$query" | jq -Rs '.')"
  printf '%s' "$response" | jq --arg q "$query" '{
    query: $q,
    provider: "perplexity",
    content: (.choices[0].message.content // "No response"),
    citations: (.citations // [])
  }'
}

# ---- Tool: shell ----

tool_shell() {
  local input="$1"
  require_command jq "shell tool requires jq"

  local cmd timeout_val
  cmd="$(printf '%s' "$input" | jq -r '.command // empty')"
  timeout_val="$(printf '%s' "$input" | jq -r '.timeout // empty')"
  timeout_val="${timeout_val:-$TOOL_SHELL_TIMEOUT}"

  if [[ -z "$cmd" ]]; then
    printf '{"error": "command parameter is required"}'
    return 1
  fi

  if _shell_is_dangerous "$cmd"; then
    log_warn "Shell tool blocked dangerous command: $cmd"
    printf '{"error": "blocked", "reason": "dangerous command pattern detected"}'
    return 1
  fi

  local output exit_code
  if is_command_available timeout; then
    output="$(timeout "$timeout_val" bash -c "$cmd" 2>&1)" || true
  elif is_command_available gtimeout; then
    output="$(gtimeout "$timeout_val" bash -c "$cmd" 2>&1)" || true
  else
    # Pure-bash timeout fallback (macOS/Termux)
    local _tmpout
    _tmpout="$(tmpfile "bashclaw_sh")"
    bash -c "$cmd" > "$_tmpout" 2>&1 &
    local _pid=$!
    local _waited=0
    while kill -0 "$_pid" 2>/dev/null && (( _waited < timeout_val )); do
      sleep 1
      _waited=$((_waited + 1))
    done
    if kill -0 "$_pid" 2>/dev/null; then
      kill -9 "$_pid" 2>/dev/null
      wait "$_pid" 2>/dev/null || true
      output="[command timed out after ${timeout_val}s]"
    else
      wait "$_pid" 2>/dev/null || true
      output="$(cat "$_tmpout")"
    fi
    rm -f "$_tmpout"
  fi
  exit_code=$?

  # Truncate output to 100KB
  if [ "${#output}" -gt 102400 ]; then
    output="${output:0:102400}... [truncated]"
  fi

  jq -nc --arg out "$output" --arg code "$exit_code" \
    '{output: $out, exitCode: ($code | tonumber)}'
}

# ---- Tool: memory ----

tool_memory() {
  local input="$1"
  require_command jq "memory tool requires jq"

  local action key value query_str
  action="$(printf '%s' "$input" | jq -r '.action // empty')"
  key="$(printf '%s' "$input" | jq -r '.key // empty')"
  value="$(printf '%s' "$input" | jq -r '.value // empty')"
  query_str="$(printf '%s' "$input" | jq -r '.query // empty')"

  local mem_dir="${BASHCLAW_STATE_DIR:?BASHCLAW_STATE_DIR not set}/memory"
  ensure_dir "$mem_dir"

  case "$action" in
    get)
      if [[ -z "$key" ]]; then
        printf '{"error": "key is required for get"}'
        return 1
      fi
      local safe_key
      safe_key="$(_memory_safe_key "$key")"
      local file="${mem_dir}/${safe_key}.json"
      if [[ ! -f "$file" ]]; then
        jq -nc --arg k "$key" '{"key": $k, "found": false}'
        return 0
      fi
      cat "$file"
      ;;
    set)
      if [[ -z "$key" ]]; then
        printf '{"error": "key is required for set"}'
        return 1
      fi
      local safe_key
      safe_key="$(_memory_safe_key "$key")"
      local file="${mem_dir}/${safe_key}.json"
      local ts
      ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      jq -nc --arg k "$key" --arg v "$value" --arg t "$ts" \
        '{"key": $k, "value": $v, "updated_at": $t}' > "$file"
      jq -nc --arg k "$key" '{"key": $k, "stored": true}'
      ;;
    delete)
      if [[ -z "$key" ]]; then
        printf '{"error": "key is required for delete"}'
        return 1
      fi
      local safe_key
      safe_key="$(_memory_safe_key "$key")"
      local file="${mem_dir}/${safe_key}.json"
      if [[ -f "$file" ]]; then
        rm -f "$file"
        jq -nc --arg k "$key" '{"key": $k, "deleted": true}'
      else
        jq -nc --arg k "$key" '{"key": $k, "deleted": false, "reason": "not found"}'
      fi
      ;;
    list)
      local keys_ndjson=""
      local f
      for f in "${mem_dir}"/*.json; do
        [[ -f "$f" ]] || continue
        local k
        k="$(jq -r '.key // empty' < "$f" 2>/dev/null)"
        if [[ -n "$k" ]]; then
          keys_ndjson="${keys_ndjson}$(jq -nc --arg k "$k" '$k')"$'\n'
        fi
      done
      local keys
      if [[ -n "$keys_ndjson" ]]; then
        keys="$(printf '%s' "$keys_ndjson" | jq -s '.')"
      else
        keys="[]"
      fi
      jq -nc --argjson ks "$keys" '{"keys": $ks, "count": ($ks | length)}'
      ;;
    search)
      if [[ -z "$query_str" ]]; then
        printf '{"error": "query is required for search"}'
        return 1
      fi
      local results
      results="$(memory_search_text "$query_str" 20)"
      jq -nc --argjson r "$results" '{"results": $r, "count": ($r | length)}'
      ;;
    *)
      printf '{"error": "unknown memory action: %s. Use get, set, delete, list, or search"}' "$action"
      return 1
      ;;
  esac
}

_memory_safe_key() {
  sanitize_key "$1"
}

# ---- Tool: cron ----

tool_cron() {
  local input="$1"
  require_command jq "cron tool requires jq"

  local action id schedule command agent_id
  action="$(printf '%s' "$input" | jq -r '.action // empty')"
  id="$(printf '%s' "$input" | jq -r '.id // empty')"
  schedule="$(printf '%s' "$input" | jq -r '.schedule // empty')"
  command="$(printf '%s' "$input" | jq -r '.command // empty')"
  agent_id="$(printf '%s' "$input" | jq -r '.agent_id // empty')"

  local cron_dir="${BASHCLAW_STATE_DIR:?BASHCLAW_STATE_DIR not set}/cron"
  ensure_dir "$cron_dir"

  case "$action" in
    add)
      if [[ -z "$schedule" || -z "$command" ]]; then
        printf '{"error": "schedule and command are required for add"}'
        return 1
      fi
      if [[ -z "$id" ]]; then
        id="$(uuid_generate)"
      fi
      local ts
      ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      local safe_id
      safe_id="$(_memory_safe_key "$id")"
      jq -nc \
        --arg id "$id" \
        --arg sched "$schedule" \
        --arg cmd "$command" \
        --arg aid "$agent_id" \
        --arg ts "$ts" \
        '{id: $id, schedule: $sched, command: $cmd, agent_id: $aid, created_at: $ts, enabled: true}' \
        > "${cron_dir}/${safe_id}.json"
      jq -nc --arg id "$id" '{"id": $id, "created": true}'
      ;;
    remove)
      if [[ -z "$id" ]]; then
        printf '{"error": "id is required for remove"}'
        return 1
      fi
      local safe_id
      safe_id="$(_memory_safe_key "$id")"
      local file="${cron_dir}/${safe_id}.json"
      if [[ -f "$file" ]]; then
        rm -f "$file"
        jq -nc --arg id "$id" '{"id": $id, "removed": true}'
      else
        jq -nc --arg id "$id" '{"id": $id, "removed": false, "reason": "not found"}'
      fi
      ;;
    list)
      local jobs_ndjson=""
      local f
      for f in "${cron_dir}"/*.json; do
        [[ -f "$f" ]] || continue
        local entry
        entry="$(cat "$f")"
        jobs_ndjson="${jobs_ndjson}${entry}"$'\n'
      done
      local jobs
      if [[ -n "$jobs_ndjson" ]]; then
        jobs="$(printf '%s' "$jobs_ndjson" | jq -s '.')"
      else
        jobs="[]"
      fi
      jq -nc --argjson j "$jobs" '{"jobs": $j, "count": ($j | length)}'
      ;;
    *)
      printf '{"error": "unknown cron action: %s. Use add, remove, or list"}' "$action"
      return 1
      ;;
  esac
}

# ---- Tool: message ----

tool_message() {
  local input="$1"
  require_command jq "message tool requires jq"

  local action channel target message_text
  action="$(printf '%s' "$input" | jq -r '.action // empty')"
  channel="$(printf '%s' "$input" | jq -r '.channel // empty')"
  target="$(printf '%s' "$input" | jq -r '.target // empty')"
  message_text="$(printf '%s' "$input" | jq -r '.message // empty')"

  if [[ "$action" != "send" ]]; then
    printf '{"error": "only send action is supported"}'
    return 1
  fi

  if [[ -z "$message_text" ]]; then
    printf '{"error": "message parameter is required"}'
    return 1
  fi

  local handler_func="_channel_send_${channel}"
  if declare -f "$handler_func" &>/dev/null; then
    "$handler_func" "$target" "$message_text"
  else
    log_warn "No channel handler for: ${channel:-<none>}, message logged only"
    jq -nc --arg ch "$channel" --arg tgt "$target" --arg msg "$message_text" \
      '{"sent": false, "channel": $ch, "target": $tgt, "message": $msg, "reason": "no handler configured"}'
  fi
}

# ---- Tool: agents_list ----

# List all configured agents from the config
tool_agents_list() {
  require_command jq "agents_list tool requires jq"

  local agents_raw
  agents_raw="$(config_get_raw '.agents.list // []')"
  local defaults
  defaults="$(config_get_raw '.agents.defaults // {}')"

  jq -nc --argjson agents "$agents_raw" --argjson defaults "$defaults" \
    '{agents: $agents, defaults: $defaults, count: ($agents | length)}'
}

# ---- Tool: session_status ----

# Query session info for a specific agent/channel/sender
tool_session_status() {
  local input="$1"
  require_command jq "session_status tool requires jq"

  local agent_id channel sender
  agent_id="$(printf '%s' "$input" | jq -r '.agent_id // "main"')"
  channel="$(printf '%s' "$input" | jq -r '.channel // "default"')"
  sender="$(printf '%s' "$input" | jq -r '.sender // empty')"

  local sess_file
  sess_file="$(session_file "$agent_id" "$channel" "$sender")"

  local msg_count=0
  local last_role=""
  if [[ -f "$sess_file" ]]; then
    msg_count="$(session_count "$sess_file")"
    last_role="$(session_last_role "$sess_file")"
  fi

  local model
  model="$(agent_resolve_model "$agent_id")"
  local provider
  provider="$(agent_resolve_provider "$model")"

  jq -nc \
    --arg aid "$agent_id" \
    --arg ch "$channel" \
    --arg snd "$sender" \
    --arg sf "$sess_file" \
    --argjson mc "$msg_count" \
    --arg lr "$last_role" \
    --arg m "$model" \
    --arg p "$provider" \
    '{agent_id: $aid, channel: $ch, sender: $snd, session_file: $sf, message_count: $mc, last_role: $lr, model: $m, provider: $p}'
}

# ---- Tool: sessions_list ----

# List all active sessions across all agents
tool_sessions_list() {
  require_command jq "sessions_list tool requires jq"
  session_list
}

# ---- Tool: read_file ----

tool_read_file() {
  local input="$1"
  require_command jq "read_file tool requires jq"

  local path offset limit
  path="$(printf '%s' "$input" | jq -r '.path // empty' 2>/dev/null)"
  offset="$(printf '%s' "$input" | jq -r '.offset // empty')"
  limit="$(printf '%s' "$input" | jq -r '.limit // empty')"

  if [[ -z "$path" ]]; then
    printf '{"error": "path parameter is required"}'
    return 1
  fi

  # Resolve relative to session workspace if set
  if [[ "$path" != /* ]]; then
    local workspace="${BASHCLAW_TOOL_WORKSPACE:-$(pwd)}"
    path="${workspace}/${path}"
  fi

  if [[ ! -f "$path" ]]; then
    jq -nc --arg p "$path" '{"error": "file not found", "path": $p}'
    return 1
  fi

  offset="${offset:-1}"
  limit="${limit:-$TOOL_READ_FILE_MAX_LINES}"

  if [ "$offset" -lt 1 ] 2>/dev/null; then
    offset=1
  fi
  if [ "$limit" -gt "$TOOL_READ_FILE_MAX_LINES" ] 2>/dev/null; then
    limit="$TOOL_READ_FILE_MAX_LINES"
  fi

  local total_lines
  total_lines="$(wc -l < "$path" | tr -d '[:space:]')"

  local content
  content="$(tail -n "+${offset}" "$path" | head -n "$limit")"

  local truncated="false"
  local end_line=$((offset + limit - 1))
  if [ "$end_line" -lt "$total_lines" ] 2>/dev/null; then
    truncated="true"
  fi

  jq -nc \
    --arg path "$path" \
    --arg content "$content" \
    --argjson offset "$offset" \
    --argjson limit "$limit" \
    --argjson total "$total_lines" \
    --arg trunc "$truncated" \
    '{path: $path, content: $content, offset: $offset, limit: $limit, totalLines: $total, truncated: ($trunc == "true")}'
}

# ---- Tool: write_file ----

tool_write_file() {
  local input="$1"
  require_command jq "write_file tool requires jq"

  local path content append_flag
  path="$(printf '%s' "$input" | jq -r '.path // empty' 2>/dev/null)"
  content="$(printf '%s' "$input" | jq -r '.content // empty')"
  append_flag="$(printf '%s' "$input" | jq -r '.append // false')"

  if [[ -z "$path" ]]; then
    printf '{"error": "path parameter is required"}'
    return 1
  fi

  if [[ -z "$content" ]]; then
    printf '{"error": "content parameter is required"}'
    return 1
  fi

  # Resolve relative to session workspace if set
  if [[ "$path" != /* ]]; then
    local workspace="${BASHCLAW_TOOL_WORKSPACE:-$(pwd)}"
    path="${workspace}/${path}"
  fi

  # Path traversal protection
  case "$path" in
    */../*|*/..)
      printf '{"error": "path traversal not allowed"}'
      return 1
      ;;
  esac

  local dir
  dir="$(dirname "$path")"
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir" 2>/dev/null || {
      jq -nc --arg p "$path" '{"error": "cannot create parent directory", "path": $p}'
      return 1
    }
  fi

  if [[ "$append_flag" == "true" ]]; then
    printf '%s' "$content" >> "$path" || {
      jq -nc --arg p "$path" '{"error": "write failed", "path": $p}'
      return 1
    }
  else
    printf '%s' "$content" > "$path" || {
      jq -nc --arg p "$path" '{"error": "write failed", "path": $p}'
      return 1
    }
  fi

  local size
  size="$(file_size_bytes "$path")"

  jq -nc --arg p "$path" --argjson s "$size" --arg a "$append_flag" \
    '{path: $p, written: true, size: $s, appended: ($a == "true")}'
}

# ---- Tool: list_files ----

tool_list_files() {
  local input="$1"
  require_command jq "list_files tool requires jq"

  local path pattern recursive
  path="$(printf '%s' "$input" | jq -r '.path // empty' 2>/dev/null)"
  pattern="$(printf '%s' "$input" | jq -r '.pattern // empty')"
  recursive="$(printf '%s' "$input" | jq -r '.recursive // false')"

  if [[ -z "$path" ]]; then
    printf '{"error": "path parameter is required"}'
    return 1
  fi

  # Resolve relative paths
  if [[ "$path" != /* ]]; then
    local workspace="${BASHCLAW_TOOL_WORKSPACE:-$(pwd)}"
    path="${workspace}/${path}"
  fi

  if [[ ! -d "$path" ]]; then
    jq -nc --arg p "$path" '{"error": "directory not found", "path": $p}'
    return 1
  fi

  local entries="[]"
  local count=0

  if [[ "$recursive" == "true" ]]; then
    local find_args=""
    if [[ -n "$pattern" ]]; then
      find_args="-name $pattern"
    fi
    local f
    local entries_ndjson=""
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if [ "$count" -ge "$TOOL_LIST_FILES_MAX" ]; then
        break
      fi
      local ftype="file"
      if [[ -d "$f" ]]; then
        ftype="directory"
      fi
      local rel
      rel="${f#${path}/}"
      entries_ndjson="${entries_ndjson}$(jq -nc --arg n "$rel" --arg t "$ftype" '{name: $n, type: $t}')"$'\n'
      count=$((count + 1))
    done <<EOF
$(find "$path" -maxdepth 10 ${find_args} 2>/dev/null | head -n "$TOOL_LIST_FILES_MAX")
EOF
    if [[ -n "$entries_ndjson" ]]; then
      entries="$(printf '%s' "$entries_ndjson" | jq -s '.')"
    fi
  else
    local f
    local entries_ndjson=""
    for f in "${path}"/*; do
      [[ -e "$f" ]] || continue
      if [ "$count" -ge "$TOOL_LIST_FILES_MAX" ]; then
        break
      fi
      local name
      name="$(basename "$f")"
      # Apply pattern filter if specified
      if [[ -n "$pattern" ]]; then
        case "$name" in
          $pattern) ;;
          *) continue ;;
        esac
      fi
      local ftype="file"
      if [[ -d "$f" ]]; then
        ftype="directory"
      elif [[ -L "$f" ]]; then
        ftype="symlink"
      fi
      entries_ndjson="${entries_ndjson}$(jq -nc --arg n "$name" --arg t "$ftype" '{name: $n, type: $t}')"$'\n'
      count=$((count + 1))
    done
    if [[ -n "$entries_ndjson" ]]; then
      entries="$(printf '%s' "$entries_ndjson" | jq -s '.')"
    fi
  fi

  jq -nc --arg p "$path" --argjson e "$entries" --argjson c "$count" \
    '{path: $p, entries: $e, count: $c, truncated: ($c >= '"$TOOL_LIST_FILES_MAX"')}'
}

# ---- Tool: file_search ----

tool_file_search() {
  local input="$1"
  require_command jq "file_search tool requires jq"

  local path name_pattern content_pattern max_results
  path="$(printf '%s' "$input" | jq -r '.path // empty' 2>/dev/null)"
  name_pattern="$(printf '%s' "$input" | jq -r '.name // empty')"
  content_pattern="$(printf '%s' "$input" | jq -r '.content // empty')"
  max_results="$(printf '%s' "$input" | jq -r '.maxResults // empty')"
  max_results="${max_results:-50}"

  if [[ -z "$path" ]]; then
    printf '{"error": "path parameter is required"}'
    return 1
  fi

  # Resolve relative paths
  if [[ "$path" != /* ]]; then
    local workspace="${BASHCLAW_TOOL_WORKSPACE:-$(pwd)}"
    path="${workspace}/${path}"
  fi

  if [[ ! -d "$path" ]]; then
    jq -nc --arg p "$path" '{"error": "directory not found", "path": $p}'
    return 1
  fi

  if [[ -z "$name_pattern" && -z "$content_pattern" ]]; then
    printf '{"error": "at least one of name or content parameter is required"}'
    return 1
  fi

  local results_ndjson=""
  local count=0

  if [[ -n "$name_pattern" && -z "$content_pattern" ]]; then
    # Name-only search
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if [ "$count" -ge "$max_results" ]; then
        break
      fi
      local rel="${f#${path}/}"
      results_ndjson="${results_ndjson}$(jq -nc --arg p "$rel" '{path: $p}')"$'\n'
      count=$((count + 1))
    done <<EOF
$(find "$path" -name "$name_pattern" -type f 2>/dev/null | head -n "$max_results")
EOF
  elif [[ -z "$name_pattern" && -n "$content_pattern" ]]; then
    # Content-only search using grep
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if [ "$count" -ge "$max_results" ]; then
        break
      fi
      local rel="${f#${path}/}"
      local match_line
      match_line="$(grep -n -m1 "$content_pattern" "$f" 2>/dev/null | head -1 | cut -d: -f1)"
      results_ndjson="${results_ndjson}$(jq -nc --arg p "$rel" --arg l "${match_line:-0}" \
        '{path: $p, line: ($l | tonumber)}')"$'\n'
      count=$((count + 1))
    done <<EOF
$(grep -rl "$content_pattern" "$path" 2>/dev/null | head -n "$max_results")
EOF
  else
    # Combined name + content search
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if grep -q "$content_pattern" "$f" 2>/dev/null; then
        if [ "$count" -ge "$max_results" ]; then
          break
        fi
        local rel="${f#${path}/}"
        local match_line
        match_line="$(grep -n -m1 "$content_pattern" "$f" 2>/dev/null | head -1 | cut -d: -f1)"
        results_ndjson="${results_ndjson}$(jq -nc --arg p "$rel" --arg l "${match_line:-0}" \
          '{path: $p, line: ($l | tonumber)}')"$'\n'
        count=$((count + 1))
      fi
    done <<EOF
$(find "$path" -name "$name_pattern" -type f 2>/dev/null | head -n 500)
EOF
  fi

  local results
  if [[ -n "$results_ndjson" ]]; then
    results="$(printf '%s' "$results_ndjson" | jq -s '.')"
  else
    results="[]"
  fi
  jq -nc --arg p "$path" --argjson r "$results" --argjson c "$count" \
    '{path: $p, results: $r, count: $c}'
}

# ---- Tool: termux_notify ----

tool_termux_notify() {
  local input="$1"
  require_command jq "termux_notify tool requires jq"

  local title message type
  title="$(printf '%s' "$input" | jq -r '.title // "BashClaw"')"
  message="$(printf '%s' "$input" | jq -r '.message // empty')"
  type="$(printf '%s' "$input" | jq -r '.type // "notification"')"

  if [[ -z "$message" ]]; then
    printf '{"error": "message parameter is required"}'
    return 1
  fi

  case "$type" in
    toast)
      if ! platform_termux_api_available termux-toast; then
        printf '{"error": "termux-toast not available"}'
        return 1
      fi
      termux-toast "$message" >/dev/null 2>&1 || {
        printf '{"error": "termux-toast failed"}'
        return 1
      }
      jq -nc --arg m "$message" '{"ok": true, "type": "toast", "message": $m}'
      ;;
    notification|"")
      if ! platform_termux_api_available termux-notification; then
        printf '{"error": "termux-notification not available"}'
        return 1
      fi
      termux-notification --title "$title" --content "$message" >/dev/null 2>&1 || {
        printf '{"error": "termux-notification failed"}'
        return 1
      }
      jq -nc --arg t "$title" --arg m "$message" '{"ok": true, "type": "notification", "title": $t, "message": $m}'
      ;;
    *)
      printf '{"error": "unknown notification type"}'
      return 1
      ;;
  esac
}

# ---- Tool: termux_clipboard ----

tool_termux_clipboard() {
  local input="$1"
  require_command jq "termux_clipboard tool requires jq"

  local action text
  action="$(printf '%s' "$input" | jq -r '.action // empty')"
  text="$(printf '%s' "$input" | jq -r '.text // empty')"

  case "$action" in
    get)
      if ! platform_termux_api_available termux-clipboard-get; then
        printf '{"error": "termux-clipboard-get not available"}'
        return 1
      fi
      local value
      value="$(termux-clipboard-get 2>/dev/null)" || {
        printf '{"error": "termux-clipboard-get failed"}'
        return 1
      }
      jq -nc --arg value "$value" '{"action": "get", "text": $value}'
      ;;
    set)
      if ! platform_termux_api_available termux-clipboard-set; then
        printf '{"error": "termux-clipboard-set not available"}'
        return 1
      fi
      termux-clipboard-set "$text" >/dev/null 2>&1 || {
        printf '{"error": "termux-clipboard-set failed"}'
        return 1
      }
      jq -nc --arg value "$text" '{"action": "set", "ok": true, "text": $value}'
      ;;
    *)
      printf '{"error": "action must be get or set"}'
      return 1
      ;;
  esac
}

# ---- Tool: termux_battery ----

tool_termux_battery() {
  local input="${1:-{}}"
  require_command jq "termux_battery tool requires jq"
  : "$input"

  if ! platform_termux_api_available termux-battery-status; then
    printf '{"error": "termux-battery-status not available"}'
    return 1
  fi

  local result
  result="$(termux-battery-status 2>/dev/null)" || {
    printf '{"error": "termux-battery-status failed"}'
    return 1
  }

  if printf '%s' "$result" | jq empty 2>/dev/null; then
    printf '%s' "$result"
  else
    jq -nc --arg raw "$result" '{"raw": $raw}'
  fi
}

# ---- Tool: termux_wifi ----

tool_termux_wifi() {
  local input="${1:-{}}"
  require_command jq "termux_wifi tool requires jq"
  : "$input"

  if ! platform_termux_api_available termux-wifi-connectioninfo; then
    printf '{"error": "termux-wifi-connectioninfo not available"}'
    return 1
  fi

  local result
  result="$(termux-wifi-connectioninfo 2>/dev/null)" || {
    printf '{"error": "termux-wifi-connectioninfo failed"}'
    return 1
  }

  if printf '%s' "$result" | jq empty 2>/dev/null; then
    printf '%s' "$result"
  else
    jq -nc --arg raw "$result" '{raw: $raw}'
  fi
}

# ---- Tool: termux_location ----

tool_termux_location() {
  local input="${1:-{}}"
  require_command jq "termux_location tool requires jq"

  if ! platform_termux_api_available termux-location; then
    printf '{"error": "termux-location not available"}'
    return 1
  fi

  local provider request
  provider="$(printf '%s' "$input" | jq -r '.provider // empty' 2>/dev/null)"
  request="$(printf '%s' "$input" | jq -r '.request // empty' 2>/dev/null)"

  local cmd=(termux-location)
  [[ -n "$provider" ]] && cmd+=("--provider" "$provider")
  [[ -n "$request" ]] && cmd+=("--request" "$request")

  local result
  result="$("${cmd[@]}" 2>/dev/null)" || {
    printf '{"error": "termux-location failed"}'
    return 1
  }

  if printf '%s' "$result" | jq empty 2>/dev/null; then
    printf '%s' "$result"
  else
    jq -nc --arg raw "$result" '{raw: $raw}'
  fi
}

# ---- Tool: termux_telephony ----

tool_termux_telephony() {
  local input="${1:-{}}"
  require_command jq "termux_telephony tool requires jq"
  : "$input"

  if ! platform_termux_api_available termux-telephony-deviceinfo; then
    printf '{"error": "termux-telephony-deviceinfo not available"}'
    return 1
  fi

  local result
  result="$(termux-telephony-deviceinfo 2>/dev/null)" || {
    printf '{"error": "termux-telephony-deviceinfo failed"}'
    return 1
  }

  if printf '%s' "$result" | jq empty 2>/dev/null; then
    printf '%s' "$result"
  else
    jq -nc --arg raw "$result" '{raw: $raw}'
  fi
}

# ---- Tool: termux_camera ----

tool_termux_camera() {
  local input="${1:-{}}"
  require_command jq "termux_camera tool requires jq"

  if ! platform_termux_api_available termux-camera-photo; then
    printf '{"error": "termux-camera-photo not available"}'
    return 1
  fi

  local path camera_id
  path="$(printf '%s' "$input" | jq -r '.path // empty' 2>/dev/null)"
  camera_id="$(printf '%s' "$input" | jq -r '.cameraId // empty' 2>/dev/null)"

  if [[ -z "$path" ]]; then
    path="$(platform_temp_base 2>/dev/null || printf '%s' "$BASHCLAW_STATE_DIR")/termux-photo-$(date +%Y%m%d-%H%M%S).jpg"
  fi

  ensure_dir "$(dirname "$path")"

  local cmd=(termux-camera-photo)
  [[ -n "$camera_id" && "$camera_id" != "null" ]] && cmd+=("-c" "$camera_id")
  cmd+=("$path")

  "${cmd[@]}" >/dev/null 2>&1 || {
    printf '{"error": "termux-camera-photo failed"}'
    return 1
  }

  jq -nc --arg path "$path" --arg camera_id "${camera_id:-0}" '{ok: true, path: $path, cameraId: ($camera_id | tonumber? // 0)}'
}

# ---- Tool: termux_recipe ----

tool_termux_recipe() {
  local input="${1:-{}}"
  require_command jq "termux_recipe tool requires jq"

  local action recipe limit notify
  action="$(printf '%s' "$input" | jq -r '.action // "list"' 2>/dev/null)"
  recipe="$(printf '%s' "$input" | jq -r '.recipe // empty' 2>/dev/null)"
  limit="$(printf '%s' "$input" | jq -r '.limit // 5' 2>/dev/null)"
  notify="$(printf '%s' "$input" | jq -r '.notify // false' 2>/dev/null)"

  case "$action" in
    list)
      jq -nc '{recipes: [
        {id: "battery", summary: "Summarize battery state and optionally notify when charge is low."},
        {id: "downloads", summary: "List the most recent files from the Termux Downloads path."},
        {id: "clipboard", summary: "Save the current clipboard into BashClaw memory logs."},
        {id: "connectivity", summary: "Summarize wifi and telephony device connectivity."},
        {id: "quiet_mode", summary: "Lower brightness and volume for a quick quiet profile."},
        {id: "daily_digest", summary: "Battery + connectivity + clipboard preview in one digest."},
        {id: "connectivity_watchdog", summary: "Check wifi/telephony status and alert on loss."}
      ]}'
      ;;
    describe)
      case "$recipe" in
        battery)
          jq -nc '{recipe: "battery", uses: ["termux_battery", "termux_notify"], summary: "Reads battery percentage, charging state, and health. Can send a low-battery notification."}'
          ;;
        downloads)
          jq -nc '{recipe: "downloads", uses: ["list_files"], summary: "Returns recent files from the shared Downloads path when it exists."}'
          ;;
        clipboard)
          jq -nc '{recipe: "clipboard", uses: ["termux_clipboard", "write_file"], summary: "Captures clipboard text and appends it to a timestamped clipboard log."}'
          ;;
        connectivity)
          jq -nc '{recipe: "connectivity", uses: ["termux_wifi", "termux_telephony"], summary: "Combines wifi and telephony details into one connectivity report."}'
          ;;
        quiet_mode)
          jq -nc '{recipe: "quiet_mode", uses: ["termux_brightness", "termux_volume", "termux_vibrate"], summary: "Sets a low-brightness, low-volume profile and gives short haptic feedback."}'
          ;;
        daily_digest)
          jq -nc '{recipe: "daily_digest", uses: ["termux_battery", "termux_wifi", "termux_telephony", "termux_clipboard"], summary: "One-shot digest of battery, connectivity, and clipboard preview."}'
          ;;
        connectivity_watchdog)
          jq -nc '{recipe: "connectivity_watchdog", uses: ["termux_wifi", "termux_telephony", "termux_notify"], summary: "Checks connectivity and notifies when wifi is missing or signal is unknown."}'
          ;;
        *)
          printf '{"error": "unknown recipe"}'
          return 1
          ;;
      esac
      ;;
    run)
      case "$recipe" in
        battery)
          local battery_json percentage status low
          battery_json="$(tool_termux_battery '{}')" || return 1
          percentage="$(printf '%s' "$battery_json" | jq -r '.percentage // .level // 0')"
          status="$(printf '%s' "$battery_json" | jq -r '.status // .plugged // "unknown"')"
          low=false
          if [[ "$percentage" =~ ^[0-9]+$ ]] && (( percentage <= 20 )); then
            low=true
            if [[ "$notify" == "true" ]] && platform_termux_api_available termux-notification; then
              termux-notification --title 'BashClaw battery alert' --content "Battery at ${percentage}% (${status})" >/dev/null 2>&1 || true
            fi
          fi
          jq -nc --argjson battery "$battery_json" --argjson low "$low" '{recipe: "battery", battery: $battery, low: $low}'
          ;;
        downloads)
          local downloads_dir files_json
          downloads_dir="$(platform_termux_downloads_dir)"
          if [[ ! -d "$downloads_dir" ]]; then
            printf '{"error": "downloads path not available"}'
            return 1
          fi
          files_json="$(find "$downloads_dir" -maxdepth 1 -type f -printf '%T@	%f
' 2>/dev/null | sort -nr | head -n "$limit" | awk -F '	' '{print $2}' | jq -R . | jq -s .)"
          jq -nc --arg path "$downloads_dir" --argjson files "${files_json:-[]}" '{recipe: "downloads", path: $path, files: $files}'
          ;;
        clipboard)
          local clip_json text log_path ts
          clip_json="$(tool_termux_clipboard '{"action":"get"}')" || return 1
          text="$(printf '%s' "$clip_json" | jq -r '.text // empty')"
          ts="$(date '+%Y-%m-%d %H:%M:%S')"
          log_path="${BASHCLAW_STATE_DIR}/memory/clipboard.log"
          ensure_dir "$(dirname "$log_path")"
          printf '[%s] %s
' "$ts" "$text" >> "$log_path"
          jq -nc --arg text "$text" --arg path "$log_path" '{recipe: "clipboard", saved: true, text: $text, path: $path}'
          ;;
        connectivity)
          local wifi_json telephony_json
          wifi_json='{}'
          telephony_json='{}'
          if platform_termux_api_available termux-wifi-connectioninfo; then
            wifi_json="$(tool_termux_wifi '{}')" || wifi_json='{}'
          fi
          if platform_termux_api_available termux-telephony-deviceinfo; then
            telephony_json="$(tool_termux_telephony '{}')" || telephony_json='{}'
          fi
          jq -nc --argjson wifi "$wifi_json" --argjson telephony "$telephony_json" '{recipe: "connectivity", wifi: $wifi, telephony: $telephony}'
          ;;
        quiet_mode)
          local brightness volume vibrated
          brightness="$(tool_termux_brightness '{"brightness":"32"}')" || true
          volume="$(tool_termux_volume '{"stream":"notification","volume":0}')" || true
          vibrated=false
          if platform_termux_api_available termux-vibrate; then
            tool_termux_vibrate '{"duration":150,"force":false}' >/dev/null 2>&1 && vibrated=true
          fi
          jq -nc --argjson brightness "${brightness:-{}}" --argjson volume "${volume:-{}}" --argjson vibrated "$vibrated" '{recipe: "quiet_mode", brightness: $brightness, volume: $volume, vibrated: $vibrated}'
          ;;
        daily_digest)
          local battery_json wifi_json telephony_json clip_json clip_preview
          battery_json='{}'; wifi_json='{}'; telephony_json='{}'; clip_json='{}'; clip_preview=""
          if platform_termux_api_available termux-battery-status; then
            battery_json="$(tool_termux_battery '{}')" || battery_json='{}'
          fi
          if platform_termux_api_available termux-wifi-connectioninfo; then
            wifi_json="$(tool_termux_wifi '{}')" || wifi_json='{}'
          fi
          if platform_termux_api_available termux-telephony-deviceinfo; then
            telephony_json="$(tool_termux_telephony '{}')" || telephony_json='{}'
          fi
          if platform_termux_api_available termux-clipboard-get; then
            clip_json="$(tool_termux_clipboard '{"action":"get"}')" || clip_json='{}'
            clip_preview="$(printf '%s' "$clip_json" | jq -r '.text // empty' | head -c 120)"
          fi
          jq -nc --argjson battery "$battery_json" --argjson wifi "$wifi_json" --argjson telephony "$telephony_json" --arg clip "$clip_preview" '{recipe: "daily_digest", battery: $battery, wifi: $wifi, telephony: $telephony, clipboardPreview: $clip}'
          ;;
        connectivity_watchdog)
          local wifi_json telephony_json degraded notify_msg
          wifi_json='{}'
          telephony_json='{}'
          degraded=false
          notify_msg=""
          if platform_termux_api_available termux-wifi-connectioninfo; then
            wifi_json="$(tool_termux_wifi '{}')" || wifi_json='{}'
            local state
            state="$(printf '%s' "$wifi_json" | jq -r '.supplicant_state // .state // empty')"
            if [[ -z "$state" || "$state" == "" || "$state" == "DISCONNECTED" || "$state" == "INACTIVE" ]]; then
              degraded=true
              notify_msg="Wi-Fi disconnected"
            fi
          fi
          if platform_termux_api_available termux-telephony-deviceinfo; then
            telephony_json="$(tool_termux_telephony '{}')" || telephony_json='{}'
            local carrier
            carrier="$(printf '%s' "$telephony_json" | jq -r '.carrier // .network // empty')"
            if [[ -z "$carrier" || "$carrier" == "unknown" ]]; then
              degraded=true
              if [[ -z "$notify_msg" ]]; then
                notify_msg="Telephony signal unavailable"
              fi
            fi
          fi
          if [[ "$degraded" == "true" && "$notify" == "true" ]] && platform_termux_api_available termux-notification; then
            termux-notification --title 'BashClaw connectivity' --content "${notify_msg:-Connectivity degraded}" >/dev/null 2>&1 || true
          fi
          jq -nc --argjson wifi "$wifi_json" --argjson telephony "$telephony_json" --argjson degraded "$degraded" '{recipe: "connectivity_watchdog", wifi: $wifi, telephony: $telephony, degraded: $degraded}'
          ;;
        *)
          printf '{"error": "unknown recipe"}'
          return 1
          ;;
      esac
      ;;
    *)
      printf '{"error": "action must be list, describe, or run"}'
      return 1
      ;;
  esac
}

# ---- Tool: termux_open ----

tool_termux_open() {
  local input="$1"
  require_command jq "termux_open tool requires jq"

  local target action
  target="$(printf '%s' "$input" | jq -r '.target // empty')"
  action="$(printf '%s' "$input" | jq -r '.action // "open"')"

  if [[ -z "$target" ]]; then
    printf '{"error": "target parameter is required"}'
    return 1
  fi

  case "$action" in
    open|"")
      if ! platform_termux_api_available termux-open; then
        printf '{"error": "termux-open not available"}'
        return 1
      fi
      termux-open "$target" >/dev/null 2>&1 || {
        printf '{"error": "termux-open failed"}'
        return 1
      }
      jq -nc --arg target "$target" '{"ok": true, "action": "open", "target": $target}'
      ;;
    share)
      if ! platform_termux_api_available termux-share; then
        printf '{"error": "termux-share not available"}'
        return 1
      fi
      termux-share "$target" >/dev/null 2>&1 || {
        printf '{"error": "termux-share failed"}'
        return 1
      }
      jq -nc --arg target "$target" '{"ok": true, "action": "share", "target": $target}'
      ;;
    *)
      printf '{"error": "action must be open or share"}'
      return 1
      ;;
  esac
}

# ---- Tool: spawn ----

tool_spawn() {
  local input="$1"
  require_command jq "spawn tool requires jq"

  local task label
  task="$(printf '%s' "$input" | jq -r '.task // empty')"
  label="$(printf '%s' "$input" | jq -r '.label // empty')"
  label="${label:-background}"

  if [[ -z "$task" ]]; then
    printf '{"error": "task parameter is required"}'
    return 1
  fi

  local spawn_id
  spawn_id="$(uuid_generate | cut -c1-8)"
  local spawn_dir="${BASHCLAW_STATE_DIR:?}/spawn"
  mkdir -p "$spawn_dir"

  local started_at
  started_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  printf '{"id":"%s","label":"%s","status":"running","started_at":"%s"}\n' \
    "$spawn_id" "$label" "$started_at" > "${spawn_dir}/${spawn_id}.json"

  (
    local result
    result="$(engine_run "main" "$task" "spawn" "subagent" "true" 2>/dev/null)" || result="error: subagent failed"
    jq -nc \
      --arg id "$spawn_id" \
      --arg label "$label" \
      --arg result "$result" \
      --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      '{id: $id, label: $label, status: "completed", result: $result, completed_at: $ts}' \
      > "${spawn_dir}/${spawn_id}.json"
  ) &

  printf 'Subagent "%s" started (id: %s). Use spawn_status to check progress.' "$label" "$spawn_id"
}

# ---- Tool: spawn_status ----

tool_spawn_status() {
  local input="$1"
  require_command jq "spawn_status tool requires jq"

  local task_id
  task_id="$(printf '%s' "$input" | jq -r '.task_id // empty')"

  if [[ -z "$task_id" ]]; then
    printf '{"error": "task_id parameter is required"}'
    return 1
  fi

  local status_file="${BASHCLAW_STATE_DIR:?}/spawn/${task_id}.json"
  if [[ -f "$status_file" ]]; then
    cat "$status_file"
  else
    printf '{"error":"task not found","id":"%s"}' "$task_id"
  fi
}

# ---- SSRF helper ----

_ssrf_is_blocked() {
  local hostname="$1"

  if _ssrf_is_private_pattern "$hostname"; then
    return 0
  fi

  # DNS resolution check
  if is_command_available dig; then
    local resolved
    resolved="$(dig +short "$hostname" 2>/dev/null | head -1)"
    if [[ -n "$resolved" ]] && _ssrf_is_private_pattern "$resolved"; then
      log_warn "SSRF blocked: $hostname resolves to private IP $resolved"
      return 0
    fi
  elif is_command_available host; then
    local resolved
    resolved="$(host "$hostname" 2>/dev/null | grep 'has address' | head -1 | awk '{print $NF}')"
    if [[ -n "$resolved" ]] && _ssrf_is_private_pattern "$resolved"; then
      log_warn "SSRF blocked: $hostname resolves to private IP $resolved"
      return 0
    fi
  fi

  return 1
}
#!/usr/bin/env bash
# Additional Termux device-state tools
# Source this file or append to tools.sh

# ---- Tool: termux_sensor ----

tool_termux_sensor() {
  local input="${1:-{}}"
  require_command jq "termux_sensor tool requires jq"

  local sensor delay
  sensor="$(printf '%s' "$input" | jq -r '.sensor // empty' 2>/dev/null)"
  delay="$(printf '%s' "$input" | jq -r '.delay // 1000' 2>/dev/null)"

  if ! platform_termux_api_available termux-sensor; then
    printf '{"error": "termux-sensor not available"}'
    return 1
  fi

  local args=("-d" "$delay")
  if [[ -n "$sensor" ]]; then
    args+=("-s" "$sensor")
  fi

  local result
  result="$(termux-sensor "${args[@]}" 2>/dev/null)" || {
    printf '{"error": "termux-sensor failed"}'
    return 1
  }

  if printf '%s' "$result" | jq empty 2>/dev/null; then
    printf '%s' "$result"
  else
    jq -nc --arg raw "$result" '{"raw": $raw}'
  fi
}

# ---- Tool: termux_brightness ----

tool_termux_brightness() {
  local input="${1:-{}}"
  require_command jq "termux_brightness tool requires jq"

  local brightness
  brightness="$(printf '%s' "$input" | jq -r '.brightness // empty' 2>/dev/null)"

  if ! platform_termux_api_available termux-brightness; then
    printf '{"error": "termux-brightness not available"}'
    return 1
  fi

  local result
  if [[ -n "$brightness" ]]; then
    # Set brightness (0-255 or auto)
    if [[ "$brightness" == "auto" ]]; then
      result="$(termux-brightness auto 2>/dev/null)" || {
        printf '{"error": "termux-brightness failed"}'
        return 1
      }
    else
      result="$(termux-brightness "$brightness" 2>/dev/null)" || {
        printf '{"error": "termux-brightness failed"}'
        return 1
      }
    fi
    jq -nc --arg b "$brightness" '{"ok": true, "brightness": $b}'
  else
    # Just execute to get current state (some devices report back)
    result="$(termux-brightness 2>/dev/null)" || {
      # If no arg fails, try to get current from settings
      local current
      current="$(settings get system screen_brightness 2>/dev/null || printf 'unknown')"
      jq -nc --arg c "$current" '{"brightness": $c}'
      return 0
    }
    if printf '%s' "$result" | jq empty 2>/dev/null; then
      printf '%s' "$result"
    else
      jq -nc --arg raw "$result" '{"raw": $raw}'
    fi
  fi
}

# ---- Tool: termux_volume ----

tool_termux_volume() {
  local input="${1:-{}}"
  require_command jq "termux_volume tool requires jq"

  local stream volume
  stream="$(printf '%s' "$input" | jq -r '.stream // "notification"' 2>/dev/null)"
  volume="$(printf '%s' "$input" | jq -r '.volume // empty' 2>/dev/null)"

  if ! platform_termux_api_available termux-volume; then
    printf '{"error": "termux-volume not available"}'
    return 1
  fi

  local result
  if [[ -n "$volume" ]]; then
    # Set volume
    result="$(termux-volume "$stream" "$volume" 2>/dev/null)" || {
      printf '{"error": "termux-volume failed"}'
      return 1
    }
    jq -nc --arg s "$stream" --arg v "$volume" '{"ok": true, "stream": $s, "volume": $v}'
  else
    # Get current volume (termux-volume without args shows all)
    result="$(termux-volume 2>/dev/null)" || {
      printf '{"error": "termux-volume failed"}'
      return 1
    }
    if printf '%s' "$result" | jq empty 2>/dev/null; then
      printf '%s' "$result"
    else
      jq -nc --arg raw "$result" '{"raw": $raw}'
    fi
  fi
}

# ---- Tool: termux_torch ----

tool_termux_torch() {
  local input="${1:-{}}"
  require_command jq "termux_torch tool requires jq"

  local state
  state="$(printf '%s' "$input" | jq -r '.state // "toggle"' 2>/dev/null)"

  if ! platform_termux_api_available termux-torch; then
    printf '{"error": "termux-torch not available"}'
    return 1
  fi

  local args=()
  case "$state" in
    on)
      args=("ON")
      ;;
    off)
      args=("OFF")
      ;;
    toggle|"")
      args=("toggle")
      ;;
    *)
      printf '{"error": "state must be on, off, or toggle"}'
      return 1
      ;;
  esac

  termux-torch "${args[@]}" >/dev/null 2>&1 || {
    printf '{"error": "termux-torch failed"}'
    return 1
  }

  jq -nc --arg s "$state" '{"ok": true, "state": $s}'
}

# ---- Tool: termux_vibrate ----

tool_termux_vibrate() {
  local input="${1:-{}}"
  require_command jq "termux_vibrate tool requires jq"

  local duration force
  duration="$(printf '%s' "$input" | jq -r '.duration // 200' 2>/dev/null)"
  force="$(printf '%s' "$input" | jq -r '.force // false' 2>/dev/null)"

  if ! platform_termux_api_available termux-vibrate; then
    printf '{"error": "termux-vibrate not available"}'
    return 1
  fi

  local args=("-d" "$duration")
  if [[ "$force" == "true" ]]; then
    args+=("-f")
  fi

  termux-vibrate "${args[@]}" >/dev/null 2>&1 || {
    printf '{"error": "termux-vibrate failed"}'
    return 1
  }

  jq -nc --arg d "$duration" --arg f "$force" '{"ok": true, "duration_ms": $d, "force": ($f == "true")}'
}

# ---- Tool: termux_wakelock ----

tool_termux_wakelock() {
  local input="${1:-{}}"
  require_command jq "termux_wakelock tool requires jq"

  local action
  action="$(printf '%s' "$input" | jq -r '.action // "status"' 2>/dev/null)"

  case "$action" in
    acquire|lock)
      if ! platform_termux_api_available termux-wake-lock; then
        printf '{"error": "termux-wake-lock not available"}'
        return 1
      fi
      termux-wake-lock >/dev/null 2>&1 || {
        printf '{"error": "termux-wake-lock failed"}'
        return 1
      }
      jq -nc '{"ok": true, "action": "acquired", "message": "Wake lock acquired, device will stay awake"}'
      ;;
    release|unlock)
      if ! platform_termux_api_available termux-wake-unlock; then
        printf '{"error": "termux-wake-unlock not available"}'
        return 1
      fi
      termux-wake-unlock >/dev/null 2>&1 || {
        printf '{"error": "termux-wake-unlock failed"}'
        return 1
      }
      jq -nc '{"ok": true, "action": "released", "message": "Wake lock released"}'
      ;;
    status|"")
      # Check if wakelock is active by looking at /proc/wakelocks or using dumpsys
      local wakelock_status
      if command -v dumpsys >/dev/null 2>&1; then
        wakelock_status="$(dumpsys power 2>/dev/null | grep -i "wake lock" | head -1 || printf 'unknown')"
      else
        wakelock_status="unknown"
      fi
      jq -nc --arg s "$wakelock_status" '{"status": $s}'
      ;;
    *)
      printf '{"error": "action must be acquire, release, or status"}'
      return 1
      ;;
  esac
}