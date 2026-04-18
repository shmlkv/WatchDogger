import Cocoa
import UserNotifications
import Darwin
import IOKit.ps

// MARK: - Process Info

struct CPUProcessInfo {
    let name: String
    let cpu: Double
    let pid: String
}

// MARK: - ProcessMonitor Delegate Protocol

protocol ProcessMonitorDelegate: AnyObject {
    func processMonitor(_ monitor: ProcessMonitor, didDetectRunaway pid: String, cpu: Double, name: String)
    func processMonitor(_ monitor: ProcessMonitor, didAutoKill pid: String, cpu: Double, name: String)
}

// MARK: - ProcessMonitor

class ProcessMonitor {
    weak var delegate: ProcessMonitorDelegate?

    // All mutable state is accessed only on the main thread
    private var cpuHistory: [String: [Double]] = [:]
    private var lastNotified: [String: Date] = [:]
    private var previousCPUTimes: [pid_t: (user: UInt64, system: UInt64, timestamp: TimeInterval)] = [:]

    // Battery state cache — re-checked every 5th monitoring cycle
    private var cachedOnBattery: Bool = false
    private var checkCycleCount: Int = 0
    private let batteryCheckInterval = 5

    // System processes to exclude from monitoring
    private let excludedProcesses: Set<String> = [
        "kernel_task", "WindowServer", "WatchDogger", "loginwindow", "hidd",
        "coreaudiod", "powerd", "launchd", "syslogd", "configd", "mds",
        "mds_stores", "mdworker", "opendirectoryd", "distnoted",
        "usermanagerd", "trustd"
    ]

    // MARK: Native Process Listing (libproc)

    private struct RawProcessData {
        let pid: pid_t
        let name: String
        let path: String
        let cpuUser: UInt64
        let cpuSystem: UInt64
    }

    /// Snapshot all processes via libproc. Called on background queue.
    private func snapshotProcesses() -> [RawProcessData] {
        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else {
            NSLog("WatchDogger: proc_listallpids failed")
            return []
        }

        var pids = [pid_t](repeating: 0, count: Int(pidCount))
        let actualCount = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        guard actualCount > 0 else { return [] }

        var results: [RawProcessData] = []
        let pathBufSize = Int(MAXPATHLEN)
        let pathBuf = UnsafeMutablePointer<CChar>.allocate(capacity: pathBufSize)
        defer { pathBuf.deallocate() }

        for i in 0..<Int(actualCount) {
            let p = pids[i]
            if p <= 0 { continue }

            var taskInfo = proc_taskinfo()
            let tiSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let ret = proc_pidinfo(p, PROC_PIDTASKINFO, 0, &taskInfo, tiSize)
            guard ret == tiSize else { continue }

            // Get process path
            memset(pathBuf, 0, pathBufSize)
            let pathLen = proc_pidpath(p, pathBuf, UInt32(pathBufSize))
            let path: String
            let name: String
            if pathLen > 0 {
                path = String(cString: pathBuf)
                name = (path as NSString).lastPathComponent
            } else {
                // Fallback: use proc_name
                var nameBuf = [CChar](repeating: 0, count: 256)
                proc_name(p, &nameBuf, 256)
                name = String(cString: nameBuf)
                path = name
            }

            if name.isEmpty { continue }

            results.append(RawProcessData(
                pid: p, name: name, path: path,
                cpuUser: taskInfo.pti_total_user,
                cpuSystem: taskInfo.pti_total_system
            ))
        }
        return results
    }

    /// Calculate CPU % from two snapshots. Must be called on main thread.
    private func calculateCPU(pid: pid_t, user: UInt64, system: UInt64) -> Double {
        let now = Foundation.ProcessInfo.processInfo.systemUptime
        let totalNow = user + system

        if let prev = previousCPUTimes[pid] {
            let dt = now - prev.timestamp
            if dt > 0.1 {
                let totalPrev = prev.user + prev.system
                let deltaCPU = Double(totalNow - totalPrev) / 1_000_000_000.0 // ns → s
                let cpuPercent = (deltaCPU / dt) * 100.0
                previousCPUTimes[pid] = (user: user, system: system, timestamp: now)
                return max(0, cpuPercent)
            }
        }

        // First sample — store baseline, return 0
        previousCPUTimes[pid] = (user: user, system: system, timestamp: now)
        return 0
    }

    func getTopCPUProcesses() -> [CPUProcessInfo] {
        // Synchronous snapshot for menu — runs on main thread
        let snapshot = snapshotProcesses()

        var results: [CPUProcessInfo] = []
        for proc in snapshot {
            let cpu = calculateCPU(pid: proc.pid, user: proc.cpuUser, system: proc.cpuSystem)
            guard cpu >= 5.0 else { continue }
            if excludedProcesses.contains(proc.name) { continue }
            results.append(CPUProcessInfo(name: proc.name, cpu: cpu, pid: String(proc.pid)))
        }

        results.sort { $0.cpu > $1.cpu }
        return Array(results.prefix(5))
    }

