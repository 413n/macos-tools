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

            Text(presentation.route.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if presentation.route != .settings {
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
        case .settings:
            SettingsDetail()
        }
    }
}

private struct HomeGrid: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presentation: PanelPresentation

    private let columns = [
        GridItem(.flexible(), spacing: Radius.grid),
        GridItem(.flexible(), spacing: Radius.grid)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Radius.grid) {
            ToolTile(
                title: "Keyboard",
                status: model.keyboardLocked ? "On" : "Off",
                isOn: model.keyboardLocked,
                isBusy: model.keyboardBusy,
                outline: "lock",
                fill: "lock.fill",
                accent: ModuleColor.keyboard,
                opticalNudge: CGSize(width: 0.5, height: 0)
            ) {
                presentation.open(.keyboard)
            }
            .stagger(index: 0, generation: presentation.generation)

            ToolTile(
                title: "Scroll",
                status: model.scrollReverseEnabled ? "On" : "Off",
                isOn: model.scrollReverseEnabled,
                outline: "computermouse",
                fill: "computermouse.fill",
                accent: ModuleColor.scroll
            ) {
                presentation.open(.scroll)
            }
            .stagger(index: 1, generation: presentation.generation)

            ToolTile(
                title: "Lid Sleep",
                status: model.lidSleepDisabled ? "On" : "Off",
                isOn: model.lidSleepDisabled,
                isBusy: model.lidBusy,
                outline: "moon.zzz",
                fill: "moon.zzz.fill",
                accent: ModuleColor.lid
            ) {
                presentation.open(.lid)
            }
            .stagger(index: 2, generation: presentation.generation)

            ToolTile(
                title: "Awake",
                status: model.awakeTileStatus,
                isOn: model.awakeActive,
                outline: "cup.and.saucer",
                fill: "cup.and.saucer.fill",
                accent: ModuleColor.awake
            ) {
                presentation.open(.awake)
            }
            .stagger(index: 3, generation: presentation.generation)

            MacStatsTile()
                .stagger(index: 4, generation: presentation.generation)
        }
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                StateSymbol(
                    outline: outline,
                    fill: fill,
                    isActive: isOn,
                    size: 18,
                    opticalNudge: opticalNudge
                )
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
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .fill(isOn ? accent : ModuleColor.offFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isBusy ? "Working, \(status)" : status)
        .animation(Motion.enter, value: isOn)
    }
}

private struct MacStatsTile: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var presentation: PanelPresentation

    var body: some View {
        Button {
            presentation.open(.machine)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                StateSymbol(
                    outline: "cpu",
                    fill: "cpu.fill",
                    isActive: false,
                    size: 18
                )
                Spacer(minLength: 6)
                Text("This Mac")
                    .font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    metric(label: "CPU", value: model.cpuPercentLabel, level: model.cpuUsageLevel)
                    metric(label: "RAM", value: model.ramShortLabel, level: model.ramUsageLevel)
                }
                .padding(.top, 3)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .aspectRatio(1, contentMode: .fit)
            .padding(Radius.tilePadding)
            .background(
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .fill(ModuleColor.offFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This Mac")
        .accessibilityValue("CPU \(model.cpuPercentLabel), RAM \(model.ramShortLabel)")
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
                .minimumScaleFactor(0.8)
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

            if model.scrollReverseEnabled && !model.accessibilityTrusted {
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
        GroupedPanel {
            MeterRow(
                label: "CPU",
                value: model.cpuPercentLabel,
                fraction: model.cpuReady ? model.cpuFraction : 0
            )
            .stagger(index: 0, generation: presentation.generation)

            MeterRow(
                label: "Memory",
                value: model.ramShortLabel,
                fraction: model.ramFraction
            )
            .stagger(index: 1, generation: presentation.generation)
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
                        Text("Keep NAF Tools in the menu bar")
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
                .stagger(index: 1, generation: presentation.generation)

                if let notice = model.statusCheckNotice {
                    Text(notice)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Quit NAF Tools") {
                model.quit()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
            .stagger(index: 2, generation: presentation.generation)
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
        NarcisoN()
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var level: UsageLevel { UsageLevel(fraction: fraction) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .regular).monospacedDigit())
                    .foregroundStyle(level.tint ?? Color.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(level.tint ?? Color.accentColor)
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 4)
        }
        .animation(reduceMotion ? nil : Motion.press, value: fraction)
        .animation(reduceMotion ? nil : Motion.press, value: level)
    }
}
