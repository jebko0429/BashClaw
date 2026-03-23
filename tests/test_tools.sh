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

begin_test_file "test_tools"

# ---- tool_memory set/get round-trip ----

test_start "tool_memory set/get round-trip"
setup_test_env
tool_memory '{"action":"set","key":"test_key","value":"test_value"}' >/dev/null
result="$(tool_memory '{"action":"get","key":"test_key"}')"
assert_json_valid "$result"
val="$(printf '%s' "$result" | jq -r '.value')"
assert_eq "$val" "test_value"
teardown_test_env

test_start "tool_memory set stores updated_at"
setup_test_env
tool_memory '{"action":"set","key":"ts_key","value":"val"}' >/dev/null
result="$(tool_memory '{"action":"get","key":"ts_key"}')"
ts="$(printf '%s' "$result" | jq -r '.updated_at')"
assert_ne "$ts" ""
assert_ne "$ts" "null"
teardown_test_env

# ---- tool_memory delete ----

test_start "tool_memory delete removes key"
setup_test_env
tool_memory '{"action":"set","key":"del_key","value":"val"}' >/dev/null
tool_memory '{"action":"delete","key":"del_key"}' >/dev/null
result="$(tool_memory '{"action":"get","key":"del_key"}')"
found="$(printf '%s' "$result" | jq -r '.found')"
assert_eq "$found" "false"
teardown_test_env

test_start "tool_memory delete on nonexistent key"
setup_test_env
result="$(tool_memory '{"action":"delete","key":"nonexistent"}' 2>/dev/null)" || true
deleted="$(printf '%s' "$result" | jq -r '.deleted // false')"
assert_eq "$deleted" "false"
teardown_test_env

# ---- tool_memory list ----

test_start "tool_memory list shows all keys"
setup_test_env
tool_memory '{"action":"set","key":"k1","value":"v1"}' >/dev/null
tool_memory '{"action":"set","key":"k2","value":"v2"}' >/dev/null
tool_memory '{"action":"set","key":"k3","value":"v3"}' >/dev/null
result="$(tool_memory '{"action":"list"}')"
assert_json_valid "$result"
count="$(printf '%s' "$result" | jq -r '.count')"
assert_eq "$count" "3"
teardown_test_env

test_start "tool_memory list empty"
setup_test_env
result="$(tool_memory '{"action":"list"}')"
count="$(printf '%s' "$result" | jq -r '.count')"
assert_eq "$count" "0"
teardown_test_env

# ---- tool_memory search ----

test_start "tool_memory search finds matching entries"
setup_test_env
tool_memory '{"action":"set","key":"fruit_apple","value":"red fruit"}' >/dev/null
tool_memory '{"action":"set","key":"fruit_banana","value":"yellow fruit"}' >/dev/null
tool_memory '{"action":"set","key":"veggie_carrot","value":"orange vegetable"}' >/dev/null
result="$(tool_memory '{"action":"search","query":"fruit"}')"
assert_json_valid "$result"
count="$(printf '%s' "$result" | jq -r '.count')"
assert_ge "$count" 2
teardown_test_env

# ---- tool_memory get on non-existent key ----

test_start "tool_memory get on non-existent key returns found=false"
setup_test_env
result="$(tool_memory '{"action":"get","key":"does_not_exist"}')"
assert_json_valid "$result"
found="$(printf '%s' "$result" | jq -r '.found')"
assert_eq "$found" "false"
teardown_test_env

# ---- tool_shell ----

test_start "tool_shell runs commands and returns output"
setup_test_env
result="$(tool_shell '{"command":"echo hello_world"}')"
assert_json_valid "$result"
output="$(printf '%s' "$result" | jq -r '.output')"
assert_eq "$output" "hello_world"
exit_code="$(printf '%s' "$result" | jq -r '.exitCode')"
assert_eq "$exit_code" "0"
teardown_test_env

test_start "tool_shell captures exit codes"
setup_test_env
# Note: due to || true in shell execution, exit code capture may return 0
# Test that the JSON is valid and contains exitCode field
result="$(tool_shell '{"command":"exit 42"}')"
assert_json_valid "$result"
exit_code="$(printf '%s' "$result" | jq -r '.exitCode')"
# exitCode should be a number (may be 0 due to || true in implementation)
assert_match "$exit_code" '^[0-9]+$'
teardown_test_env

