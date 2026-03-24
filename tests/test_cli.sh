#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHCLAW_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/framework.sh"

begin_test_file "test_cli"

CLI="${BASHCLAW_ROOT}/bashclaw"

# ---- bashclaw --version ----

test_start "bashclaw --version outputs version"
setup_test_env
result="$(bash "$CLI" --version 2>&1)"
assert_contains "$result" "BashClaw"
assert_match "$result" '[0-9]+\.[0-9]+\.[0-9]+'
teardown_test_env

test_start "bashclaw version outputs version"
setup_test_env
result="$(bash "$CLI" version 2>&1)"
assert_contains "$result" "BashClaw"
teardown_test_env

# ---- bashclaw --help ----

test_start "bashclaw --help shows usage"
setup_test_env
result="$(bash "$CLI" --help 2>&1)"
assert_contains "$result" "Usage:"
assert_contains "$result" "Commands:"
assert_contains "$result" "config"
assert_contains "$result" "session"
assert_contains "$result" "doctor"
assert_contains "$result" "termux"
teardown_test_env

test_start "bashclaw help shows usage"
setup_test_env
result="$(bash "$CLI" help 2>&1)"
assert_contains "$result" "Usage:"
teardown_test_env

test_start "bashclaw with no args shows usage"
setup_test_env
result="$(bash "$CLI" 2>&1)"
assert_contains "$result" "Usage:"
teardown_test_env

# ---- bashclaw config init ----

test_start "bashclaw config init creates config"
setup_test_env
result="$(bash "$CLI" config init 2>&1)"
assert_file_exists "$BASHCLAW_CONFIG"
content="$(cat "$BASHCLAW_CONFIG")"
assert_json_valid "$content"
teardown_test_env

# ---- bashclaw config show ----

test_start "bashclaw config show outputs JSON"
setup_test_env
bash "$CLI" config init >/dev/null 2>&1
result="$(bash "$CLI" config show 2>&1)"
assert_contains "$result" "agents"
teardown_test_env

# ---- bashclaw config get ----

test_start "bashclaw config get returns values"
setup_test_env
bash "$CLI" config init >/dev/null 2>&1
result="$(bash "$CLI" config get '.gateway.port' 2>&1)"
assert_contains "$result" "18789"
teardown_test_env

# ---- bashclaw config set ----

test_start "bashclaw config set updates values"
setup_test_env
bash "$CLI" config init >/dev/null 2>&1
bash "$CLI" config set '.gateway.port' '9999' >/dev/null 2>&1
result="$(bash "$CLI" config get '.gateway.port' 2>&1)"
assert_contains "$result" "9999"
teardown_test_env

# ---- bashclaw session list ----

test_start "bashclaw session list works with no sessions"
setup_test_env
bash "$CLI" config init >/dev/null 2>&1
result="$(bash "$CLI" session list 2>&1)"
# May output "No sessions found." or JSON array
assert_contains "$result" "session"
teardown_test_env

# ---- bashclaw doctor ----

test_start "bashclaw doctor checks dependencies"
setup_test_env
bash "$CLI" config init >/dev/null 2>&1
result="$(bash "$CLI" doctor 2>&1)" || true
assert_contains "$result" "BashClaw doctor"
assert_contains "$result" "bash"
assert_contains "$result" "jq"
assert_contains "$result" "curl"
teardown_test_env

# ---- bashclaw termux doctor ----

test_start "bashclaw termux doctor shows termux diagnostics"
setup_test_env
result="$(bash "$CLI" termux doctor 2>&1)" || true
assert_contains "$result" "BashClaw Termux doctor"
assert_contains "$result" "Writable temp base"
assert_contains "$result" "Termux API Commands"
teardown_test_env

# ---- bashclaw termux enable ----

test_start "bashclaw termux enable initializes state and config"
setup_test_env
export TERMUX_VERSION="0.118.0"
result="$(bash "$CLI" termux enable 2>&1)" || true
assert_contains "$result" "BashClaw Termux enable"
assert_contains "$result" "State dir:"
assert_contains "$result" "Config:"
assert_file_exists "$BASHCLAW_CONFIG"
unset TERMUX_VERSION
teardown_test_env

# ---- bashclaw status ----

test_start "bashclaw status shows state"
setup_test_env
bash "$CLI" config init >/dev/null 2>&1
result="$(bash "$CLI" status 2>&1)"
assert_contains "$result" "BashClaw status"
assert_contains "$result" "Version:"
assert_contains "$result" "State dir:"
teardown_test_env

# ---- Unknown command ----

test_start "bashclaw unknown command shows error"
setup_test_env
result="$(bash "$CLI" nonexistent_command 2>&1)" || true
# The error goes to stderr via log_error, then usage is printed
# Check that usage is shown (which means the error path was hit)
assert_contains "$result" "Usage:"
teardown_test_env


# ---- bashclaw termux recipes ----

test_start "bashclaw termux recipes lists built-in workflows"
setup_test_env
result="$(bash "$CLI" termux recipes 2>&1)" || true
assert_contains "$result" "BashClaw Termux recipes"
assert_contains "$result" "battery"
assert_contains "$result" "clipboard"
assert_contains "$result" "quiet_mode"
assert_contains "$result" "daily_digest"
assert_contains "$result" "connectivity_watchdog"
teardown_test_env

# ---- bashclaw termux operator ----

test_start "bashclaw termux operator enable sets termux profile"
setup_test_env
bash "$CLI" config init >/dev/null 2>&1
result="$(bash "$CLI" termux operator enable 2>&1)" || true
assert_contains "$result" "Termux operator mode enabled"
profile="$(jq -r '.agents.defaults.tools.profile' "$BASHCLAW_CONFIG")"
assert_eq "$profile" "termux-operator"
teardown_test_env


# ---- bashclaw skill import/list ----

test_start "bashclaw skill import adapts a ClawHub-style skill"
setup_test_env
source_skill="${BASHCLAW_STATE_DIR}/clawhub_skill"
mkdir -p "$source_skill"
printf '# Device Helper
Drive Android host workflows.
' > "${source_skill}/SKILL.md"
result="$(bash "$CLI" skill import main "$source_skill" 2>&1)"
assert_json_valid "$result"
listed="$(bash "$CLI" skill list main 2>&1)"
assert_contains "$listed" "Device Helper"
teardown_test_env

# ---- bashclaw skill disable/enable/remove ----

test_start "bashclaw skill disable enable and remove manage lifecycle"
setup_test_env
source_skill="${BASHCLAW_STATE_DIR}/life_skill"
mkdir -p "$source_skill"
printf '# Lifecycle
Skill lifecycle test.
' > "${source_skill}/SKILL.md"
bash "$CLI" skill import main "$source_skill" >/dev/null 2>&1
result="$(bash "$CLI" skill disable main lifecycle 2>&1)"
assert_contains "$result" '"enabled":false'
listed="$(bash "$CLI" skill list main 2>&1)"
assert_contains "$listed" '"enabled": false'
enable_result="$(bash "$CLI" skill enable main lifecycle 2>&1)"
assert_contains "$enable_result" '"enabled":true'
remove_result="$(bash "$CLI" skill remove main lifecycle 2>&1)"
assert_contains "$remove_result" '"removed":true'
final_list="$(bash "$CLI" skill list main 2>&1)"
assert_eq "$final_list" "[]"
teardown_test_env

report_results
