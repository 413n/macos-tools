import Foundation

/// Built-in keyboard lock, ported from `~/Code/keyboard-lock/builtin-keyboard.sh`.
///
/// Uses hidutil's UserKeyMapping to remap every key on the internal keyboard
/// to "no event". No sudo, no kext, no SIP changes. Trackpad, external
/// keyboards and the power button stay untouched. The mapping lasts for the
/// current boot only — reboot or logout always restores the keyboard.
struct KeyboardLockError: LocalizedError {
    let errorDescription: String?
}

final class KeyboardLockService {
    struct Snapshot {
        var locked: Bool
        var remainingMinutes: Int?
    }

    /// Fired on the service's caller-facing path after the auto-unlock sleep
    /// elapses, so the UI can refresh and the backlight can be restored.
    var onTimerExpired: (() -> Void)?

    private let cacheDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/yeobun")
    private var timerPIDFile: URL { cacheDir.appendingPathComponent("keyboard-timer.pid") }
    private var timerMetaFile: URL { cacheDir.appendingPathComponent("keyboard-timer.json") }
    private var cachedIDs: KeyboardIDs?
    private let backlight = KeyboardBacklightService()
    private var unlockWorkItem: DispatchWorkItem?

    func invalidateIDs() {
        cachedIDs = nil
    }

    func snapshot() throws -> Snapshot {
        Snapshot(locked: try isDisabledThrowing(), remainingMinutes: remainingTimerMinutes())
    }

    func isDisabled() -> Bool {
        (try? isDisabledThrowing()) ?? false
    }

    func isDisabledThrowing() throws -> Bool {
        let ids = try builtinKeyboardIDs()
        return try mappingIsActive(matching: ids.matching)
    }

    func disable(timeoutMinutes: Int?, preserveExistingTimer: Bool = false) throws {
        let ids = try builtinKeyboardIDs()
        // Same as builtin-keyboard.sh: discard hidutil's stdout so a huge
        // mapping dump cannot fill the pipe and hang (the script uses >/dev/null).
        try hidutil(
            ["property", "--matching", ids.matching, "--set", Self.killMappingJSON],
            captureOutput: false
        )
        guard try mappingIsActive(matching: ids.matching) else {
            throw KeyboardLockError(errorDescription: "hidutil accepted the mapping but it did not stick.")
        }
        if preserveExistingTimer { return }
        if let timeoutMinutes, timeoutMinutes > 0 {
            armTimer(minutes: timeoutMinutes, matching: ids.matching)
        } else {
            cancelTimer()
        }
    }

    func enable() throws {
        cancelTimer()
        let ids = try builtinKeyboardIDs()
        try hidutil(
            ["property", "--matching", ids.matching, "--set", "{\"UserKeyMapping\":[]}"],
            captureOutput: false
        )
    }

    func syncBacklight(locked: Bool, dimWhileLocked: Bool) {
        if locked, dimWhileLocked {
            backlight.forceOff()
        } else {
            backlight.restoreIfNeeded()
        }
    }

    func restoreBacklightIfNeeded() {
        backlight.restoreIfNeeded()
    }

    func remainingTimerMinutes() -> Int? {
        guard let remaining = remainingTimerInterval() else { return nil }
        let minutes = Int(ceil(remaining / 60))
        return minutes > 0 ? minutes : nil
    }

