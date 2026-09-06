import Darwin
import Foundation

struct SystemSample {
    var cpuFraction: Double
    var cpuReady: Bool
    var ramUsed: UInt64
    var ramTotal: UInt64
}

/// Host-wide CPU and RAM, sampled while the menu is open.
final class SystemStatsService {
    var onUpdate: ((SystemSample) -> Void)?

    private var timer: DispatchSourceTimer?
    private var previousIdle: UInt64 = 0
    private var previousTotal: UInt64 = 0
    private var havePreviousCPU = false
    private let queue = DispatchQueue(label: "naf.system-stats", qos: .utility)

    func start() {
        stop()
        havePreviousCPU = false
        publish()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.3, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.publish()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        havePreviousCPU = false
    }

    /// Two tick reads ~300ms apart so CPU percent is meaningful from the CLI.
    func sampleOnce(interval: TimeInterval = 0.3) -> SystemSample {
        havePreviousCPU = false
        _ = currentSample()
        Thread.sleep(forTimeInterval: interval)
        return currentSample()
    }

    private func publish() {
        onUpdate?(currentSample())
    }

    private func currentSample() -> SystemSample {
        let ram = memoryUsage()
        let cpu = cpuUsage()
        return SystemSample(
            cpuFraction: cpu.fraction,
            cpuReady: cpu.ready,
            ramUsed: ram.used,
            ramTotal: ram.total
        )
    }

    private func cpuUsage() -> (fraction: Double, ready: Bool) {
        guard let ticks = cpuTicks() else {
            return (0, havePreviousCPU)
        }
        defer {
            previousIdle = ticks.idle
            previousTotal = ticks.total
            havePreviousCPU = true
        }
        guard havePreviousCPU else { return (0, false) }

        let idleDelta = ticks.idle &- previousIdle
        let totalDelta = ticks.total &- previousTotal
        guard totalDelta > 0 else { return (0, true) }
        let busy = 1.0 - Double(idleDelta) / Double(totalDelta)
        return (min(max(busy, 0), 1), true)
    }

    private func cpuTicks() -> (idle: UInt64, total: UInt64)? {
        var processorCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        let status = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard status == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            let bytes = vm_size_t(Int(cpuInfoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), bytes)
        }

        var idle: UInt64 = 0
        var total: UInt64 = 0
        let values = UnsafeBufferPointer(start: cpuInfo, count: Int(cpuInfoCount))
        let stride = Int(CPU_STATE_MAX)
        for cpu in 0..<Int(processorCount) {
            let base = cpu * stride
            guard base + Int(CPU_STATE_IDLE) < values.count else { break }
            func tick(_ state: Int32) -> UInt64 {
                UInt64(UInt32(bitPattern: values[base + Int(state)]))
            }
            let user = tick(CPU_STATE_USER)
            let system = tick(CPU_STATE_SYSTEM)
            let nice = tick(CPU_STATE_NICE)
            let idleTicks = tick(CPU_STATE_IDLE)
            idle += idleTicks
            total += user + system + nice + idleTicks
        }
        return (idle, total)
    }

    private func memoryUsage() -> (used: UInt64, total: UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let status = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else {
            return (0, total)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let appPages = internalPages > purgeable ? internalPages - purgeable : 0
        let wired = UInt64(stats.wire_count)
        let compressed = UInt64(stats.compressor_page_count)
        let used = (appPages + wired + compressed) * pageSize
        return (min(used, total), total)
    }
}
