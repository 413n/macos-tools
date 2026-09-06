import Foundation

struct KeyboardStatusJSON: Encodable {
    var locked: Bool
    var remainingMinutes: Int?
    var dim: Bool

    enum CodingKeys: String, CodingKey { case locked, remainingMinutes, dim }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(locked, forKey: .locked)
        try container.encode(remainingMinutes, forKey: .remainingMinutes)
        try container.encode(dim, forKey: .dim)
    }
}

struct ScrollMouseJSON: Encodable {
    var id: String
    var name: String
    var enabled: Bool
}

struct ScrollStatusJSON: Encodable {
    var enabled: Bool
    var active: Bool
    var accessibility: Bool
    var mice: [ScrollMouseJSON]
}

struct LidStatusJSON: Encodable {
    var disabled: Bool
}

struct AwakeStatusJSON: Encodable {
    var active: Bool
    var remainingSeconds: Int?

    enum CodingKeys: String, CodingKey { case active, remainingSeconds }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(active, forKey: .active)
        try container.encode(remainingSeconds, forKey: .remainingSeconds)
    }
}

struct MacStatusJSON: Encodable {
    var cpuPercent: Int
    var ramUsedBytes: UInt64
    var ramTotalBytes: UInt64
}

struct ToolsSnapshot: Encodable {
    var keyboard: KeyboardStatusJSON
    var scroll: ScrollStatusJSON
    var lid: LidStatusJSON
    var awake: AwakeStatusJSON
    var mac: MacStatusJSON?
}

enum StatusBuilder {
    static func make(includeMac: Bool) -> ToolsSnapshot {
        let store = ToolStateStore.shared.current
        let keyboard = (try? KeyboardLockService().snapshot()) ?? .init(locked: false, remainingMinutes: nil)
        let mice = DeviceMonitor.listMiceOnce()
        let lid = LidSleepService().snapshot()
        let awake = CaffeinateService().snapshot()
        return ToolsSnapshot(
            keyboard: KeyboardStatusJSON(
                locked: keyboard.locked,
                remainingMinutes: keyboard.remainingMinutes,
                dim: store.dimKeyboardWhenLocked
            ),
            scroll: ScrollStatusJSON(
                enabled: store.scrollReverseEnabled,
                active: ScrollHelperController.shared.isRunning,
                accessibility: AccessibilityAuth.hasPermission,
                mice: mice.map { mouse in
                    ScrollMouseJSON(
                        id: mouse.id,
                        name: mouse.name,
                        enabled: store.scrollReverseByDevice[mouse.id] ?? true
                    )
                }
            ),
            lid: LidStatusJSON(disabled: lid.disabled),
            awake: AwakeStatusJSON(
                active: awake.active,
                remainingSeconds: awake.remainingSeconds
            ),
            mac: includeMac ? macStatus() : nil
        )
    }

    static func macStatus() -> MacStatusJSON {
        let sample = SystemStatsService().sampleOnce()
        return MacStatusJSON(
            cpuPercent: sample.cpuReady ? Int((sample.cpuFraction * 100).rounded()) : 0,
            ramUsedBytes: sample.ramUsed,
            ramTotalBytes: sample.ramTotal
        )
    }

    static func jsonString(_ snapshot: ToolsSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
