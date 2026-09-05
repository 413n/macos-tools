import AppKit
import CoreGraphics
import Foundation

/// Reverses discrete mouse-wheel scrolling while leaving the trackpad alone.
///
/// macOS has one system-wide "Natural Scrolling" switch. This tap flips only
/// events that look like a mouse wheel (and Magic Mouse, when an external
/// mouse is connected) so the trackpad can stay natural.
final class ScrollReverseService {
    static let shared = ScrollReverseService()

    private let stateLock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false

    private init() {
        ScrollReverseService.sharedReference = self
    }

    var isActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard isRunning, let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    @discardableResult
    func start() -> Bool {
        if !Thread.isMainThread {
            return DispatchQueue.main.sync { self.start() }
        }

        stateLock.lock()
        let already = isRunning
        let existing = eventTap
        stateLock.unlock()
        if already {
            reEnableIfNeeded()
            return isActive
        }
        if existing != nil {
            stop()
        }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollTapCallback,
            userInfo: nil
        ) else {
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        stateLock.lock()
        eventTap = tap
        runLoopSource = source
        isRunning = true
        stateLock.unlock()
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func stop() {
        if !Thread.isMainThread {
            DispatchQueue.main.sync { self.stop() }
            return
        }

        stateLock.lock()
        let tap = eventTap
        let source = runLoopSource
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        stateLock.unlock()

        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
    }

    func reEnableIfNeeded() {
        stateLock.lock()
        let tap = eventTap
        let running = isRunning
        stateLock.unlock()
        guard running else { return }
        guard let tap else {
            stop()
            _ = start()
            return
        }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        if !CGEvent.tapIsEnabled(tap: tap) {
            stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                _ = self?.start()
            }
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reEnableIfNeeded()
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else {
            return Unmanaged.passUnretained(event)
        }
        if isMouseScroll(event) && shouldReverseCurrentMouse() {
            invert(event, axis: 1)
            invert(event, axis: 2)
            invertIOHIDScroll(event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func shouldReverseCurrentMouse() -> Bool {
        let enabled = DeviceMonitor.reverseEnabledIDs
        guard !enabled.isEmpty else { return false }
        if let id = DeviceMonitor.activeMouseID(),
           DeviceMonitor.connectedMouseIDs.contains(id) {
            return enabled.contains(id)
        }
        return true
    }

    private func isMouseScroll(_ event: CGEvent) -> Bool {
        let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        if scrollPhase != 0 || momentumPhase != 0 {
            return false
        }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        if !continuous {
            return true
        }
        return DeviceMonitor.hasExternalMouseCached
    }

    private func invert(_ event: CGEvent, axis: Int) {
        let deltaField: CGEventField = axis == 1 ? .scrollWheelEventDeltaAxis1 : .scrollWheelEventDeltaAxis2
        let fixedField: CGEventField = axis == 1 ? .scrollWheelEventFixedPtDeltaAxis1 : .scrollWheelEventFixedPtDeltaAxis2
        let pointField: CGEventField = axis == 1 ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventPointDeltaAxis2
        let delta = event.getIntegerValueField(deltaField)
        let fixed = event.getDoubleValueField(fixedField)
        let point = event.getIntegerValueField(pointField)
        event.setIntegerValueField(deltaField, value: -delta)
        event.setDoubleValueField(fixedField, value: -fixed)
        event.setIntegerValueField(pointField, value: -point)
    }

    private func invertIOHIDScroll(_ event: CGEvent) {
        guard let unmanaged = CGEventCopyIOHIDEvent(event) else { return }
        let hidEvent = unmanaged.takeRetainedValue()
        IOHIDEventSetFloatValue(hidEvent, kIOHIDEventFieldScrollY, -IOHIDEventGetFloatValue(hidEvent, kIOHIDEventFieldScrollY))
        IOHIDEventSetFloatValue(hidEvent, kIOHIDEventFieldScrollX, -IOHIDEventGetFloatValue(hidEvent, kIOHIDEventFieldScrollX))
    }

    fileprivate static weak var sharedReference: ScrollReverseService?
}

private func scrollTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let service = ScrollReverseService.sharedReference {
        return service.handle(type: type, event: event)
    }
    return Unmanaged.passUnretained(event)
}

private let kIOHIDEventFieldScrollX: UInt32 = (6 << 16)
private let kIOHIDEventFieldScrollY: UInt32 = (6 << 16) | 1

@_silgen_name("CGEventCopyIOHIDEvent")
private func CGEventCopyIOHIDEvent(_ event: CGEvent) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: UInt32) -> Double

@_silgen_name("IOHIDEventSetFloatValue")
private func IOHIDEventSetFloatValue(_ event: CFTypeRef, _ field: UInt32, _ value: Double)
