import Darwin
import Foundation

/// Idle/display sleep hold, wrapping `/usr/bin/caffeinate`.
///
/// KeepingYouAwake and Caffeine do the same thing with IOPM assertions.
/// `caffeinate -di` creates `PreventUserIdleDisplaySleep` plus
/// `PreventUserIdleSystemSleep`. `-t` drops them after N seconds.
/// `-s` is intentionally unused: that assertion blocks lid-close sleep on AC,
/// which is Lid Sleep's job.
struct CaffeinateError: LocalizedError {
    let errorDescription: String?
}

final class CaffeinateService {
    struct Snapshot {
        var active: Bool
        var remainingSeconds: Int?
    }

    /// Fired on the main queue when `caffeinate -t` exits on its own.
    var onExpired: (() -> Void)?

    private var process: Process?
    private var deadline: Date?
    private let pidDefaultsKey = "caffeinatePID"

    func snapshot() -> Snapshot {
        guard isRunning else {
            return Snapshot(active: false, remainingSeconds: nil)
        }
        if let deadline {
            return Snapshot(
                active: true,
                remainingSeconds: max(0, Int(deadline.timeIntervalSinceNow.rounded(.down)))
            )
        }
        return Snapshot(active: true, remainingSeconds: nil)
    }

    func start(timeoutSeconds: Int?) throws {
        stop()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        var arguments = ["-d", "-i"]
        if let timeoutSeconds, timeoutSeconds > 0 {
            arguments += ["-t", "\(timeoutSeconds)"]
            deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        } else {
            deadline = nil
        }
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                self?.handleTermination(of: finished)
            }
        }
        do {
            try process.run()
        } catch {
            throw CaffeinateError(errorDescription: "Could not start caffeinate.")
        }
        self.process = process
        UserDefaults.standard.set(Int(process.processIdentifier), forKey: pidDefaultsKey)
    }

    func stop() {
        let current = process
        process = nil
        deadline = nil
        if let current {
            current.terminationHandler = nil
            if current.isRunning {
                current.terminate()
                DispatchQueue.global(qos: .utility).async {
                    current.waitUntilExit()
                }
            }
            UserDefaults.standard.removeObject(forKey: pidDefaultsKey)
            return
        }
        killStoredCaffeinateIfNeeded()
    }

    private var isRunning: Bool {
        process?.isRunning == true
    }

    private func handleTermination(of finished: Process) {
        guard process === finished else { return }
        process = nil
        deadline = nil
        UserDefaults.standard.removeObject(forKey: pidDefaultsKey)
        onExpired?()
    }

    /// After a crash the child `caffeinate` can be reparented to launchd.
    /// Only signal it when `ps` still says the PID is caffeinate.
    private func killStoredCaffeinateIfNeeded() {
        let pid = UserDefaults.standard.integer(forKey: pidDefaultsKey)
        UserDefaults.standard.removeObject(forKey: pidDefaultsKey)
        guard pid > 1, pid != Int(process?.processIdentifier ?? 0) else { return }
        guard let name = commandName(of: pid_t(pid)), name.hasSuffix("caffeinate") else { return }
        kill(pid_t(pid), SIGTERM)
    }

    private func commandName(of pid: pid_t) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "comm="]
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let name = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }
}
