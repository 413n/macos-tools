import AppKit
import ApplicationServices
import Combine
import Darwin
import Foundation
import ServiceManagement
import SwiftUI

final class AppModel: ObservableObject {
    @Published var keyboardLocked = false
    @Published var keyboardStatus = "Checking built-in keyboard…"
    @Published var keyboardError: String?
    @Published var autoUnlockMinutes: Int {
        didSet { UserDefaults.standard.set(autoUnlockMinutes, forKey: Keys.autoUnlockMinutes) }
    }
    @Published var dimKeyboardWhenLocked: Bool {
        didSet { UserDefaults.standard.set(dimKeyboardWhenLocked, forKey: Keys.dimKeyboardWhenLocked) }
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
            UserDefaults.standard.set(awakeMinutes, forKey: Keys.awakeMinutes)
            if awakeActive {
                startAwake(timeoutSeconds: Self.timeoutSeconds(for: awakeMinutes))
            }
        }
    }

    @Published var loginItemNotice: String?
    @Published var statusCheckNotice: String?
    @Published var statusCheckBusy = false
    @Published var keyboardBusy = false
    @Published var cpuFraction: Double = 0
    @Published var cpuReady = false
    @Published var ramUsed: UInt64 = 0
    @Published var ramTotal: UInt64 = 0
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin()
        }
    }
    @Published var menuBarDisplay: MenuBarDisplay {
        didSet { UserDefaults.standard.set(menuBarDisplay.rawValue, forKey: Keys.menuBarDisplay) }
    }

    let timeoutChoices = [0, 5, 10, 15, 30, 60]
    let awakeDurationChoices = [0, 5, 10, 15, 30, 60, 120, 300]

    private let keyboard = KeyboardLockService()
    private let keyboardQueue = DispatchQueue(label: "naf.tools.keyboard", qos: .userInitiated)
    private var keyboardEpoch = 0
    private let lid = LidSleepService()
    private let lidQueue = DispatchQueue(label: "naf.tools.lid", qos: .userInitiated)
    private var lidEpoch = 0
    private let caffeinate = CaffeinateService()
    private var awakeTick: Timer?
    private let devices = DeviceMonitor()
    private let stats = SystemStatsService()
    private var wakeObserver: NSObjectProtocol?
    private var accessibilityTimer: Timer?

    private enum Keys {
        static let autoUnlockMinutes = "autoUnlockMinutes"
        static let dimKeyboardWhenLocked = "dimKeyboardWhenLocked"
        static let keyboardLocked = "keyboardLocked"
        static let keyboardLockBoot = "keyboardLockBoot"
        static let scrollReverseEnabled = "scrollReverseEnabled"
        static let scrollReverseByDevice = "scrollReverseByDevice"
        static let lidSleepDisabled = "lidSleepDisabled"
        static let awakeEnabled = "awakeEnabled"
        static let awakeMinutes = "awakeMinutes"
        static let awakeDeadline = "awakeDeadline"
        static let launchAtLogin = "launchAtLogin"
        static let menuBarDisplay = "menuBarDisplay"
        static let didLaunch = "didCompleteFirstLaunch"
    }

    private var defaultReverseForNewMice = true

    init() {
        let defaults = UserDefaults.standard
        autoUnlockMinutes = defaults.object(forKey: Keys.autoUnlockMinutes) as? Int ?? 0
        dimKeyboardWhenLocked = defaults.object(forKey: Keys.dimKeyboardWhenLocked) as? Bool ?? true
        defaultReverseForNewMice = defaults.object(forKey: Keys.scrollReverseEnabled) as? Bool ?? false
        scrollReverseEnabled = defaultReverseForNewMice
        if let stored = defaults.dictionary(forKey: Keys.scrollReverseByDevice) {
            scrollReverseByDevice = stored.reduce(into: [:]) { result, pair in
                if let flag = pair.value as? Bool {
                    result[pair.key] = flag
                } else if let number = pair.value as? NSNumber {
                    result[pair.key] = number.boolValue
                }
            }
        }
        lidSleepDisabled = defaults.bool(forKey: Keys.lidSleepDisabled)
        let storedAwakeMinutes = defaults.object(forKey: Keys.awakeMinutes) as? Int ?? 0
        awakeMinutes = [0, 5, 10, 15, 30, 60, 120, 300].contains(storedAwakeMinutes) ? storedAwakeMinutes : 0
        awakeActive = defaults.bool(forKey: Keys.awakeEnabled)
        let savedBoot = defaults.double(forKey: Keys.keyboardLockBoot)
        keyboardLocked = defaults.bool(forKey: Keys.keyboardLocked) && Self.isCurrentBoot(savedBoot)
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
    }

    var activeMenuBarTools: [MenuBarTool] {
        var tools: [MenuBarTool] = []
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
        cpuReady ? String(format: "%.0f%%", cpuFraction * 100) : "…"
    }

    var ramShortLabel: String {
        guard ramTotal > 0 else { return "…" }
        return "\(Self.gigabytes(ramUsed)) / \(Self.gigabytes(ramTotal))"
    }

    var ramFraction: Double {
        guard ramTotal > 0 else { return 0 }
        return min(max(Double(ramUsed) / Double(ramTotal), 0), 1)
    }

    var cpuUsageLevel: UsageLevel {
        cpuReady ? UsageLevel(fraction: cpuFraction) : .normal
    }

    var ramUsageLevel: UsageLevel {
        ramTotal > 0 ? UsageLevel(fraction: ramFraction) : .normal
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 10 {
            return String(format: "%.0f GB", gb)
        }
        return String(format: "%.1f GB", gb)
    }

    func start() {
        refreshAccessibility()
        keyboard.onTimerExpired = { [weak self] in
            DispatchQueue.main.async {
                self?.persistKeyboardLocked(false)
                self?.refreshKeyboardStatus()
            }
        }
        caffeinate.onExpired = { [weak self] in
            self?.handleAwakeExpired()
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

        if !UserDefaults.standard.bool(forKey: Keys.didLaunch) {
            UserDefaults.standard.set(true, forKey: Keys.didLaunch)
            applyLaunchAtLogin()
        } else if launchAtLogin {
            applyLaunchAtLogin()
        }
    }

    func stop() {
        accessibilityTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        stats.stop()
        ScrollReverseService.shared.stop()
        stopAwakeTick()
        caffeinate.stop()
        // Leave the hidutil mapping and the bash auto-unlock timer running so
        // a quit does not drop keyboard lock for the rest of this boot.
        devices.stop()
    }

    func startStats() {
        stats.onUpdate = { [weak self] sample in
            DispatchQueue.main.async {
                self?.cpuFraction = sample.cpuFraction
                self?.cpuReady = sample.cpuReady
                self?.ramUsed = sample.ramUsed
                self?.ramTotal = sample.ramTotal
            }
        }
        stats.start()
    }

    func stopStats() {
        stats.stop()
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
        defaultReverseForNewMice = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.scrollReverseEnabled)
        for mouse in mice {
            scrollReverseByDevice[mouse.id] = enabled
        }
        persistMousePrefs()
        refreshScrollReverseState()
    }

    func unlockKeyboard() {
        setKeyboardLocked(false)
    }

    func setKeyboardLocked(_ locked: Bool) {
        guard !keyboardBusy, locked != keyboardLocked else { return }
        keyboardError = nil
        keyboardLocked = locked
        persistKeyboardLocked(locked)
        keyboardBusy = true
        keyboardStatus = locked ? "Locking built-in keyboard…" : "Unlocking built-in keyboard…"
        keyboardEpoch += 1
        let epoch = keyboardEpoch
        let timeout = autoUnlockMinutes == 0 ? nil : autoUnlockMinutes
        let dim = dimKeyboardWhenLocked
        keyboardQueue.async { [weak self] in
            guard let self else { return }
            do {
                if locked {
                    try self.keyboard.disable(timeoutMinutes: timeout)
                } else {
                    try self.keyboard.enable()
                }
                let snapshot = try self.keyboard.snapshot()
                self.keyboard.syncBacklight(locked: snapshot.locked, dimWhileLocked: dim)
                DispatchQueue.main.async {
                    guard epoch == self.keyboardEpoch else { return }
                    self.keyboardBusy = false
                    self.applyKeyboardSnapshot(snapshot, persist: true)
                }
            } catch {
                let snapshot = try? self.keyboard.snapshot()
                if let snapshot {
                    self.keyboard.syncBacklight(locked: snapshot.locked, dimWhileLocked: dim)
                }
                DispatchQueue.main.async {
                    guard epoch == self.keyboardEpoch else { return }
                    self.keyboardBusy = false
                    if let snapshot {
                        self.applyKeyboardSnapshot(snapshot, persist: true)
                        // hidutil can apply the mapping and still look like it
                        // failed (e.g. a killed process). Trust the hardware.
                        if snapshot.locked != locked {
                            self.keyboardError = error.localizedDescription
                        }
                    } else {
                        self.keyboard.invalidateIDs()
                        self.keyboardError = error.localizedDescription
                        self.keyboardLocked = false
                        self.persistKeyboardLocked(false)
                        self.keyboardStatus = error.localizedDescription
                    }
                }
            }
        }
    }

    func refreshKeyboardStatus(alignBacklight: Bool = false) {
        let epoch = keyboardEpoch
        let dim = dimKeyboardWhenLocked
        keyboardQueue.async { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try self.keyboard.snapshot()
                if snapshot.locked {
                    self.keyboard.resumeUITimerIfNeeded()
                    if alignBacklight, dim {
                        self.keyboard.syncBacklight(locked: true, dimWhileLocked: true)
                    }
                } else {
                    self.keyboard.restoreBacklightIfNeeded()
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
        let dim = dimKeyboardWhenLocked
        keyboardQueue.async { [weak self] in
            self?.keyboard.syncBacklight(locked: true, dimWhileLocked: dim)
        }
    }

    private func applyKeyboardSnapshot(_ snapshot: KeyboardLockService.Snapshot, persist: Bool = false) {
        keyboardLocked = snapshot.locked
        if persist {
            persistKeyboardLocked(snapshot.locked)
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
        persistLidSleepDisabled(disabled)
        lidBusy = true
        lidStatus = disabled ? "Keeping the Mac awake…" : "Restoring lid sleep…"
        lidEpoch += 1
        let epoch = lidEpoch
        lidQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.runLidChangeOnMain {
                    try self.lid.setDisabled(disabled)
                }
                let snapshot = self.lid.snapshot()
                DispatchQueue.main.async {
                    guard epoch == self.lidEpoch else { return }
                    self.lidBusy = false
                    self.applyLidSnapshot(snapshot)
                }
            } catch {
                let snapshot = self.lid.snapshot()
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
            let snapshot = self.lid.snapshot()
            DispatchQueue.main.async {
                guard epoch == self.lidEpoch, !self.lidBusy else { return }
                self.applyLidSnapshot(snapshot)
            }
        }
    }

    private func applyLidSnapshot(_ snapshot: LidSleepService.Snapshot) {
        lidSleepDisabled = snapshot.disabled
        persistLidSleepDisabled(snapshot.disabled)
        if snapshot.disabled {
            lidStatus = "Battery stays awake with the lid closed"
        } else {
            lidStatus = "Battery sleeps when the lid closes"
        }
    }

    private func runLidChangeOnMain(_ body: @escaping () throws -> Void) throws {
        if Thread.isMainThread {
            try body()
            return
        }
        var caught: Error?
        DispatchQueue.main.sync {
            do {
                try body()
            } catch {
                caught = error
            }
        }
        if let caught { throw caught }
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
        scrollReverseByDevice[id] ?? defaultReverseForNewMice
    }

    func setScrollReverse(for id: String, enabled: Bool) {
        scrollReverseByDevice[id] = enabled
        persistMousePrefs()
        refreshScrollReverseState()
    }

    func scrollReverseBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { self.isScrollReverseOn(for: id) },
            set: { self.setScrollReverse(for: id, enabled: $0) }
        )
    }

    private func seedMouseDefaults() {
        var changed = false
        for mouse in mice where scrollReverseByDevice[mouse.id] == nil {
            scrollReverseByDevice[mouse.id] = defaultReverseForNewMice
            changed = true
        }
        if changed {
            persistMousePrefs()
        }
    }

    private func persistMousePrefs() {
        UserDefaults.standard.set(scrollReverseByDevice, forKey: Keys.scrollReverseByDevice)
    }

    private func refreshScrollReverseState() {
        let enabledIDs = Set(mice.filter { isScrollReverseOn(for: $0.id) }.map(\.id))
        DeviceMonitor.reverseEnabledIDs = enabledIDs
        scrollReverseEnabled = !enabledIDs.isEmpty
        if !mice.isEmpty {
            defaultReverseForNewMice = scrollReverseEnabled
            UserDefaults.standard.set(scrollReverseEnabled, forKey: Keys.scrollReverseEnabled)
        }
        applyScrollReverse()
    }

    private func handleWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.devices.refresh()
            ScrollReverseService.shared.reEnableIfNeeded()
            if self.keyboardLocked {
                self.reapplyKeyboardLock()
            } else {
                self.keyboardQueue.async {
                    self.keyboard.invalidateIDs()
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

    private func restoreKeyboardIfNeeded() {
        let defaults = UserDefaults.standard
        let wantedLock = defaults.bool(forKey: Keys.keyboardLocked)
        let savedBoot = defaults.double(forKey: Keys.keyboardLockBoot)
        guard wantedLock && Self.isCurrentBoot(savedBoot) else {
            if wantedLock {
                persistKeyboardLocked(false)
            }
            refreshKeyboardStatus(alignBacklight: true)
            return
        }
        let epoch = keyboardEpoch
        let dim = dimKeyboardWhenLocked
        keyboardQueue.async { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try self.keyboard.snapshot()
                if snapshot.locked {
                    self.keyboard.resumeUITimerIfNeeded()
                    if dim {
                        self.keyboard.syncBacklight(locked: true, dimWhileLocked: true)
                    }
                    DispatchQueue.main.async {
                        guard epoch == self.keyboardEpoch, !self.keyboardBusy else { return }
                        self.applyKeyboardSnapshot(snapshot)
                    }
                } else {
                    DispatchQueue.main.async {
                        guard epoch == self.keyboardEpoch, !self.keyboardBusy else { return }
                        self.reapplyKeyboardLock()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard epoch == self.keyboardEpoch, !self.keyboardBusy else { return }
                    self.reapplyKeyboardLock()
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
        let dim = dimKeyboardWhenLocked
        keyboardQueue.async { [weak self] in
            guard let self else { return }
            self.keyboard.invalidateIDs()
            do {
                try self.keyboard.disable(timeoutMinutes: nil, preserveExistingTimer: true)
                self.keyboard.resumeUITimerIfNeeded()
                let snapshot = try self.keyboard.snapshot()
                self.keyboard.syncBacklight(locked: snapshot.locked, dimWhileLocked: dim)
                DispatchQueue.main.async {
                    guard epoch == self.keyboardEpoch else { return }
                    self.keyboardBusy = false
                    self.applyKeyboardSnapshot(snapshot, persist: true)
                }
            } catch {
                let snapshot = try? self.keyboard.snapshot()
                if let snapshot {
                    self.keyboard.syncBacklight(locked: snapshot.locked, dimWhileLocked: dim)
                }
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

    private func persistKeyboardLocked(_ locked: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(locked, forKey: Keys.keyboardLocked)
        if locked {
            defaults.set(Self.currentBootTime(), forKey: Keys.keyboardLockBoot)
        }
    }

    private func persistLidSleepDisabled(_ disabled: Bool) {
        UserDefaults.standard.set(disabled, forKey: Keys.lidSleepDisabled)
    }

    func setAwakeActive(_ active: Bool) {
        awakeError = nil
        if active {
            if awakeActive, caffeinate.snapshot().active { return }
            startAwake(timeoutSeconds: Self.timeoutSeconds(for: awakeMinutes))
        } else {
            if !awakeActive, !caffeinate.snapshot().active { return }
            stopAwake(persist: true)
        }
    }

    private func startAwake(timeoutSeconds: Int?) {
        awakeError = nil
        do {
            try caffeinate.start(timeoutSeconds: timeoutSeconds)
        } catch {
            stopAwakeTick()
            awakeActive = false
            awakeRemainingSeconds = nil
            persistAwakeEnabled(false)
            awakeError = error.localizedDescription
            awakeStatus = error.localizedDescription
            return
        }
        awakeActive = true
        persistAwakeEnabled(true)
        if let timeoutSeconds, timeoutSeconds > 0 {
            UserDefaults.standard.set(
                Date().timeIntervalSince1970 + Double(timeoutSeconds),
                forKey: Keys.awakeDeadline
            )
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.awakeDeadline)
        }
        applyAwakeSnapshot(caffeinate.snapshot())
        startAwakeTick()
    }

    private func stopAwake(persist: Bool) {
        stopAwakeTick()
        caffeinate.stop()
        awakeActive = false
        awakeRemainingSeconds = nil
        if persist {
            persistAwakeEnabled(false)
        }
        awakeStatus = "Mac can sleep as usual"
    }

    private func handleAwakeExpired() {
        stopAwakeTick()
        awakeActive = false
        awakeRemainingSeconds = nil
        persistAwakeEnabled(false)
        awakeStatus = "Mac can sleep as usual"
    }

    private func restoreAwakeIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Keys.awakeEnabled) else {
            if awakeActive || caffeinate.snapshot().active {
                stopAwake(persist: false)
            }
            return
        }
        if caffeinate.snapshot().active {
            applyAwakeSnapshot(caffeinate.snapshot())
            startAwakeTick()
            return
        }
        if awakeMinutes == 0 {
            startAwake(timeoutSeconds: nil)
            return
        }
        let deadline = defaults.double(forKey: Keys.awakeDeadline)
        let remaining = Int((deadline - Date().timeIntervalSince1970).rounded(.down))
        if remaining > 1 {
            startAwake(timeoutSeconds: remaining)
        } else {
            stopAwake(persist: true)
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
        let snapshot = caffeinate.snapshot()
        if snapshot.active {
            applyAwakeSnapshot(snapshot)
        } else if awakeActive {
            handleAwakeExpired()
        }
    }

    private func persistAwakeEnabled(_ enabled: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: Keys.awakeEnabled)
        if !enabled {
            defaults.removeObject(forKey: Keys.awakeDeadline)
        }
    }

    private static func timeoutSeconds(for minutes: Int) -> Int? {
        minutes > 0 ? minutes * 60 : nil
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
        let trusted = AccessibilityAuth.hasPermission || ScrollReverseService.shared.isActive
        let changed = trusted != accessibilityTrusted
        accessibilityTrusted = trusted
        if changed {
            applyScrollReverse()
        } else {
            updateScrollStatus()
        }
    }

    private func applyScrollReverse() {
        if scrollReverseEnabled {
            if ScrollReverseService.shared.start() {
                accessibilityTrusted = true
            } else {
                accessibilityTrusted = AccessibilityAuth.hasPermission
                ScrollReverseService.shared.stop()
            }
        } else {
            ScrollReverseService.shared.stop()
        }
        updateScrollStatus()
    }

    private func updateScrollStatus() {
        if mice.isEmpty {
            scrollStatus = "No mouse connected"
            return
        }
        if scrollReverseEnabled {
            if ScrollReverseService.shared.isActive {
                scrollStatus = "Trackpad stays natural"
            } else if !accessibilityTrusted {
                scrollStatus = "Needs Accessibility permission to reverse the wheel."
            } else {
                scrollStatus = "Could not start scroll reverse. Toggle NAF Tools off and on in Accessibility, then reopen the app."
            }
        } else {
            scrollStatus = "Mouse scroll follows System Settings"
        }
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

enum AccessibilityAuth {
    static var hasPermission: Bool {
        AXIsProcessTrusted() || CGPreflightPostEventAccess() || CGPreflightListenEventAccess()
    }

    static func isTrusted(prompt: Bool) -> Bool {
        if prompt {
            requestIfNeeded()
        }
        return hasPermission
    }

    static func requestIfNeeded() {
        if hasPermission { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