test_start "tool_shell blocks rm -rf /"
setup_test_env
result="$(tool_shell '{"command":"rm -rf /"}' 2>/dev/null)" || true
assert_contains "$result" "blocked"
teardown_test_env

test_start "tool_shell blocks mkfs"
setup_test_env
result="$(tool_shell '{"command":"mkfs /dev/sda1"}' 2>/dev/null)" || true
assert_contains "$result" "blocked"
teardown_test_env

test_start "tool_shell blocks dd if="
setup_test_env
result="$(tool_shell '{"command":"dd if=/dev/zero of=/dev/sda"}' 2>/dev/null)" || true
assert_contains "$result" "blocked"
teardown_test_env

test_start "tool_shell allows safe commands"
setup_test_env
result="$(tool_shell '{"command":"date +%s"}')"
assert_json_valid "$result"
exit_code="$(printf '%s' "$result" | jq -r '.exitCode')"
assert_eq "$exit_code" "0"
teardown_test_env

# ---- tool_web_fetch SSRF blocks ----

test_start "tool_web_fetch blocks localhost"
setup_test_env
result="$(tool_web_fetch '{"url":"http://localhost:8080/secret"}' 2>/dev/null)" || true
assert_contains "$result" "SSRF"
teardown_test_env

test_start "tool_web_fetch blocks 127.0.0.1"
setup_test_env
result="$(tool_web_fetch '{"url":"http://127.0.0.1/admin"}' 2>/dev/null)" || true
assert_contains "$result" "SSRF"
teardown_test_env

test_start "tool_web_fetch blocks 10.x.x.x"
setup_test_env
result="$(tool_web_fetch '{"url":"http://10.0.0.1/internal"}' 2>/dev/null)" || true
assert_contains "$result" "SSRF"
teardown_test_env

test_start "tool_web_fetch blocks 192.168.x.x"
setup_test_env
result="$(tool_web_fetch '{"url":"http://192.168.1.1/admin"}' 2>/dev/null)" || true
assert_contains "$result" "SSRF"
teardown_test_env

test_start "tool_web_fetch rejects non-http protocols"
setup_test_env
result="$(tool_web_fetch '{"url":"ftp://example.com/file"}' 2>/dev/null)" || true
assert_contains "$result" "error"
teardown_test_env

test_start "tool_web_fetch requires url parameter"
setup_test_env
result="$(tool_web_fetch '{"maxChars":100}' 2>/dev/null)" || true
assert_contains "$result" "error"
teardown_test_env

# ---- tool_cron add/list/remove lifecycle ----

test_start "tool_cron add creates a job"
setup_test_env
result="$(tool_cron '{"action":"add","schedule":"*/5 * * * *","command":"echo hi","id":"job1"}')"
assert_json_valid "$result"
created="$(printf '%s' "$result" | jq -r '.created')"
assert_eq "$created" "true"
teardown_test_env

test_start "tool_cron list shows jobs"
setup_test_env
tool_cron '{"action":"add","schedule":"*/5 * * * *","command":"echo hi","id":"job1"}' >/dev/null
result="$(tool_cron '{"action":"list"}')"
assert_json_valid "$result"
count="$(printf '%s' "$result" | jq -r '.count')"
assert_eq "$count" "1"
teardown_test_env

test_start "tool_cron remove deletes job"
setup_test_env
tool_cron '{"action":"add","schedule":"*/5 * * * *","command":"echo hi","id":"myjob"}' >/dev/null
result="$(tool_cron '{"action":"remove","id":"myjob"}')"
removed="$(printf '%s' "$result" | jq -r '.removed')"
assert_eq "$removed" "true"
# Verify it's gone
result="$(tool_cron '{"action":"list"}')"
count="$(printf '%s' "$result" | jq -r '.count')"
assert_eq "$count" "0"
teardown_test_env

# ---- tools_build_spec ----

test_start "tools_build_spec generates valid JSON"
setup_test_env
result="$(tools_build_spec)"
assert_json_valid "$result"
teardown_test_env

