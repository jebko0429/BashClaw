# BashClaw x Termux God-Mode Plan

## Goal

Make BashClaw feel Termux-native enough that it acts like the control plane of the environment, not just an app running inside it.

The target is not merely "portable shell agent on Android."

The target is:

"Termux-native agent runtime for Android power users."

## Product Direction

BashClaw should become the shell brain of Termux:

- command orchestrator
- phone-aware automation runtime
- persistent memory and state layer
- notification-capable assistant
- scheduled task engine
- file and workspace operator
- chat entrypoint across terminal, browser, and messaging

## Core Principles

- Treat Termux as a first-class platform, not a compatibility edge case.
- Prefer app-owned writable paths over standard Linux assumptions.
- Build for Android lifecycle constraints: battery, storage permissions, boot, background execution.
- Make mobile UX intentional rather than desktop behavior squeezed onto a phone.
- Keep BashClaw usable in plain Bash, but optimize behavior when running under Termux.

## What "One With Termux" Means

- No hard assumptions about `/tmp`, `/var`, `systemd`, or desktop browser behavior.
- Deep integration with `termux-*` commands where available.
- Safe handling of app sandbox paths and shared storage.
- Background services that survive Android realities as well as possible.
- Notification-driven workflows so the user does not need an active terminal open.
- A tool layer that can observe and act on phone state.

## Missing Pieces

### Platform Layer

- Dedicated Termux environment detection.
- Centralized path resolution for temp, cache, logs, config, downloads, and shared storage.
- Package and capability detection via `pkg` and `termux-*` command availability.
- Better Android-safe daemon and watchdog behavior.

### Native Termux Tools

Expose first-class tools around:

- `termux-notification`
- `termux-toast`
- `termux-open`
- `termux-share`
- `termux-clipboard-get`
- `termux-clipboard-set`
- `termux-location`
- `termux-battery-status`
- `termux-wifi-connectioninfo`
- `termux-telephony-deviceinfo`
- `termux-sms-send`
- `termux-camera-photo`

### UX Gaps

- Mobile-first flows for setup and daily use.
- Better browser dashboard behavior on phone screens.
- Better notification and background-task UX.
- Cleaner automation patterns for local-device workflows.

### Reliability Gaps

- Remove remaining Linux-path assumptions.
- Harden installer and update flows for Termux.
- Validate service behavior across app restarts, boot, and idle periods.
- Improve offline/local-first resilience.

## Recommended Architecture

Add a Termux-specific platform layer:

- `lib/platform_termux.sh`
- `lib/tools_termux.sh`
- `lib/cmd_termux.sh`

Responsibilities:

- detect whether runtime is Termux
- expose Termux-safe writable directories
- detect installed capabilities and missing packages
- wrap `termux-*` APIs as BashClaw tools
- support Android-safe background behaviors
- expose notification, clipboard, device-state, and media helpers

## Command Surface To Add

### `bashclaw termux doctor`

Checks:

- whether running inside Termux
- whether Termux:API commands are available
- storage permission state
- writable temp/cache/state directories
- battery optimization concerns
- boot integration readiness
- package health and missing dependencies

### `bashclaw termux enable`

Initializes:

- Termux-native directories
- recommended defaults
- capability checks
- optional notifications and boot setup

### `bashclaw termux status`

Shows:

- device/runtime summary
- battery info
- network info
- API capability availability
- daemon/watchdog health
- storage path map

## First-Class Termux Tooling

### Device and Environment

- battery status
- wifi info
- telephony info
- location
- volume and brightness wrappers if available

### User Interaction

- notifications
- toast messages
- open URL/file
- share text/file
- clipboard read/write

### Media and Files

- camera capture
- screenshot integration if available
- download and shared storage helpers
- file picker or import/export flows where practical

## Example Workflows

- "Notify me when battery drops below 20%."
- "Copy the current clipboard into memory."
- "Summarize the latest downloaded file."
- "Open this generated report in Android."
- "Take a photo and attach it to the current task."
- "Check wifi details and save a diagnostic snapshot."
- "Run every morning and notify me with today’s agenda."

## Background Execution Strategy

Because Android is hostile to long-running background processes, BashClaw should support:

- Termux boot integration
- watchdog restart behavior
- resumable jobs
- idempotent task execution
- notification-based completion reporting
- graceful degradation when background execution is interrupted

## Packaging Priorities

- Avoid assumptions about global Linux directories.
- Keep all critical state inside safe writable app-owned locations by default.
- Make installer and updater Termux-aware.
- Prefer dependency checks with actionable `pkg install ...` guidance.

## Roadmap

### Phase 1: Foundations [x]

- add Termux environment detection
- centralize writable path resolution
- remove remaining `/tmp` assumptions
- add `bashclaw termux doctor`
- add capability detection for Termux API commands

### Phase 2: Native Tools [x]

- add clipboard tool support
- add notification and toast support
- add battery and wifi status tools
- add open/share helpers
- expose these tools through normal BashClaw tool routing

### Phase 3: Runtime Hardening [x]

- improve daemon/watchdog behavior for Termux
- add boot integration helpers
- harden update/install flows
- improve local logging and recovery behavior

### Phase 4: Mobile UX [x]

- improve phone-sized web dashboard behavior
- add Termux-focused onboarding
- improve interactive CLI for mobile usage patterns
- make notifications part of normal task completion flows

### Phase 5: Phone Operator Mode [x]

- add richer device-state tools
- add automation recipes for battery, downloads, clipboard, and connectivity
- support agent-driven local-device workflows as a first-class product mode

## Success Criteria

BashClaw should feel like the "brain of Termux" when:

- it installs cleanly in Termux with minimal manual repair
- it uses only safe writable paths by default
- it can notify, open, share, and inspect device state
- it survives common Android lifecycle interruptions reasonably well
- it can automate useful phone-local workflows
- the user prefers invoking BashClaw instead of stitching shell scripts manually

## Immediate Next Step

Validate and harden the Termux operator mode on real devices:

1. run end-to-end checks on fresh Termux installs and existing power-user setups
2. verify boot, watchdog, notification, and storage flows across app restarts and idle periods
3. expand regression coverage for operator recipes and mobile dashboard actions
4. tighten install and upgrade docs around Termux:API, Termux:Boot, and shared storage permissions

### Phase 6: Operator Recipes and Controls [x]

- add device-control tools for sensors, torch, brightness, volume, vibration, and wakelock
- expand built-in phone recipes (alerts, quiet mode, daily digest, connectivity watchdog)
- add dashboard mobile widgets for quick device-state actions
- tighten .env and secret handling for mobile operator mode
- add CLI/mobile flows to toggle operator mode and recipes
