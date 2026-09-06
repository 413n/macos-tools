import Foundation
import IOKit
import IOKit.hid
import IOKit.ps

enum BatteryStats {
    static func battery() -> BatterySample? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any]
            else { continue }
            let type = description[kIOPSTypeKey] as? String
            guard type == kIOPSInternalBatteryType else { continue }

            let current = double(description[kIOPSCurrentCapacityKey])
            let maxCapacity = double(description[kIOPSMaxCapacityKey])
            guard maxCapacity > 0 else { continue }
            let percent = min(Swift.max(current / maxCapacity, 0), 1)
            let charging = bool(description[kIOPSIsChargingKey])
            let state = description[kIOPSPowerSourceStateKey] as? String
            let plugged = state == kIOPSACPowerValue
            let toEmpty = minutes(description[kIOPSTimeToEmptyKey])
            let toFull = minutes(description[kIOPSTimeToFullChargeKey])
            let registry = smartBattery()
            return BatterySample(
                percent: percent,
                isCharging: charging,
                isPluggedIn: plugged,
                isFull: percent >= 0.995 && plugged && !charging,
                minutesToEmpty: charging ? nil : toEmpty,
                minutesToFull: charging ? toFull : nil,
                health: registry.health ?? (description["BatteryHealth"] as? String),
                cycleCount: registry.cycleCount
            )
        }
        return nil
    }

    static func accessories() -> [AccessoryBattery] {
        var seen = Set<String>()
        var list: [AccessoryBattery] = []
        for item in hidAccessories() {
            let key = item.name.lowercased()
            guard seen.insert(key).inserted else { continue }
            list.append(item)
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func hidAccessories() -> [AccessoryBattery] {
        var results: [AccessoryBattery] = []
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOHIDDevice")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let percent = intProperty(service, "BatteryPercent"),
                  percent > 0, percent <= 100
            else { continue }
            let product = stringProperty(service, kIOHIDProductKey) ?? stringProperty(service, "Product") ?? "Accessory"
            if product.localizedCaseInsensitiveContains("Battery") { continue }
            if product.localizedCaseInsensitiveContains("Backlight") { continue }
            results.append(AccessoryBattery(name: product, percent: percent))
        }
        return results
    }

    private static func smartBattery() -> (cycleCount: Int?, health: String?) {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        return (
            intProperty(service, "CycleCount"),
            stringProperty(service, "BatteryHealth")
        )
    }

    private static func double(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? 0
    }

    private static func bool(_ value: Any?) -> Bool {
        (value as? NSNumber)?.boolValue ?? false
    }

    private static func minutes(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let minutes = number.intValue
        guard minutes > 0, minutes < 60 * 24 * 7 else { return nil }
        return minutes
    }

    private static func intProperty(_ service: io_service_t, _ key: String) -> Int? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }
        return (unmanaged.takeRetainedValue() as? NSNumber)?.intValue
    }

    private static func stringProperty(_ service: io_service_t, _ key: String) -> String? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }
        return unmanaged.takeRetainedValue() as? String
    }
}
