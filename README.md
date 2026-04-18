# WatchDogger

Monitor Safari tabs for runaway CPU usage and kill them with a native notification.

## Features

- Menu bar utility that runs silently in the background (no Dock icon)
- Monitors WebKit.WebContent processes (Safari tabs) for high CPU usage
- Sends native macOS notifications when a tab exceeds the CPU threshold
- One-tap Kill button in notifications to terminate runaway processes
- Configurable CPU threshold, check interval, and notification cooldown
- Lightweight single-file Swift application
- Programmatically generated app icon (blue shield with red eye)

## Quick Start

1. **Build the app**
   ```bash
   cd /Users/sh/code/WatchDogger
   swift main.swift
   ```

2. **Generate the icon** (optional, only if icon is missing)
   ```bash
   swift make-icon.swift
   ```

3. **Run the binary**
   ```bash
   ./main
   ```

4. **Grant notification permissions** when prompted by macOS

## Configuration

Edit the constants at the top of `main.swift`:

```swift
let cpuThreshold: Double = 90.0           // CPU % threshold
let checkInterval: TimeInterval = 30      // Check every N seconds
let notificationCooldown: TimeInterval = 60 // Don't re-notify same PID for N seconds
```

## How It Works

1. Every 30 seconds (configurable), the app runs `ps` to get a list of WebKit processes and their CPU usage
2. If a process exceeds the CPU threshold, a notification is sent
3. Users can tap "Kill" to send SIGTERM to the process, or "Ignore" to dismiss
4. A cooldown prevents duplicate notifications for the same process within 60 seconds

## Menu Bar

- **Check Now** — Run a check immediately
- **Quit** — Exit the app

The app runs as LSUIElement (no Dock icon) and starts automatically as a menu bar item.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 5.x |
| Framework | Cocoa / AppKit |
| Notifications | UserNotifications.framework |
| Process Monitoring | ps command (shell) |
| Codesigning | Ad-hoc |

## Project Structure

```
WatchDogger/
├── main.swift              # App delegate, monitoring logic, notification handling
├── make-icon.swift         # Icon generator (blue shield + red eye)
├── WatchDogger.app/        # Compiled app bundle
│   └── Contents/
│       ├── Info.plist      # Bundle configuration
│       ├── MacOS/
│       │   └── WatchDogger # Compiled binary
│       └── Resources/
│           └── AppIcon.icns # Generated icon set
└── README.md
```

## Requirements

- macOS 14 (Sonoma) or later
- Notification permissions enabled

## Notes

- The app is code-signed ad-hoc (no Apple Developer account required)
- Bundle ID: `com.sh.watchdogger`
- No external dependencies
- Single-threaded event loop with Timer-based checks
