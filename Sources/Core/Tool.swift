import Foundation

enum ToolKind {
    case toggle
    case informational
}

enum ToolID: String, CaseIterable, Identifiable {
    case keyboard
    case scroll
    case lid
    case awake
    case machine
    case battery
    case network
    case storage

    var id: String { rawValue }

    var kind: ToolKind {
        switch self {
        case .keyboard, .scroll, .lid, .awake: .toggle
        case .machine, .battery, .network, .storage: .informational
        }
    }

    static var toggleIDs: [ToolID] {
        allCases.filter { $0.kind == .toggle }
    }
}

struct ToolOptions {
    var minutes: Int?
    var dim: Bool?

    init(minutes: Int? = nil, dim: Bool? = nil) {
        self.minutes = minutes
        self.dim = dim
    }
}

struct ToggleSnapshot {
    var isOn: Bool
    var remainingSeconds: Int?
    var remainingMinutes: Int?
}

enum ToolError: LocalizedError {
    case failed(String)
    case permission(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message), .permission(let message):
            return message
        }
    }

    static func failed(_ error: Error) -> ToolError {
        .failed(error.localizedDescription)
    }

    static func lid(_ error: Error) -> ToolError {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("cancel")
            || message.localizedCaseInsensitiveContains("administrator") {
            return .permission(message)
        }
        return .failed(message)
    }
}

protocol ToggleTool: AnyObject {
    var id: ToolID { get }
    func snapshot() throws -> ToggleSnapshot
    func setEnabled(_ enabled: Bool, options: ToolOptions) throws
    func restore()
}
