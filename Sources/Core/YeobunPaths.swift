import Darwin
import Foundation

enum YeobunPaths {
    static let stateDidChangeNotification = Notification.Name("studio.n6.yeobun.stateDidChange")
    static let scrollReloadNotification = Notification.Name("studio.n6.yeobun.scrollReload")
    static let scrollHelperName = "yeobun-scroll"

    static var applicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Yeobun", isDirectory: true)
    }

    static var legacyApplicationSupport: URL {
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

    static func migrateLegacySupportIfNeeded() {
        let fm = FileManager.default
        if fm.fileExists(atPath: stateFile.path) { return }
        let legacy = legacyApplicationSupport.appendingPathComponent("state.json")
        guard fm.fileExists(atPath: legacy.path) else { return }
        try? fm.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        try? fm.copyItem(at: legacy, to: stateFile)
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
