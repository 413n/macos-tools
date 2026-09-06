import AppKit
import SwiftUI

@main
enum CaptureScreenshots {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        guard CommandLine.arguments.count >= 2 else {
            fputs("usage: capture-screenshots OUT_DIR\n", stderr)
            exit(1)
        }
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

        DispatchQueue.main.async {
            do {
                try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                try captureAll(to: out)
                exit(0)
            } catch {
                fputs("capture failed: \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }
}

@MainActor
private func captureAll(to out: URL) throws {
    try write(name: "home-dark.png", appearance: .darkAqua, to: out) { model, presentation in
        presentation.route = .home
        seedHome(model)
    }
    try write(name: "home-light.png", appearance: .aqua, to: out) { model, presentation in
        presentation.route = .home
        seedHome(model)
    }
    try write(name: "keyboard.png", appearance: .darkAqua, to: out) { model, presentation in
        presentation.route = .keyboard
        seedHome(model)
    }
    try write(name: "scroll.png", appearance: .darkAqua, to: out) { model, presentation in
        presentation.route = .scroll
        seedHome(model)
        model.scrollReverseEnabled = true
        model.scrollStatus = "Trackpad stays natural"
        model.mice = [
            MouseDevice(vendor: 1133, product: 16514, name: "MX Master 3S")
        ]
        model.mouseNames = ["MX Master 3S"]
        model.mouseConnected = true
        model.scrollReverseByDevice = ["1133:16514": true]
        model.accessibilityTrusted = true
    }
    try write(name: "awake.png", appearance: .darkAqua, to: out) { model, presentation in
        presentation.route = .awake
        seedHome(model)
    }
    try write(name: "this-mac.png", appearance: .darkAqua, to: out) { model, presentation in
        presentation.route = .machine
        seedHome(model)
    }
    try write(name: "settings.png", appearance: .darkAqua, to: out) { model, presentation in
        presentation.route = .settings
        seedHome(model)
        model.menuBarDisplay = .logoAndActive
    }
}

@MainActor
private func seedHome(_ model: AppModel) {
    model.keyboardLocked = true
    model.keyboardStatus = "Built-in keys ignored until you unlock or reboot"
    model.keyboardError = nil
    model.keyboardBusy = false
    model.autoUnlockMinutes = 0
    model.dimKeyboardWhenLocked = true

    model.scrollReverseEnabled = false
    model.scrollStatus = "Mouse scroll follows System Settings"
    model.mice = [
        MouseDevice(vendor: 1133, product: 16514, name: "MX Master 3S")
    ]
    model.mouseNames = ["MX Master 3S"]
    model.mouseConnected = true
    model.accessibilityTrusted = true

    model.lidSleepDisabled = false
    model.lidStatus = "Battery sleeps when the lid closes"
    model.lidError = nil
    model.lidBusy = false

    model.awakeActive = false
    model.awakeMinutes = 60
    model.awakeActive = true
    model.awakeRemainingSeconds = 47 * 60
    model.awakeStatus = "Staying awake · 47 min left"
    model.awakeError = nil

    model.cpuReady = true
    model.cpuFraction = 0.12
    model.ramUsed = 18 * 1_073_741_824
    model.ramTotal = 36 * 1_073_741_824
}

@MainActor
private func write(
    name: String,
    appearance: NSAppearance.Name,
    to directory: URL,
    configure: (AppModel, PanelPresentation) -> Void
) throws {
    let model = AppModel()
    let presentation = PanelPresentation()
    presentation.generation = 1
    configure(model, presentation)

    let scheme: ColorScheme = appearance == .darkAqua ? .dark : .light
    let canvas = ShotCanvas {
        ToolsPanel()
            .environmentObject(model)
            .environmentObject(presentation)
    }
    .environment(\.colorScheme, scheme)

    let url = directory.appendingPathComponent(name)
    try render(canvas, appearance: appearance, to: url)
    fputs("wrote \(url.path)\n", stderr)
}

@MainActor
private func render<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) throws {
    let hosting = NSHostingView(rootView: view)
    hosting.appearance = NSAppearance(named: appearance)
    hosting.wantsLayer = true

    let window = NSWindow(
        contentRect: NSRect(x: -2400, y: -2400, width: 640, height: 800),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.appearance = NSAppearance(named: appearance)
    window.contentView = hosting
    window.orderFront(nil)

    hosting.layoutSubtreeIfNeeded()
    var size = hosting.fittingSize
    if size.width < 2 { size.width = 388 }
    if size.height < 2 { size.height = 560 }
    hosting.setFrameSize(size)
    window.setContentSize(size)
    hosting.layoutSubtreeIfNeeded()
    // Staggered tile entrance: last home tile starts at 0.4s and lasts 0.3s.
    RunLoop.current.run(until: Date().addingTimeInterval(0.9))

    let bounds = hosting.bounds
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else {
        throw CaptureError.bitmapFailed
    }
    hosting.cacheDisplay(in: bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw CaptureError.pngFailed
    }
    try png.write(to: url)
    window.orderOut(nil)
    window.close()
}

private enum CaptureError: Error {
    case bitmapFailed
    case pngFailed
}

private struct ShotCanvas<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.35), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 28, y: 14)
            .padding(44)
            .background {
                Rectangle().fill(wallpaper)
            }
    }

    private var wallpaper: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.22, blue: 0.34),
                    Color(red: 0.07, green: 0.08, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.78, green: 0.84, blue: 0.92),
                Color(red: 0.90, green: 0.91, blue: 0.94)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
