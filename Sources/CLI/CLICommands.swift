import Darwin
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
        let service = KeyboardLockService()
        switch action {
        case .status:
            break
        case .on(let minutes, let dim):
            ToolStateStore.shared.update { state in
                if let minutes { state.autoUnlockMinutes = minutes }
                if let dim { state.dimKeyboardWhenLocked = dim }
            }
            let timeout = ToolStateStore.shared.current.autoUnlockMinutes
            do {
                try service.disable(timeoutMinutes: timeout > 0 ? timeout : nil)
            } catch {
                throw CLIError.failed(error.localizedDescription)
            }
            let lockedDim = ToolStateStore.shared.current.dimKeyboardWhenLocked
            service.syncBacklight(locked: true, dimWhileLocked: lockedDim)
            persistKeyboardLocked(true)
            ToolStateStore.shared.notifyChange()
        case .off:
            do {
                try service.enable()
            } catch {
                throw CLIError.failed(error.localizedDescription)
            }
            service.syncBacklight(locked: false, dimWhileLocked: false)
            persistKeyboardLocked(false)
            ToolStateStore.shared.notifyChange()
        }
        emit(StatusBuilder.make(includeMac: false), json: json, focus: .keyboard)
    }

    static func scroll(_ action: CLISwitch, json: Bool) throws {
        switch action {
        case .status:
            break
        case .on:
            if !AccessibilityAuth.hasPermission {
                AccessibilityAuth.requestIfNeeded()
            }
            let mice = DeviceMonitor.listMiceOnce()
            ToolStateStore.shared.update { state in
                state.scrollReverseEnabled = true
                for mouse in mice where state.scrollReverseByDevice[mouse.id] == nil {
                    state.scrollReverseByDevice[mouse.id] = true
                }
            }
            let shouldRun = mice.contains {
                ToolStateStore.shared.current.scrollReverseByDevice[$0.id] ?? true
            }
            if shouldRun {
                guard ScrollHelperController.shared.start() else {
                    if !AccessibilityAuth.hasPermission {
                        throw CLIError.permission(
                            "Scroll reverse needs Accessibility permission (System Settings → Privacy & Security → Accessibility)."
                        )
                    }
                    throw CLIError.failed("Could not start scroll reverse.")
                }
            }
            ToolStateStore.shared.notifyChange()
        case .off:
            ToolStateStore.shared.update { $0.scrollReverseEnabled = false }
            ScrollHelperController.shared.stop()
            ToolStateStore.shared.notifyChange()
        }
        emit(StatusBuilder.make(includeMac: false), json: json, focus: .scroll)
    }

    static func lid(_ action: CLISwitch, json: Bool) throws {
        let service = LidSleepService()
        switch action {
        case .status:
            break
        case .on:
            do {
                try service.setDisabled(true)
            } catch {
                throw lidError(error)
            }
            ToolStateStore.shared.update { $0.lidSleepDisabled = true }
            ToolStateStore.shared.notifyChange()
        case .off:
            do {
                try service.setDisabled(false)
            } catch {
                throw lidError(error)
            }
            ToolStateStore.shared.update { $0.lidSleepDisabled = false }
            ToolStateStore.shared.notifyChange()
        }
        emit(StatusBuilder.make(includeMac: false), json: json, focus: .lid)
    }

    static func awake(_ action: CLISwitch, json: Bool) throws {
        let service = CaffeinateService()
        switch action {
        case .status:
            break
        case .on(let minutes, _):
            let chosen = minutes ?? 0
            do {
                try service.start(timeoutSeconds: chosen > 0 ? chosen * 60 : nil)
            } catch {
                throw CLIError.failed(error.localizedDescription)
            }
            ToolStateStore.shared.update {
                $0.awakeEnabled = true
                $0.awakeMinutes = chosen
            }
            ToolStateStore.shared.notifyChange()
        case .off:
            service.stop()
            ToolStateStore.shared.update { $0.awakeEnabled = false }
            ToolStateStore.shared.notifyChange()
        }
        emit(StatusBuilder.make(includeMac: false), json: json, focus: .awake)
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
        return "CPU \(status.cpuPercent)%  RAM \(used) / \(total)"
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

    private static func persistKeyboardLocked(_ locked: Bool) {
        ToolStateStore.shared.update { state in
            state.keyboardLocked = locked
            if locked {
                var boot = timeval()
                var size = MemoryLayout<timeval>.size
                sysctlbyname("kern.boottime", &boot, &size, nil, 0)
                state.keyboardLockBoot = TimeInterval(boot.tv_sec)
            }
        }
    }

    private static func lidError(_ error: Error) -> CLIError {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("cancel")
            || message.localizedCaseInsensitiveContains("administrator") {
            return .permission(message)
        }
        return .failed(message)
    }
}
