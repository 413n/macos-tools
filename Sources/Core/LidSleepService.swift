import AppKit
import Darwin
import Foundation

/// Lid-sleep control on battery, ported from the `lid-sleep-off` / `lid-sleep-on`
/// helpers in zshrc.
///
/// `pmset -b disablesleep 1` plus `pmset -b sleep 0` keep the Mac awake on
/// battery with the lid shut. Restoring uses `disablesleep 0` and `sleep 60`.
/// Changing those settings needs root. After a one-time administrator grant
/// (`/etc/sudoers.d/naf-tools-lid-sleep`), later toggles use `sudo -n` and do
/// not prompt.
struct LidSleepError: LocalizedError {
    let errorDescription: String?
}

final class LidSleepService {
    struct Snapshot {
        var disabled: Bool
        var batterySleepMinutes: Int?
    }

    static let defaultRestoreMinutes = 60
    private static let sudoersPath = "/etc/sudoers.d/naf-tools-lid-sleep"

    func snapshot() -> Snapshot {
        let general = run("/usr/bin/pmset", ["-g"], captureOutput: true).output
        let custom = run("/usr/bin/pmset", ["-g", "custom"], captureOutput: true).output
        let battery = section(custom, named: "Battery Power")
        let disabled =
            intValue(in: general, key: "SleepDisabled") == 1
            || intValue(in: general, key: "disablesleep") == 1
            || intValue(in: battery, key: "SleepDisabled") == 1
            || intValue(in: battery, key: "disablesleep") == 1
        return Snapshot(
            disabled: disabled,
            batterySleepMinutes: intValue(in: battery, key: "sleep")
        )
    }

    func setDisabled(_ disabled: Bool, restoreSleepMinutes: Int = defaultRestoreMinutes) throws {
        let restore = restoreSleepMinutes > 0 ? restoreSleepMinutes : Self.defaultRestoreMinutes
        let commands: [[String]]
        if disabled {
            commands = [
                ["-b", "sleep", "0"],
                ["-b", "disablesleep", "1"]
            ]
        } else {
            commands = [
                ["-b", "sleep", "\(restore)"],
                ["-b", "disablesleep", "0"]
            ]
        }
        try apply(commands)
    }

    private func apply(_ argumentSets: [[String]]) throws {
        if argumentSets.allSatisfy({ run("/usr/bin/pmset", $0, captureOutput: false).status == 0 }) {
            return
        }
        if argumentSets.allSatisfy({ sudoPmset($0) == 0 }) {
            return
        }
        if isatty(STDIN_FILENO) != 0, isatty(STDOUT_FILENO) != 0 {
            try installGrantViaTTY(argumentSets)
            return
        }
        // Menu-bar apps have no TTY. `sudo -n` failing (no grant yet, or sudo
        // insisting on a terminal) means we need the one-time admin sheet.
        try installGrantAndRun(argumentSets)
    }

    private func installGrantViaTTY(_ argumentSets: [[String]]) throws {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            throw LidSleepError(errorDescription: "Could not install administrator grant for this account.")
        }
        let restore = Self.defaultRestoreMinutes
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -b sleep 0, /usr/bin/pmset -b sleep \(restore), /usr/bin/pmset -b disablesleep 0, /usr/bin/pmset -b disablesleep 1"
        let pmset = argumentSets
            .map { "/usr/bin/pmset " + $0.joined(separator: " ") }
            .joined(separator: " && ")
        let shell =
            "set -e; tmp=/tmp/naf-tools-lid-sleep.$$; /usr/bin/printf '%s\\n' '\(rule)' > $tmp; "
            + "/usr/sbin/visudo -cf $tmp; /usr/sbin/chown root:wheel $tmp; /bin/chmod 0440 $tmp; "
            + "/bin/mv $tmp \(Self.sudoersPath); \(pmset)"
        let status = runInteractive("/usr/bin/sudo", ["/bin/sh", "-lc", shell])
        if status != 0 {
            throw LidSleepError(
                errorDescription: "Could not change lid-sleep settings (administrator access required)."
            )
        }
    }

    private func runInteractive(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            return 1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func sudoPmset(_ arguments: [String]) -> Int32 {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset"] + arguments, captureOutput: false).status
    }

    private func installGrantAndRun(_ argumentSets: [[String]]) throws {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            throw LidSleepError(errorDescription: "Could not install administrator grant for this account.")
        }
        let restore = Self.defaultRestoreMinutes
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -b sleep 0, /usr/bin/pmset -b sleep \(restore), /usr/bin/pmset -b disablesleep 0, /usr/bin/pmset -b disablesleep 1"
        let pmset = argumentSets
            .map { "/usr/bin/pmset " + $0.joined(separator: " ") }
            .joined(separator: " && ")
        let shell =
            "set -e; tmp=/tmp/naf-tools-lid-sleep.$$; /usr/bin/printf '%s\\n' '\(rule)' > $tmp; "
            + "/usr/sbin/chown root:wheel $tmp; /bin/chmod 0440 $tmp; /usr/sbin/visudo -cf $tmp; "
            + "/bin/mv $tmp \(Self.sudoersPath); \(pmset)"
        try runOsascriptAdmin(shell)
    }

    private func runOsascriptAdmin(_ shell: String) throws {
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw LidSleepError(errorDescription: "Could not ask for administrator access.")
        }
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if number == -128 {
                throw LidSleepError(errorDescription: "Administrator authorization was cancelled.")
            }
            let message = (errorInfo[NSAppleScript.errorMessage] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LidSleepError(
                errorDescription: (message?.isEmpty == false)
                    ? message
                    : "Could not change lid-sleep settings."
            )
        }
    }

    private func section(_ text: String, named: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.hasPrefix(named) }) else { return "" }
        var collected: [String] = []
        for line in lines[(start + 1)...] {
            if let first = line.first, first.isLetter, line.hasSuffix(":"), !line.hasPrefix(" ") {
                break
            }
            collected.append(line)
        }
        return collected.joined(separator: "\n")
    }

    private func intValue(in text: String, key: String) -> Int? {
        for line in text.split(separator: "\n") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard
                let index = parts.firstIndex(where: { $0.caseInsensitiveCompare(key) == .orderedSame }),
                index + 1 < parts.count,
                let number = Int(parts[index + 1])
            else { continue }
            return number
        }
        return nil
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String], captureOutput: Bool) -> (status: Int32, output: String, err: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = captureOutput ? stdout : FileHandle.nullDevice
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return (1, "", error.localizedDescription)
        }
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        if captureOutput {
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
        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