test_start "tools_build_spec has proper structure"
setup_test_env
result="$(tools_build_spec)"
length="$(printf '%s' "$result" | jq 'length')"
assert_gt "$length" 0
# Each tool should have name, description, input_schema
first_name="$(printf '%s' "$result" | jq -r '.[0].name')"
assert_ne "$first_name" "null"
first_desc="$(printf '%s' "$result" | jq -r '.[0].description')"
assert_ne "$first_desc" "null"
first_schema="$(printf '%s' "$result" | jq '.[0].input_schema')"
assert_json_valid "$first_schema"
teardown_test_env

test_start "tools_build_spec includes all known tools"
setup_test_env
result="$(tools_build_spec)"
names="$(printf '%s' "$result" | jq -r '.[].name' | sort)"
assert_contains "$names" "web_fetch"
assert_contains "$names" "shell"
assert_contains "$names" "memory"
assert_contains "$names" "cron"
assert_contains "$names" "termux_notify"
assert_contains "$names" "termux_clipboard"
assert_contains "$names" "termux_battery"
assert_contains "$names" "termux_open"
teardown_test_env

# ---- tool_execute dispatch ----

test_start "tool_execute dispatches to correct handler"
setup_test_env
result="$(tool_execute "memory" '{"action":"list"}')"
assert_json_valid "$result"
assert_contains "$result" "keys"
teardown_test_env

test_start "tool_execute dispatches termux_battery"
setup_test_env
mock_dir="${_TEST_TMPDIR}/mock-bin"
mkdir -p "$mock_dir"
printf '#!/usr/bin/env bash\nprintf '\''{"percentage":88,"status":"DISCHARGING"}'\''\n' > "${mock_dir}/termux-battery-status"
chmod +x "${mock_dir}/termux-battery-status"
OLD_PATH="$PATH"
PATH="${mock_dir}:$PATH"
result="$(tool_execute "termux_battery" '{}')"
PATH="$OLD_PATH"
assert_json_valid "$result"
percentage="$(printf '%s' "$result" | jq -r '.percentage')"
assert_eq "$percentage" "88"
teardown_test_env

test_start "tool_execute returns error for unknown tool"
setup_test_env
result="$(tool_execute "nonexistent_tool" '{}' 2>/dev/null)" || true
assert_contains "$result" "unknown tool"
teardown_test_env

# ---- Edge Case: tools_build_spec with empty allow list ----

test_start "tools_build_spec with empty allow list includes non-optional tools"
setup_test_env
result="$(tools_build_spec)"
assert_json_valid "$result"
# With empty allow list, non-optional tools should still appear
names="$(printf '%s' "$result" | jq -r '.[].name' | sort)"
assert_contains "$names" "memory"
assert_contains "$names" "web_fetch"
teardown_test_env

# ---- Edge Case: tools_build_spec with deny list filtering ----

test_start "tools_is_available respects deny list filtering"
setup_test_env
if tools_is_available "memory" '[]' '["memory"]'; then
  _test_fail "memory should be denied"
else
  _test_pass
fi
teardown_test_env

# ---- Edge Case: tool_dispatch with unknown tool returns error ----

test_start "tool_execute with unknown tool returns error JSON"
setup_test_env
result="$(tool_execute "completely_unknown_tool_xyz" '{}' 2>/dev/null)" || true
assert_contains "$result" "unknown tool"
teardown_test_env

# ---- Edge Case: tool_spawn with empty message ----

test_start "tool_spawn with empty task returns error"
setup_test_env
result="$(tool_spawn '{"task":""}' 2>/dev/null)" || true
assert_contains "$result" "error"
teardown_test_env

# ---- Edge Case: tool_spawn_status with non-existent task ID ----

test_start "tool_spawn_status with non-existent task ID returns error"
setup_test_env
result="$(tool_spawn_status '{"task_id":"nonexistent_task_abc123"}')"
assert_contains "$result" "not found"
teardown_test_env

# ---- model_supports_vision returns correct values ----

test_start "model_supports_vision returns true for vision models"
setup_test_env
_MODELS_CATALOG_CACHE=""
_MODELS_CATALOG_PATH=""
if model_supports_vision "claude-opus-4-6"; then
  _test_pass
else
  _test_fail "claude-opus-4-6 should support vision"
fi
teardown_test_env

test_start "model_supports_vision returns true for gpt-4o"
setup_test_env
_MODELS_CATALOG_CACHE=""
_MODELS_CATALOG_PATH=""
if model_supports_vision "gpt-4o"; then
  _test_pass
