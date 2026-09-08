import Foundation

enum CLIParser {
    static let keyboardMinutes = [5, 10, 15, 30, 60]
    static let awakeMinutes = [5, 10, 15, 30, 60, 120, 300]

    static let helpText = """
    yeobun — control Yeobun from the terminal

    Usage:
      yeobun status [--json]
      yeobun keyboard on [--minutes N] [--dim|--no-dim] [--json]
      yeobun keyboard off [--json]
      yeobun keyboard status [--json]
      yeobun scroll on [--json]
      yeobun scroll off [--json]
      yeobun scroll status [--json]
      yeobun lid on [--json]
      yeobun lid off [--json]
      yeobun lid status [--json]
      yeobun awake on [--minutes N] [--json]
      yeobun awake off [--json]
      yeobun awake status [--json]
      yeobun mac [--json]

    Keyboard --minutes: \(keyboardMinutes.map(String.init).joined(separator: ", "))
    Awake --minutes: \(awakeMinutes.map(String.init).joined(separator: ", ")) (omit for indefinitely)

    Exit codes: 0 ok, 1 failed, 2 usage, 3 permission

    """

    static func parse(_ args: [String]) throws -> CLIRequest {
        if args.isEmpty {
            return CLIRequest(command: .status, json: false)
        }
        var tokens = args
        var json = false
        tokens.removeAll { token in
            if token == "--json" {
                json = true
                return true
            }
            return false
        }
        guard let first = tokens.first else {
            return CLIRequest(command: .status, json: json)
        }
        if first == "--help" || first == "-h" || first == "help" {
            return CLIRequest(command: .help, json: json)
        }
        switch first {
        case "status":
            guard tokens.count == 1 else { throw CLIError.usage("Unexpected arguments for status.") }
            return CLIRequest(command: .status, json: json)
        case "mac":
            guard tokens.count == 1 else { throw CLIError.usage("Unexpected arguments for mac.") }
            return CLIRequest(command: .mac, json: json)
        case "keyboard":
            return CLIRequest(command: .keyboard(try parseSwitch(Array(tokens.dropFirst()), tool: .keyboard)), json: json)
        case "scroll":
            return CLIRequest(command: .scroll(try parseSwitch(Array(tokens.dropFirst()), tool: .scroll)), json: json)
        case "lid":
            return CLIRequest(command: .lid(try parseSwitch(Array(tokens.dropFirst()), tool: .lid)), json: json)
        case "awake":
            return CLIRequest(command: .awake(try parseSwitch(Array(tokens.dropFirst()), tool: .awake)), json: json)
        default:
            throw CLIError.usage("Unknown command: \(first)")
        }
    }

    private static func parseSwitch(_ tokens: [String], tool: ToolID) throws -> CLISwitch {
        guard let action = tokens.first else {
            return .status
        }
        switch action {
        case "status":
            guard tokens.count == 1 else { throw CLIError.usage("Unexpected arguments for status.") }
            return .status
        case "off":
            guard tokens.count == 1 else { throw CLIError.usage("Unexpected arguments for off.") }
            return .off
        case "on":
            return try parseOn(Array(tokens.dropFirst()), tool: tool)
        default:
            throw CLIError.usage("Unknown action: \(action) (expected on, off, or status)")
        }
    }

    private static func parseOn(_ tokens: [String], tool: ToolID) throws -> CLISwitch {
        var minutes: Int?
        var dim: Bool?
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            switch token {
            case "--minutes":
                guard tool == .keyboard || tool == .awake else {
                    throw CLIError.usage("\(toolName(tool)) does not take --minutes.")
                }
                i += 1
                guard i < tokens.count, let value = Int(tokens[i]) else {
                    throw CLIError.usage("--minutes needs a number.")
                }
                minutes = try validateMinutes(value, tool: tool)
            case "--dim":
                guard tool == .keyboard else { throw CLIError.usage("Only keyboard takes --dim.") }
                dim = true
            case "--no-dim":
                guard tool == .keyboard else { throw CLIError.usage("Only keyboard takes --no-dim.") }
                dim = false
            default:
                throw CLIError.usage("Unexpected argument: \(token)")
            }
            i += 1
        }
        return .on(minutes: minutes, dim: dim)
    }

    private static func validateMinutes(_ value: Int, tool: ToolID) throws -> Int {
        let allowed = tool == .keyboard ? keyboardMinutes : awakeMinutes
        guard allowed.contains(value) else {
            throw CLIError.usage(
                "--minutes must be one of \(allowed.map(String.init).joined(separator: ", "))."
            )
        }
        return value
    }

    private static func toolName(_ tool: ToolID) -> String {
        tool.rawValue
    }
}
