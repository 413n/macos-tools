import Darwin
import Foundation

final class KeyboardTool: ToggleTool {
    let id: ToolID = .keyboard
    var onTimerExpired: (() -> Void)?

    private let service = KeyboardLockService()

    init() {
        service.onTimerExpired = { [weak self] in
            self?.persistLocked(false)
            self?.service.restoreBacklightIfNeeded()
            self?.onTimerExpired?()
        }
    }

    func snapshot() throws -> ToggleSnapshot {
        let hardware = try service.snapshot()
        return ToggleSnapshot(
            isOn: hardware.locked,
            remainingSeconds: nil,
            remainingMinutes: hardware.remainingMinutes
        )
    }

    func hardwareSnapshot() throws -> KeyboardLockService.Snapshot {
        try service.snapshot()
    }

    func setEnabled(_ enabled: Bool, options: ToolOptions) throws {
        if options.minutes != nil || options.dim != nil {
            ToolStateStore.shared.update { state in
                if let minutes = options.minutes { state.autoUnlockMinutes = minutes }
                if let dim = options.dim { state.dimKeyboardWhenLocked = dim }
            }
        }
        do {
            if enabled {
                let timeout = ToolStateStore.shared.current.autoUnlockMinutes
                try service.disable(timeoutMinutes: timeout > 0 ? timeout : nil)
            } else {
                try service.enable()
            }
        } catch {
            syncBacklight()
            throw ToolError.failed(error)
        }
        persistLocked(enabled)
        syncBacklight()
        ToolStateStore.shared.notifyChange()
    }

    func restore() {
        let state = ToolStateStore.shared.current
        let wantedLock = state.keyboardLocked
        guard wantedLock && Self.isCurrentBoot(state.keyboardLockBoot) else {
            if wantedLock {
                persistLocked(false)
            }
            alignAfterRestore()
            return
        }
        do {
            let snapshot = try service.snapshot()
            if snapshot.locked {
                service.resumeUITimerIfNeeded()
                syncBacklight(locked: true)
                return
            }
        } catch {
            // Mapping missing or hidutil failed — re-apply below.
        }
        do {
            try reapplyLock()
        } catch {
            syncBacklight()
        }
    }

    func reapplyLock() throws {
        service.invalidateIDs()
        do {
            try service.disable(timeoutMinutes: nil, preserveExistingTimer: true)
            service.resumeUITimerIfNeeded()
            let snapshot = try service.snapshot()
            persistLocked(snapshot.locked)
            syncBacklight(locked: snapshot.locked)
            ToolStateStore.shared.notifyChange()
        } catch {
            if let snapshot = try? service.snapshot() {
                persistLocked(snapshot.locked)
                syncBacklight(locked: snapshot.locked)
            }
            throw ToolError.failed(error)
        }
    }

    func invalidateIDs() {
        service.invalidateIDs()
    }

    func resumeUITimerIfNeeded() {
        service.resumeUITimerIfNeeded()
    }

    func syncBacklight(locked: Bool? = nil) {
        let isLocked = locked ?? ((try? service.snapshot().locked) ?? false)
        let dim = ToolStateStore.shared.current.dimKeyboardWhenLocked
        service.syncBacklight(locked: isLocked, dimWhileLocked: dim)
    }

    func restoreBacklightIfNeeded() {
        service.restoreBacklightIfNeeded()
    }

    func persistLocked(_ locked: Bool) {
        ToolStateStore.shared.update {
            $0.keyboardLocked = locked
            if locked {
                $0.keyboardLockBoot = Self.currentBootTime()
            }
        }
    }

    private func alignAfterRestore() {
        do {
            let snapshot = try service.snapshot()
            if snapshot.locked {
                service.resumeUITimerIfNeeded()
                syncBacklight(locked: true)
            } else {
                restoreBacklightIfNeeded()
            }
        } catch {
            restoreBacklightIfNeeded()
        }
    }

    private static func currentBootTime() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &boot, &size, nil, 0)
        return TimeInterval(boot.tv_sec)
    }

    private static func isCurrentBoot(_ saved: TimeInterval) -> Bool {
        guard saved > 0 else { return false }
        return abs(saved - currentBootTime()) < 1
    }
}