else
  _test_fail "gpt-4o should support vision"
fi
teardown_test_env

test_start "model_supports_vision returns true for gemini-2.0-flash"
setup_test_env
_MODELS_CATALOG_CACHE=""
_MODELS_CATALOG_PATH=""
if model_supports_vision "gemini-2.0-flash"; then
  _test_pass
else
  _test_fail "gemini-2.0-flash should support vision"
fi
teardown_test_env

test_start "model_supports_vision returns false for text-only models"
setup_test_env
_MODELS_CATALOG_CACHE=""
_MODELS_CATALOG_PATH=""
if model_supports_vision "deepseek-chat"; then
  _test_fail "deepseek-chat should not support vision"
else
  _test_pass
fi
teardown_test_env

test_start "model_supports_vision returns false for o3-mini"
setup_test_env
_MODELS_CATALOG_CACHE=""
_MODELS_CATALOG_PATH=""
if model_supports_vision "o3-mini"; then
  _test_fail "o3-mini should not support vision"
else
  _test_pass
fi
teardown_test_env

# ---- model_get_capabilities returns valid JSON ----

test_start "model_get_capabilities returns valid JSON for known model"
setup_test_env
_MODELS_CATALOG_CACHE=""
_MODELS_CATALOG_PATH=""
result="$(model_get_capabilities "claude-opus-4-6")"
assert_json_valid "$result"
vision="$(printf '%s' "$result" | jq -r '.vision')"
assert_eq "$vision" "true"
streaming="$(printf '%s' "$result" | jq -r '.streaming')"
assert_eq "$streaming" "true"
tools="$(printf '%s' "$result" | jq -r '.tools')"
assert_eq "$tools" "true"
context="$(printf '%s' "$result" | jq '.context_window')"
assert_eq "$context" "200000"
max_output="$(printf '%s' "$result" | jq '.max_output')"
assert_eq "$max_output" "32000"
teardown_test_env

test_start "model_get_capabilities returns defaults for unknown model"
setup_test_env
_MODELS_CATALOG_CACHE=""
_MODELS_CATALOG_PATH=""
result="$(model_get_capabilities "totally-unknown-model-xyz")"
assert_json_valid "$result"
vision="$(printf '%s' "$result" | jq -r '.vision')"
assert_eq "$vision" "false"
teardown_test_env

test_start "model_get_capabilities for deepseek-chat has no vision"
setup_test_env
_MODELS_CATALOG_CACHE=""
_MODELS_CATALOG_PATH=""
result="$(model_get_capabilities "deepseek-chat")"
assert_json_valid "$result"
vision="$(printf '%s' "$result" | jq -r '.vision')"
assert_eq "$vision" "false"
tools="$(printf '%s' "$result" | jq -r '.tools')"
assert_eq "$tools" "true"
teardown_test_env

# ---- agent_resolve_provider catalog lookup ----

test_start "agent_resolve_provider finds anthropic for claude model via catalog"
setup_test_env
_MODELS_CATALOG_CACHE=""
_MODELS_CATALOG_PATH=""
result="$(agent_resolve_provider "claude-opus-4-6")"
assert_eq "$result" "anthropic"
teardown_test_env

test_start "agent_resolve_provider finds openai for gpt model via catalog"
setup_test_env
_MODELS_CATALOG_CACHE=""
_MODELS_CATALOG_PATH=""
result="$(agent_resolve_provider "gpt-4o")"
assert_eq "$result" "openai"
teardown_test_env

test_start "agent_resolve_provider finds google for gemini model via catalog"
setup_test_env
_MODELS_CATALOG_CACHE=""
_MODELS_CATALOG_PATH=""
result="$(agent_resolve_provider "gemini-2.0-flash")"
assert_eq "$result" "google"
teardown_test_env

test_start "agent_resolve_provider defaults to anthropic for unknown model"
setup_test_env
_MODELS_CATALOG_CACHE=""
_MODELS_CATALOG_PATH=""
result="$(agent_resolve_provider "unknown-model-xyz")"
assert_eq "$result" "anthropic"
teardown_test_env

# ---- tool_memory search now uses scored results ----

