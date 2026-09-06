import Foundation

final class LidTool: ToggleTool {
    let id: ToolID = .lid
    private let service = LidSleepService()

    func snapshot() throws -> ToggleSnapshot {
        ToggleSnapshot(
            isOn: service.snapshot().disabled,
            remainingSeconds: nil,
            remainingMinutes: nil
        )
    }

    func hardwareSnapshot() -> LidSleepService.Snapshot {
        service.snapshot()
    }

    func setEnabled(_ enabled: Bool, options: ToolOptions) throws {
        _ = options
        do {
            try runOnMain {
                try self.service.setDisabled(enabled)
            }
        } catch {
            throw ToolError.lid(error)
        }
        persist(enabled)
        ToolStateStore.shared.notifyChange()
    }

    func restore() {
        persist(service.snapshot().disabled)
    }

    private func persist(_ disabled: Bool) {
        ToolStateStore.shared.update { $0.lidSleepDisabled = disabled }
    }

    private func runOnMain(_ body: @escaping () throws -> Void) throws {
        if Thread.isMainThread {
            try body()
            return
        }
        var caught: Error?
        DispatchQueue.main.sync {
            do {
                try body()
            } catch {
                caught = error
            }
        }
        if let caught { throw caught }
    }
}
