import Foundation

final class ToolRegistry {
    static let shared = ToolRegistry()

    let keyboard = KeyboardTool()
    let scroll = ScrollTool()
    let lid = LidTool()
    let awake = AwakeTool()

    var toggles: [any ToggleTool] {
        [keyboard, scroll, lid, awake]
    }

    func toggle(_ id: ToolID) -> any ToggleTool {
        switch id {
        case .keyboard: keyboard
        case .scroll: scroll
        case .lid: lid
        case .awake: awake
        case .machine, .battery, .network, .storage:
            preconditionFailure("\(id.rawValue) is informational")
        }
    }

    func restoreAll() {
        for tool in toggles {
            tool.restore()
        }
    }
}
