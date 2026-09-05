import Darwin
import Foundation
import ObjectiveC

/// Keyboard backlight via private CoreBrightness (`KeyboardBrightnessClient`).
///
/// IOKit's `KeyboardBacklightBrightness` property is a state mirror on Apple
/// Silicon and does not drive the LEDs. This is the same client System Settings
/// uses. Symbols are resolved at runtime so we do not link the private framework.
final class KeyboardBacklightService {
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"

    private let lock = NSLock()
    private var client: NSObject?

    private let idsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
    private let getSel = NSSelectorFromString("brightnessForKeyboard:")
    private let setSel = NSSelectorFromString("setBrightness:forKeyboard:")
    private let builtInSel = NSSelectorFromString("isKeyboardBuiltIn:")
    private let autoGetSel = NSSelectorFromString("isAutoBrightnessEnabledForKeyboard:")
    private let autoSetSel = NSSelectorFromString("enableAutoBrightness:forKeyboard:")

    private typealias FloatFromID = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias BoolFromID = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias BoolFromFloatAndID = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
    private typealias BoolFromBoolAndID = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool

    private enum Keys {
        static let didForce = "keyboardBacklightDidForce"
        static let brightness = "keyboardBacklightSavedBrightness"
        static let auto = "keyboardBacklightSavedAuto"
    }

    /// Turns the built-in keyboard backlight off and remembers the previous
    /// brightness / auto-brightness so `restoreIfNeeded` can put them back.
    func forceOff() {
        lock.lock()
        defer { lock.unlock() }
        guard let client = loadClient(), let id = keyboardID(client) else { return }
        if !UserDefaults.standard.bool(forKey: Keys.didForce) {
            UserDefaults.standard.set(brightness(client, id: id), forKey: Keys.brightness)
            UserDefaults.standard.set(isAutoEnabled(client, id: id), forKey: Keys.auto)
            UserDefaults.standard.set(true, forKey: Keys.didForce)
        }
        _ = setAuto(client, id: id, enabled: false)
        _ = setBrightness(client, id: id, value: 0)
    }

    func restoreIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard UserDefaults.standard.bool(forKey: Keys.didForce) else { return }
        let brightness = (UserDefaults.standard.object(forKey: Keys.brightness) as? NSNumber)?.floatValue ?? 0
        let auto = UserDefaults.standard.bool(forKey: Keys.auto)
        clearSavedState()
        guard let client = loadClient(), let id = keyboardID(client) else { return }
        _ = setBrightness(client, id: id, value: brightness)
        _ = setAuto(client, id: id, enabled: auto)
    }

    private func clearSavedState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.didForce)
        defaults.removeObject(forKey: Keys.brightness)
        defaults.removeObject(forKey: Keys.auto)
    }

    private func loadClient() -> NSObject? {
        if let client { return client }
        if dlopen(Self.frameworkPath, RTLD_NOW) == nil { return nil }
        guard let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            return nil
        }
        let client = cls.init()
        self.client = client
        return client
    }

    private func keyboardID(_ client: NSObject) -> UInt64? {
        guard client.responds(to: idsSel),
              let ids = client.perform(idsSel)?.takeRetainedValue() as? [NSNumber],
              !ids.isEmpty
        else { return nil }
        if client.responds(to: builtInSel),
           let isBuiltIn = imp(client, builtInSel, as: BoolFromID.self) {
            for number in ids where isBuiltIn(client, builtInSel, number.uint64Value) {
                return number.uint64Value
            }
        }
        return ids[0].uint64Value
    }

    private func brightness(_ client: NSObject, id: UInt64) -> Float {
        guard let fn = imp(client, getSel, as: FloatFromID.self) else { return 0 }
        return fn(client, getSel, id)
    }

    @discardableResult
    private func setBrightness(_ client: NSObject, id: UInt64, value: Float) -> Bool {
        guard let fn = imp(client, setSel, as: BoolFromFloatAndID.self) else { return false }
        return fn(client, setSel, max(0, min(1, value)), id)
    }

    private func isAutoEnabled(_ client: NSObject, id: UInt64) -> Bool {
        guard let fn = imp(client, autoGetSel, as: BoolFromID.self) else { return false }
        return fn(client, autoGetSel, id)
    }

    @discardableResult
    private func setAuto(_ client: NSObject, id: UInt64, enabled: Bool) -> Bool {
        guard let fn = imp(client, autoSetSel, as: BoolFromBoolAndID.self) else { return false }
        return fn(client, autoSetSel, enabled, id)
    }

    private func imp<T>(_ client: NSObject, _ selector: Selector, as: T.Type) -> T? {
        guard client.responds(to: selector), let method = client.method(for: selector) else {
            return nil
        }
        return unsafeBitCast(method, to: T.self)
    }
}
