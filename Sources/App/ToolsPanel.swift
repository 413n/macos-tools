import SwiftUI

struct ToolsPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presentation: PanelPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            screen
                .id(presentation.route)
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : Motion.enterOffset)))
        }
        .animation(reduceMotion ? nil : Motion.enter, value: presentation.route)
        .animation(reduceMotion ? nil : Motion.enter, value: presentation.isEditingHome)
        .padding(Radius.panelPadding)
        .frame(width: 300)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            if presentation.route == .home {
                LogoMark()
            } else {
                ChromeButton(
                    systemName: "chevron.left",
                    label: "Back",
                    opticalNudge: CGSize(width: -0.5, height: 0)
                ) {
                    presentation.back()
                }
            }

            if presentation.route == .home, !presentation.isEditingHome {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Brand.studio)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(Brand.product)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .lineLimit(1)
            } else {
                Text(presentation.isEditingHome ? "Edit" : presentation.route.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if presentation.route == .home, !presentation.isEditingHome {
                Text(model.appVersion)
                    .font(.system(size: 11, weight: .regular).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if presentation.route == .home {
                if presentation.isEditingHome {
                    ChromeButton(systemName: "checkmark", label: "Done") {
                        presentation.isEditingHome = false
                    }
                } else {
                    ChromeButton(systemName: "pencil", label: "Edit Home") {
                        presentation.isEditingHome = true
                    }
                    ChromeButton(systemName: "gearshape", label: "Settings") {
                        presentation.open(.settings)
                    }
                }
            } else if presentation.route != .settings {
                ChromeButton(systemName: "gearshape", label: "Settings") {
                    presentation.open(.settings)
                }
            }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch presentation.route {
        case .home:
            HomeGrid()
        case .keyboard:
            KeyboardDetail()
        case .scroll:
            ScrollDetail()
        case .lid:
            LidDetail()
        case .awake:
            AwakeDetail()
        case .machine:
            MachineDetail()
        case .battery:
            BatteryDetail()
        case .network:
            NetworkDetail()
        case .storage:
            StorageDetail()
        case .settings:
            SettingsDetail()
        }
    }
}

private struct HomeGrid: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presentation: PanelPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragging: HomeTool?
    @State private var dragTranslation: CGSize = .zero
    @State private var dragStartFrame: CGRect = .zero
    @State private var gridWidth: CGFloat = 0
    @State private var lift = false
    @State private var settling = false

    private let columns = [
        GridItem(.flexible(), spacing: Radius.grid),
        GridItem(.flexible(), spacing: Radius.grid)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Radius.grid) {
            HomeTabBar(selection: $model.homeTab)

            if model.tabVisibleHomeTools.isEmpty {
                if !presentation.isEditingHome {
                    Text(model.homeTab.emptyLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            } else {
                tileGrid
            }

            if presentation.isEditingHome, !model.tabHiddenHomeTools.isEmpty {
                Text("Hidden")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                GroupedPanel {
                    ForEach(Array(model.tabHiddenHomeTools.enumerated()), id: \.element.id) { index, tool in
                        if index > 0 {
                            Divider()
                        }
                        HiddenToolRow(tool: tool) {
                            withAnimation(reduceMotion ? nil : Motion.enter) {
                                model.showHomeTool(tool)
                            }
                        }
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : Motion.enter, value: model.tabHiddenHomeTools)
        .animation(reduceMotion ? nil : Motion.enter, value: presentation.isEditingHome)
        .animation(reduceMotion ? nil : Motion.enter, value: model.homeTab)
        .onChange(of: presentation.isEditingHome) { _, editing in
            if !editing {
                cancelDrag()
            }
        }
        .onChange(of: model.homeTab) { _, _ in
            cancelDrag()
            presentation.generation += 1
        }
    }

    private var tileGrid: some View {
        LazyVGrid(columns: columns, spacing: Radius.grid) {
            ForEach(Array(model.tabVisibleHomeTools.enumerated()), id: \.element.id) { index, tool in
                visibleCell(tool)
                    .stagger(index: index, generation: presentation.generation)
            }
        }
        .coordinateSpace(name: "homeGrid")
        .contentShape(Rectangle())
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: HomeGridWidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(HomeGridWidthKey.self) { gridWidth = $0 }
        .overlay(alignment: .topLeading) {
            if let dragging {
                tile(for: dragging)
                    .frame(width: cellSize, height: cellSize)
                    .scaleEffect(lift && !reduceMotion ? Motion.hoverScale : 1)
                    .animation(reduceMotion ? nil : Motion.press, value: lift)
                    .offset(
                        x: dragStartFrame.minX + dragTranslation.width,
                        y: dragStartFrame.minY + dragTranslation.height
                    )
                    .animation(settling && !reduceMotion ? Motion.press : nil, value: dragTranslation)
                    .allowsHitTesting(false)
            }
        }
    }

    private func visibleCell(_ tool: HomeTool) -> some View {
        ZStack(alignment: .topTrailing) {
            if dragging == tool {
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .fill(ModuleColor.offFill)
                    .aspectRatio(1, contentMode: .fit)
            } else {
                tile(for: tool)
                    .allowsHitTesting(!presentation.isEditingHome)
            }

            if presentation.isEditingHome {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    .gesture(cellDrag(for: tool))
                    .help("Drag to reorder")
            }

            if presentation.isEditingHome, dragging != tool {
                VisibilityBadge(
                    symbol: "minus.circle.fill",
                    tint: .red,
                    label: "Hide \(tool.title)"
                ) {
                    cancelDrag()
                    withAnimation(reduceMotion ? nil : Motion.enter) {
                        model.hideHomeTool(tool)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tile(for tool: HomeTool) -> some View {
        switch tool {
        case .keyboard:
            ToolTile(
                title: tool.title,
                status: model.keyboardLocked ? "On" : "Off",
                isOn: model.keyboardLocked,
                isBusy: model.keyboardBusy,
                outline: tool.outline,
                fill: tool.fill,
                accent: tool.accent,
                opticalNudge: tool.opticalNudge,
                onToggle: { model.toggleKeyboard() },
                action: { presentation.open(.keyboard) }
            )
        case .scroll:
            ToolTile(
                title: tool.title,
                status: model.scrollReverseEnabled ? "On" : "Off",
                isOn: model.scrollReverseEnabled,
                outline: tool.outline,
                fill: tool.fill,
                accent: tool.accent,
                onToggle: { model.toggleScrollReverse() },
                action: { presentation.open(.scroll) }
            )
        case .lid:
            ToolTile(
                title: tool.title,
                status: model.lidSleepDisabled ? "On" : "Off",
                isOn: model.lidSleepDisabled,
                isBusy: model.lidBusy,
                outline: tool.outline,
                fill: tool.fill,
                accent: tool.accent,
                onToggle: { model.toggleLidSleep() },
                action: { presentation.open(.lid) }
            )
        case .awake:
            ToolTile(
                title: tool.title,
                status: model.awakeTileStatus,
                isOn: model.awakeActive,
                outline: tool.outline,
                fill: tool.fill,
                accent: tool.accent,
                onToggle: { model.toggleAwake() },
                action: { presentation.open(.awake) }
            )
        case .machine:
            InfoStatsTile(
                title: tool.title,
                outline: tool.outline,
                fill: tool.fill,
                route: .machine,
                lines: [
                    InfoMetric(label: "CPU", value: model.cpuPercentLabel, level: model.cpuUsageLevel),
                    InfoMetric(label: "RAM", value: model.ramShortLabel, level: model.ramUsageLevel)
                ],
                accessibilityValue: "CPU \(model.cpuPercentLabel), RAM \(model.ramShortLabel)"
            )
        case .battery:
            InfoStatsTile(
                title: tool.title,
                outline: tool.outline,
                fill: tool.fill,
                route: .battery,
                lines: [
                    InfoMetric(label: "Charge", value: model.batteryPercentLabel, level: model.batteryUsageLevel),
                    InfoMetric(label: "Status", value: model.stats.battery == nil ? "Desktop" : compactBatteryStatus, level: .normal)
                ],
                accessibilityValue: "\(model.batteryPercentLabel), \(model.batteryStatusLabel)"
            )
        case .network:
            InfoStatsTile(
                title: tool.title,
                outline: tool.outline,
                fill: tool.fill,
                route: .network,
                lines: [
                    InfoMetric(label: "Rate", value: model.networkPrimaryLabel, level: .normal),
                    InfoMetric(label: "Link", value: model.networkSecondaryLabel, level: .normal)
                ],
                accessibilityValue: "\(model.networkPrimaryLabel), \(model.networkSecondaryLabel)"
            )
        case .storage:
            InfoStatsTile(
                title: tool.title,
                outline: tool.outline,
                fill: tool.fill,
                route: .storage,
                lines: [
                    InfoMetric(label: "Free", value: model.diskFreeLabel, level: model.diskUsageLevel),
                    InfoMetric(label: "Used", value: model.diskUsedLabel, level: model.diskUsageLevel)
                ],
                accessibilityValue: "\(model.diskFreeLabel) free, \(model.diskUsedLabel) used"
            )
        }
    }

    private var compactBatteryStatus: String {
        guard let battery = model.stats.battery else { return "Desktop" }
        if battery.isFull { return "Full" }
        if battery.isCharging { return "Charging" }
        if let minutes = battery.minutesToEmpty {
            return StatsFormat.durationMinutes(minutes)
        }
        return battery.isPluggedIn ? "Plugged in" : "On battery"
    }

    private func cellDrag(for tool: HomeTool) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("homeGrid"))
            .onChanged { value in
                handleDragChanged(value, tool: tool)
            }
            .onEnded { _ in
                if dragging == tool {
                    handleDragEnded()
                }
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value, tool: HomeTool) {
        guard presentation.isEditingHome, !settling else { return }

        if dragging == nil {
            dragging = tool
            if let index = model.tabVisibleHomeTools.firstIndex(of: tool) {
                dragStartFrame = slotFrame(index: index)
            }
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) {
                dragTranslation = value.translation
            }
            withAnimation(reduceMotion ? nil : Motion.press) {
                lift = true
            }
            return
        }

        guard dragging == tool else { return }

        var follow = Transaction()
        follow.disablesAnimations = true
        withTransaction(follow) {
            dragTranslation = value.translation
        }
        guard let current = model.tabVisibleHomeTools.firstIndex(of: tool) else { return }
        let center = CGPoint(
            x: dragStartFrame.midX + value.translation.width,
            y: dragStartFrame.midY + value.translation.height
        )
        let target = slotIndex(at: center, current: current)
        guard current != target else { return }
        withAnimation(reduceMotion ? nil : Motion.press) {
            model.moveVisibleHomeTool(tool, to: target)
        }
    }

    private func handleDragEnded() {
        guard let tool = dragging else { return }
        settling = true
        let destination: CGRect = {
            if let index = model.tabVisibleHomeTools.firstIndex(of: tool) {
                return slotFrame(index: index)
            }
            return dragStartFrame
        }()
        let translation = CGSize(
            width: destination.minX - dragStartFrame.minX,
            height: destination.minY - dragStartFrame.minY
        )
        withAnimation(reduceMotion ? nil : Motion.press) {
            dragTranslation = translation
            lift = false
        } completion: {
            cancelDrag()
        }
    }

    private func cancelDrag() {
        dragging = nil
        dragTranslation = .zero
        dragStartFrame = .zero
        lift = false
        settling = false
    }

    private var cellSize: CGFloat {
        let width = gridWidth > 0 ? gridWidth : 272
        return (width - Radius.grid) / 2
    }

    private func slotFrame(index: Int) -> CGRect {
        let cell = cellSize
        let gap = Radius.grid
        let col = CGFloat(index % 2)
        let row = CGFloat(index / 2)
        return CGRect(
            x: col * (cell + gap),
            y: row * (cell + gap),
            width: cell,
            height: cell
        )
    }

    private func slotIndex(at point: CGPoint, current: Int) -> Int {
        let count = model.tabVisibleHomeTools.count
        guard count > 0 else { return 0 }
        let cell = cellSize
        let gap = Radius.grid
        let stride = cell + gap
        guard stride > 0 else { return 0 }
        let col = point.x < cell + gap / 2 ? 0 : 1
        let row = Int(floor(max(0, point.y) / stride))
        let proposed = min(count - 1, max(0, row * 2 + col))
        if proposed == current { return current }
        let inset = cell * 0.2
        guard slotFrame(index: proposed).insetBy(dx: inset, dy: inset).contains(point) else {
            return current
        }
        return proposed
    }
}

private struct HomeTabBar: View {
    @Binding var selection: HomeTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(HomeTab.allCases) { tab in
                let selected = selection == tab
                Button {
                    selection = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? ModuleColor.glyphOffFill : Color.clear)
                        }
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(ModuleColor.groupFill)
        )
        .animation(reduceMotion ? nil : Motion.press, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Home")
    }
}

private struct HomeGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct VisibilityBadge: View {
    let symbol: String
    let tint: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, tint)
                .font(.system(size: 16, weight: .semibold))
                .padding(6)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(label)
    }
}

private struct HiddenToolRow: View {
    let tool: HomeTool
    let onShow: () -> Void

    var body: some View {
        Button(action: onShow) {
            HStack(spacing: 10) {
                Image(systemName: tool.outline)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: Radius.chrome, height: Radius.chrome)
                    .background(ModuleColor.offFill, in: Circle())
                    .accessibilityHidden(true)
                Text(tool.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "plus.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.green)
                    .font(.system(size: 16, weight: .semibold))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel("Show \(tool.title)")
    }
}

private struct ToolTile: View {
    let title: String
    let status: String
    let isOn: Bool
    var isBusy: Bool = false
    let outline: String
    let fill: String
    let accent: Color
    var opticalNudge: CGSize = .zero
    let onToggle: () -> Void
    let action: () -> Void

    @State private var ignoreOpen = false
    @State private var cardHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: openDetail) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(width: Radius.glyph, height: Radius.glyph)
                    Spacer(minLength: 6)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Group {
                        if isBusy {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(isOn ? .white : .secondary)
                                .padding(.top, 3)
                        } else {
                            Text(status)
                                .font(.system(size: 11, weight: .regular))
                                .monospacedDigit()
                                .opacity(0.8)
                                .padding(.top, 1)
                        }
                    }
                }
                .foregroundStyle(isOn ? .white : .primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .aspectRatio(1, contentMode: .fit)
                .padding(Radius.tilePadding)
                .background(
                    TileBackdrop(isOn: isOn, hovering: cardHovering, accent: accent)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            }
            .buttonStyle(PressScaleButtonStyle())
            .onHover { cardHovering = $0 }
            .animation(reduceMotion ? nil : Motion.hover, value: cardHovering)
            .help("Show \(title) options")
            .accessibilityLabel(title)
            .accessibilityValue(isBusy ? "Working, \(status)" : status)
            .accessibilityHint("Shows options")

            Button(action: toggleNow) {
                GlyphCircle(
                    outline: outline,
                    fill: fill,
                    isOn: isOn,
                    opticalNudge: opticalNudge
                )
            }
            .buttonStyle(PressScaleButtonStyle())
            .contentShape(Circle())
            .disabled(isBusy)
            .opacity(isBusy ? 0.45 : 1)
            .padding(Radius.tilePadding)
            .zIndex(1)
            .help(isOn ? "Turn \(title) off" : "Turn \(title) on")
            .accessibilityLabel(title)
            .accessibilityValue(isBusy ? "Working, \(status)" : status)
            .accessibilityHint(isOn ? "Turns off" : "Turns on")
        }
        .animation(Motion.enter, value: isOn)
    }

    private func toggleNow() {
        ignoreOpen = true
        onToggle()
        DispatchQueue.main.async {
            ignoreOpen = false
        }
    }

    private func openDetail() {
        guard !ignoreOpen else { return }
        action()
    }
}

private struct InfoMetric {
    var label: String
    var value: String
    var level: UsageLevel
}

private struct InfoStatsTile: View {
    @EnvironmentObject private var presentation: PanelPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    let title: String
    let outline: String
    let fill: String
    let route: PanelRoute
    let lines: [InfoMetric]
    let accessibilityValue: String

    var body: some View {
        Button {
            presentation.open(route)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                GlyphCircle(
                    outline: outline,
                    fill: fill,
                    isOn: false
                )
                Spacer(minLength: 6)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        metric(label: line.label, value: line.value, level: line.level)
                    }
                }
                .padding(.top, 3)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .aspectRatio(1, contentMode: .fit)
            .padding(Radius.tilePadding)
            .background(
                TileBackdrop(isOn: false, hovering: hovering)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : Motion.hover, value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private func metric(label: String, value: String, level: UsageLevel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .regular).monospacedDigit())
                .foregroundStyle(level.tint ?? Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .animation(Motion.press, value: level)
        }
    }
}

private struct KeyboardDetail: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presentation: PanelPresentation

    var body: some View {
        GroupedPanel {
            HStack(alignment: .center, spacing: 10) {
                StateSymbol(
                    outline: "lock",
                    fill: "lock.fill",
                    isActive: model.keyboardLocked,
                    opticalNudge: CGSize(width: 0.5, height: 0)
                )
                .foregroundStyle(model.keyboardLocked ? ModuleColor.keyboard : .primary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Built-in keyboard")
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.keyboardStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    if model.keyboardBusy {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(model.keyboardLocked ? "Locking" : "Unlocking")
                    }
                    Toggle(
                        "Keyboard lock",
                        isOn: Binding(
                            get: { model.keyboardLocked },
                            set: { model.setKeyboardLocked($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(model.keyboardBusy)
                    .opacity(model.keyboardBusy ? 0.45 : 1)
                }
            }
            .stagger(index: 0, generation: presentation.generation)

            Divider()

            HStack {
                Text("Auto-unlock")
                    .font(.system(size: 13))
                Spacer()
                Picker("Auto-unlock", selection: $model.autoUnlockMinutes) {
                    Text("Off").tag(0)
                    ForEach(model.timeoutChoices.filter { $0 > 0 }, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .disabled(model.keyboardBusy)
            }
            .stagger(index: 1, generation: presentation.generation)

            HStack {
                Text("Lights off")
                    .font(.system(size: 13))
                Spacer()
                Toggle(
                    "Lights off",
                    isOn: Binding(
                        get: { model.dimKeyboardWhenLocked },
                        set: { model.setDimKeyboardWhenLocked($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(model.keyboardBusy)
            }
            .stagger(index: 2, generation: presentation.generation)

            if model.keyboardLocked {
                Button("Unlock now") {
                    model.setKeyboardLocked(false)
                }
                .controlSize(.small)
                .disabled(model.keyboardBusy)
            }

            if let error = model.keyboardError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ScrollDetail: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presentation: PanelPresentation

    var body: some View {
        GroupedPanel {
            HStack(alignment: .center, spacing: 10) {
                StateSymbol(
                    outline: "computermouse",
                    fill: "computermouse.fill",
                    isActive: model.scrollReverseEnabled
                )
                .foregroundStyle(model.scrollReverseEnabled ? ModuleColor.scroll : .primary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Mouse scroll")
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.scrollStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle(
                    "Mouse scroll",
                    isOn: Binding(
                        get: { model.scrollReverseEnabled },
                        set: { model.setScrollReverseEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
            .stagger(index: 0, generation: presentation.generation)

            Divider()

            if model.mice.isEmpty {
                Text("No mouse connected")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .stagger(index: 1, generation: presentation.generation)
            } else {
                ForEach(Array(model.mice.enumerated()), id: \.element.id) { index, mouse in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mouse.name)
                                .font(.system(size: 13))
                                .lineLimit(1)
                            Text("Reverse scroll")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Toggle("Reverse scroll", isOn: model.scrollReverseBinding(for: mouse.id))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                    .stagger(index: index + 1, generation: presentation.generation)
                }
            }

            if model.scrollReverseEnabled
                && !model.accessibilityTrusted
                && model.mice.contains(where: { model.isScrollReverseOn(for: $0.id) }) {
                Button("Allow Settings") {
                    AccessibilityAuth.requestIfNeeded()
                    model.openAccessibilitySettings()
                    model.refreshAccessibility()
                }
                .controlSize(.small)
            }
        }
    }
}

private struct LidDetail: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presentation: PanelPresentation

    var body: some View {
        GroupedPanel {
            HStack(alignment: .center, spacing: 10) {
                StateSymbol(
                    outline: "moon.zzz",
                    fill: "moon.zzz.fill",
                    isActive: model.lidSleepDisabled
                )
                .foregroundStyle(model.lidSleepDisabled ? ModuleColor.lid : .primary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Stay awake")
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.lidStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    if model.lidBusy {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(model.lidSleepDisabled ? "Turning on" : "Turning off")
                    }
                    Toggle(
                        "Stay awake",
                        isOn: Binding(
                            get: { model.lidSleepDisabled },
                            set: { model.setLidSleepDisabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(model.lidBusy)
                    .opacity(model.lidBusy ? 0.45 : 1)
                }
            }
            .stagger(index: 0, generation: presentation.generation)

            if let error = model.lidError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AwakeDetail: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presentation: PanelPresentation

    var body: some View {
        GroupedPanel {
            HStack(alignment: .center, spacing: 10) {
                StateSymbol(
                    outline: "cup.and.saucer",
                    fill: "cup.and.saucer.fill",
                    isActive: model.awakeActive
                )
                .foregroundStyle(model.awakeActive ? ModuleColor.awake : .primary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Prevent sleep")
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.awakeStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle(
                    "Prevent sleep",
                    isOn: Binding(
                        get: { model.awakeActive },
                        set: { model.setAwakeActive($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
            .stagger(index: 0, generation: presentation.generation)

            Divider()

            HStack {
                Text("Activate for")
                    .font(.system(size: 13))
                Spacer()
                Picker("Activate for", selection: $model.awakeMinutes) {
                    ForEach(model.awakeDurationChoices, id: \.self) { minutes in
                        Text(AppModel.awakeDurationLabel(minutes)).tag(minutes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
            }
            .stagger(index: 1, generation: presentation.generation)

            if let error = model.awakeError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct MachineDetail: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presentation: PanelPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupedPanel {
                MeterRow(
                    label: "CPU",
                    value: model.cpuPercentLabel,
                    fraction: model.stats.cpuReady ? model.stats.cpuFraction : 0,
                    level: model.cpuUsageLevel
                )
                .stagger(index: 0, generation: presentation.generation)

                if model.stats.cpuHistory.count > 1 {
                    Sparkline(values: model.stats.cpuHistory)
                        .stagger(index: 1, generation: presentation.generation)
                }

                MeterRow(
                    label: "Memory",
                    value: model.ramShortLabel,
                    fraction: model.ramFraction,
                    level: model.ramUsageLevel
                )
                .stagger(index: 2, generation: presentation.generation)

                StatRow(label: "Pressure", value: model.stats.memoryPressure.label, level: model.memoryPressureLevel)
                    .stagger(index: 3, generation: presentation.generation)

                if model.stats.swapTotal > 0 {
                    StatRow(
                        label: "Swap",
                        value: "\(StatsFormat.gigabytes(model.stats.swapUsed)) / \(StatsFormat.gigabytes(model.stats.swapTotal))"
                    )
                    .stagger(index: 4, generation: presentation.generation)
                }

                StatRow(label: "Thermal", value: StatsFormat.thermal(model.stats.thermal), level: model.thermalLevel)
                    .stagger(index: 5, generation: presentation.generation)

                StatRow(label: "Up", value: StatsFormat.uptime(model.stats.uptimeSeconds))
                    .stagger(index: 6, generation: presentation.generation)
            }

            if !model.stats.topProcesses.isEmpty {
                GroupedPanel {
                    Text("Top processes")
                        .font(.system(size: 12, weight: .semibold))
                        .stagger(index: 7, generation: presentation.generation)
                    ForEach(Array(model.stats.topProcesses.enumerated()), id: \.element.id) { index, process in
                        ProcessRow(process: process)
                            .stagger(index: 8 + index, generation: presentation.generation)
                    }
                }
            }
        }
    }
}

private struct BatteryDetail: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presentation: PanelPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupedPanel {
                if let battery = model.stats.battery {
                    MeterRow(
                        label: "Charge",
                        value: model.batteryPercentLabel,
                        fraction: battery.percent,
                        level: model.batteryUsageLevel
                    )
                    .stagger(index: 0, generation: presentation.generation)

                    StatRow(label: "Status", value: model.batteryStatusLabel)
                        .stagger(index: 1, generation: presentation.generation)

                    if let health = battery.health, !health.isEmpty {
                        StatRow(label: "Health", value: health)
                            .stagger(index: 2, generation: presentation.generation)
                    }
                    if let cycles = battery.cycleCount {
                        StatRow(label: "Cycles", value: "\(cycles)")
                            .stagger(index: 3, generation: presentation.generation)
                    }
                } else {
                    Text("This Mac has no battery")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .stagger(index: 0, generation: presentation.generation)
                }
            }

            if !model.stats.accessories.isEmpty {
                GroupedPanel {
                    Text("Accessories")
                        .font(.system(size: 12, weight: .semibold))
                        .stagger(index: 4, generation: presentation.generation)
                    ForEach(Array(model.stats.accessories.enumerated()), id: \.element.id) { index, accessory in
                        StatRow(
                            label: accessory.name,
                            value: "\(accessory.percent)%",
                            level: .remaining(Double(accessory.percent) / 100)
                        )
                        .stagger(index: 5 + index, generation: presentation.generation)
                    }
                }
            }
        }
    }
}

private struct NetworkDetail: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presentation: PanelPresentation

    var body: some View {
        GroupedPanel {
            StatRow(label: "Link", value: model.stats.network.connected ? model.stats.network.kind : "Offline")
                .stagger(index: 0, generation: presentation.generation)

            if let ssid = model.stats.network.ssid {
                StatRow(label: "Wi-Fi", value: ssid)
                    .stagger(index: 1, generation: presentation.generation)
            }
            if let ip = model.stats.network.ipAddress {
                StatRow(label: "IP", value: ip)
                    .stagger(index: 2, generation: presentation.generation)
            }

            StatRow(
                label: "Down",
                value: model.stats.network.ratesReady
                    ? StatsFormat.rate(model.stats.network.bytesInPerSecond, compact: false)
                    : "…"
            )
            .stagger(index: 3, generation: presentation.generation)

            StatRow(
                label: "Up",
                value: model.stats.network.ratesReady
                    ? StatsFormat.rate(model.stats.network.bytesOutPerSecond, compact: false)
                    : "…"
            )
            .stagger(index: 4, generation: presentation.generation)
        }
    }
}

private struct StorageDetail: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presentation: PanelPresentation

    var body: some View {
        let volumes = model.stats.volumes.isEmpty
            ? model.stats.bootVolume.map { [$0] } ?? []
            : model.stats.volumes
        return GroupedPanel {
            if volumes.isEmpty {
                Text("No disks")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .stagger(index: 0, generation: presentation.generation)
            } else {
                ForEach(Array(volumes.enumerated()), id: \.element.id) { index, volume in
                    MeterRow(
                        label: volume.name,
                        value: "\(StatsFormat.gigabytes(volume.free)) free",
                        fraction: volume.usedFraction,
                        level: UsageLevel(fraction: volume.usedFraction)
                    )
                    .stagger(index: index, generation: presentation.generation)
                }
            }
        }
    }
}

private struct SettingsDetail: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presentation: PanelPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupedPanel {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Open at login")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Keep Yeobun in the menu bar")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Toggle("Open at login", isOn: $model.launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                .stagger(index: 0, generation: presentation.generation)

                if let notice = model.loginItemNotice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GroupedPanel {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Menu bar")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Preview of tools that are on")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Picker("Menu bar", selection: $model.menuBarDisplay) {
                        ForEach(MenuBarDisplay.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
                .stagger(index: 1, generation: presentation.generation)

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Menu bar stats")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Glance next to the logo")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Picker("Menu bar stats", selection: $model.menuBarStats) {
                        ForEach(MenuBarStats.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
                .stagger(index: 2, generation: presentation.generation)
            }

            GroupedPanel {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Check status")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Read each tool from this Mac")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if model.statusCheckBusy {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Checking status")
                    }
                    Button("Check") {
                        model.checkStatus()
                    }
                    .controlSize(.small)
                    .disabled(model.statusCheckBusy || model.keyboardBusy || model.lidBusy)
                }
                .stagger(index: 3, generation: presentation.generation)

                if let notice = model.statusCheckNotice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GroupedPanel {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Version")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(Brand.studio) · \(model.appVersion)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if model.updateCheckBusy {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Checking for updates")
                    }
                    Button("Check") {
                        model.checkLatestVersion()
                    }
                    .controlSize(.small)
                    .disabled(model.updateCheckBusy)
                    .accessibilityLabel("Check latest version")
                    if model.newerVersion != nil {
                        Button("Open") {
                            model.openLatestRelease()
                        }
                        .controlSize(.small)
                        .accessibilityLabel("Open latest release")
                    }
                }
                .stagger(index: 4, generation: presentation.generation)

                if let notice = model.updateCheckNotice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Quit Yeobun") {
                model.quit()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
            .stagger(index: 5, generation: presentation.generation)
        }
    }
}

private struct GroupedPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(Radius.groupPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
                .fill(ModuleColor.groupFill)
        )
    }
}

private struct LogoMark: View {
    var body: some View {
        YeobunN()
            .fill(.primary)
            .frame(width: 14, height: 14)
            .frame(width: Radius.chrome, height: Radius.chrome)
            .background(ModuleColor.offFill, in: Circle())
            .accessibilityHidden(true)
    }
}

private struct MeterRow: View {
    let label: String
    let value: String
    let fraction: Double
    var level: UsageLevel? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resolvedLevel: UsageLevel { level ?? UsageLevel(fraction: fraction) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .regular).monospacedDigit())
                    .foregroundStyle(resolvedLevel.tint ?? Color.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(resolvedLevel.tint ?? Color.accentColor)
                        .frame(width: max(4, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
            .frame(height: 4)
        }
        .animation(reduceMotion ? nil : Motion.press, value: fraction)
        .animation(reduceMotion ? nil : Motion.press, value: resolvedLevel)
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    var level: UsageLevel = .normal

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .regular).monospacedDigit())
                .foregroundStyle(level.tint ?? Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct ProcessRow: View {
    let process: ProcessUsage

    var body: some View {
        HStack(spacing: 8) {
            Text(process.name)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(String(format: "%.0f%%", process.cpuPercent))
                .font(.system(size: 11, weight: .regular).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            Text(StatsFormat.bytes(process.ramBytes))
                .font(.system(size: 11, weight: .regular).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }
}

private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 1, 0.05)
            Path { path in
                guard values.count > 1, geo.size.width > 0 else { return }
                for (index, value) in values.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(values.count - 1)
                    let y = geo.size.height * (1 - CGFloat(min(max(value / maxValue, 0), 1)))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 28)
        .accessibilityHidden(true)
    }
}
