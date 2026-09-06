import Foundation

final class ScrollTool: ToggleTool {
    let id: ToolID = .scroll

    static let accessibilityMessage =
        "Scroll reverse needs Accessibility permission (System Settings → Privacy & Security → Accessibility)."

    func snapshot() throws -> ToggleSnapshot {
        ToggleSnapshot(
            isOn: ToolStateStore.shared.current.scrollReverseEnabled,
            remainingSeconds: nil,
            remainingMinutes: nil
        )
    }

    func setEnabled(_ enabled: Bool, options: ToolOptions) throws {
        _ = options
        try setEnabled(enabled, mice: DeviceMonitor.listMiceOnce())
    }

    func setEnabled(_ enabled: Bool, mice: [MouseDevice]) throws {
        if enabled {
            try turnOn(mice: mice)
        } else {
            turnOff()
        }
        ToolStateStore.shared.notifyChange()
    }

    func restore() {
        apply(mice: DeviceMonitor.listMiceOnce())
    }

    func setDevice(id: String, enabled: Bool, mice: [MouseDevice]) {
        ToolStateStore.shared.update { $0.scrollReverseByDevice[id] = enabled }
        apply(mice: mice)
        ToolStateStore.shared.notifyChange()
    }

    func seedMouseDefaults(_ mice: [MouseDevice]) -> Bool {
        var changed = false
        ToolStateStore.shared.update { state in
            for mouse in mice where state.scrollReverseByDevice[mouse.id] == nil {
                state.scrollReverseByDevice[mouse.id] = true
                changed = true
            }
        }
        return changed
    }

    func apply(mice: [MouseDevice]) {
        let state = ToolStateStore.shared.current
        let enabledIDs = ScrollPolicy.enabledIDs(
            mice: mice,
            map: state.scrollReverseByDevice,
            enabled: state.scrollReverseEnabled
        )
        DeviceMonitor.reverseEnabledIDs = enabledIDs
        let shouldRun = state.scrollReverseEnabled && mice.contains {
            state.scrollReverseByDevice[$0.id] ?? true
        }
        if shouldRun {
            if !ScrollHelperController.shared.start() {
                ScrollHelperController.shared.stop()
            }
        } else {
            ScrollHelperController.shared.stop()
        }
    }

    func isOn(for id: String) -> Bool {
        ToolStateStore.shared.current.scrollReverseByDevice[id] ?? true
    }

    private func turnOn(mice: [MouseDevice]) throws {
        if !AccessibilityAuth.hasPermission {
            AccessibilityAuth.requestIfNeeded()
        }
        ToolStateStore.shared.update { state in
            state.scrollReverseEnabled = true
            for mouse in mice where state.scrollReverseByDevice[mouse.id] == nil {
                state.scrollReverseByDevice[mouse.id] = true
            }
        }
        apply(mice: mice)
        let shouldRun = mice.contains {
            ToolStateStore.shared.current.scrollReverseByDevice[$0.id] ?? true
        }
        if shouldRun, !ScrollHelperController.shared.isRunning {
            if !AccessibilityAuth.hasPermission {
                throw ToolError.permission(Self.accessibilityMessage)
            }
            throw ToolError.failed("Could not start scroll reverse.")
        }
    }

    private func turnOff() {
        ToolStateStore.shared.update { $0.scrollReverseEnabled = false }
        ScrollHelperController.shared.stop()
    }
}
