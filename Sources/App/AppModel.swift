import AppKit
import Darwin
import Foundation
import ServiceManagement
import SwiftUI

final class AppModel: ObservableObject {
    @Published var keyboardLocked = false
    @Published var keyboardStatus = "Checking built-in keyboard…"
    @Published var keyboardError: String?
    @Published var autoUnlockMinutes: Int {
        didSet { ToolStateStore.shared.update { $0.autoUnlockMinutes = autoUnlockMinutes } }
    }
    @Published var dimKeyboardWhenLocked: Bool {
        didSet { ToolStateStore.shared.update { $0.dimKeyboardWhenLocked = dimKeyboardWhenLocked } }
    }

    @Published var scrollReverseByDevice: [String: Bool] = [:]

    @Published var scrollReverseEnabled: Bool = false
    @Published var mouseConnected = false
    @Published var mouseNames: [String] = []
    @Published var mice: [MouseDevice] = []
    @Published var accessibilityTrusted = false
    @Published var scrollStatus = "Mouse scroll is unchanged."

    @Published var lidSleepDisabled = false
    @Published var lidStatus = "Checking lid sleep…"
    @Published var lidError: String?
    @Published var lidBusy = false

    @Published var awakeActive = false
    @Published var awakeStatus = "Mac can sleep as usual"
    @Published var awakeError: String?
    @Published var awakeRemainingSeconds: Int?
    @Published var awakeMinutes: Int {
        didSet {
            ToolStateStore.shared.update { $0.awakeMinutes = awakeMinutes }
            if suppressAwakeRestart { return }
            if awakeActive {
                startAwake()
            }
        }
    }

