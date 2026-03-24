# BashClaw Termux Validation Checklist

Use this checklist on real Android devices to verify that BashClaw behaves correctly in Termux before shipping changes that affect mobile workflows.

## Test Matrix

Record these details for each run:

- device model and Android version
- Termux version
- whether Termux:API is installed
- whether Termux:Boot is installed
- whether storage permission has been granted
- whether the device is using battery optimization restrictions

## 1. Fresh Install

Run:

```sh
pkg install jq curl termux-api
./install.sh
bashclaw termux doctor
```

Verify:

- `bashclaw termux doctor` reports a Termux-style runtime
- temp and state directories are writable
- missing optional capabilities are shown as warnings, not fatal errors
- the command exits successfully when core dependencies are present

## 2. Enable Mobile Defaults

Run:

```sh
bashclaw termux enable --setup-storage --install-boot --notify
bashclaw termux status
bashclaw termux paths
```

Verify:

- state, cache, config, logs, memory, and sessions directories exist
- shared storage links exist after `--setup-storage`
- the boot script exists under `~/.termux/boot/`
- `bashclaw termux status` shows the expected paths and service mode
- completion notification succeeds when Termux:API is available

## 3. Operator Mode

Run:

```sh
bashclaw termux operator enable
bashclaw termux operator status
```

Verify:

- operator mode is enabled in config
- the default agent tool profile is `termux-operator`
- a new agent session exposes Termux tools without manual config edits

## 4. Termux API Smoke Tests

Run:

```sh
bashclaw agent -m "Send a toast saying BashClaw mobile check via termux_notify"
bashclaw agent -m "Copy the text mobile-check into the clipboard using termux_clipboard"
bashclaw termux recipes daily_digest run
```

If supported on the device, also verify:

- `termux_open` opens a URL or file intent correctly
- `termux_sms` can prepare and send a test message
- `termux_battery`, `termux_wifi`, and `termux_location` return valid JSON
- device control tools such as brightness, volume, torch, vibrate, and wakelock succeed or fail with clear error messages

## 5. Boot and Restart Resilience

Run:

```sh
bashclaw gateway start
bashclaw watchdog start
```

Verify:

- the gateway and watchdog can be started manually
- after killing the Termux app and reopening it, `bashclaw termux status` still reports sane paths and state
- after a device reboot with Termux:Boot installed, the boot script still exists and the expected service behavior occurs
- logs under BashClaw state directories show recoverable restarts instead of silent failures

## 6. Shared Storage and File Flows

Verify:

- files written to the Downloads helper path are visible from Android file apps
- generated reports can be opened through `termux_open`
- share flows succeed through `termux-share`
- missing storage permission produces actionable output instead of cryptic shell errors

## 7. Recipe Regression Pass

Run at least these built-ins:

```sh
bashclaw termux recipes clipboard run
bashclaw termux recipes connectivity run
bashclaw termux recipes battery run
bashclaw termux recipes daily_digest run
```

Verify:

- each recipe either completes successfully or returns a specific missing-capability error
- notification-based recipes do not hang when the terminal is backgrounded
- degraded connectivity states are surfaced clearly

## 8. Upgrade Path

Starting from an existing BashClaw install with prior state:

```sh
git pull --rebase
./bashclaw update
bashclaw termux doctor
```

Verify:

- upgrades do not break existing state directories or config
- boot integration remains intact
- operator mode settings survive the upgrade
- Termux tool commands still resolve correctly after the update

## Exit Criteria

A device passes validation when:

- fresh install and upgrade flows both succeed
- operator mode enables without manual repair
- core Termux API features work or degrade with explicit guidance
- boot, restart, and storage flows behave predictably
- built-in recipes complete without shell-level breakage
