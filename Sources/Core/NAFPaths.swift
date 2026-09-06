import Darwin
import Foundation

enum NAFPaths {
    static let stateDidChangeNotification = Notification.Name("com.alessandro.naf-tools.stateDidChange")
    static let scrollReloadNotification = Notification.Name("com.alessandro.naf-tools.scrollReload")
    static let scrollHelperName = "naf-tools-scroll"

    static var applicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NAF Tools", isDirectory: true)
    }

    static var stateFile: URL {
        applicationSupport.appendingPathComponent("state.json")
    }

    static var executableDirectory: URL {
        let bundled = Bundle.main.executableURL?.deletingLastPathComponent()
        if let bundled, FileManager.default.fileExists(atPath: helperURL(in: bundled).path) {
            return bundled
        }
        return resolvedExecutable().deletingLastPathComponent()
    }

    static var scrollHelperURL: URL {
        helperURL(in: executableDirectory)
    }

    private static func helperURL(in directory: URL) -> URL {
        directory.appendingPathComponent(scrollHelperName)
    }

    private static func resolvedExecutable() -> URL {
        let argv0 = CommandLine.arguments[0]
        if argv0.contains("/") {
            return URL(fileURLWithPath: argv0).resolvingSymlinksInPath()
        }
        if let path = getenv("PATH") {
            for dir in String(cString: path).split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(argv0)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate.resolvingSymlinksInPath()
                }
            }
        }
        return URL(fileURLWithPath: argv0).resolvingSymlinksInPath()
    }
}
