import Darwin
import Foundation

final class ProcessSampler {
    private var previous: [Int32: (user: UInt64, system: UInt64, at: TimeInterval)] = [:]

    func reset() {
        previous = [:]
    }

    func sample(limit: Int = 3) -> [ProcessUsage] {
        let pids = listPIDs()
        let now = ProcessInfo.processInfo.systemUptime
        var current: [Int32: (user: UInt64, system: UInt64, ram: UInt64, name: String)] = [:]
        current.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.stride)
            let written = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
            guard written == size else { continue }
            var buffer = [CChar](repeating: 0, count: 256)
            guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            let name = String(cString: buffer)
            guard !name.isEmpty else { continue }
            current[pid] = (info.pti_total_user, info.pti_total_system, info.pti_resident_size, name)
        }

        var ranked: [ProcessUsage] = []
        ranked.reserveCapacity(current.count)
        for (pid, snapshot) in current {
            var cpu = 0.0
            if let last = previous[pid] {
                let elapsed = now - last.at
                if elapsed > 0.05 {
                    let user = snapshot.user &- last.user
                    let system = snapshot.system &- last.system
                    let seconds = Double(user + system) / 1_000_000_000
                    cpu = max(0, (seconds / elapsed) * 100)
                }
            }
            ranked.append(
                ProcessUsage(pid: pid, name: snapshot.name, cpuPercent: cpu, ramBytes: snapshot.ram)
            )
        }

        previous = current.mapValues { (user: $0.user, system: $0.system, at: now) }

        ranked.sort {
            if abs($0.cpuPercent - $1.cpuPercent) > 0.05 {
                return $0.cpuPercent > $1.cpuPercent
            }
            return $0.ramBytes > $1.ramBytes
        }
        if ranked.prefix(limit).allSatisfy({ $0.cpuPercent < 0.05 }) {
            ranked.sort { $0.ramBytes > $1.ramBytes }
        }
        return Array(ranked.prefix(limit))
    }

    private func listPIDs() -> [pid_t] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        let count = bytes / Int32(MemoryLayout<pid_t>.stride)
        var pids = [pid_t](repeating: 0, count: Int(count))
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bytes)
        guard written > 0 else { return [] }
        let filled = Int(written) / MemoryLayout<pid_t>.stride
        return Array(pids.prefix(filled)).filter { $0 > 0 }
    }
}
