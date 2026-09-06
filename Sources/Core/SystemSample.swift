import Foundation

struct AccessoryBattery: Equatable, Identifiable {
    var name: String
    var percent: Int

    var id: String { name }
}

struct VolumeSample: Equatable, Identifiable {
    var name: String
    var path: String
    var used: UInt64
    var total: UInt64
    var isBoot: Bool

    var id: String { path }

    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(used) / Double(total), 0), 1)
    }

    var free: UInt64 { total > used ? total - used : 0 }
}

struct BatterySample: Equatable {
    var percent: Double
    var isCharging: Bool
    var isPluggedIn: Bool
    var isFull: Bool
    var minutesToEmpty: Int?
    var minutesToFull: Int?
    var health: String?
    var cycleCount: Int?
}

struct NetworkSample: Equatable {
    var connected: Bool
    var kind: String
    var interfaceName: String?
    var ssid: String?
    var ipAddress: String?
    var bytesInPerSecond: UInt64
    var bytesOutPerSecond: UInt64
    var ratesReady: Bool
}

struct ProcessUsage: Equatable, Identifiable {
    var pid: Int32
    var name: String
    var cpuPercent: Double
    var ramBytes: UInt64

    var id: Int32 { pid }
}

enum MemoryPressure: Int, Equatable {
    case normal = 0
    case warning = 1
    case urgent = 2
    case critical = 3

    var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Warning"
        case .urgent: "Urgent"
        case .critical: "Critical"
        }
    }
}

struct SystemSample: Equatable {
    var cpuFraction: Double = 0
    var cpuReady: Bool = false
    var cpuHistory: [Double] = []

    var ramUsed: UInt64 = 0
    var ramTotal: UInt64 = 0
    var ramCompressed: UInt64 = 0
    var ramWired: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var memoryPressure: MemoryPressure = .normal

    var thermal: ProcessInfo.ThermalState = .nominal
    var uptimeSeconds: TimeInterval = 0

    var battery: BatterySample?
    var accessories: [AccessoryBattery] = []

    var bootVolume: VolumeSample?
    var volumes: [VolumeSample] = []

    var network: NetworkSample = NetworkSample(
        connected: false,
        kind: "Offline",
        interfaceName: nil,
        ssid: nil,
        ipAddress: nil,
        bytesInPerSecond: 0,
        bytesOutPerSecond: 0,
        ratesReady: false
    )

    var topProcesses: [ProcessUsage] = []
}

enum StatsFormat {
    static func gigabytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 10 {
            return String(format: "%.0f GB", gb)
        }
        return String(format: "%.1f GB", gb)
    }

    static func bytes(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 {
            return gigabytes(bytes)
        }
        let mb = Double(bytes) / 1_048_576
        if mb >= 10 {
            return String(format: "%.0f MB", mb)
        }
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(bytes) / 1_024
        if kb >= 1 {
            return String(format: "%.0f KB", kb)
        }
        return "\(bytes) B"
    }

    static func rate(_ bytesPerSecond: UInt64, compact: Bool) -> String {
        let value: String
        if bytesPerSecond >= 1_048_576 {
            let mb = Double(bytesPerSecond) / 1_048_576
            value = mb >= 10 ? String(format: "%.0fM", mb) : String(format: "%.1fM", mb)
        } else if bytesPerSecond >= 1_024 {
            value = String(format: "%.0fK", Double(bytesPerSecond) / 1_024)
        } else {
            value = "0K"
        }
        return compact ? value : "\(value)B/s"
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(total)s"
    }

    static func durationMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            if rest == 0 {
                return hours == 1 ? "1h" : "\(hours)h"
            }
            return "\(hours)h \(rest)m"
        }
        return "\(minutes)m"
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}
