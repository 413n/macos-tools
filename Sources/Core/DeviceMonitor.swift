import Foundation
import IOKit
import IOKit.hid

struct MouseDevice: Identifiable, Hashable {
    let vendor: Int
    let product: Int
    let name: String

    var id: String { "\(vendor):\(product)" }

    static func make(from device: IOHIDDevice) -> MouseDevice? {
        let vendor = intValue(device, kIOHIDVendorIDKey) ?? 0
        let product = intValue(device, kIOHIDProductIDKey) ?? 0
        let name = stringValue(device, kIOHIDProductKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard vendor != 0 || product != 0 || !name.isEmpty else { return nil }
        return MouseDevice(
            vendor: vendor,
            product: product,
            name: name.isEmpty ? "Mouse" : name
        )
    }
}

struct DeviceSnapshot {
    var mice: [MouseDevice]
    var keyboardCompositeIDs: Set<String> = []

    var hasExternalMouse: Bool { !mice.isEmpty }
    var mouseNames: [String] { mice.map(\.name) }
}

final class DeviceMonitor {
    static private(set) var hasExternalMouseCached = false
    static private(set) var lastActiveMouseID: String?
    static private(set) var keyboardCompositeIDs: Set<String> = []

    private static let stateLock = NSLock()

    static func noteActiveMouse(id: String) {
        stateLock.lock()
        lastActiveMouseID = id
        stateLock.unlock()
    }

    static func activeMouseID() -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return lastActiveMouseID
    }

    static var reverseEnabledIDs: Set<String> = []
    static var connectedMouseIDs: [String] = []

    var onChange: ((DeviceSnapshot) -> Void)?

    private var manager: IOHIDManager?
    private var hidutilMice: [MouseDevice] = []
    private var hidutilKeyboardIDs: Set<String> = []

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey as String: 1, kIOHIDDeviceUsageKey as String: 2],
            [kIOHIDDeviceUsagePageKey as String: 1, kIOHIDDeviceUsageKey as String: 1],
            [kIOHIDDeviceUsagePageKey as String: 1, kIOHIDDeviceUsageKey as String: 6]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceArrived, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceRemoved, context)
        // Input callbacks need Input Monitoring. Register them only when
        // granted so a denied TCC grant cannot empty the device list.
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
            IOHIDManagerRegisterInputValueCallback(manager, hidInputValue, context)
        }
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        publish()
        DispatchQueue.main.async { [weak self] in
            self?.publish()
        }
        refreshHidutil()
    }

    func refresh() {
        publish()
        refreshHidutil()
    }

    private func refreshHidutil() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let parsed = miceFromHidutil()
            DispatchQueue.main.async {
                self?.hidutilMice = parsed.mice
                self?.hidutilKeyboardIDs = parsed.keyboardIDs
                self?.publish()
            }
        }
    }

    func stop() {
        guard let manager else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    func publish() {
        let snapshot = currentSnapshot(from: manager)
        DeviceMonitor.hasExternalMouseCached = snapshot.hasExternalMouse
        DeviceMonitor.connectedMouseIDs = snapshot.mice.map(\.id)
        DeviceMonitor.keyboardCompositeIDs = snapshot.keyboardCompositeIDs
        onChange?(snapshot)
    }

    static func listMiceOnce() -> [MouseDevice] {
        miceFromHidutil().mice.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func builtinKeyboardIDs() -> (vendor: Int, product: Int)? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: 1,
            kIOHIDDeviceUsageKey as String: 6
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        return firstBuiltinKeyboard(in: IOHIDManagerCopyDevices(manager))
    }

    fileprivate static func firstBuiltinKeyboard(in set: CFSet?) -> (vendor: Int, product: Int)? {
        var found: (vendor: Int, product: Int)?
        forEachDevice(in: set) { device in
            guard found == nil, isBuiltinKeyboard(device) else { return }
            if let vendor = intValue(device, kIOHIDVendorIDKey),
               let product = intValue(device, kIOHIDProductIDKey),
               vendor != 0 {
                found = (vendor, product)
            }
        }
        return found
    }

    private func currentSnapshot(from manager: IOHIDManager?) -> DeviceSnapshot {
        var mice: [MouseDevice] = []
        var keyboardIDs = hidutilKeyboardIDs
        if let manager {
            forEachDevice(in: IOHIDManagerCopyDevices(manager)) { device in
                guard isKeyboard(device), let id = MouseDevice.make(from: device)?.id else { return }
                keyboardIDs.insert(id)
            }
            forEachDevice(in: IOHIDManagerCopyDevices(manager)) { device in
                guard isExternalMouse(device), let mouse = MouseDevice.make(from: device) else { return }
                guard isRealMouse(mouse, keyboardIDs: keyboardIDs) else { return }
                if !mice.contains(where: { $0.id == mouse.id }) {
                    mice.append(mouse)
                }
            }
        }
        for mouse in hidutilMice where isRealMouse(mouse, keyboardIDs: keyboardIDs) {
            if !mice.contains(where: { $0.id == mouse.id }) {
                mice.append(mouse)
            }
        }
        mice.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return DeviceSnapshot(mice: mice, keyboardCompositeIDs: keyboardIDs)
    }
}

