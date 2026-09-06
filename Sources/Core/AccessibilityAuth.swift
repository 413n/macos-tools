import ApplicationServices
import Foundation

enum AccessibilityAuth {
    static var hasPermission: Bool {
        AXIsProcessTrusted() || CGPreflightPostEventAccess() || CGPreflightListenEventAccess()
    }

    static func isTrusted(prompt: Bool) -> Bool {
        if prompt {
            requestIfNeeded()
        }
        return hasPermission
    }

    static func requestIfNeeded() {
        if hasPermission { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
