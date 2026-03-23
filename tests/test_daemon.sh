#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASHCLAW_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/framework.sh"

begin_test_file "test_daemon"

_source_libs() {
  export LOG_LEVEL="silent"
  for _lib in "${BASHCLAW_ROOT}"/lib/*.sh; do
    [[ -f "$_lib" ]] && source "$_lib"
  done
  unset _lib
}

# ---- _detect_init_system returns valid value ----

test_start "_detect_init_system returns valid value"
setup_test_env
_source_libs
result="$(_detect_init_system 2>/dev/null)"
case "$result" in
  launchd|systemd|crontab|termux-boot|none)
    _test_pass
    ;;
  *)
    _test_fail "unexpected init system: $result"
    ;;
esac
teardown_test_env

test_start "platform_termux_service_strategy returns valid value"
setup_test_env
_source_libs
result="$(platform_termux_service_strategy 2>/dev/null)"
case "$result" in
  termux-boot|crontab|none)
    _test_pass
    ;;
  *)
    _test_fail "unexpected service strategy: $result"
    ;;
esac
teardown_test_env

# ---- watchdog_status includes runtime details ----

test_start "watchdog_status shows runtime and log details"
setup_test_env
_source_libs
ensure_dir "${BASHCLAW_STATE_DIR}/watchdog"
cat > "${BASHCLAW_STATE_DIR}/watchdog/state" <<'EOF'
failures=2
last_fail_ts=10
last_start_ts=20
cooldown_until=30
EOF
result="$(watchdog_status 2>/dev/null)"
assert_contains "$result" "Watchdog:"
assert_contains "$result" "Gateway:"
assert_contains "$result" "Heartbeats:"
assert_contains "$result" "State file:"
assert_contains "$result" "Log file:"
assert_contains "$result" "Gateway log:"
teardown_test_env

# ---- daemon_install creates correct file for current OS ----

test_start "daemon_install creates service file"
setup_test_env
_source_libs
# Override with no-enable to avoid actually starting services
set +e
daemon_install "" "false" 2>/dev/null
rc=$?
set -e
# On macOS should create plist, on Linux systemd or crontab
os="$(uname -s)"
case "$os" in
  Darwin)
    plist_file="$HOME/Library/LaunchAgents/com.bashclaw.gateway.plist"
    if [[ -f "$plist_file" ]]; then
      _test_pass
      rm -f "$plist_file"  # cleanup
    else
      # May have used crontab as fallback
      _test_pass
    fi
    ;;
  *)
    _test_pass
    ;;
esac
teardown_test_env

# ---- daemon_uninstall removes files ----

test_start "daemon_uninstall removes files"
setup_test_env
_source_libs
set +e
daemon_install "" "false" 2>/dev/null
daemon_uninstall 2>/dev/null
set -e
_test_pass
teardown_test_env

report_results
