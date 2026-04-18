import Cocoa
import SwiftUI
import ServiceManagement

// MARK: - Settings Manager

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let cpuThreshold = "cpuThreshold"
        static let checkInterval = "checkInterval"
        static let notificationCooldown = "notificationCooldown"
        static let monitoredProcessNames = "monitoredProcessNames"
        static let autoKill = "autoKill"
        static let launchAtLogin = "launchAtLogin"
        static let soundEnabled = "soundEnabled"
        static let monitorAllProcesses = "monitorAllProcesses"
        static let ignoredProcesses = "ignoredProcesses"
        static let batteryModeEnabled = "batteryModeEnabled"
        static let batteryThreshold = "batteryThreshold"
    }

    private init() {
        defaults.register(defaults: [
            Keys.cpuThreshold: 90.0, Keys.checkInterval: 30.0,
            Keys.notificationCooldown: 60.0, Keys.autoKill: false,
            Keys.launchAtLogin: false, Keys.soundEnabled: true,
            Keys.monitorAllProcesses: false,
            Keys.batteryModeEnabled: true,
            Keys.batteryThreshold: 25.0,
        ])
    }

    var cpuThreshold: Double {
        get { defaults.double(forKey: Keys.cpuThreshold) }
        set { defaults.set(newValue, forKey: Keys.cpuThreshold); objectWillChange.send() }
    }
    var checkInterval: TimeInterval {
        get { defaults.double(forKey: Keys.checkInterval) }
        set { defaults.set(newValue, forKey: Keys.checkInterval); objectWillChange.send() }
    }
    var notificationCooldown: TimeInterval {
        get { defaults.double(forKey: Keys.notificationCooldown) }
        set { defaults.set(newValue, forKey: Keys.notificationCooldown); objectWillChange.send() }
    }
    var monitoredProcessNames: [String] {
        get { defaults.stringArray(forKey: Keys.monitoredProcessNames) ?? ["Safari", "Chrome"] }
        set { defaults.set(newValue, forKey: Keys.monitoredProcessNames); objectWillChange.send() }
    }
    var autoKill: Bool {
        get { defaults.bool(forKey: Keys.autoKill) }
        set { defaults.set(newValue, forKey: Keys.autoKill); objectWillChange.send() }
    }
    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin); objectWillChange.send() }
    }
    var soundEnabled: Bool {
        get { defaults.bool(forKey: Keys.soundEnabled) }
        set { defaults.set(newValue, forKey: Keys.soundEnabled); objectWillChange.send() }
    }
    var monitorAllProcesses: Bool {
        get { defaults.bool(forKey: Keys.monitorAllProcesses) }
        set { defaults.set(newValue, forKey: Keys.monitorAllProcesses); objectWillChange.send() }
    }
    var ignoredProcesses: [String] {
        get { defaults.stringArray(forKey: Keys.ignoredProcesses) ?? [] }
        set { defaults.set(newValue, forKey: Keys.ignoredProcesses); objectWillChange.send() }
    }
    var batteryModeEnabled: Bool {
        get { defaults.bool(forKey: Keys.batteryModeEnabled) }
        set { defaults.set(newValue, forKey: Keys.batteryModeEnabled); objectWillChange.send() }
    }
    var batteryThreshold: Double {
        get { defaults.double(forKey: Keys.batteryThreshold) }
        set { defaults.set(newValue, forKey: Keys.batteryThreshold); objectWillChange.send() }
    }

    func ignoreProcess(_ name: String) {
        var list = ignoredProcesses
        if !list.contains(name) {
            list.append(name)
            ignoredProcesses = list
        }
    }

    func unignoreProcess(_ name: String) {
        var list = ignoredProcesses
        list.removeAll { $0 == name }
        ignoredProcesses = list
    }

    func addMonitoredProcess(_ name: String) {
        var list = monitoredProcessNames
        if !list.contains(name) { list.append(name); monitoredProcessNames = list }
    }

    func removeMonitoredProcess(_ name: String) {
        monitoredProcessNames = monitoredProcessNames.filter { $0 != name }
    }
}

// MARK: - SwiftUI Settings View

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var newProcessName = ""

    let intervalOptions: [(String, TimeInterval)] = [
        ("10 seconds", 10), ("15 seconds", 15), ("30 seconds", 30),
        ("1 minute", 60), ("2 minutes", 120)
    ]
    let cooldownOptions: [(String, TimeInterval)] = [
        ("30 seconds", 30), ("1 minute", 60), ("2 minutes", 120), ("5 minutes", 300)
    ]

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("CPU Threshold")
                        Spacer()
                        Text("\(Int(settings.cpuThreshold))%")
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    Slider(value: Binding(
                        get: { settings.cpuThreshold },
                        set: { settings.cpuThreshold = round($0) }
                    ), in: 50...100, step: 5)
                }
                Picker("Check Every", selection: Binding(
                    get: { settings.checkInterval },
                    set: { settings.checkInterval = $0 }
                )) {
                    ForEach(intervalOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
                Picker("Cooldown", selection: Binding(
                    get: { settings.notificationCooldown },
                    set: { settings.notificationCooldown = $0 }
                )) {
                    ForEach(cooldownOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
                Toggle("Battery mode", isOn: Binding(
                    get: { settings.batteryModeEnabled },
                    set: { settings.batteryModeEnabled = $0 }
                ))
                if settings.batteryModeEnabled {
                    Text("Lowers threshold to 25% on battery power")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Monitoring")
            } footer: {
                Text("Fires a notification when any process crosses the line. Cooldown keeps it from nagging you about the same one.")
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle("Monitor all apps", isOn: Binding(
                    get: { settings.monitorAllProcesses },
                    set: { settings.monitorAllProcesses = $0 }
                ))

                if !settings.monitorAllProcesses {
                    ForEach(settings.monitoredProcessNames, id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button(role: .destructive) {
                                settings.removeMonitoredProcess(name)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        TextField("Process name", text: $newProcessName)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let name = newProcessName.trimmingCharacters(in: .whitespaces)
                            if !name.isEmpty {
                                settings.addMonitoredProcess(name)
                                newProcessName = ""
                            }
                        }
                        .disabled(newProcessName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } header: {
                Text("What to watch")
            } footer: {
                Text("Monitor all apps catches anything hogging your CPU. Or add specific process names to watch.")
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle("Auto-Kill", isOn: Binding(
                    get: { settings.autoKill },
                    set: { settings.autoKill = $0 }
                ))
                if settings.autoKill {
                    Text("Processes get killed on sight. Hope you saved your work.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Toggle("Sound", isOn: Binding(
                    get: { settings.soundEnabled },
                    set: { settings.soundEnabled = $0 }
                ))
                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        settings.launchAtLogin = newValue
                        if #available(macOS 13.0, *) {
                            do {
                                if newValue { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                            } catch { NSLog("WatchDogger: login item error: \(error)") }
                        }
                    }
                ))
            } header: {
                Text("Behavior")
            } footer: {
                Text("Auto-Kill terminates the process immediately, no notification. Careful with this one outside of browsers.")
                    .foregroundColor(.secondary)
            }

            Section {
                if settings.ignoredProcesses.isEmpty {
                    Text("None yet. Tap Ignore on a notification to add.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(settings.ignoredProcesses, id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button(role: .destructive) {
                                settings.unignoreProcess(name)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("Ignored processes")
            } footer: {
                Text("These won't bother you again. Remove them here if you change your mind.")
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Text("WatchDogger v1.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
    }
}

// MARK: - Settings Window

class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WatchDogger"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = hostingView

        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() { window?.orderOut(nil) }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
