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
        model.homeTab = .tools
    }
    try write(name: "home-light.png", appearance: .aqua, to: out) { model, presentation in
        presentation.route = .home
        seedHome(model)
        model.homeTab = .tools
    }
    try write(name: "stats-dark.png", appearance: .darkAqua, to: out) { model, presentation in
        presentation.route = .home
        seedHome(model)
        model.homeTab = .stats
    }
    try write(name: "stats-light.png", appearance: .aqua, to: out) { model, presentation in
        presentation.route = .home
        seedHome(model)
        model.homeTab = .stats
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
    try write(name: "battery.png", appearance: .darkAqua, to: out) { model, presentation in
        presentation.route = .battery
        seedHome(model)
    }
    try write(name: "network.png", appearance: .darkAqua, to: out) { model, presentation in
        presentation.route = .network
        seedHome(model)
    }
    try write(name: "storage.png", appearance: .darkAqua, to: out) { model, presentation in
        presentation.route = .storage
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

    model.visibleHomeTools = Array(HomeTool.allCases)
    model.hiddenHomeTools = []
    model.menuBarStats = .cpu
    model.stats = demoStats()
}

@MainActor
private func demoStats() -> SystemSample {
    var sample = SystemSample()
    sample.cpuReady = true
    sample.cpuFraction = 0.12
    sample.cpuHistory = [0.08, 0.11, 0.09, 0.14, 0.18, 0.12, 0.10, 0.13, 0.16, 0.12]
    sample.ramUsed = 18 * 1_073_741_824
    sample.ramTotal = 36 * 1_073_741_824
    sample.ramCompressed = 2 * 1_073_741_824
    sample.swapUsed = 0
    sample.swapTotal = 0
    sample.memoryPressure = .normal
    sample.thermal = .nominal
    sample.uptimeSeconds = ((2 * 24) + 4) * 3600
    sample.battery = BatterySample(
        percent: 0.82,
        isCharging: false,
        isPluggedIn: false,
        isFull: false,
        minutesToEmpty: 154,
        minutesToFull: nil,
        health: "Good",
        cycleCount: 214
    )
    sample.accessories = [
        AccessoryBattery(name: "Magic Mouse", percent: 64),
        AccessoryBattery(name: "AirPods Pro", percent: 78)
    ]
    sample.bootVolume = VolumeSample(
        name: "Macintosh HD",
        path: "/",
        used: 312 * 1_073_741_824,
        total: 512 * 1_073_741_824,
        isBoot: true
    )
    sample.volumes = [sample.bootVolume!]
    sample.network = NetworkSample(
        connected: true,
        kind: "Wi-Fi",
        interfaceName: "en0",
        ssid: "Studio",
        ipAddress: "192.168.1.42",
        bytesInPerSecond: 1_250_000,
        bytesOutPerSecond: 42_000,
        ratesReady: true
    )
    sample.topProcesses = [
        ProcessUsage(pid: 1, name: "Cursor", cpuPercent: 18, ramBytes: 2_200_000_000),
        ProcessUsage(pid: 2, name: "Safari", cpuPercent: 6, ramBytes: 1_100_000_000),
        ProcessUsage(pid: 3, name: "WindowServer", cpuPercent: 4, ramBytes: 480_000_000)
    ]
    return sample
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
    // Home has 4 tiles per tab (last stagger 0.3s + 0.3s). This Mac processes go to index 10.
    RunLoop.current.run(until: Date().addingTimeInterval(1.8))

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
