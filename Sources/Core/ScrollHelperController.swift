import Darwin
import Foundation

final class ScrollHelperController {
    static let shared = ScrollHelperController()

    var isRunning: Bool {
        let pid = pid_t(ToolStateStore.shared.current.scrollHelperPID)
        return DetachedProcess.isRunning(pid: pid, commandContains: NAFPaths.scrollHelperName)
    }

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let url = NAFPaths.scrollHelperURL
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            return false
        }
        do {
            let pid = try DetachedProcess.spawn(executable: url.path, arguments: [])
            ToolStateStore.shared.update { $0.scrollHelperPID = Int(pid) }
            usleep(250_000)
            if isRunning { return true }
            usleep(250_000)
            return isRunning
        } catch {
            return false
        }
    }

    func stop() {
        let pid = pid_t(ToolStateStore.shared.current.scrollHelperPID)
        if DetachedProcess.isRunning(pid: pid, commandContains: NAFPaths.scrollHelperName) {
            kill(pid, SIGTERM)
            for _ in 0..<30 {
                if !DetachedProcess.isRunning(pid: pid, commandContains: NAFPaths.scrollHelperName) {
                    break
                }
                usleep(50_000)
            }
        }
        ToolStateStore.shared.update { $0.scrollHelperPID = 0 }
    }
}

enum ScrollPolicy {
    static func enabledIDs(mice: [MouseDevice], map: [String: Bool], enabled: Bool) -> Set<String> {
        guard enabled else { return [] }
        return Set(mice.filter { map[$0.id] ?? true }.map(\.id))
    }
}
