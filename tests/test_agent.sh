#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHCLAW_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/framework.sh"

export BASHCLAW_STATE_DIR="$(test_bootstrap_state_dir)"
export LOG_LEVEL="silent"
mkdir -p "$BASHCLAW_STATE_DIR"
for _lib in "${BASHCLAW_ROOT}"/lib/*.sh; do
  [[ -f "$_lib" ]] && source "$_lib"
done
unset _lib

begin_test_file "test_agent"

# ---- agent_resolve_model ----

test_start "agent_resolve_model reads from config"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "agents": {
    "defaults": {"model": "claude-opus-4-6"},
    "list": [{"id": "research", "model": "gpt-4o"}]
  }
}
EOF
_CONFIG_CACHE=""
config_load
result="$(agent_resolve_model "research")"
assert_eq "$result" "gpt-4o"
teardown_test_env

test_start "agent_resolve_model falls back to defaults"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "agents": {
    "defaults": {"model": "claude-opus-4-6"},
    "list": [{"id": "research"}]
  }
}
EOF
_CONFIG_CACHE=""
config_load
result="$(agent_resolve_model "research")"
assert_eq "$result" "claude-opus-4-6"
teardown_test_env

test_start "agent_resolve_model uses AGENT_MODEL_OVERRIDE"
setup_test_env
AGENT_MODEL_OVERRIDE="override-model"
_CONFIG_CACHE=""
config_load
result="$(agent_resolve_model "main")"
assert_eq "$result" "override-model"
unset AGENT_MODEL_OVERRIDE
teardown_test_env

test_start "agent_resolve_model uses MODEL_ID env"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "agents": {"defaults": {}, "list": []}
}
EOF
_CONFIG_CACHE=""
config_load
export MODEL_ID="glm-5"
result="$(agent_resolve_model "main")"
assert_eq "$result" "glm-5"
unset MODEL_ID
teardown_test_env

# ---- agent_resolve_provider ----

test_start "agent_resolve_provider returns anthropic for claude models"
setup_test_env
result="$(agent_resolve_provider "claude-opus-4-6")"
assert_eq "$result" "anthropic"
teardown_test_env

test_start "agent_resolve_provider returns openai for gpt models"
setup_test_env
result="$(agent_resolve_provider "gpt-4o")"
assert_eq "$result" "openai"
teardown_test_env

test_start "agent_resolve_provider returns zhipu for glm models"
setup_test_env
result="$(agent_resolve_provider "glm-5")"
assert_eq "$result" "zhipu"
teardown_test_env

test_start "agent_resolve_provider returns ollama for glm-5:cloud"
setup_test_env
result="$(agent_resolve_provider "glm-5:cloud")"
assert_eq "$result" "ollama"
teardown_test_env

test_start "agent_resolve_provider returns anthropic for unknown models"
setup_test_env
result="$(agent_resolve_provider "unknown-model-xyz")"
assert_eq "$result" "anthropic"
teardown_test_env

test_start "agent_resolve_fallback_model uses defaults chain"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "agents": {
    "defaults": {
      "fallbackModels": ["gpt-4o", "gemini-2.5-pro"]
    },
    "list": []
  }
}
EOF
_CONFIG_CACHE=""
config_load
result="$(agent_resolve_fallback_model "main" "claude-opus-4-6")"
assert_eq "$result" "gpt-4o"
result="$(agent_resolve_fallback_model "main" "gpt-4o")"
assert_eq "$result" "gemini-2.5-pro"
teardown_test_env

test_start "agent_resolve_fallback_model uses agent-specific chain"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "agents": {
    "defaults": {
      "fallbackModels": ["gpt-4o", "gemini-2.5-pro"]
    },
    "list": [
      {
        "id": "ops",
        "fallbackModels": ["gpt-4o-mini", "gemini-2.5-flash"]
      }
    ]
  }
}
EOF
_CONFIG_CACHE=""
config_load
result="$(agent_resolve_fallback_model "ops" "claude-sonnet-4-5")"
assert_eq "$result" "gpt-4o-mini"
result="$(agent_resolve_fallback_model "ops" "gpt-4o-mini")"
assert_eq "$result" "gemini-2.5-flash"
teardown_test_env

# ---- agent_build_system_prompt ----

test_start "agent_build_system_prompt includes identity"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "agents": {
    "defaults": {"identity": "a helpful coding assistant"},
    "list": []
  }
}
EOF
_CONFIG_CACHE=""
config_load
result="$(agent_build_system_prompt "main")"
assert_contains "$result" "a helpful coding assistant"
teardown_test_env

test_start "agent_build_system_prompt includes tool descriptions"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "agents": {"defaults": {}, "list": []}
}
EOF
_CONFIG_CACHE=""
config_load
result="$(agent_build_system_prompt "main")"
assert_contains "$result" "Available tools"
assert_contains "$result" "web_fetch"
assert_contains "$result" "shell"
assert_contains "$result" "memory"
teardown_test_env

test_start "agent_build_system_prompt default identity"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "agents": {"defaults": {}, "list": []}
}
EOF
_CONFIG_CACHE=""
config_load
result="$(agent_build_system_prompt "main")"
assert_contains "$result" "helpful AI assistant"
teardown_test_env

test_start "agent_build_system_prompt includes custom systemPrompt"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "agents": {
    "defaults": {"systemPrompt": "Always respond in haiku format."},
    "list": []
  }
}
EOF
_CONFIG_CACHE=""
config_load
result="$(agent_build_system_prompt "main")"
assert_contains "$result" "haiku format"
teardown_test_env

# ---- agent_build_messages ----

test_start "agent_build_messages produces correct message array"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{"session": {"scope": "global"}}
EOF
_CONFIG_CACHE=""
config_load
f="$(session_file "main" "test")"
session_append "$f" "user" "hello"
session_append "$f" "assistant" "hi there"
result="$(agent_build_messages "$f" "new question" 50)"
assert_json_valid "$result"
length="$(printf '%s' "$result" | jq 'length')"
assert_eq "$length" "3"
# Last message should be the new user question
last_role="$(printf '%s' "$result" | jq -r '.[-1].role')"
assert_eq "$last_role" "user"
last_content="$(printf '%s' "$result" | jq -r '.[-1].content')"
assert_eq "$last_content" "new question"
teardown_test_env

test_start "agent_build_messages empty session"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{"session": {"scope": "global"}}
EOF
_CONFIG_CACHE=""
config_load
f="${BASHCLAW_STATE_DIR}/sessions/empty.jsonl"
result="$(agent_build_messages "$f" "first message" 50)"
assert_json_valid "$result"
length="$(printf '%s' "$result" | jq 'length')"
assert_eq "$length" "1"
teardown_test_env

test_start "openai message conversion flattens tool blocks"
setup_test_env
messages='[
  {"role":"assistant","content":[
    {"type":"text","text":"Working on it"},
    {"type":"tool_use","id":"tool_123","name":"web_search","input":{"q":"bashclaw"}}
  ]},
  {"role":"user","content":[
    {"type":"tool_result","tool_use_id":"tool_123","content":"{\"ok\":true}","is_error":false}
  ]}
]'
result="$(_openai_convert_messages "system prompt" "$messages")"
assert_json_valid "$result"
assert_eq "$(printf '%s' "$result" | jq -r '.[0].role')" "system"
assert_eq "$(printf '%s' "$result" | jq -r '.[1].role')" "assistant"
assert_eq "$(printf '%s' "$result" | jq -r '.[1].tool_calls[0].id')" "tool_123"
assert_eq "$(printf '%s' "$result" | jq -r '.[1].tool_calls[0].function.name')" "web_search"
assert_eq "$(printf '%s' "$result" | jq -r '.[2].role')" "tool"
assert_eq "$(printf '%s' "$result" | jq -r '.[2].tool_call_id')" "tool_123"
assert_eq "$(printf '%s' "$result" | jq -r '.[2].content')" '{"ok":true}'
teardown_test_env

test_start "openai message conversion keeps assistant tool-call content as string"
setup_test_env
messages='[
  {"role":"assistant","content":[
    {"type":"tool_use","id":"tool_456","name":"memory","input":{"action":"get","key":"todo"}}
  ]}
]'
result="$(_openai_convert_messages "system prompt" "$messages")"
assert_json_valid "$result"
assert_eq "$(printf '%s' "$result" | jq -r '.[1].role')" "assistant"
assert_eq "$(printf '%s' "$result" | jq -r '.[1].content')" ""
assert_eq "$(printf '%s' "$result" | jq -r '.[1].tool_calls[0].id')" "tool_456"
teardown_test_env

test_start "agent_resolve_model maps ollama alias to glm-5:cloud"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "agents": {"defaults": {}, "list": []}
}
EOF
_CONFIG_CACHE=""
config_load
export MODEL_ID="ollama"
result="$(agent_resolve_model "main")"
assert_eq "$result" "glm-5:cloud"
unset MODEL_ID
teardown_test_env

# ---- agent_build_tools_spec ----

test_start "agent_build_tools_spec generates valid tool specs"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "agents": {"defaults": {}, "list": []}
}
EOF
_CONFIG_CACHE=""
config_load
result="$(agent_build_tools_spec "main")"
assert_json_valid "$result"
length="$(printf '%s' "$result" | jq 'length')"
assert_gt "$length" 0
teardown_test_env

test_start "agent_build_tools_spec filters to configured tools"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "agents": {
    "defaults": {"tools": ["memory", "shell"]},
    "list": []
  }
}
EOF
_CONFIG_CACHE=""
config_load
result="$(agent_build_tools_spec "main")"
assert_json_valid "$result"
length="$(printf '%s' "$result" | jq 'length')"
assert_eq "$length" "2"
names="$(printf '%s' "$result" | jq -r '.[].name' | sort | tr '\n' ',')"
assert_contains "$names" "memory"
assert_contains "$names" "shell"
teardown_test_env

# ---- agent_track_usage writes to usage.jsonl ----

test_start "agent_track_usage writes to usage.jsonl"
setup_test_env
ensure_dir "${BASHCLAW_STATE_DIR}/usage"
agent_track_usage "main" "claude-opus-4-6" 1000 500
usage_file="${BASHCLAW_STATE_DIR}/usage/usage.jsonl"
assert_file_exists "$usage_file"
line="$(tail -n 1 "$usage_file")"
assert_json_valid "$line"
aid="$(printf '%s' "$line" | jq -r '.agent_id')"
assert_eq "$aid" "main"
model="$(printf '%s' "$line" | jq -r '.model')"
assert_eq "$model" "claude-opus-4-6"
it="$(printf '%s' "$line" | jq '.input_tokens')"
assert_eq "$it" "1000"
ot="$(printf '%s' "$line" | jq '.output_tokens')"
assert_eq "$ot" "500"
teardown_test_env

# ---- agent_estimate_tokens returns number > 0 ----

test_start "agent_estimate_tokens returns number > 0 for non-empty session"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{"session": {"scope": "global"}}
EOF
_CONFIG_CACHE=""
config_load
f="$(session_file "main" "test")"
session_append "$f" "user" "hello world this is a test"
session_append "$f" "assistant" "sure here is my response to your query"
tokens="$(agent_estimate_tokens "$f")"
assert_match "$tokens" '^[0-9]+$'
assert_gt "$tokens" 0
teardown_test_env

test_start "agent_estimate_tokens returns 0 for missing file"
setup_test_env
tokens="$(agent_estimate_tokens "/nonexistent/session.jsonl")"
assert_eq "$tokens" "0"
teardown_test_env

# ---- cmd_agent mobile helpers ----

test_start "_cmd_agent_current_model uses override first"
setup_test_env
AGENT_MODEL_OVERRIDE="gpt-4o-mini"
result="$(_cmd_agent_current_model "main")"
assert_eq "$result" "gpt-4o-mini"
unset AGENT_MODEL_OVERRIDE
teardown_test_env

test_start "_cmd_agent_set_model_override reset clears override"
setup_test_env
AGENT_MODEL_OVERRIDE="gpt-4o-mini"
_cmd_agent_set_model_override reset
assert_eq "${AGENT_MODEL_OVERRIDE:-}" ""
teardown_test_env

test_start "_cmd_agent_resolve_model_input expands unique prefix"
setup_test_env
result="$(_cmd_agent_resolve_model_input "gpt-4o-m")"
assert_eq "$result" "gpt-4o-mini"
teardown_test_env

test_start "_cmd_agent_resolve_model_input shows matches for ambiguous prefix"
setup_test_env
stdout_file="${_TEST_TMPDIR}/stdout.txt"
stderr_file="${_TEST_TMPDIR}/stderr.txt"
_cmd_agent_resolve_model_input "gpt" >"$stdout_file" 2>"$stderr_file"
result="$(cat "$stdout_file")"
status_text="$(cat "$stderr_file")"
assert_eq "$result" ""
assert_contains "$status_text" "Model matches:"
assert_contains "$status_text" "gpt-4o"
assert_contains "$status_text" "gpt-4o-mini"
teardown_test_env

test_start "_cmd_agent_prompt_label includes override model"
setup_test_env
AGENT_MODEL_OVERRIDE="gpt-4o-mini"
result="$(_cmd_agent_prompt_label)"
assert_eq "$result" "You[gpt-4o-mini@openai]"
unset AGENT_MODEL_OVERRIDE
teardown_test_env

test_start "_cmd_agent_collect_multiline joins lines until /end"
setup_test_env
result="$(printf 'first line
second line
/end
' | _cmd_agent_collect_multiline)"
assert_eq "$result" $'first line
second line'
teardown_test_env

test_start "_cmd_agent_compact_mode returns true on Termux"
setup_test_env
platform_is_termux() { return 0; }
if _cmd_agent_compact_mode; then
  _test_pass
else
  _test_fail "compact mode should enable on Termux"
fi
teardown_test_env

test_start "_cmd_agent_notify_completion sends notification when enabled"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{"termux": {"notifyOnAgentResponse": true}}
EOF
_CONFIG_CACHE=""
config_load
mock_dir="${_TEST_TMPDIR}/mockbin"
mkdir -p "$mock_dir"
notify_file="${_TEST_TMPDIR}/notify.txt"
cat > "${mock_dir}/termux-notification" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "__NOTIFY_FILE__"
EOF
sed -i "s|__NOTIFY_FILE__|$notify_file|" "${mock_dir}/termux-notification"
chmod +x "${mock_dir}/termux-notification"
OLD_PATH="$PATH"
PATH="${mock_dir}:$PATH"
platform_is_termux() { return 0; }
platform_termux_api_available() { [[ "$1" == "termux-notification" ]]; }
_cmd_agent_notify_completion "finished task successfully"
PATH="$OLD_PATH"
args="$(cat "$notify_file")"
assert_contains "$args" "BashClaw reply ready"
teardown_test_env


test_start "agent_build_system_prompt includes termux operator guidance when enabled"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "termux": {"operatorMode": true},
  "agents": {"defaults": {}, "list": []}
}
EOF
_CONFIG_CACHE=""
config_load
result="$(agent_build_system_prompt "main")"
assert_contains "$result" "Termux operator mode"
assert_contains "$result" "termux_recipe"
teardown_test_env


test_start "_cmd_agent_prompt_label includes resolved model and provider"
setup_test_env
cat > "$BASHCLAW_CONFIG" <<'EOF'
{
  "agents": {
    "defaults": {"model": "gpt-4o-mini"},
    "list": []
  }
}
EOF
_CONFIG_CACHE=""
config_load
result="$(_cmd_agent_prompt_label "main")"
assert_eq "$result" "You[gpt-4o-mini@openai]"
teardown_test_env

test_start "_cmd_agent_complete_line expands unique slash command"
setup_test_env
result="$(_cmd_agent_complete_line "/sta")"
assert_eq "$result" "/status"
teardown_test_env

test_start "_cmd_agent_complete_line expands model prefix"
setup_test_env
result="$(_cmd_agent_complete_line "/model gpt-4o-m")"
assert_eq "$result" "/model gpt-4o-mini"
teardown_test_env

test_start "_cmd_agent_complete_line shows ambiguous slash matches"
setup_test_env
stdout_file="${_TEST_TMPDIR}/stdout-complete.txt"
stderr_file="${_TEST_TMPDIR}/stderr-complete.txt"
_cmd_agent_complete_line "/mo" >"$stdout_file" 2>"$stderr_file"
result="$(cat "$stdout_file")"
status_text="$(cat "$stderr_file")"
assert_eq "$result" "/mo"
assert_contains "$status_text" "Completion matches:"
assert_contains "$status_text" "/model"
assert_contains "$status_text" "/models"
teardown_test_env

test_start "_cmd_agent_collect_block_input joins lines until terminator"
setup_test_env
result="$(printf 'first
second
:::
' | _cmd_agent_collect_block_input ':::')"
assert_eq "$result" $'first
second'
teardown_test_env

test_start "_cmd_agent_collect_editor_input reads edited content"
setup_test_env
editor_script="${_TEST_TMPDIR}/mock-editor.sh"
cat > "$editor_script" <<'EOF'
#!/usr/bin/env bash
printf '# ignored
from editor
second line
' > "$1"
EOF
chmod +x "$editor_script"
EDITOR="$editor_script"
result="$(_cmd_agent_collect_editor_input)"
assert_eq "$result" $'from editor
second line'
unset EDITOR
teardown_test_env

test_start "_cmd_agent_apply_setting persists notify"
setup_test_env
result="$(_cmd_agent_apply_setting notify on)"
assert_eq "$result" "notifyOnAgentResponse = true"
assert_eq "$(config_get '.termux.notifyOnAgentResponse' 'false')" "true"
teardown_test_env

test_start "_cmd_agent_apply_setting persists default model"
setup_test_env
result="$(_cmd_agent_apply_setting model gpt-4o-m)"
assert_eq "$result" "default model = gpt-4o-mini"
assert_eq "$(config_get '.agents.defaults.model' '')" "gpt-4o-mini"
teardown_test_env
report_results
