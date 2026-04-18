# WatchDogger

Menu bar app for macOS that watches your CPU and kills runaway processes.

You know the drill: you leave a tab open, walk away, come back and your fans are screaming. Or some app just hangs and starts eating a whole core for no reason. WatchDogger sits in the menu bar, keeps an eye on things, and pings you with a notification when something goes wrong. You tap Kill, the process dies, you move on.

## Why

Apps hang. Tabs go rogue. Background processes lose their minds. macOS doesn't tell you about any of this until your battery is dead or your laptop is too hot to touch. WatchDogger fills that gap — it watches CPU usage and lets you deal with problems before they become problems.

## What it does

- Watches any process (or just specific ones from your watchlist) for high CPU
- Sends a native notification when something crosses the line
- Kill or Ignore straight from the notification, no windows to open
- Auto-kill mode if you don't even want to be asked
- Adapts the threshold when you're on battery (defaults to 25%)
- Shows you what's eating CPU right now via the "What's hot" menu
- Won't false-alarm on short spikes — needs 2+ readings in a row
- No Dock icon, just the menu bar

## Quick start

```bash
git clone https://github.com/shmlkv/WatchDogger.git
cd WatchDogger
bash build.sh
open WatchDogger.app
```

macOS will ask for notification permissions on first launch.

## Requirements

macOS 14+ (Sonoma). Nothing else — no dependencies, no packages, no Homebrew.

## How it works

WatchDogger uses `libproc` (the native macOS process API) to snapshot CPU usage. No shelling out to `ps` or `top`. Every 30 seconds it takes a reading, computes CPU percentage from the delta, and compares against your threshold. If a process stays above the threshold for two consecutive checks, you get a notification. Tap Kill to send SIGTERM, or Ignore to never hear about that process again.

When you're on battery, the threshold drops automatically so you catch smaller drains too.

## Settings

Open from the menu bar icon → "Open WatchDogger":

| Setting | Default | What it does |
|---------|---------|--------------|
| CPU threshold | 90% | How much CPU before you get alerted |
| Check interval | 30s | Time between readings |
| Cooldown | 60s | Don't nag about the same process within this window |
| Battery mode | On | Uses a lower threshold (25%) on battery |
| Monitor all apps | Off | Watch everything, not just the watchlist |
| Watchlist | Safari, Chrome | Which processes to keep an eye on |
| Auto-kill | Off | Skip the notification, just kill it |
| Sound | On | Play a sound with the notification |
| Launch at login | Off | Start automatically with macOS |

## Menu bar

- Open WatchDogger — settings window
- Check Now — run a check right now (skips the 2-reading requirement)
- What's hot — top 5 CPU consumers at this moment
- Quit

## Tech stack

| | |
|--|--|
| Swift | AppKit + SwiftUI for the settings window |
| libproc | `proc_pidinfo`, `proc_pidpath` for process monitoring |
| IOKit | `IOPSCopyPowerSourcesInfo` for battery state |
| UserNotifications | Native macOS notifications with actions |
| ServiceManagement | Login item support |

## Project structure

```
WatchDogger/
├── main.swift             # ProcessMonitor, notifications, menu bar, app delegate
├── SettingsWindow.swift   # Settings storage and SwiftUI settings view
├── build.sh               # Compile, generate icon + sound, sign
├── make-icon.swift        # Programmatic app icon (shield with eye)
├── make-sound.swift       # Generates alert.aiff
├── Info.plist             # LSUIElement, bundle ID
├── Tests/
│   └── WatchDoggerTests.swift
└── WatchDogger.app/
```

## Tests

```bash
swiftc -o /tmp/wd_tests Tests/WatchDoggerTests.swift && /tmp/wd_tests
```

Covers sustained detection logic, cooldown filtering, process name matching, and history window management.

## License

MIT