    /// Re-arms the in-process callback after a relaunch so the UI catches the
    /// existing bash auto-unlock instead of waiting for the next status poll.
    func resumeUITimerIfNeeded() {
        guard let remaining = remainingTimerInterval() else { return }
        unlockWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onTimerExpired?()
        }
        unlockWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + remaining,
            execute: work
        )
    }

    func cancelTimer() {
        unlockWorkItem?.cancel()
        unlockWorkItem = nil
        if let pidString = try? String(contentsOf: timerPIDFile, encoding: .utf8),
           let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let killChildren = Process()
            killChildren.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            killChildren.arguments = ["-P", "\(pid)"]
            try? killChildren.run()
            killChildren.waitUntilExit()
            kill(pid, SIGTERM)
        }
        try? FileManager.default.removeItem(at: timerPIDFile)
        try? FileManager.default.removeItem(at: timerMetaFile)
    }

    private func armTimer(minutes: Int, matching: String) {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        cancelTimer()
        scheduleUnlockWorkItem(minutes: minutes)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            """
            sleep \(minutes * 60)
            /usr/bin/hidutil property --matching '\(matching)' --set '{"UserKeyMapping":[]}' >/dev/null 2>&1
            rm -f '\(timerPIDFile.path)' '\(timerMetaFile.path)'
            """
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            try "\(process.processIdentifier)".write(to: timerPIDFile, atomically: true, encoding: .utf8)
            let meta = TimerMeta(deadline: Date().addingTimeInterval(TimeInterval(minutes * 60)))
            try JSONEncoder().encode(meta).write(to: timerMetaFile, options: .atomic)
        } catch {
            return
        }
    }

    private func remainingTimerInterval() -> TimeInterval? {
        guard let data = try? Data(contentsOf: timerMetaFile),
              let meta = try? JSONDecoder().decode(TimerMeta.self, from: data)
        else { return nil }
        let remaining = meta.deadline.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    private func scheduleUnlockWorkItem(minutes: Int) {
        let work = DispatchWorkItem { [weak self] in
            self?.onTimerExpired?()
        }
        unlockWorkItem = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + .seconds(minutes * 60),
            execute: work
        )
    }

    private struct TimerMeta: Codable {
        let deadline: Date
    }

    private struct KeyboardIDs {
        let vendor: Int
        let product: Int
        var matching: String { "{\"VendorID\":\(vendor),\"ProductID\":\(product)}" }
    }

    private func builtinKeyboardIDs() throws -> KeyboardIDs {
        if let cachedIDs { return cachedIDs }
        // Same discovery as builtin-keyboard.sh:
        // hidutil list | awk 'NR>1 && $NF==1 && /Keyboard/ {print $1, $2}'
        if let fromList = idsFromHidutilList() {
            cachedIDs = fromList
            return fromList
        }
        if let fromIOKit = DeviceMonitor.builtinKeyboardIDs() {
            let ids = KeyboardIDs(vendor: fromIOKit.vendor, product: fromIOKit.product)
            cachedIDs = ids
            return ids
        }
        throw KeyboardLockError(
            errorDescription: "No built-in keyboard found (device may still be re-enumerating after sleep — retry in a moment)."
        )
    }

    private func idsFromHidutilList() -> KeyboardIDs? {
        guard let listing = try? hidutil(["list"], captureOutput: true) else { return nil }
        for line in listing.split(separator: "\n").dropFirst() {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2, parts.last == "1" else { continue }
            guard line.contains("Keyboard"), !line.contains("Backlight") else { continue }
            if let vendor = parseHexOrDec(parts[0]), let product = parseHexOrDec(parts[1]) {
                return KeyboardIDs(vendor: vendor, product: product)
            }
        }
        return nil
    }

    private func mappingIsActive(matching: String) throws -> Bool {
        // Script reads the property into a variable then greps; a `grep -q`
        // pipeline SIGPIPEs hidutil and looks like failure.
        let current = try hidutil(
            ["property", "--matching", matching, "--get", "UserKeyMapping"],
            captureOutput: true
        )
        return current.contains("HIDKeyboardModifierMappingSrc")
    }

    private func parseHexOrDec(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("0x") {
            return Int(trimmed.dropFirst(2), radix: 16)
        }
        return Int(trimmed)
    }

    /// Every HID Keyboard/Keypad usage (page 0x07): 0x04 through 0xE7, plus
    /// Apple's vendor-defined fn key 0xFF00000003.
    private static let killMappingJSON: String = {
        var pairs: [String] = []
        pairs.reserveCapacity(230)
        for usage in 4...231 {
            pairs.append(
                String(
                    format: "{\"HIDKeyboardModifierMappingSrc\":0x7000000%02x,\"HIDKeyboardModifierMappingDst\":0x700000000}",
                    usage
                )
            )
        }
        pairs.append("{\"HIDKeyboardModifierMappingSrc\":0xFF00000003,\"HIDKeyboardModifierMappingDst\":0x700000000}")
        return "{\"UserKeyMapping\":[\(pairs.joined(separator: ","))]}"
    }()

    @discardableResult
    private func hidutil(_ arguments: [String], captureOutput: Bool) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let stdout = captureOutput ? Pipe() : nil
        let stderr = Pipe()
        process.standardOutput = stdout ?? FileHandle.nullDevice
        process.standardError = stderr

        try process.run()

        // Drain pipes while hidutil runs. Waiting first with unread pipes can
        // deadlock once the mapping dump fills the buffer.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        if let stdout {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                outData = stdout.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        process.waitUntilExit()
        group.wait()

        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw KeyboardLockError(
                errorDescription: err.isEmpty ? "hidutil failed (\(process.terminationStatus))" : err
            )
        }
        return out
    }
}