    // MARK: Battery State (IOKit)

    private func updateBatteryState() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              !sources.isEmpty else {
            cachedOnBattery = false
            return
        }

        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?.takeUnretainedValue() as? [String: Any],
               let powerSource = desc[kIOPSPowerSourceStateKey] as? String {
                cachedOnBattery = (powerSource == kIOPSBatteryPowerValue)
                return
            }
        }
        cachedOnBattery = false
    }

    // MARK: Runaway Process Detection

    func checkForRunawayProcesses(immediate: Bool = false) {
        let settings = SettingsManager.shared
        if !settings.monitorAllProcesses && settings.monitoredProcessNames.isEmpty { return }

        // Update battery state every Nth cycle (on main thread via Timer)
        checkCycleCount += 1
        if checkCycleCount >= batteryCheckInterval || checkCycleCount == 1 {
            checkCycleCount = 0
            updateBatteryState()
        }

        let effectiveThreshold: Double
        if settings.batteryModeEnabled && cachedOnBattery {
            effectiveThreshold = settings.batteryThreshold
        } else {
            effectiveThreshold = settings.cpuThreshold
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let snapshot = self.snapshotProcesses()

            DispatchQueue.main.async {
                let now = Date()
                var activePIDs: Set<String> = []

                for proc in snapshot {
                    let pid = String(proc.pid)
                    activePIDs.insert(pid)

                    let cpu = self.calculateCPU(pid: proc.pid, user: proc.cpuUser, system: proc.cpuSystem)
                    guard cpu >= effectiveThreshold else { continue }

                    if settings.monitorAllProcesses {
                        if self.excludedProcesses.contains(proc.name) { continue }
                    } else {
                        let matchesMonitored = settings.monitoredProcessNames.contains { monitoredName in
                            proc.name.localizedCaseInsensitiveContains(monitoredName) ||
                            proc.path.localizedCaseInsensitiveContains(monitoredName)
                        }
                        if !matchesMonitored { continue }
                    }

                    // Track CPU history for sustained detection
                    var history = self.cpuHistory[pid] ?? []
                    history.append(cpu)
                    if history.count > 3 { history = Array(history.suffix(3)) }
                    self.cpuHistory[pid] = history

                    if !immediate {
                        if history.count < 2 { continue }
                        if !history.allSatisfy({ $0 >= effectiveThreshold }) { continue }
                    }

                    let displayName: String
                    if let matched = settings.monitoredProcessNames.first(where: {
                        proc.name.localizedCaseInsensitiveContains($0) || proc.path.localizedCaseInsensitiveContains($0)
                    }) {
                        displayName = matched
                    } else {
                        displayName = proc.name
                    }

                    if settings.ignoredProcesses.contains(displayName) { continue }

                    if let last = self.lastNotified[pid],
                       now.timeIntervalSince(last) < settings.notificationCooldown { continue }

                    self.lastNotified[pid] = now

                    if settings.autoKill {
                        if let p = Int32(pid) {
                            kill(p, SIGTERM)
                            NSLog("WatchDogger: auto-killed PID \(pid) (\(displayName)) at \(String(format: "%.0f", cpu))%% CPU")
                            self.delegate?.processMonitor(self, didAutoKill: pid, cpu: cpu, name: displayName)
                        }
                    } else {
                        self.delegate?.processMonitor(self, didDetectRunaway: pid, cpu: cpu, name: displayName)
                    }
                }

                // Clean up stale entries
                self.cpuHistory = self.cpuHistory.filter { activePIDs.contains($0.key) }
                self.previousCPUTimes = self.previousCPUTimes.filter { activePIDs.contains(String($0.key)) }
                self.lastNotified = self.lastNotified.filter { now.timeIntervalSince($0.value) < settings.notificationCooldown * 2 }
            }
        }
    }
}

// MARK: - NotificationAction Delegate Protocol

protocol NotificationActionDelegate: AnyObject {
    func notificationDidRequestKill(pid: String)
    func notificationDidRequestIgnore(processName: String)
}

