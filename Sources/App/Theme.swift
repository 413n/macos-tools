import AppKit
import SwiftUI

final class PanelPresentation: ObservableObject {
    @Published var generation = 0
    @Published var route: PanelRoute = .home
    @Published var isEditingHome = false

    func menuDidOpen() {
        generation += 1
    }

    func menuDidClose() {
        route = .home
        isEditingHome = false
        generation = 0
    }

    func open(_ route: PanelRoute) {
        isEditingHome = false
        self.route = route
        generation += 1
    }

    func back() {
        isEditingHome = false
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

enum HomeTool: String, CaseIterable, Identifiable {
    case keyboard
    case scroll
    case lid
    case awake
    case machine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keyboard: "Keyboard"
        case .scroll: "Scroll"
        case .lid: "Lid Sleep"
        case .awake: "Awake"
        case .machine: "This Mac"
        }
    }

    var outline: String {
        switch self {
        case .keyboard: "lock"
        case .scroll: "computermouse"
        case .lid: "moon.zzz"
        case .awake: "cup.and.saucer"
        case .machine: "cpu"
        }
    }

    var fill: String {
        switch self {
        case .keyboard: "lock.fill"
        case .scroll: "computermouse.fill"
        case .lid: "moon.zzz.fill"
        case .awake: "cup.and.saucer.fill"
        case .machine: "cpu.fill"
        }
    }

    var accent: Color {
        switch self {
        case .keyboard: ModuleColor.keyboard
        case .scroll: ModuleColor.scroll
        case .lid: ModuleColor.lid
        case .awake: ModuleColor.awake
        case .machine: ModuleColor.machine
        }
    }

    var opticalNudge: CGSize {
        switch self {
        case .keyboard: CGSize(width: 0.5, height: 0)
        default: .zero
        }
    }

    var route: PanelRoute {
        switch self {
        case .keyboard: .keyboard
        case .scroll: .scroll
        case .lid: .lid
        case .awake: .awake
        case .machine: .machine
        }
    }
}

enum Motion {
    static let enter = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.3)
    static let press = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.15)
    static let hover = press
    static let icon = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.3)
    static let stagger: TimeInterval = 0.1
    static let enterOffset: CGFloat = 8
    static let pressScale: CGFloat = 0.96
    static let hoverScale: CGFloat = 1.06
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
    static let glyph: CGFloat = 30
}

enum ModuleColor {
    static let keyboard = Color.orange
    static let scroll = Color.accentColor
    static let lid = Color.purple
    static let awake = Color.brown
    static let machine = Color.secondary
    static let offFill = Color.primary.opacity(0.08)
    static let offFillHover = Color.primary.opacity(0.13)
    static let glyphOffFill = Color.primary.opacity(0.14)
    static let glyphOffFillHover = Color.primary.opacity(0.22)
    static let glyphOnFill = Color.white.opacity(0.22)
    static let glyphOnFillHover = Color.white.opacity(0.36)
    static let onHoverWash = Color.white.opacity(0.14)
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
        PressScaleButtonBody(configuration: configuration, isStatic: isStatic)
    }
}

private struct PressScaleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    var isStatic: Bool
    @State private var cursorPushed = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .scaleEffect(isStatic || !configuration.isPressed ? 1 : Motion.pressScale)
            .animation(isStatic ? nil : Motion.press, value: configuration.isPressed)
            .onHover { inside in
                setCursor(inside && isEnabled && !isStatic)
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { setCursor(false) }
            }
            .onDisappear { setCursor(false) }
    }

    private func setCursor(_ on: Bool) {
        if on, !cursorPushed {
            NSCursor.pointingHand.push()
            cursorPushed = true
        } else if !on, cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}

struct TileBackdrop: View {
    var isOn: Bool
    var hovering: Bool
    var accent: Color = .clear

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
            .fill(isOn ? accent : (hovering ? ModuleColor.offFillHover : ModuleColor.offFill))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .fill(isOn && hovering ? ModuleColor.onHoverWash : Color.clear)
            }
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

struct GlyphCircle: View {
    let outline: String
    let fill: String
    let isOn: Bool
    var opticalNudge: CGSize = .zero

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StateSymbol(
            outline: outline,
            fill: fill,
            isActive: isOn,
            size: 14,
            opticalNudge: opticalNudge
        )
        .foregroundStyle(isOn ? .white : .primary)
        .frame(width: Radius.glyph, height: Radius.glyph)
        .background(glyphFill, in: Circle())
        .contentShape(Circle())
        .scaleEffect(reduceMotion || !hovering ? 1 : Motion.hoverScale)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : Motion.hover, value: hovering)
        .accessibilityHidden(true)
    }

    private var glyphFill: Color {
        if isOn {
            return hovering ? ModuleColor.glyphOnFillHover : ModuleColor.glyphOnFill
        }
        return hovering ? ModuleColor.glyphOffFillHover : ModuleColor.glyphOffFill
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
