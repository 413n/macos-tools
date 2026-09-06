import Darwin
import Foundation

/// Host-wide stats. Sampled while the panel is open, and while menu-bar glances are on.
final class SystemStatsService {
    var onUpdate: ((SystemSample) -> Void)?

    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval = 1
    private var includeDetail = true
    private var previousIdle: UInt64 = 0
    private var previousTotal: UInt64 = 0
    private var havePreviousCPU = false
    private var cpuHistory: [Double] = []
    private let historyLimit = 30
    private let queue = DispatchQueue(label: "naf.system-stats", qos: .utility)
    private lazy var network = NetworkSampler(queue: queue)
    private let processes = ProcessSampler()
    private let stateLock = NSLock()
    private var generation = 0

    func start(interval: TimeInterval = 1.0, detail: Bool = true) {
        let id = nextGeneration()
        queue.async { [weak self] in
            guard let self, self.isCurrent(id) else { return }
            self.includeDetail = detail
            if self.timer != nil, abs(self.interval - interval) < 0.01 {
                return
            }
            self.interval = interval
            self.stopTimer(reset: false)
            self.network.start()
            self.publish()
            guard self.isCurrent(id) else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + interval, repeating: interval)
            timer.setEventHandler { [weak self] in
                guard let self, self.isCurrent(id) else { return }
                self.publish()
            }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        _ = nextGeneration()
        queue.sync {
            stopTimer(reset: true)
            network.stop()
            processes.reset()
        }
    }

    private func nextGeneration() -> Int {
        stateLock.lock()
        generation += 1
        let value = generation
        stateLock.unlock()
        return value
    }

    private func isCurrent(_ id: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation == id
    }

    /// Two tick reads ~300ms apart so CPU percent is meaningful from the CLI.
    func sampleOnce(interval: TimeInterval = 0.3) -> SystemSample {
        queue.sync {
            havePreviousCPU = false
            cpuHistory = []
            processes.reset()
            network.resetRates()
            network.start()
            _ = makeSample(detail: true)
        }
        Thread.sleep(forTimeInterval: interval)
        return queue.sync {
            let sample = makeSample(detail: true)
            network.stop()
            return sample
        }
    }

    private func stopTimer(reset: Bool) {
        timer?.cancel()
        timer = nil
        if reset {
            havePreviousCPU = false
            cpuHistory = []
        }
    }

    private func publish() {
        onUpdate?(makeSample(detail: includeDetail))
    }

    private func makeSample(detail: Bool) -> SystemSample {
        autoreleasepool {
            makeSampleUnpooled(detail: detail)
        }
    }

    private func makeSampleUnpooled(detail: Bool) -> SystemSample {
        let ram = memoryUsage()
        let cpu = cpuUsage()
        if cpu.ready {
            cpuHistory.append(cpu.fraction)
            if cpuHistory.count > historyLimit {
                cpuHistory.removeFirst(cpuHistory.count - historyLimit)
            }
        }

        var sample = SystemSample()
        sample.cpuFraction = cpu.fraction
        sample.cpuReady = cpu.ready
        sample.cpuHistory = cpuHistory
        sample.ramUsed = ram.used
        sample.ramTotal = ram.total
        sample.ramCompressed = ram.compressed
        sample.ramWired = ram.wired
        sample.swapUsed = ram.swapUsed
        sample.swapTotal = ram.swapTotal
        sample.memoryPressure = memoryPressure()
        sample.thermal = ProcessInfo.processInfo.thermalState
        sample.uptimeSeconds = ProcessInfo.processInfo.systemUptime
        sample.battery = BatteryStats.battery()
        sample.network = network.sample()
        sample.bootVolume = DiskStats.bootVolume()
        if detail {
            sample.accessories = BatteryStats.accessories()
            sample.volumes = DiskStats.volumes()
            sample.topProcesses = processes.sample()
        }
        return sample
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

    private func memoryUsage() -> (
        used: UInt64,
        total: UInt64,
        compressed: UInt64,
        wired: UInt64,
        swapUsed: UInt64,
        swapTotal: UInt64
    ) {
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

        var used: UInt64 = 0
        var compressed: UInt64 = 0
        var wired: UInt64 = 0
        if status == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            let appPages = internalPages > purgeable ? internalPages - purgeable : 0
            wired = UInt64(stats.wire_count) * pageSize
            compressed = UInt64(stats.compressor_page_count) * pageSize
            used = min((appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize, total)
        }

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapUsed: UInt64 = 0
        var swapTotal: UInt64 = 0
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            swapUsed = UInt64(swap.xsu_used)
            swapTotal = UInt64(swap.xsu_total)
        }

        return (used, total, compressed, wired, swapUsed, swapTotal)
    }

    private func memoryPressure() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .normal
        }
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }
}