    @Published var loginItemNotice: String?
    @Published var statusCheckNotice: String?
    @Published var statusCheckBusy = false
    @Published var updateCheckNotice: String?
    @Published var updateCheckBusy = false
    @Published var newerVersion: String?
    @Published var keyboardBusy = false
    @Published var stats = SystemSample()
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin()
        }
    }
    @Published var menuBarDisplay: MenuBarDisplay {
        didSet { UserDefaults.standard.set(menuBarDisplay.rawValue, forKey: Keys.menuBarDisplay) }
    }
    @Published var menuBarStats: MenuBarStats {
        didSet {
            UserDefaults.standard.set(menuBarStats.rawValue, forKey: Keys.menuBarStats)
            syncStatsSampling()
        }
    }
    @Published var visibleHomeTools: [HomeTool]
    @Published var hiddenHomeTools: [HomeTool]
    @Published var homeTab: HomeTab {
        didSet {
            guard homeTab != oldValue else { return }
            UserDefaults.standard.set(homeTab.rawValue, forKey: Keys.homeTab)
        }
    }

    let timeoutChoices = [0, 5, 10, 15, 30, 60]
    let awakeDurationChoices = [0, 5, 10, 15, 30, 60, 120, 300]

    private let tools = ToolRegistry.shared
    private let keyboardQueue = DispatchQueue(label: "naf.tools.keyboard", qos: .userInitiated)
    private var keyboardEpoch = 0
    private let lidQueue = DispatchQueue(label: "naf.tools.lid", qos: .userInitiated)
    private var lidEpoch = 0
    private var awakeTick: Timer?
    private let devices = DeviceMonitor()
    private let statsService = SystemStatsService()
    private var wakeObserver: NSObjectProtocol?
    private var accessibilityTimer: Timer?
    private var updateCheckTask: URLSessionDataTask?
    private var updateCheckEpoch = 0
    private var latestReleaseURL: URL?
    private var stateObserver: NSObjectProtocol?
    private var suppressAwakeRestart = false

    private var panelWantsStats = false

    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let menuBarDisplay = "menuBarDisplay"
        static let menuBarStats = "menuBarStats"
        static let visibleHomeTools = "visibleHomeTools"
        static let hiddenHomeTools = "hiddenHomeTools"
        static let homeTab = "homeTab"
        static let didLaunch = "didCompleteFirstLaunch"
    }

    init() {
        let defaults = UserDefaults.standard
        let state = ToolStateStore.shared.current
        autoUnlockMinutes = state.autoUnlockMinutes
        dimKeyboardWhenLocked = state.dimKeyboardWhenLocked
        scrollReverseEnabled = state.scrollReverseEnabled
        scrollReverseByDevice = state.scrollReverseByDevice
        lidSleepDisabled = state.lidSleepDisabled
        let storedAwakeMinutes = state.awakeMinutes
        awakeMinutes = [0, 5, 10, 15, 30, 60, 120, 300].contains(storedAwakeMinutes) ? storedAwakeMinutes : 0
        awakeActive = state.awakeEnabled
        keyboardLocked = state.keyboardLocked && Self.isCurrentBoot(state.keyboardLockBoot)
        if defaults.object(forKey: Keys.launchAtLogin) == nil {
            launchAtLogin = true
            defaults.set(true, forKey: Keys.launchAtLogin)
        } else {
            launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        }
        if let raw = defaults.string(forKey: Keys.menuBarDisplay),
           let stored = MenuBarDisplay(rawValue: raw) {
            menuBarDisplay = stored
        } else {
            menuBarDisplay = .logoOnly
        }
        if let raw = defaults.string(forKey: Keys.menuBarStats),
           let stored = MenuBarStats(rawValue: raw) {
            menuBarStats = stored
        } else {
            menuBarStats = .off
        }
        let layout = Self.loadHomeLayout(defaults: defaults)
        visibleHomeTools = layout.visible
        hiddenHomeTools = layout.hidden
        if let raw = defaults.string(forKey: Keys.homeTab),
           let stored = HomeTab(rawValue: raw) {
            homeTab = stored
        } else {
            homeTab = .tools
        }
    }

    var tabVisibleHomeTools: [HomeTool] {
        visibleHomeTools.filter { $0.tab == homeTab }
    }

    var tabHiddenHomeTools: [HomeTool] {
        hiddenHomeTools.filter { $0.tab == homeTab }
    }

    func hideHomeTool(_ tool: HomeTool) {
        guard let index = visibleHomeTools.firstIndex(of: tool) else { return }
        visibleHomeTools.remove(at: index)
        if !hiddenHomeTools.contains(tool) {
            hiddenHomeTools.append(tool)
        }
        persistHomeLayout()
    }

    func showHomeTool(_ tool: HomeTool) {
        guard let index = hiddenHomeTools.firstIndex(of: tool) else { return }
        hiddenHomeTools.remove(at: index)
        if !visibleHomeTools.contains(tool) {
            visibleHomeTools.append(tool)
        }
        persistHomeLayout()
    }

    func moveVisibleHomeTool(_ tool: HomeTool, to destination: Int) {
        let tab = tool.tab
        var subset = visibleHomeTools.filter { $0.tab == tab }
        guard let from = subset.firstIndex(of: tool) else { return }
        let clamped = min(max(destination, 0), subset.count - 1)
        guard from != clamped else { return }
        subset.move(
            fromOffsets: IndexSet(integer: from),
            toOffset: clamped > from ? clamped + 1 : clamped
        )
        var next: [HomeTool] = []
        var subsetIndex = 0
        for item in visibleHomeTools {
            if item.tab == tab {
                next.append(subset[subsetIndex])
                subsetIndex += 1
            } else {
                next.append(item)
            }
        }
        visibleHomeTools = next
        persistHomeLayout()
    }

    private func persistHomeLayout() {
        UserDefaults.standard.set(visibleHomeTools.map(\.rawValue), forKey: Keys.visibleHomeTools)
        UserDefaults.standard.set(hiddenHomeTools.map(\.rawValue), forKey: Keys.hiddenHomeTools)
    }

    private static func loadHomeLayout(defaults: UserDefaults) -> (visible: [HomeTool], hidden: [HomeTool]) {
        let storedVisible = defaults.stringArray(forKey: Keys.visibleHomeTools)
        let storedHidden = defaults.stringArray(forKey: Keys.hiddenHomeTools)
        guard storedVisible != nil || storedHidden != nil else {
            return (Array(HomeTool.allCases), [])
        }
        var visible = uniqued((storedVisible ?? []).compactMap(HomeTool.init(rawValue:)))
        var hidden = uniqued((storedHidden ?? []).compactMap(HomeTool.init(rawValue:)))
        hidden.removeAll(where: visible.contains)
        let known = Set(visible).union(hidden)
        for tool in HomeTool.allCases where !known.contains(tool) {
            visible.append(tool)
        }
        if visible.isEmpty, hidden.isEmpty {
            return (Array(HomeTool.allCases), [])
        }
        return (visible, hidden)
    }

    private static func uniqued(_ tools: [HomeTool]) -> [HomeTool] {
        var seen = Set<HomeTool>()
        return tools.filter { seen.insert($0).inserted }
    }

    var activeMenuBarTools: [ToolID] {
        var tools: [ToolID] = []
        if keyboardLocked { tools.append(.keyboard) }
        if scrollReverseEnabled { tools.append(.scroll) }
        if lidSleepDisabled { tools.append(.lid) }
        if awakeActive { tools.append(.awake) }
        return tools
    }

    var mouseSummary: String {
        if mouseNames.isEmpty { return "No mouse connected" }
        if mouseNames.count == 1 { return mouseNames[0] }
        return "\(mouseNames.count) mice connected"
    }

    var cpuPercentLabel: String {
        stats.cpuReady ? StatsFormat.percent(stats.cpuFraction) : "…"
    }

    var ramShortLabel: String {
        guard stats.ramTotal > 0 else { return "…" }
        return "\(StatsFormat.gigabytes(stats.ramUsed)) / \(StatsFormat.gigabytes(stats.ramTotal))"
    }

    var ramFraction: Double {
        guard stats.ramTotal > 0 else { return 0 }
        return min(max(Double(stats.ramUsed) / Double(stats.ramTotal), 0), 1)
    }

    var cpuUsageLevel: UsageLevel {
        stats.cpuReady ? UsageLevel(fraction: stats.cpuFraction) : .normal
    }

    var ramUsageLevel: UsageLevel {
        stats.ramTotal > 0 ? UsageLevel(fraction: ramFraction) : .normal
    }

    var memoryPressureLevel: UsageLevel {
        switch stats.memoryPressure {
        case .normal: .normal
        case .warning: .warning
        case .urgent, .critical: .critical
        }
    }

    var thermalLevel: UsageLevel {
        switch stats.thermal {
        case .nominal: .normal
        case .fair: .warning
        case .serious, .critical: .critical
        @unknown default: .normal
        }
    }

    var batteryPercentLabel: String {
        guard let battery = stats.battery else { return "—" }
        return StatsFormat.percent(battery.percent)
    }

    var batteryStatusLabel: String {
        guard let battery = stats.battery else { return "No battery" }
        if battery.isFull { return "Full" }
        if battery.isCharging {
            if let minutes = battery.minutesToFull {
                return "\(StatsFormat.durationMinutes(minutes)) to full"
            }
            return "Charging"
        }
        if let minutes = battery.minutesToEmpty {
            return "\(StatsFormat.durationMinutes(minutes)) left"
        }
        return battery.isPluggedIn ? "Plugged in" : "On battery"
    }

    var batteryUsageLevel: UsageLevel {
        guard let battery = stats.battery, !battery.isCharging, !battery.isFull else { return .normal }
        return .remaining(battery.percent)
    }

    var networkPrimaryLabel: String {
        if !stats.network.connected { return "Offline" }
        if stats.network.ratesReady {
            return "\(StatsFormat.rate(stats.network.bytesInPerSecond, compact: true))↓ \(StatsFormat.rate(stats.network.bytesOutPerSecond, compact: true))↑"
        }
        return stats.network.ssid ?? stats.network.kind
    }

    var networkSecondaryLabel: String {
        if !stats.network.connected { return "No connection" }
        if stats.network.ratesReady {
            return stats.network.ssid ?? stats.network.ipAddress ?? stats.network.kind
        }
        return stats.network.ipAddress ?? stats.network.kind
    }

    var diskFreeLabel: String {
        guard let volume = stats.bootVolume else { return "…" }
        return StatsFormat.gigabytes(volume.free)
    }

    var diskUsedLabel: String {
        guard let volume = stats.bootVolume else { return "…" }
        return StatsFormat.percent(volume.usedFraction)
    }

    var diskUsageLevel: UsageLevel {
        guard let volume = stats.bootVolume else { return .normal }
        return UsageLevel(fraction: volume.usedFraction)
    }

    var menuBarStatsText: String? {
        switch menuBarStats {
        case .off:
            return nil
        case .cpu:
            return stats.cpuReady ? StatsFormat.percent(stats.cpuFraction) : "…"
        case .battery:
            return stats.battery.map { StatsFormat.percent($0.percent) } ?? "—"
        case .network:
            if !stats.network.connected { return "Offline" }
            guard stats.network.ratesReady else { return "…" }
            return "\(StatsFormat.rate(stats.network.bytesInPerSecond, compact: true))↓ \(StatsFormat.rate(stats.network.bytesOutPerSecond, compact: true))↑"
        }
    }

    var appVersion: String {
        UpdateCheckService.currentVersion
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        StatsFormat.gigabytes(bytes)
    }

    func start() {
        refreshAccessibility()
        tools.keyboard.onTimerExpired = { [weak self] in
            DispatchQueue.main.async {
                self?.refreshKeyboardStatus()
            }
        }
        devices.onChange = { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.mice = snapshot.mice
                self?.mouseConnected = snapshot.hasExternalMouse
                self?.mouseNames = snapshot.mouseNames
                self?.seedMouseDefaults()
                self?.refreshScrollReverseState()
                if self?.keyboardBusy != true {
                    self?.restoreKeyboardIfNeeded()
                }
            }
        }
        devices.start()
        restorePersistedTools()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }

        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshAccessibility()
        }

        stateObserver = DistributedNotificationCenter.default().addObserver(
            forName: NAFPaths.stateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if (notification.object as? String) == "\(getpid())" { return }
            self?.handleExternalStateChange()
        }

        if !UserDefaults.standard.bool(forKey: Keys.didLaunch) {
            UserDefaults.standard.set(true, forKey: Keys.didLaunch)
            applyLaunchAtLogin()
        } else if launchAtLogin {
            applyLaunchAtLogin()
        }
        syncStatsSampling()
    }

    func stop() {
        accessibilityTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let stateObserver {
            DistributedNotificationCenter.default().removeObserver(stateObserver)
        }
        statsService.stop()
        updateCheckEpoch += 1
        updateCheckTask?.cancel()
        updateCheckTask = nil
        stopAwakeTick()
        // Leave keyboard mapping, lid sleep, caffeinate, and the scroll helper
        // running so CLI and a quit of the menu-bar app stay independent.
        devices.stop()
    }

    func startStats() {
        panelWantsStats = true
        syncStatsSampling()
    }

    func stopStats() {
        panelWantsStats = false
        syncStatsSampling()
    }

    private func syncStatsSampling() {
        let menuWantsStats = menuBarStats != .off
        guard panelWantsStats || menuWantsStats else {
            statsService.stop()
            return
        }
        statsService.onUpdate = { [weak self] sample in
            DispatchQueue.main.async {
                self?.stats = sample
            }
        }
        statsService.start(
            interval: panelWantsStats ? 1.0 : 2.0,
            detail: panelWantsStats
        )
    }

    func toggleKeyboard() {
        setKeyboardLocked(!keyboardLocked)
    }

    func toggleLidSleep() {
        setLidSleepDisabled(!lidSleepDisabled)
    }

    func toggleAwake() {
        setAwakeActive(!awakeActive)
    }

    var awakeTileStatus: String {
        if !awakeActive { return "Off" }
        if let remaining = awakeRemainingSeconds {
            return Self.formatAwakeRemaining(remaining, compact: true)
        }
        return "On"
    }

    static func awakeDurationLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Indefinitely"
        case 60: return "1 hour"
        case 120: return "2 hours"
        case 300: return "5 hours"
        default: return "\(minutes) minutes"
        }
    }

    func toggleScrollReverse() {
        setScrollReverseEnabled(!scrollReverseEnabled)
    }

    func setScrollReverseEnabled(_ enabled: Bool) {
        guard enabled != scrollReverseEnabled else { return }
        scrollReverseEnabled = enabled
        do {
            try tools.scroll.setEnabled(enabled, mice: mice)
        } catch {
            // Store is on; helper may still be down — surface that in scrollStatus.
        }
        accessibilityTrusted = AccessibilityAuth.hasPermission || ScrollHelperController.shared.isRunning
        updateScrollStatus()
    }

    func unlockKeyboard() {
        setKeyboardLocked(false)
    }

    func setKeyboardLocked(_ locked: Bool) {
        guard !keyboardBusy, locked != keyboardLocked else { return }
        keyboardError = nil
        keyboardLocked = locked
        keyboardBusy = true
        keyboardStatus = locked ? "Locking built-in keyboard…" : "Unlocking built-in keyboard…"
        keyboardEpoch += 1
        let epoch = keyboardEpoch
        keyboardQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.tools.keyboard.setEnabled(locked, options: ToolOptions())
                let snapshot = try self.tools.keyboard.hardwareSnapshot()
                DispatchQueue.main.async {
                    guard epoch == self.keyboardEpoch else { return }
                    self.keyboardBusy = false
                    self.applyKeyboardSnapshot(snapshot)
                }
            } catch {
                let snapshot = try? self.tools.keyboard.hardwareSnapshot()
                if let snapshot {
                    self.tools.keyboard.syncBacklight(locked: snapshot.locked)
                }
                DispatchQueue.main.async {
                    guard epoch == self.keyboardEpoch else { return }
                    self.keyboardBusy = false
                    if let snapshot {
                        self.applyKeyboardSnapshot(snapshot, persist: true)
                        if snapshot.locked != locked {
                            self.keyboardError = error.localizedDescription
                        }
                    } else {
                        self.tools.keyboard.invalidateIDs()
                        self.keyboardError = error.localizedDescription
                        self.keyboardLocked = false
                        self.tools.keyboard.persistLocked(false)
                        self.keyboardStatus = error.localizedDescription
                    }
                }
            }
        }
    }

    func refreshKeyboardStatus(alignBacklight: Bool = false) {
        let epoch = keyboardEpoch
        keyboardQueue.async { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try self.tools.keyboard.hardwareSnapshot()
                if snapshot.locked {
                    self.tools.keyboard.resumeUITimerIfNeeded()
                    if alignBacklight {
                        self.tools.keyboard.syncBacklight(locked: true)
                    }
                } else {
                    self.tools.keyboard.restoreBacklightIfNeeded()
                }
                DispatchQueue.main.async {
                    guard epoch == self.keyboardEpoch, !self.keyboardBusy else { return }
                    self.applyKeyboardSnapshot(snapshot)
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    guard epoch == self.keyboardEpoch, !self.keyboardBusy else { return }
                    self.keyboardLocked = false
                    self.keyboardStatus = message
                }
            }
        }
    }

    func setDimKeyboardWhenLocked(_ enabled: Bool) {
        dimKeyboardWhenLocked = enabled
        syncBacklightWithLock()
    }

    private func syncBacklightWithLock() {
        guard keyboardLocked, !keyboardBusy else { return }
        keyboardQueue.async { [weak self] in
            self?.tools.keyboard.syncBacklight(locked: true)
        }
    }

    private func applyKeyboardSnapshot(_ snapshot: KeyboardLockService.Snapshot, persist: Bool = false) {
        keyboardLocked = snapshot.locked
        if persist {
            tools.keyboard.persistLocked(snapshot.locked)
        }
        if snapshot.locked {
            if let remaining = snapshot.remainingMinutes {
                keyboardStatus = "Built-in keys ignored · auto-unlock in \(remaining) min"
            } else {
                keyboardStatus = "Built-in keys ignored until you unlock or reboot"
            }
        } else {
            keyboardStatus = "Built-in keyboard is live"
        }
    }

    func setLidSleepDisabled(_ disabled: Bool) {
        guard !lidBusy, disabled != lidSleepDisabled else { return }
        lidError = nil
        lidSleepDisabled = disabled
        lidBusy = true
        lidStatus = disabled ? "Keeping the Mac awake…" : "Restoring lid sleep…"
        lidEpoch += 1
        let epoch = lidEpoch
        lidQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.tools.lid.setEnabled(disabled, options: ToolOptions())
                let snapshot = self.tools.lid.hardwareSnapshot()
                DispatchQueue.main.async {
                    guard epoch == self.lidEpoch else { return }
                    self.lidBusy = false
                    self.applyLidSnapshot(snapshot)
                }
            } catch {
                let snapshot = self.tools.lid.hardwareSnapshot()
                DispatchQueue.main.async {
                    guard epoch == self.lidEpoch else { return }
                    self.lidBusy = false
                    self.lidError = error.localizedDescription
                    self.applyLidSnapshot(snapshot)
                }
            }
        }
    }

    func refreshLidStatus() {
        let epoch = lidEpoch
        lidQueue.async { [weak self] in
            guard let self else { return }
            self.tools.lid.restore()
            let snapshot = self.tools.lid.hardwareSnapshot()
            DispatchQueue.main.async {
                guard epoch == self.lidEpoch, !self.lidBusy else { return }
                self.applyLidSnapshot(snapshot)
            }
        }
    }

    private func applyLidSnapshot(_ snapshot: LidSleepService.Snapshot) {
        lidSleepDisabled = snapshot.disabled
        if snapshot.disabled {
            lidStatus = "Battery stays awake with the lid closed"
        } else {
            lidStatus = "Battery sleeps when the lid closes"
        }
    }

    func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func isScrollReverseOn(for id: String) -> Bool {
        scrollReverseByDevice[id] ?? true
    }

    func setScrollReverse(for id: String, enabled: Bool) {
        scrollReverseByDevice[id] = enabled
        tools.scroll.setDevice(id: id, enabled: enabled, mice: mice)
        accessibilityTrusted = AccessibilityAuth.hasPermission || ScrollHelperController.shared.isRunning
        updateScrollStatus()
    }

    func scrollReverseBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { self.isScrollReverseOn(for: id) },
            set: { self.setScrollReverse(for: id, enabled: $0) }
        )
    }

    private func seedMouseDefaults() {
        if tools.scroll.seedMouseDefaults(mice) {
            scrollReverseByDevice = ToolStateStore.shared.current.scrollReverseByDevice
        }
    }

    private func refreshScrollReverseState() {
        tools.scroll.apply(mice: mice)
        accessibilityTrusted = AccessibilityAuth.hasPermission || ScrollHelperController.shared.isRunning
        updateScrollStatus()
    }

    private func handleWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.devices.refresh()
            self.refreshScrollReverseState()
            if self.keyboardLocked {
                self.reapplyKeyboardLock()
            } else {
                self.keyboardQueue.async {
                    self.tools.keyboard.invalidateIDs()
                    DispatchQueue.main.async {
                        self.refreshKeyboardStatus(alignBacklight: true)
                    }
                }
            }
        }
    }

    /// Re-apply last-on tools after a relaunch, then read lid sleep from `pmset`.
    /// Keyboard lock is only restored for the same boot — a reboot always
    /// unlocks, so you cannot trap yourself out of the built-in keys.
    func restorePersistedTools() {
        restoreKeyboardIfNeeded()
        refreshLidStatus()
        restoreAwakeIfNeeded()
        refreshScrollReverseState()
    }

    /// Read each tool from the Mac and restore anything that dropped.
    func checkStatus() {
        guard !statusCheckBusy else { return }
        statusCheckBusy = true
        statusCheckNotice = nil
        restorePersistedTools()
        devices.refresh()
        refreshAccessibility()
        refreshScrollReverseState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.statusCheckBusy = false
            self.statusCheckNotice = "Updated from this Mac"
        }
    }

    func checkLatestVersion() {
        guard !updateCheckBusy else { return }
        updateCheckBusy = true
        updateCheckNotice = nil
        newerVersion = nil
        latestReleaseURL = nil
        updateCheckEpoch += 1
        let epoch = updateCheckEpoch
        updateCheckTask?.cancel()
        updateCheckTask = UpdateCheckService.fetchLatest { [weak self] result in
            DispatchQueue.main.async {
                guard let self, epoch == self.updateCheckEpoch else { return }
                self.updateCheckBusy = false
                self.updateCheckTask = nil
                switch result {
                case .success(let release):
                    self.latestReleaseURL = release.pageURL
                    switch UpdateCheckService.compare(latest: release.version, current: self.appVersion) {
                    case .orderedDescending:
                        self.newerVersion = release.version
                        self.updateCheckNotice = "\(release.version) is available"
                    case .orderedSame:
                        self.updateCheckNotice = "You're on the latest version"
                    case .orderedAscending:
                        self.updateCheckNotice = "This build is ahead of GitHub"
                    }
                case .failure(let error):
                    self.updateCheckNotice = error.localizedDescription
                }
            }
        }
    }

    func openLatestRelease() {
        let url = latestReleaseURL ?? UpdateCheckService.releasesPageURL
        NSWorkspace.shared.open(url)
    }

    private func restoreKeyboardIfNeeded() {
        let epoch = keyboardEpoch
        keyboardQueue.async { [weak self] in
            guard let self else { return }
            self.tools.keyboard.restore()
            do {
                let snapshot = try self.tools.keyboard.hardwareSnapshot()
                DispatchQueue.main.async {
                    guard epoch == self.keyboardEpoch, !self.keyboardBusy else { return }
                    self.applyKeyboardSnapshot(snapshot)
                }
            } catch {
                DispatchQueue.main.async {
                    guard epoch == self.keyboardEpoch, !self.keyboardBusy else { return }
                    self.keyboardLocked = false
                    self.keyboardStatus = error.localizedDescription
                }
            }
        }
    }

    private func reapplyKeyboardLock() {
        keyboardError = nil
        keyboardBusy = true
        keyboardStatus = "Re-applying keyboard lock…"
        keyboardEpoch += 1
        let epoch = keyboardEpoch
        keyboardQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.tools.keyboard.reapplyLock()
                let snapshot = try self.tools.keyboard.hardwareSnapshot()
                DispatchQueue.main.async {
                    guard epoch == self.keyboardEpoch else { return }
                    self.keyboardBusy = false
                    self.applyKeyboardSnapshot(snapshot)
                }
            } catch {
                let snapshot = try? self.tools.keyboard.hardwareSnapshot()
                DispatchQueue.main.async {
                    guard epoch == self.keyboardEpoch else { return }
                    self.keyboardBusy = false
                    self.keyboardError = error.localizedDescription
                    if let snapshot {
                        self.applyKeyboardSnapshot(snapshot, persist: true)
                    } else {
                        self.keyboardStatus = error.localizedDescription
                    }
                }
            }
        }
    }

    func setAwakeActive(_ active: Bool) {
        awakeError = nil
        if active {
            if awakeActive, tools.awake.hardwareSnapshot().active { return }
            startAwake()
        } else {
            if !awakeActive, !tools.awake.hardwareSnapshot().active { return }
            stopAwake()
        }
    }

    private func startAwake() {
        awakeError = nil
        do {
            try tools.awake.setEnabled(true, options: ToolOptions(minutes: awakeMinutes))
        } catch {
            stopAwakeTick()
            awakeActive = false
            awakeRemainingSeconds = nil
            awakeError = error.localizedDescription
            awakeStatus = error.localizedDescription
            return
        }
        applyAwakeSnapshot(tools.awake.hardwareSnapshot())
        startAwakeTick()
    }

    private func stopAwake() {
        stopAwakeTick()
        try? tools.awake.setEnabled(false, options: ToolOptions())
        awakeActive = false
        awakeRemainingSeconds = nil
        awakeStatus = "Mac can sleep as usual"
    }

    private func handleAwakeExpired() {
        stopAwakeTick()
        tools.awake.noteExpired()
        awakeActive = false
        awakeRemainingSeconds = nil
        awakeStatus = "Mac can sleep as usual"
    }

    private func restoreAwakeIfNeeded() {
        tools.awake.restore()
        let snapshot = tools.awake.hardwareSnapshot()
        if snapshot.active {
            applyAwakeSnapshot(snapshot)
            startAwakeTick()
        } else if awakeActive {
            stopAwakeTick()
            awakeActive = false
            awakeRemainingSeconds = nil
            awakeStatus = "Mac can sleep as usual"
        }
    }

    private func applyAwakeSnapshot(_ snapshot: CaffeinateService.Snapshot) {
        awakeActive = snapshot.active
        awakeRemainingSeconds = snapshot.remainingSeconds
        if snapshot.active {
            if let remaining = snapshot.remainingSeconds {
                awakeStatus = "Staying awake · \(Self.formatAwakeRemaining(remaining, compact: false)) left"
            } else {
                awakeStatus = "Staying awake until you turn it off"
            }
        } else {
            awakeStatus = "Mac can sleep as usual"
        }
    }

    private func startAwakeTick() {
        guard awakeTick == nil else { return }
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshAwakeRemaining()
        }
        tick.tolerance = 0.25
        RunLoop.main.add(tick, forMode: .common)
        awakeTick = tick
    }

    private func stopAwakeTick() {
        awakeTick?.invalidate()
        awakeTick = nil
    }

    private func refreshAwakeRemaining() {
        let snapshot = tools.awake.hardwareSnapshot()
        if snapshot.active {
            applyAwakeSnapshot(snapshot)
        } else if awakeActive {
            handleAwakeExpired()
        }
    }

    private static func formatAwakeRemaining(_ seconds: Int, compact: Bool) -> String {
        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            if compact {
                return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
            }
            if minutes > 0 {
                return "\(hours) hr \(minutes) min"
            }
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        if seconds >= 60 {
            let minutes = seconds / 60
            if compact { return "\(minutes) min" }
            return minutes == 1 ? "1 min" : "\(minutes) min"
        }
        return compact ? "\(seconds)s" : "\(seconds) sec"
    }

    private static func currentBootTime() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        sysctlbyname("kern.boottime", &boot, &size, nil, 0)
        return TimeInterval(boot.tv_sec)
    }

    private static func isCurrentBoot(_ saved: TimeInterval) -> Bool {
        guard saved > 0 else { return false }
        return abs(saved - currentBootTime()) < 1
    }

    func refreshAccessibility() {
        let trusted = AccessibilityAuth.hasPermission || ScrollHelperController.shared.isRunning
        let changed = trusted != accessibilityTrusted
        accessibilityTrusted = trusted
        if changed {
            refreshScrollReverseState()
        } else {
            updateScrollStatus()
        }
    }

    private func updateScrollStatus() {
        if mice.isEmpty {
            scrollStatus = "No mouse connected"
            return
        }
        if !scrollReverseEnabled {
            scrollStatus = "Mouse scroll follows System Settings"
            return
        }
        if !mice.contains(where: { isScrollReverseOn(for: $0.id) }) {
            scrollStatus = "No mouse set to reverse"
            return
        }
        if ScrollHelperController.shared.isRunning {
            scrollStatus = "Trackpad stays natural"
        } else if !accessibilityTrusted {
            scrollStatus = "Needs Accessibility permission to reverse the wheel."
        } else {
            scrollStatus = "Could not start scroll reverse. Toggle NAF Tools off and on in Accessibility, then reopen the app."
        }
    }

    private func handleExternalStateChange() {
        ToolStateStore.shared.reload()
        let state = ToolStateStore.shared.current
        suppressAwakeRestart = true
        autoUnlockMinutes = state.autoUnlockMinutes
        dimKeyboardWhenLocked = state.dimKeyboardWhenLocked
        scrollReverseEnabled = state.scrollReverseEnabled
        scrollReverseByDevice = state.scrollReverseByDevice
        awakeMinutes = [0, 5, 10, 15, 30, 60, 120, 300].contains(state.awakeMinutes)
            ? state.awakeMinutes
            : awakeMinutes
        suppressAwakeRestart = false
        refreshKeyboardStatus(alignBacklight: true)
        refreshLidStatus()
        restoreAwakeIfNeeded()
        refreshScrollReverseState()
        refreshAccessibility()
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemNotice = "Could not update login item: \(error.localizedDescription)"
        }
    }
}