private func forEachDevice(in set: CFSet?, body: (IOHIDDevice) -> Void) {
    guard let set else { return }
    for object in (set as NSSet) {
        let device = unsafeBitCast(object as AnyObject, to: IOHIDDevice.self)
        body(device)
    }
}

private func hidDeviceArrived(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<DeviceMonitor>.fromOpaque(context).takeUnretainedValue().publish()
}

private func hidDeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    Unmanaged<DeviceMonitor>.fromOpaque(context).takeUnretainedValue().publish()
}

private func hidInputValue(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    let element = IOHIDValueGetElement(value)
    guard isPointerOrWheelElement(element) else { return }
    let device = IOHIDElementGetDevice(element)
    guard isExternalMouse(device), let mouse = MouseDevice.make(from: device) else { return }
    if !isMouse(device), !isRealMouse(mouse, keyboardIDs: DeviceMonitor.keyboardCompositeIDs) { return }
    DeviceMonitor.noteActiveMouse(id: mouse.id)
}

private func isPointerOrWheelElement(_ element: IOHIDElement) -> Bool {
    let page = Int(IOHIDElementGetUsagePage(element))
    let usage = Int(IOHIDElementGetUsage(element))
    if page == 1 {
        switch usage {
        case 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38:
            return true
        default:
            return false
        }
    }
    if page == 9 { return usage >= 1 && usage <= 8 }
    if page == 12 { return usage == 0x238 }
    return false
}

private func isRealMouse(_ mouse: MouseDevice, keyboardIDs: Set<String>) -> Bool {
    guard keyboardIDs.contains(mouse.id) else { return true }
    return mouse.name.localizedCaseInsensitiveContains("Mouse")
}

private func isBuiltinKeyboard(_ device: IOHIDDevice) -> Bool {
    guard isKeyboard(device) else { return false }
    let product = stringValue(device, kIOHIDProductKey) ?? ""
    if product.localizedCaseInsensitiveContains("Backlight") { return false }
    if boolValue(device, kIOHIDBuiltInKey) { return true }
    if product.localizedCaseInsensitiveContains("Internal Keyboard") { return true }
    let transport = stringValue(device, kIOHIDTransportKey) ?? ""
    return transport.caseInsensitiveCompare("SPI") == .orderedSame && product.localizedCaseInsensitiveContains("Keyboard")
}

private func isExternalMouse(_ device: IOHIDDevice) -> Bool {
    if boolValue(device, kIOHIDBuiltInKey) { return false }
    let product = stringValue(device, kIOHIDProductKey) ?? ""
    if product.localizedCaseInsensitiveContains("Internal Keyboard") { return false }
    if product.localizedCaseInsensitiveContains("Trackpad") { return false }
    if product.localizedCaseInsensitiveContains("Touchpad") { return false }
    if product.localizedCaseInsensitiveContains("Backlight") { return false }
    if isMouse(device) { return true }
    return product.localizedCaseInsensitiveContains("Mouse")
}

private func primaryUsage(_ device: IOHIDDevice) -> (page: Int, usage: Int)? {
    let page = intValue(device, kIOHIDPrimaryUsagePageKey) ?? intValue(device, kIOHIDDeviceUsagePageKey)
    let usage = intValue(device, kIOHIDPrimaryUsageKey) ?? intValue(device, kIOHIDDeviceUsageKey)
    guard let page, let usage else { return nil }
    return (page, usage)
}

