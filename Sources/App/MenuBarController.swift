import AppKit
import Combine
import SwiftUI

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: AppModel
    private let presentation = PanelPresentation()
    private var eventMonitor: Any?
    private var displayRefreshWork: DispatchWorkItem?
    private var iconCancellables = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        statusItem = Self.makeStatusItem()
        super.init()

        let host = NSHostingController(
            rootView: ToolsPanel()
                .environmentObject(model)
                .environmentObject(presentation)
        )
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        configureStatusItem()
        observeDisplayChanges()
        observeActiveTools()
    }

    deinit {
        displayRefreshWork?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        model.restorePersistedTools()
        model.refreshAccessibility()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        startEventMonitor()
    }

    @objc private func togglePopover(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        if popover.isShown {
            popover.performClose(sender)
            stopEventMonitor()
            return
        }
        showPopover()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(withTitle: "Open NAF Tools", action: #selector(openFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(toggleItem(
            title: "Keyboard lock",
            action: #selector(toggleKeyboardFromMenu),
            isOn: model.keyboardLocked,
            isEnabled: !model.keyboardBusy
        ))
        menu.addItem(toggleItem(
            title: "Reverse scroll",
            action: #selector(toggleScrollFromMenu),
            isOn: model.scrollReverseEnabled,
            isEnabled: true
        ))
        menu.addItem(toggleItem(
            title: "Stay awake",
            action: #selector(toggleLidFromMenu),
            isOn: model.lidSleepDisabled,
            isEnabled: !model.lidBusy
        ))
        menu.addItem(toggleItem(
            title: "Prevent sleep",
            action: #selector(toggleAwakeFromMenu),
            isOn: model.awakeActive,
            isEnabled: true
        ))
        menu.addItem(.separator())
        menu.addItem(menuBarDisplayItem())
        menu.addItem(menuBarStatsItem())
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quitFromMenu), keyEquivalent: "q")

        menu.items.forEach { item in
            if item.action != nil {
                item.target = self
            }
        }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
            self?.statusItem.button?.target = self
            self?.statusItem.button?.action = #selector(self?.togglePopover(_:))
            self?.statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func toggleItem(title: String, action: Selector, isOn: Bool, isEnabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.state = isOn ? .on : .off
        item.isEnabled = isEnabled
        return item
    }

    @objc private func openFromMenu() {
        showPopover()
    }

    @objc private func toggleKeyboardFromMenu() {
        model.toggleKeyboard()
    }

    @objc private func toggleScrollFromMenu() {
        model.toggleScrollReverse()
    }

    @objc private func toggleLidFromMenu() {
        model.toggleLidSleep()
    }

    @objc private func toggleAwakeFromMenu() {
        model.toggleAwake()
    }

    @objc private func quitFromMenu() {
        model.quit()
    }

    private func menuBarDisplayItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Menu bar", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (index, mode) in MenuBarDisplay.allCases.enumerated() {
            let entry = NSMenuItem(title: mode.title, action: #selector(selectMenuBarDisplay(_:)), keyEquivalent: "")
            entry.tag = index
            entry.state = model.menuBarDisplay == mode ? .on : .off
            entry.target = self
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    @objc private func selectMenuBarDisplay(_ sender: NSMenuItem) {
        let modes = MenuBarDisplay.allCases
        guard modes.indices.contains(sender.tag) else { return }
        model.menuBarDisplay = modes[sender.tag]
    }

    private func menuBarStatsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Menu bar stats", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (index, mode) in MenuBarStats.allCases.enumerated() {
            let entry = NSMenuItem(title: mode.title, action: #selector(selectMenuBarStats(_:)), keyEquivalent: "")
            entry.tag = index
            entry.state = model.menuBarStats == mode ? .on : .off
            entry.target = self
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    @objc private func selectMenuBarStats(_ sender: NSMenuItem) {
        let modes = MenuBarStats.allCases
        guard modes.indices.contains(sender.tag) else { return }
        model.menuBarStats = modes[sender.tag]
    }

    private static func makeStatusItem() -> NSStatusItem {
        NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    }

    private func configureStatusItem() {
        statusItem.autosaveName = "NAFTools.StatusItem"
        statusItem.isVisible = true
        if #available(macOS 13.0, *) {
            statusItem.behavior = []
        }
        applyIcon()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func applyIcon() {
        guard let button = statusItem.button else { return }
        let mode = model.menuBarDisplay
        let tools = model.activeMenuBarTools
        statusItem.length = MenuBarIcon.statusItemLength(mode: mode, tools: tools, statsText: model.menuBarStatsText)
        button.image = nil
        button.image = MenuBarIcon.makeImage(mode: mode, tools: tools, statsText: model.menuBarStatsText)
        button.imageScaling = .scaleNone
        button.imagePosition = .imageOnly
        button.toolTip = MenuBarIcon.tooltip(tools: tools, statsText: model.menuBarStatsText)
    }

    private func observeActiveTools() {
        Publishers.CombineLatest4(
            model.$keyboardLocked,
            model.$scrollReverseEnabled,
            model.$lidSleepDisabled,
            model.$awakeActive
        )
        .combineLatest(model.$menuBarDisplay)
        .combineLatest(model.$menuBarStats)
        .combineLatest(model.$stats)
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.applyIcon()
        }
        .store(in: &iconCancellables)
    }

    private func observeDisplayChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(backingPropertiesChanged),
            name: NSWindow.didChangeBackingPropertiesNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        scheduleStatusItemRebuild()
    }

    @objc private func backingPropertiesChanged(_ notification: Notification) {
        guard (notification.object as? NSWindow) == statusItem.button?.window else { return }
        applyIcon()
    }

    private func scheduleStatusItemRebuild() {
        displayRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.rebuildStatusItem()
        }
        displayRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func rebuildStatusItem() {
        if popover.isShown {
            popover.performClose(nil)
            stopEventMonitor()
        }
        NSStatusBar.system.removeStatusItem(statusItem)
        statusItem = Self.makeStatusItem()
        configureStatusItem()
    }

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
            self.stopEventMonitor()
        }
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}

extension MenuBarController: NSPopoverDelegate {
    func popoverWillShow(_ notification: Notification) {
        presentation.menuDidOpen()
        model.startStats()
    }

    func popoverDidClose(_ notification: Notification) {
        presentation.menuDidClose()
        model.stopStats()
        stopEventMonitor()
    }
}