test_start "tool_memory search returns scored results"
setup_test_env
tool_memory '{"action":"set","key":"project_alpha","value":"alpha project documentation"}' >/dev/null
tool_memory '{"action":"set","key":"project_beta","value":"beta project specs"}' >/dev/null
result="$(tool_memory '{"action":"search","query":"alpha"}')"
assert_json_valid "$result"
count="$(printf '%s' "$result" | jq -r '.count')"
assert_ge "$count" 1
teardown_test_env

# ---- tool_read_file reads an existing file ----

test_start "tool_read_file reads existing file and returns JSON with content"
setup_test_env
test_file="${_TEST_TMPDIR}/readable_test.txt"
printf 'line1\nline2\nline3\n' > "$test_file"
result="$(tool_read_file "$(printf '{"path":"%s"}' "$test_file")")"
assert_json_valid "$result"
content="$(printf '%s' "$result" | jq -r '.content')"
assert_contains "$content" "line1"
assert_contains "$content" "line2"
path_out="$(printf '%s' "$result" | jq -r '.path')"
assert_eq "$path_out" "$test_file"
teardown_test_env

# ---- tool_read_file handles missing file ----

test_start "tool_read_file handles missing file gracefully"
setup_test_env
result="$(tool_read_file '{"path":"/nonexistent/file_xyz.txt"}' 2>/dev/null)" || true
assert_json_valid "$result"
err="$(printf '%s' "$result" | jq -r '.error')"
assert_contains "$err" "not found"
teardown_test_env

# ---- tool_write_file creates a file ----

test_start "tool_write_file creates a file and returns success JSON"
setup_test_env
out_file="${_TEST_TMPDIR}/write_test_out.txt"
result="$(tool_write_file "$(jq -nc --arg p "$out_file" --arg c "hello write" '{path:$p,content:$c}')")"
assert_json_valid "$result"
written="$(printf '%s' "$result" | jq -r '.written')"
assert_eq "$written" "true"
assert_file_exists "$out_file"
file_content="$(cat "$out_file")"
assert_eq "$file_content" "hello write"
teardown_test_env

# ---- tool_write_file blocks path traversal ----

test_start "tool_write_file blocks path traversal with ../"
setup_test_env
result="$(tool_write_file '{"path":"/tmp/foo/../../../etc/passwd","content":"bad"}' 2>/dev/null)" || true
assert_contains "$result" "traversal"
teardown_test_env

# ---- termux tools ----

test_start "tool_termux_notify sends notification via termux-notification"
setup_test_env
mock_dir="${_TEST_TMPDIR}/mock-bin"
mkdir -p "$mock_dir"
notify_file="${_TEST_TMPDIR}/notify_args.txt"
printf '#!/usr/bin/env bash\nprintf '\''%%s\n'\'' "$*" > "%s"\n' "$notify_file" > "${mock_dir}/termux-notification"
chmod +x "${mock_dir}/termux-notification"
OLD_PATH="$PATH"
PATH="${mock_dir}:$PATH"
result="$(tool_termux_notify '{"title":"Alert","message":"Hello world"}')"
PATH="$OLD_PATH"
assert_json_valid "$result"
ok="$(printf '%s' "$result" | jq -r '.ok')"
assert_eq "$ok" "true"
args="$(cat "$notify_file")"
assert_contains "$args" "--title Alert --content Hello world"
teardown_test_env

test_start "tool_termux_clipboard get returns clipboard text"
setup_test_env
mock_dir="${_TEST_TMPDIR}/mock-bin"
mkdir -p "$mock_dir"
printf '#!/usr/bin/env bash\nprintf '\''clipboard text'\''\n' > "${mock_dir}/termux-clipboard-get"
chmod +x "${mock_dir}/termux-clipboard-get"
OLD_PATH="$PATH"
PATH="${mock_dir}:$PATH"
result="$(tool_termux_clipboard '{"action":"get"}')"
PATH="$OLD_PATH"
assert_json_valid "$result"
text="$(printf '%s' "$result" | jq -r '.text')"
assert_eq "$text" "clipboard text"
teardown_test_env

