import Foundation

enum CLICommands {
    static func status(json: Bool) throws {
        emit(StatusBuilder.make(includeMac: true), json: json)
    }

    static func mac(json: Bool) throws {
        if json {
            emit(StatusBuilder.make(includeMac: true), json: true)
            return
        }
        print(humanMac(StatusBuilder.macStatus()))
    }

    static func keyboard(_ action: CLISwitch, json: Bool) throws {
        try run(.keyboard, action)
        emit(StatusBuilder.make(includeMac: false), json: json, focus: .keyboard)
    }

    static func scroll(_ action: CLISwitch, json: Bool) throws {
        try run(.scroll, action)
        emit(StatusBuilder.make(includeMac: false), json: json, focus: .scroll)
    }

    static func lid(_ action: CLISwitch, json: Bool) throws {
        try run(.lid, action)
        emit(StatusBuilder.make(includeMac: false), json: json, focus: .lid)
    }

    static func awake(_ action: CLISwitch, json: Bool) throws {
        try run(.awake, action)
        emit(StatusBuilder.make(includeMac: false), json: json, focus: .awake)
    }

    private static func run(_ id: ToolID, _ action: CLISwitch) throws {
        let tool = ToolRegistry.shared.toggle(id)
        switch action {
        case .status:
            return
        case .on(let minutes, let dim):
            let options: ToolOptions
            if id == .awake {
                options = ToolOptions(minutes: minutes ?? 0)
            } else {
                options = ToolOptions(minutes: minutes, dim: dim)
            }
            try mapError { try tool.setEnabled(true, options: options) }
        case .off:
            try mapError { try tool.setEnabled(false, options: ToolOptions()) }
        }
    }

    private static func mapError(_ body: () throws -> Void) throws {
        do {
            try body()
        } catch let error as ToolError {
            switch error {
            case .permission(let message):
                throw CLIError.permission(message)
            case .failed(let message):
                throw CLIError.failed(message)
            }
        } catch {
            throw CLIError.failed(error.localizedDescription)
        }
    }

    private enum Focus {
        case keyboard, scroll, lid, awake, all
    }

    private static func emit(_ snapshot: ToolsSnapshot, json: Bool, focus: Focus = .all) {
        if json {
            if let text = try? StatusBuilder.jsonString(snapshot) {
                print(text)
            }
            return
        }
        switch focus {
        case .all:
            print(humanLine("keyboard", humanKeyboard(snapshot.keyboard)))
            print(humanLine("scroll", humanScroll(snapshot.scroll)))
            print(humanLine("lid", humanLid(snapshot.lid)))
            print(humanLine("awake", humanAwake(snapshot.awake)))
            if let mac = snapshot.mac {
                print(humanLine("mac", humanMac(mac)))
            }
        case .keyboard:
            print(humanLine("keyboard", humanKeyboard(snapshot.keyboard)))
        case .scroll:
            print(humanLine("scroll", humanScroll(snapshot.scroll)))
        case .lid:
            print(humanLine("lid", humanLid(snapshot.lid)))
        case .awake:
            print(humanLine("awake", humanAwake(snapshot.awake)))
        }
    }

    private static func humanLine(_ name: String, _ rest: String) -> String {
        name.padding(toLength: 10, withPad: " ", startingAt: 0) + rest
    }

    private static func humanKeyboard(_ status: KeyboardStatusJSON) -> String {
        if !status.locked { return "off" }
        var parts = ["on"]
        if let remaining = status.remainingMinutes {
            parts.append("auto-unlock \(remaining) min")
        }
        if status.dim { parts.append("dim") }
        return parts.joined(separator: "  ")
    }

    private static func humanScroll(_ status: ScrollStatusJSON) -> String {
        if !status.enabled { return "off" }
        var parts = [status.active ? "on" : "on (inactive)"]
        if !status.accessibility { parts.append("needs Accessibility") }
        if status.mice.isEmpty {
            parts.append("no mouse")
        } else {
            let names = status.mice.map { mouse in
                mouse.enabled ? mouse.name : "\(mouse.name) off"
            }
            parts.append(names.joined(separator: ", "))
        }
        return parts.joined(separator: "  ")
    }

    private static func humanLid(_ status: LidStatusJSON) -> String {
        status.disabled ? "on (lid stays awake on battery)" : "off"
    }

    private static func humanAwake(_ status: AwakeStatusJSON) -> String {
        if !status.active { return "off" }
        if let remaining = status.remainingSeconds {
            return "on  \(formatRemaining(remaining)) left"
        }
        return "on  indefinitely"
    }

    private static func humanMac(_ status: MacStatusJSON) -> String {
        let used = formatGB(status.ramUsedBytes)
        let total = formatGB(status.ramTotalBytes)
        var parts = ["CPU \(status.cpuPercent)%", "RAM \(used) / \(total)"]
        parts.append("pressure \(status.memoryPressure)")
        if let diskUsed = status.diskUsedBytes, let diskTotal = status.diskTotalBytes, diskTotal > 0 {
            parts.append("disk \(formatGB(diskTotal - diskUsed)) free")
        }
        if let battery = status.batteryPercent {
            let charge = status.batteryCharging == true ? " charging" : ""
            parts.append("battery \(battery)%\(charge)")
        }
        parts.append(status.networkKind)
        if status.networkDownBytesPerSecond > 0 || status.networkUpBytesPerSecond > 0 {
            parts.append(
                "↓\(StatsFormat.rate(status.networkDownBytesPerSecond, compact: true)) ↑\(StatsFormat.rate(status.networkUpBytesPerSecond, compact: true))"
            )
        }
        return parts.joined(separator: "  ")
    }

    private static func formatRemaining(_ seconds: Int) -> String {
        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if seconds >= 60 { return "\(seconds / 60) min" }
        return "\(seconds)s"
    }

    private static func formatGB(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 10 { return String(format: "%.0f GB", gb) }
        return String(format: "%.1f GB", gb)
    }
}
