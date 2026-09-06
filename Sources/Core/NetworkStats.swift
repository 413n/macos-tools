import CoreWLAN
import Foundation
import Network
import SystemConfiguration

final class NetworkSampler {
    private var monitor: NWPathMonitor?
    private let queue: DispatchQueue
    private var path: NWPath?
    private var previous: (name: String, incoming: UInt64, outgoing: UInt64, at: TimeInterval)?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.path = path
        }
        monitor.start(queue: queue)
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        path = nil
        previous = nil
    }

    func resetRates() {
        previous = nil
    }

    func sample() -> NetworkSample {
        let counters = interfaceCounters()
        let ips = interfaceAddresses()
        let chosen = chosenInterface(counters: counters, ips: ips)
        let now = ProcessInfo.processInfo.systemUptime
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        var ratesReady = false

        if let chosen, let pair = counters[chosen.name] {
            if let previous, previous.name == chosen.name {
                let elapsed = now - previous.at
                if elapsed > 0.05 {
                    bytesIn = delta(pair.incoming, previous.incoming, elapsed: elapsed)
                    bytesOut = delta(pair.outgoing, previous.outgoing, elapsed: elapsed)
                    ratesReady = true
                }
            }
            previous = (chosen.name, pair.incoming, pair.outgoing, now)
        } else {
            previous = nil
        }

        let connected = chosen != nil
        let ssid = chosen?.kind == "Wi-Fi" ? CWWiFiClient.shared().interface()?.ssid() : nil
        return NetworkSample(
            connected: connected,
            kind: chosen?.kind ?? "Offline",
            interfaceName: chosen?.name,
            ssid: ssid,
            ipAddress: chosen.flatMap { ips[$0.name] },
            bytesInPerSecond: bytesIn,
            bytesOutPerSecond: bytesOut,
            ratesReady: ratesReady
        )
    }

    private func chosenInterface(
        counters: [String: (incoming: UInt64, outgoing: UInt64)],
        ips: [String: String]
    ) -> (name: String, kind: String)? {
        if let path, path.status == .satisfied {
            let interfaces = path.availableInterfaces.filter { $0.type != .loopback && $0.type != .other }
            let preferred = interfaces.first { $0.type == .wifi }
                ?? interfaces.first { $0.type == .wiredEthernet }
                ?? interfaces.first
            if let preferred {
                return (preferred.name, kindLabel(preferred.type))
            }
            if path.usesInterfaceType(.wifi) { return first(kind: "Wi-Fi", counters: counters, ips: ips) }
            if path.usesInterfaceType(.wiredEthernet) { return first(kind: "Ethernet", counters: counters, ips: ips) }
        } else if path?.status == .unsatisfied {
            return nil
        }
        return first(kind: nil, counters: counters, ips: ips)
    }

    private func first(
        kind: String?,
        counters: [String: (incoming: UInt64, outgoing: UInt64)],
        ips: [String: String]
    ) -> (name: String, kind: String)? {
        let names = ips.keys.sorted() + counters.keys.filter { ips[$0] == nil }.sorted()
        for name in names where !isIgnored(name) {
            let inferred = inferredKind(name)
            if let kind, inferred != kind, kind != "Network" { continue }
            return (name, kind ?? inferred)
        }
        return nil
    }

    private func kindLabel(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: "Wi-Fi"
        case .wiredEthernet: "Ethernet"
        case .cellular: "Cellular"
        default: "Network"
        }
    }

    private func inferredKind(_ name: String) -> String {
        if name.hasPrefix("bridge") { return "Ethernet" }
        return "Network"
    }

    private func isIgnored(_ name: String) -> Bool {
        name == "lo0"
            || name.hasPrefix("awdl")
            || name.hasPrefix("llw")
            || name.hasPrefix("utun")
            || name.hasPrefix("anpi")
            || name.hasPrefix("ap")
            || name.hasPrefix("gif")
            || name.hasPrefix("stf")
            || name.hasPrefix("vlan")
    }

    private func delta(_ now: UInt64, _ then: UInt64, elapsed: TimeInterval) -> UInt64 {
        let raw = now >= then ? now - then : now
        return UInt64((Double(raw) / elapsed).rounded())
    }

    private func interfaceCounters() -> [String: (incoming: UInt64, outgoing: UInt64)] {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return [:] }
        defer { freeifaddrs(first) }

        var result: [String: (incoming: UInt64, outgoing: UInt64)] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = pointer {
            defer { pointer = ifa.pointee.ifa_next }
            let name = String(cString: ifa.pointee.ifa_name)
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            guard let data = ifa.pointee.ifa_data else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            result[name] = (UInt64(stats.ifi_ibytes), UInt64(stats.ifi_obytes))
        }
        return result
    }

    private func interfaceAddresses() -> [String: String] {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return [:] }
        defer { freeifaddrs(first) }

        var result: [String: String] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = pointer {
            defer { pointer = ifa.pointee.ifa_next }
            let name = String(cString: ifa.pointee.ifa_name)
            guard !isIgnored(name), result[name] == nil else { continue }
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let size = socklen_t(MemoryLayout<sockaddr_in>.size)
            guard getnameinfo(addr, size, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
                continue
            }
            let ip = String(cString: host)
            if !ip.isEmpty { result[name] = ip }
        }
        return result
    }
}
