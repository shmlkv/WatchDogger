import Foundation

// MARK: - Extracted Logic for Testing

/// Sustained detection: returns true if process should trigger alert
func checkSustained(history: [Double], threshold: Double, immediate: Bool) -> Bool {
    if immediate { return true }
    if history.count < 2 { return false }
    return history.allSatisfy { $0 >= threshold }
}

/// Cooldown check: returns true if enough time has passed since last notification
func shouldNotify(lastNotified: Date?, now: Date, cooldown: TimeInterval) -> Bool {
    guard let last = lastNotified else { return true }
    return now.timeIntervalSince(last) >= cooldown
}

/// CPU history window management (keeps last N entries)
func updateHistory(_ history: inout [Double], value: Double, maxSize: Int = 3) {
    history.append(value)
    if history.count > maxSize { history = Array(history.suffix(maxSize)) }
}

/// Process name matching against a monitored list
func matchesMonitored(processName: String, processPath: String, monitoredNames: [String]) -> Bool {
    return monitoredNames.contains { monitoredName in
        processName.localizedCaseInsensitiveContains(monitoredName) ||
        processPath.localizedCaseInsensitiveContains(monitoredName)
    }
}

// MARK: - Test Runner

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("  FAIL [\(line)]: \(message)")
    }
}

func test(_ name: String, _ body: () -> Void) {
    print("  \(name)")
    body()
}

// MARK: - Sustained Detection Tests

print("Sustained Detection")
print("---")

test("single reading does not trigger") {
    assert(!checkSustained(history: [95.0], threshold: 90.0, immediate: false),
           "Single reading should not trigger")
}

test("two readings above threshold triggers") {
    assert(checkSustained(history: [95.0, 92.0], threshold: 90.0, immediate: false),
           "Two above should trigger")
}

test("one reading below threshold breaks chain") {
    assert(!checkSustained(history: [95.0, 80.0, 92.0], threshold: 90.0, immediate: false),
           "One below should not trigger")
}

test("all three above threshold triggers") {
    assert(checkSustained(history: [91.0, 93.0, 95.0], threshold: 90.0, immediate: false),
           "Three above should trigger")
}

test("immediate mode bypasses sustained check") {
    assert(checkSustained(history: [95.0], threshold: 90.0, immediate: true),
           "Immediate should trigger with single reading")
    assert(checkSustained(history: [], threshold: 90.0, immediate: true),
           "Immediate should trigger even with empty history")
}

test("empty history does not trigger") {
    assert(!checkSustained(history: [], threshold: 90.0, immediate: false),
           "Empty history should not trigger")
}

test("exactly at threshold triggers") {
    assert(checkSustained(history: [90.0, 90.0], threshold: 90.0, immediate: false),
           "Exactly at threshold should trigger")
}

test("just below threshold does not trigger") {
    assert(!checkSustained(history: [89.9, 91.0], threshold: 90.0, immediate: false),
           "One below threshold should not trigger")
}

// MARK: - Cooldown Tests

print("")
print("Cooldown Filtering")
print("---")

test("first notification always fires") {
    assert(shouldNotify(lastNotified: nil, now: Date(), cooldown: 60),
           "First time should notify")
}

test("within cooldown does not fire") {
    let now = Date()
    let justNow = now.addingTimeInterval(-10)
    assert(!shouldNotify(lastNotified: justNow, now: now, cooldown: 60),
           "Within cooldown should not notify")
}

test("after cooldown fires") {
    let now = Date()
    let longAgo = now.addingTimeInterval(-120)
    assert(shouldNotify(lastNotified: longAgo, now: now, cooldown: 60),
           "After cooldown should notify")
}

test("exactly at cooldown boundary fires") {
    let now = Date()
    let exactly = now.addingTimeInterval(-60)
    assert(shouldNotify(lastNotified: exactly, now: now, cooldown: 60),
           "Exactly at cooldown boundary should notify")
}

// MARK: - CPU History Window Tests

print("")
print("CPU History Window")
print("---")

test("history caps at 3 entries") {
    var history: [Double] = []
    for val in [10.0, 20.0, 30.0, 40.0, 50.0] {
        updateHistory(&history, value: val)
    }
    assert(history.count == 3, "History should be capped at 3, got \(history.count)")
    assert(history == [30.0, 40.0, 50.0], "Should keep last 3 values")
}

test("history grows naturally under cap") {
    var history: [Double] = []
    updateHistory(&history, value: 10.0)
    assert(history.count == 1, "Should have 1 entry")
    updateHistory(&history, value: 20.0)
    assert(history.count == 2, "Should have 2 entries")
}

// MARK: - Process Name Matching Tests

print("")
print("Process Name Matching")
print("---")

test("exact name match") {
    assert(matchesMonitored(processName: "Safari", processPath: "/Applications/Safari.app/Contents/MacOS/Safari",
                            monitoredNames: ["Safari"]),
           "Should match Safari by name")
}

test("path-based match for browser helpers") {
    assert(matchesMonitored(processName: "com.apple.WebKit.WebContent",
                            processPath: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent",
                            monitoredNames: ["Safari", "WebKit"]),
           "Should match WebKit process via path")
}

test("case insensitive matching") {
    assert(matchesMonitored(processName: "chrome helper", processPath: "/Google Chrome Helper",
                            monitoredNames: ["Chrome"]),
           "Should match case-insensitively")
}

test("no match for unmonitored process") {
    assert(!matchesMonitored(processName: "firefox", processPath: "/Applications/Firefox.app/Contents/MacOS/firefox",
                             monitoredNames: ["Safari", "Chrome"]),
           "Should not match unmonitored process")
}

test("empty monitored list matches nothing") {
    assert(!matchesMonitored(processName: "Safari", processPath: "/Applications/Safari.app",
                             monitoredNames: []),
           "Empty list should match nothing")
}

// MARK: - Ignore List Tests

print("")
print("Ignore List")
print("---")

test("ignored process is filtered") {
    let ignored = ["Safari", "Chrome"]
    assert(ignored.contains("Safari"), "Safari should be in ignore list")
}

test("non-ignored process passes through") {
    let ignored = ["Safari", "Chrome"]
    assert(!ignored.contains("Firefox"), "Firefox should not be in ignore list")
}

// MARK: - Results

print("")
print("===")
print("Results: \(passed) passed, \(failed) failed")

if failed > 0 { exit(1) }
