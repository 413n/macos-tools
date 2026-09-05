import AppKit
import SwiftUI

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: AppModel
    private let presentation = PanelPresentation()
    private var eventMonitor: Any?
    private var displayRefreshWork: DispatchWorkItem?

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
        menu.addItem(withTitle: "Open NAF Tools", action: #selector(openFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quitFromMenu), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
            self?.statusItem.button?.target = self
            self?.statusItem.button?.action = #selector(self?.togglePopover(_:))
            self?.statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func openFromMenu() {
        showPopover()
    }

    @objc private func quitFromMenu() {
        model.quit()
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
            button.toolTip = "NAF Tools"
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func applyIcon() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.image = MenuBarIcon.makeImage()
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
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