private func isMouse(_ device: IOHIDDevice) -> Bool {
    // Primary usage is the per-interface truth. ConformsTo can be true for
    // both mouse and keyboard on a composite HID device, and returns false
    // for everything when IOHIDManagerOpen is not permitted.
    if let usage = primaryUsage(device), usage.page == 1, usage.usage == 2 { return true }
    if let usage = primaryUsage(device), usage.page == 1, usage.usage == 1 { return true }
    return IOHIDDeviceConformsTo(device, 1, 2)
}

private func isKeyboard(_ device: IOHIDDevice) -> Bool {
    if let usage = primaryUsage(device) {
        if usage.page == 1 && usage.usage == 6 { return true }
        return false
    }
    return IOHIDDeviceConformsTo(device, 1, 6)
}

private func miceFromHidutil() -> (mice: [MouseDevice], keyboardIDs: Set<String>) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
    process.arguments = ["list"]
    process.standardInput = FileHandle.nullDevice
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    do {
        try process.run()
    } catch {
        return ([], [])
    }
    var outData = Data()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        outData = stdout.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        _ = stderr.fileHandleForReading.readDataToEndOfFile()
        group.leave()
    }
    process.waitUntilExit()
    group.wait()
    let output = String(data: outData, encoding: .utf8) ?? ""
    return parseHidutilMice(output)
}

private func parseHidutilMice(_ listing: String) -> (mice: [MouseDevice], keyboardIDs: Set<String>) {
    let lines = listing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let header = lines.first(where: { $0.contains("VendorID") && $0.contains("Product") && $0.contains("Built-In") }),
          let userClassRange = header.range(of: "UserClass")
    else { return ([], []) }
    let beforeUserClass = header[..<userClassRange.lowerBound]
    // `Product` must not match `ProductID`. Search backwards from UserClass.
    guard let productRange = beforeUserClass.range(of: "Product", options: .backwards)
    else { return ([], []) }

    let productStart = header.distance(from: header.startIndex, to: productRange.lowerBound)
    let productEnd = header.distance(from: header.startIndex, to: userClassRange.lowerBound)
    var keyboardIDs: Set<String> = []
    var mice: [MouseDevice] = []

    for line in lines {
        guard line != header, line.count > productEnd else { continue }
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.count > 4,
              let vendor = parseHexOrDec(tokens[0]),
              let productID = parseHexOrDec(tokens[1]),
              parseHexOrDec(tokens[3]) == 1,
              parseHexOrDec(tokens[4]) == 6
        else { continue }
        keyboardIDs.insert("\(vendor):\(productID)")
    }

    for line in lines {
        guard line != header, line.count > productEnd else { continue }
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard tokens.count > 4,
              parseHexOrDec(tokens.last ?? "") == 0,
              parseHexOrDec(tokens[3]) == 1,
              let usage = parseHexOrDec(tokens[4]),
              usage == 1 || usage == 2,
              let vendor = parseHexOrDec(tokens[0]),
              let productID = parseHexOrDec(tokens[1])
        else { continue }

        let start = line.index(line.startIndex, offsetBy: productStart, limitedBy: line.endIndex) ?? line.endIndex
        let end = line.index(line.startIndex, offsetBy: productEnd, limitedBy: line.endIndex) ?? line.endIndex
        guard start < end else { continue }
        let product = String(line[start..<end]).trimmingCharacters(in: .whitespaces)
        guard !product.isEmpty, product != "(null)" else { continue }
        if product.localizedCaseInsensitiveContains("Trackpad") { continue }
        if product.localizedCaseInsensitiveContains("Touchpad") { continue }
        if product.localizedCaseInsensitiveContains("Internal Keyboard") { continue }
        if product.localizedCaseInsensitiveContains("Backlight") { continue }

        let mouse = MouseDevice(vendor: vendor, product: productID, name: product)
        guard isRealMouse(mouse, keyboardIDs: keyboardIDs) else { continue }
        if !mice.contains(where: { $0.id == mouse.id }) {
            mice.append(mouse)
        }
    }
    return (mice, keyboardIDs)
}

private func parseHexOrDec(_ raw: String) -> Int? {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    if trimmed.lowercased().hasPrefix("0x") {
        return Int(trimmed.dropFirst(2), radix: 16)
    }
    return Int(trimmed)
}

func intValue(_ device: IOHIDDevice, _ key: String) -> Int? {
    (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
}

func stringValue(_ device: IOHIDDevice, _ key: String) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
}

private func boolValue(_ device: IOHIDDevice, _ key: String) -> Bool {
    (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.boolValue ?? false
}
