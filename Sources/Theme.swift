import SwiftUI

final class PanelPresentation: ObservableObject {
    @Published var generation = 0
    @Published var route: PanelRoute = .home

    func menuDidOpen() {
        generation += 1
    }

    func menuDidClose() {
        route = .home
        generation = 0
    }

    func open(_ route: PanelRoute) {
        self.route = route
        generation += 1
    }

    func back() {
        route = .home
        generation += 1
    }
}

enum PanelRoute: Equatable {
    case home
    case keyboard
    case scroll
    case lid
    case awake
    case machine
    case settings

    var title: String {
        switch self {
        case .home: "NAF Tools"
        case .keyboard: "Keyboard"
        case .scroll: "Scroll"
        case .lid: "Lid Sleep"
        case .awake: "Awake"
        case .machine: "This Mac"
        case .settings: "Settings"
        }
    }
}

enum Motion {
    static let enter = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.3)
    static let press = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.15)
    static let icon = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.3)
    static let stagger: TimeInterval = 0.1
    static let enterOffset: CGFloat = 8
    static let pressScale: CGFloat = 0.96
    static let iconFromScale: CGFloat = 0.25
    static let iconBlur: CGFloat = 4
}

enum Radius {
    static let tile: CGFloat = 16
    static let tilePadding: CGFloat = 12
    static let group: CGFloat = 16
    static let groupPadding: CGFloat = 14
    static let panelPadding: CGFloat = 14
    static let grid: CGFloat = 10
    static let chrome: CGFloat = 28
}

enum ModuleColor {
    static let keyboard = Color.orange
    static let scroll = Color.accentColor
    static let lid = Color.purple
    static let awake = Color.brown
    static let machine = Color.secondary
    static let offFill = Color.primary.opacity(0.08)
    static let groupFill = Color.primary.opacity(0.06)
    static let usageWarning = Color.orange
    static let usageCritical = Color.red
}

enum UsageLevel: Equatable {
    case normal
    case warning
    case critical

    static let warningAt: Double = 0.70
    static let criticalAt: Double = 0.90

    init(fraction: Double) {
        if fraction >= Self.criticalAt {
            self = .critical
        } else if fraction >= Self.warningAt {
            self = .warning
        } else {
            self = .normal
        }
    }

    var tint: Color? {
        switch self {
        case .normal: nil
        case .warning: ModuleColor.usageWarning
        case .critical: ModuleColor.usageCritical
        }
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    var isStatic = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isStatic || !configuration.isPressed ? 1 : Motion.pressScale)
            .animation(isStatic ? nil : Motion.press, value: configuration.isPressed)
    }
}

struct ChromeButton: View {
    let systemName: String
    let label: String
    var opticalNudge: CGSize = .zero
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .offset(opticalNudge)
                .foregroundStyle(.primary)
                .frame(width: Radius.chrome, height: Radius.chrome)
                .background(ModuleColor.offFill, in: Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(label)
    }
}

struct StateSymbol: View {
    let outline: String
    let fill: String
    let isActive: Bool
    var size: CGFloat = 20
    var opticalNudge: CGSize = .zero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            symbol(outline, shown: !isActive, weight: .regular)
                .offset(opticalNudge)
            symbol(fill, shown: isActive, weight: .semibold)
        }
        .frame(width: size + 4, height: size + 4)
        .accessibilityHidden(true)
    }

    private func symbol(_ name: String, shown: Bool, weight: Font.Weight) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : Motion.iconFromScale)
            .blur(radius: reduceMotion || shown ? 0 : Motion.iconBlur)
            .animation(reduceMotion ? nil : Motion.icon, value: shown)
    }
}

struct StaggeredEntrance: ViewModifier {
    let index: Int
    let generation: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var played = 0

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : Motion.enterOffset)
            .onAppear { sync() }
            .onChange(of: generation) { _, _ in
                sync()
            }
    }

    private func sync() {
        if generation == 0 {
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) {
                shown = false
                played = 0
            }
            return
        }
        replay()
    }

    private func replay() {
        guard generation != played else { return }
        played = generation
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) { shown = false }
        if reduceMotion {
            shown = true
            return
        }
        withAnimation(Motion.enter.delay(Double(index) * Motion.stagger)) {
            shown = true
        }
    }
}

extension View {
    func stagger(index: Int, generation: Int) -> some View {
        modifier(StaggeredEntrance(index: index, generation: generation))
    }
}
