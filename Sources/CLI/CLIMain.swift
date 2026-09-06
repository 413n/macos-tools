import Foundation

@main
struct NAFToolsCLI {
    static func main() {
        do {
            let request = try CLIParser.parse(Array(CommandLine.arguments.dropFirst()))
            try request.run()
        } catch let error as CLIError {
            switch error {
            case .usage(let message):
                if !message.isEmpty {
                    fputs("\(message)\n\n", stderr)
                }
                fputs(CLIParser.helpText, stderr)
                exit(2)
            case .failed(let message):
                fputs("\(message)\n", stderr)
                exit(1)
            case .permission(let message):
                fputs("\(message)\n", stderr)
                exit(3)
            }
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

enum CLIError: Error {
    case usage(String)
    case failed(String)
    case permission(String)
}

struct CLIRequest {
    var command: CLICommand
    var json: Bool

    func run() throws {
        switch command {
        case .help:
            print(CLIParser.helpText, terminator: "")
        case .status:
            try CLICommands.status(json: json)
        case .keyboard(let action):
            try CLICommands.keyboard(action, json: json)
        case .scroll(let action):
            try CLICommands.scroll(action, json: json)
        case .lid(let action):
            try CLICommands.lid(action, json: json)
        case .awake(let action):
            try CLICommands.awake(action, json: json)
        case .mac:
            try CLICommands.mac(json: json)
        }
    }
}

enum CLICommand {
    case help
    case status
    case keyboard(CLISwitch)
    case scroll(CLISwitch)
    case lid(CLISwitch)
    case awake(CLISwitch)
    case mac
}

enum CLISwitch {
    case on(minutes: Int?, dim: Bool?)
    case off
    case status
}