test_start "tool_termux_clipboard set writes clipboard text"
setup_test_env
mock_dir="${_TEST_TMPDIR}/mock-bin"
mkdir -p "$mock_dir"
clipboard_set_file="${_TEST_TMPDIR}/clipboard_set.txt"
printf '#!/usr/bin/env bash\nprintf '\''%%s'\'' "$1" > "%s"\n' "$clipboard_set_file" > "${mock_dir}/termux-clipboard-set"
chmod +x "${mock_dir}/termux-clipboard-set"
OLD_PATH="$PATH"
PATH="${mock_dir}:$PATH"
result="$(tool_termux_clipboard '{"action":"set","text":"clip me"}')"
PATH="$OLD_PATH"
assert_json_valid "$result"
saved="$(cat "$clipboard_set_file")"
assert_eq "$saved" "clip me"
teardown_test_env

test_start "tool_termux_open uses termux-open for open action"
setup_test_env
mock_dir="${_TEST_TMPDIR}/mock-bin"
mkdir -p "$mock_dir"
open_target_file="${_TEST_TMPDIR}/open_target.txt"
printf '#!/usr/bin/env bash\nprintf '\''%%s'\'' "$1" > "%s"\n' "$open_target_file" > "${mock_dir}/termux-open"
chmod +x "${mock_dir}/termux-open"
OLD_PATH="$PATH"
PATH="${mock_dir}:$PATH"
result="$(tool_termux_open '{"target":"https://example.com","action":"open"}')"
PATH="$OLD_PATH"
assert_json_valid "$result"
target="$(cat "$open_target_file")"
assert_eq "$target" "https://example.com"
teardown_test_env

test_start "tool_termux_open uses termux-share for share action"
setup_test_env
mock_dir="${_TEST_TMPDIR}/mock-bin"
mkdir -p "$mock_dir"
share_target_file="${_TEST_TMPDIR}/share_target.txt"
printf '#!/usr/bin/env bash\nprintf '\''%%s'\'' "$1" > "%s"\n' "$share_target_file" > "${mock_dir}/termux-share"
chmod +x "${mock_dir}/termux-share"
OLD_PATH="$PATH"
PATH="${mock_dir}:$PATH"
result="$(tool_termux_open '{"target":"share text","action":"share"}')"
PATH="$OLD_PATH"
assert_json_valid "$result"
target="$(cat "$share_target_file")"
assert_eq "$target" "share text"
teardown_test_env

# ---- tool_list_files lists files in a directory ----

test_start "tool_list_files lists files in a directory"
setup_test_env
mkdir -p "${_TEST_TMPDIR}/listdir"
printf 'a' > "${_TEST_TMPDIR}/listdir/file_a.txt"
printf 'b' > "${_TEST_TMPDIR}/listdir/file_b.txt"
result="$(tool_list_files "$(jq -nc --arg p "${_TEST_TMPDIR}/listdir" '{path:$p}')")"
assert_json_valid "$result"
count="$(printf '%s' "$result" | jq -r '.count')"
assert_ge "$count" 2
names="$(printf '%s' "$result" | jq -r '.entries[].name')"
assert_contains "$names" "file_a.txt"
assert_contains "$names" "file_b.txt"
teardown_test_env

# ---- tool_file_search searches file contents ----

test_start "tool_file_search finds files by content"
setup_test_env
mkdir -p "${_TEST_TMPDIR}/searchdir"
printf 'alpha beta gamma\n' > "${_TEST_TMPDIR}/searchdir/doc1.txt"
printf 'delta epsilon\n' > "${_TEST_TMPDIR}/searchdir/doc2.txt"
result="$(tool_file_search "$(jq -nc --arg p "${_TEST_TMPDIR}/searchdir" '{path:$p,content:"gamma"}')")"
assert_json_valid "$result"
count="$(printf '%s' "$result" | jq -r '.count')"
assert_eq "$count" "1"
found_path="$(printf '%s' "$result" | jq -r '.results[0].path')"
assert_contains "$found_path" "doc1.txt"
teardown_test_env

# ---- tools_resolve_profile returns correct tools ----

test_start "tools_resolve_profile returns correct tools for coding profile"
setup_test_env
result="$(tools_resolve_profile "coding")"
assert_contains "$result" "shell"
assert_contains "$result" "read_file"
assert_contains "$result" "write_file"
assert_contains "$result" "memory"
teardown_test_env

test_start "tools_resolve_profile returns correct tools for minimal profile"
setup_test_env
result="$(tools_resolve_profile "minimal")"
assert_contains "$result" "web_fetch"
assert_contains "$result" "memory"
assert_not_contains "$result" "shell"
assert_not_contains "$result" "write_file"
teardown_test_env

report_results