// MARK: - NotificationManager

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    weak var actionDelegate: NotificationActionDelegate?

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let killAction = UNNotificationAction(identifier: "KILL", title: "Kill", options: [.destructive])
        let ignoreAction = UNNotificationAction(identifier: "IGNORE", title: "Ignore", options: [])
        let category = UNNotificationCategory(
            identifier: "WATCHDOGGER",
            actions: [killAction, ignoreAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if !granted { NSLog("WatchDogger: notification permission denied") }
        }

        let settings = SettingsManager.shared
        NSLog("WatchDogger: monitoring started (threshold: \(Int(settings.cpuThreshold))%%, interval: \(Int(settings.checkInterval))s)")
    }

    func sendNotification(pid: String, cpu: Double, processName: String) {
        let settings = SettingsManager.shared

        let content = UNMutableNotificationContent()
        content.title = "WatchDogger"
        content.subtitle = "\(processName) using \(String(format: "%.0f", cpu))% CPU"
        content.body = "PID \(pid) — tap Kill to terminate"
        content.sound = settings.soundEnabled ? UNNotificationSound(named: UNNotificationSoundName("alert.aiff")) : nil
        content.categoryIdentifier = "WATCHDOGGER"
        content.userInfo = ["pid": pid, "processName": processName]

        let request = UNNotificationRequest(
            identifier: "watchdogger-\(pid)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("WatchDogger: notification error: \(error)")
            } else {
                NSLog("WatchDogger: notified about PID \(pid) (\(processName)) at \(String(format: "%.0f", cpu))%% CPU")
            }
        }
    }

    func sendAutoKillNotification(pid: String, cpu: Double, name: String) {
        let settings = SettingsManager.shared
        let content = UNMutableNotificationContent()
        content.title = "WatchDogger"
        content.body = "Auto-killed \(name) (PID \(pid)) at \(String(format: "%.0f", cpu))% CPU"
        content.sound = settings.soundEnabled ? UNNotificationSound(named: UNNotificationSoundName("alert.aiff")) : nil
        let req = UNNotificationRequest(identifier: "wd-killed-\(pid)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // Handle action button tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if response.actionIdentifier == "KILL" {
            let pid = userInfo["pid"] as? String ?? ""
            actionDelegate?.notificationDidRequestKill(pid: pid)

            // Confirm kill with a follow-up notification
            let content = UNMutableNotificationContent()
            content.title = "WatchDogger"
            content.body = "Killed process PID \(pid)"
            content.sound = SettingsManager.shared.soundEnabled ? .default : nil
            let req = UNNotificationRequest(
                identifier: "watchdogger-killed-\(pid)",
                content: content,
                trigger: nil
            )
            center.add(req)
        } else if response.actionIdentifier == "IGNORE" {
            if let name = userInfo["processName"] as? String {
                actionDelegate?.notificationDidRequestIgnore(processName: name)
            }
        }
        completionHandler()
    }

    // Show notification even when app is active
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if SettingsManager.shared.soundEnabled {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.banner])
        }
    }
}

// MARK: - MenuBarAction Delegate Protocol

protocol MenuBarActionDelegate: AnyObject {
    func menuBarDidRequestOpenSettings()
    func menuBarDidRequestCheckNow()
    func menuBarDidRequestQuit()
}

// MARK: - MenuBarController

class MenuBarController: NSObject, NSMenuDelegate {
    weak var actionDelegate: MenuBarActionDelegate?
    var processMonitor: ProcessMonitor?

    var statusItem: NSStatusItem?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = makeMenuBarIcon()
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open WatchDogger", action: #selector(openSettings), keyEquivalent: "o")
        openItem.target = self
        openItem.isEnabled = true
        menu.addItem(openItem)

        let checkItem = NSMenuItem(title: "Check Now", action: #selector(checkNow), keyEquivalent: "c")
        checkItem.target = self
        checkItem.isEnabled = true
        menu.addItem(checkItem)

        let hotItem = NSMenuItem(title: "What's hot", action: nil, keyEquivalent: "")
        hotItem.submenu = NSMenu(title: "What's hot")
        hotItem.tag = 999  // tag to find it in menuNeedsUpdate
        menu.addItem(hotItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem?.menu = menu
    }

    @objc func openSettings() {
        actionDelegate?.menuBarDidRequestOpenSettings()
    }

    @objc func checkNow() {
        actionDelegate?.menuBarDidRequestCheckNow()
    }

    @objc func quit() {
        actionDelegate?.menuBarDidRequestQuit()
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let hotItem = menu.item(withTag: 999),
              let submenu = hotItem.submenu else { return }

        submenu.removeAllItems()

        let topProcesses = processMonitor?.getTopCPUProcesses() ?? []
        if topProcesses.isEmpty {
            let quiet = NSMenuItem(title: "All quiet", action: nil, keyEquivalent: "")
            quiet.isEnabled = false
            submenu.addItem(quiet)
        } else {
            for proc in topProcesses {
                let title = "\(proc.name) \u{2014} \(Int(proc.cpu))% CPU (PID \(proc.pid))"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                submenu.addItem(item)
            }
        }
    }

    // MARK: Menu Bar Icon

    func makeMenuBarIcon() -> NSImage {
        let s: CGFloat = 18
        let image = NSImage(size: NSSize(width: s, height: s))
        image.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext

        // Shield outline
        let shield = CGMutablePath()
        shield.move(to: CGPoint(x: s*0.5, y: s*0.9))
        shield.addCurve(to: CGPoint(x: s*0.12, y: s*0.55),
                        control1: CGPoint(x: s*0.25, y: s*0.87),
                        control2: CGPoint(x: s*0.12, y: s*0.72))
        shield.addLine(to: CGPoint(x: s*0.12, y: s*0.32))
        shield.addLine(to: CGPoint(x: s*0.5, y: s*0.1))
        shield.addLine(to: CGPoint(x: s*0.88, y: s*0.32))
        shield.addLine(to: CGPoint(x: s*0.88, y: s*0.55))
        shield.addCurve(to: CGPoint(x: s*0.5, y: s*0.9),
                        control1: CGPoint(x: s*0.88, y: s*0.72),
                        control2: CGPoint(x: s*0.75, y: s*0.87))
        shield.closeSubpath()

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1.2)
        ctx.addPath(shield)
        ctx.strokePath()

        // Eye
        let eyeY = s * 0.52
        let eye = CGMutablePath()
        eye.move(to: CGPoint(x: s*0.28, y: eyeY))
        eye.addQuadCurve(to: CGPoint(x: s*0.72, y: eyeY), control: CGPoint(x: s*0.5, y: eyeY + s*0.2))
        eye.addQuadCurve(to: CGPoint(x: s*0.28, y: eyeY), control: CGPoint(x: s*0.5, y: eyeY - s*0.2))
        eye.closeSubpath()

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1.0)
        ctx.addPath(eye)
        ctx.strokePath()

        // Pupil
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillEllipse(in: CGRect(x: s*0.5 - 2.5, y: eyeY - 2.5, width: 5, height: 5))

        image.unlockFocus()
        return image
    }
}

// MARK: - App Delegate

class WatchDoggerDelegate: NSObject, NSApplicationDelegate, ProcessMonitorDelegate, NotificationActionDelegate, MenuBarActionDelegate {
    var timer: Timer?
    var currentInterval: TimeInterval = 0

    let processMonitor = ProcessMonitor()
    let notificationManager = NotificationManager()
    let menuBarController = MenuBarController()
    var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance protection
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sh.watchdogger3"
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSLog("WatchDogger: another instance is already running, exiting")
            NSApp.terminate(nil)
            return
        }

        // Wire up delegates
        processMonitor.delegate = self
        notificationManager.actionDelegate = self
        menuBarController.actionDelegate = self
        menuBarController.processMonitor = processMonitor

        // Menu bar icon
        menuBarController.setup()

        // Show settings window
        settingsWindow = SettingsWindow()
        settingsWindow?.show()

        // Defer notification setup and monitoring to not block UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.notificationManager.setup()
            self?.startTimer()
        }
    }

    // MARK: Timer Management

    func startTimer() {
        let interval = SettingsManager.shared.checkInterval
        currentInterval = interval
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.processMonitor.checkForRunawayProcesses()
            self?.restartTimerIfNeeded()
        }
    }

    func restartTimerIfNeeded() {
        let newInterval = SettingsManager.shared.checkInterval
        if newInterval != currentInterval {
            startTimer()
        }
    }

    // MARK: ProcessMonitorDelegate

    func processMonitor(_ monitor: ProcessMonitor, didDetectRunaway pid: String, cpu: Double, name: String) {
        notificationManager.sendNotification(pid: pid, cpu: cpu, processName: name)
    }

    func processMonitor(_ monitor: ProcessMonitor, didAutoKill pid: String, cpu: Double, name: String) {
        notificationManager.sendAutoKillNotification(pid: pid, cpu: cpu, name: name)
    }

    // MARK: NotificationActionDelegate

    func notificationDidRequestKill(pid: String) {
        if let p = Int32(pid) {
            kill(p, SIGTERM)
            NSLog("WatchDogger: killed PID \(pid)")
        }
    }

    func notificationDidRequestIgnore(processName: String) {
        SettingsManager.shared.ignoreProcess(processName)
        NSLog("WatchDogger: added '\(processName)' to ignore list")
    }

    // MARK: MenuBarActionDelegate

    func menuBarDidRequestOpenSettings() {
        settingsWindow?.show()
    }

    func menuBarDidRequestCheckNow() {
        processMonitor.checkForRunawayProcesses(immediate: true)
    }

    func menuBarDidRequestQuit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Main
let app = NSApplication.shared
let delegate = WatchDoggerDelegate()
app.delegate = delegate
app.run()
