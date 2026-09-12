// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import SwiftUI

private struct DPIStageTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct DPIStageDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct DPIStageSelection: Identifiable, Equatable {
    let index: Int

    var id: Int { index }
}

private struct PointerCursorModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        content.onHover { isHovering in
            guard isHovering else {
                NSCursor.arrow.set()
                return
            }
            (enabled ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }
}

private extension View {
    func pointerCursor(enabled: Bool = true) -> some View {
        modifier(PointerCursorModifier(enabled: enabled))
    }
}

private struct EscapeKeyMonitor: NSViewRepresentable {
    let onEscape: () -> Void

    final class Coordinator {
        var onEscape: () -> Void
        var monitor: Any?

        init(onEscape: @escaping () -> Void) {
            self.onEscape = onEscape
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                self?.onEscape()
                return nil
            }
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit { remove() }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onEscape: onEscape)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }
}

private struct DPIStageBar: View {
    let stages: [String]
    let defaultStage: Int
    let shiftStage: Int
    let capabilities: DPICapabilities
    let isLoading: Bool
    let onDragValue: (Int, Int) -> Void
    let onAdjust: (Int, DPICapabilities.AdjustmentDirection) -> Void
    let onTextChange: (Int, String) -> Void
    let onCommitText: (Int) -> Void
    let onSetDefault: (Int) -> Void
    let onSetShift: (Int) -> Void
    let onDelete: (Int) -> Void

    @State private var editingStage: DPIStageSelection?
    @State private var stageInteractionStart: TimeInterval?
    @State private var presentedStage: DPIStageSelection?
    @State private var fadingStage: DPIStageSelection?
    @State private var popoverContentOpacity = 1.0
    @FocusState private var focusedStageIndex: Int?

    private let clickDurationLimit: TimeInterval = 0.3
    private let stageSwitchDuration: TimeInterval = 0.08

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if editingStage != nil {
                    Rectangle()
                        .fill(Color.black.opacity(0.001))
                        .contentShape(Rectangle())
                        .onTapGesture { dismissStageEditor() }
                        .zIndex(1)
                    EscapeKeyMonitor(onEscape: dismissStageEditor)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                }

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.88), .purple.opacity(0.84)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 6)
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.12), lineWidth: 0.5)
                    }
                    .frame(width: max(proxy.size.width - 28, 1))
                    .position(x: proxy.size.width / 2, y: 55)

                ForEach(tickValues, id: \.self) { value in
                    Rectangle()
                        .fill(.secondary.opacity(0.52))
                        .frame(width: 1, height: 10)
                        .position(x: position(for: value, width: proxy.size.width), y: 55)
                }

                ForEach(Array(stages.enumerated()).filter { Int($0.element) != nil }, id: \.offset) { item in
                    stageHandle(index: item.offset, text: item.element, width: proxy.size.width)
                }

                ZStack {
                    HStack {
                        Text(capabilities.minimum.map(String.init) ?? "100")
                        Spacer()
                        Text(capabilities.maximum.map(String.init) ?? "65535")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: proxy.size.width)
                    dpiLegend
                }
                .position(x: proxy.size.width / 2, y: 105)

            }
            // Keep one bubble alive while moving between stages. Replacing
            // separate per-stage popovers was the source of the occasional
            // remove/insert flicker and focus handoff.
            .overlay(alignment: .bottomLeading) {
                if !isLoading,
                   let editingStage,
                   stages.indices.contains(editingStage.index) {
                    let value = Int(stages[editingStage.index]) ?? capabilities.minimum ?? 800
                    VStack(spacing: -1) {
                        ZStack(alignment: .topLeading) {
                            if let fadingStage,
                               stages.indices.contains(fadingStage.index) {
                                stagePopover(index: fadingStage.index, isInteractive: false)
                                    .opacity(1 - popoverContentOpacity)
                                    .allowsHitTesting(false)
                            }
                            if let presentedStage,
                               stages.indices.contains(presentedStage.index) {
                                stagePopover(index: presentedStage.index, isInteractive: true)
                                    .opacity(popoverContentOpacity)
                            }
                        }
                        .frame(width: 230)
                        DPIStageTriangle()
                            .fill(Color.black.opacity(0.86))
                            .frame(width: 22, height: 11)
                            .rotationEffect(.degrees(180))
                    }
                    .frame(width: 230)
                    .compositingGroup()
                    .offset(
                        x: position(for: value, width: proxy.size.width) - 115,
                        y: -(proxy.size.height - 30)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                    .zIndex(100)
                }
            }
            .coordinateSpace(name: "dpiBar")
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("DPI stage bar")
        .onChange(of: isLoading) { loading in
            if loading { dismissStageEditor() }
        }
        .onChange(of: editingStage) { newValue in
            focusedStageIndex = newValue?.index
        }
        .onChange(of: focusedStageIndex) { newValue in
            if newValue == nil, let editingStage {
                onCommitText(editingStage.index)
            }
        }
    }

    private func stageHandle(index: Int, text: String, width: CGFloat) -> some View {
        let parsedValue = Int(text)
        let displayValue = parsedValue.map(String.init) ?? "Enter DPI"
        let positionValue = parsedValue ?? capabilities.minimum ?? 800
        let isDefault = defaultStage == index + 1
        let isShift = shiftStage == index + 1
        let x = position(for: positionValue, width: width)

        return ZStack(alignment: .topLeading) {
            ZStack {
                stageShape(isDefault: isDefault, isShift: isShift, isValid: parsedValue != nil)
                    .frame(width: 30, height: 30)
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .offset(y: isShift && !isDefault ? 2 : 0)
            }
            .frame(width: 34, height: 34)
            .position(x: 42, y: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("dpiBar"))
                    .onChanged { drag in
                        if stageInteractionStart == nil {
                            stageInteractionStart = ProcessInfo.processInfo.systemUptime
                        }
                        guard let candidate = value(at: drag.location.x, width: width, index: index) else { return }
                        if drag.translation != .zero {
                            onDragValue(index, candidate)
                        }
                    }
                    .onEnded { drag in
                        let now = ProcessInfo.processInfo.systemUptime
                        let duration = now - (stageInteractionStart ?? now)
                        stageInteractionStart = nil
                        guard duration < clickDurationLimit else { return }
                        presentStageEditor(index)
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { presentStageEditor(index) }
            .accessibilityLabel("DPI stage \(index + 1)")
            .accessibilityValue(parsedValue.map { "\($0) DPI" } ?? "Invalid value")
            .accessibilityHint("Click to edit, drag to change, or use the keyboard adjustment action.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    onAdjust(index, .increase)
                case .decrement:
                    onAdjust(index, .decrease)
                @unknown default:
                    break
                }
            }
            Text(displayValue)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(parsedValue == nil ? .orange : .primary)
                .lineLimit(1)
                .frame(width: 84)
                .position(x: 42, y: 45)
                .allowsHitTesting(false)
        }
        .frame(width: 84, height: 62)
        .position(x: x, y: 70)
        .zIndex(2)
    }

    @ViewBuilder
    private func stageShape(isDefault: Bool, isShift: Bool, isValid: Bool) -> some View {
        if isDefault {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isValid ? Color.red : Color.orange)
        } else if isShift {
            DPIStageDiamond()
                .fill(isValid ? Color.orange : Color.red)
        } else {
            Circle()
                .fill(isValid ? Color.blue : Color.red)
        }
    }

    private func stagePopover(index: Int, isInteractive: Bool) -> some View {
        let isDefault = defaultStage == index + 1
        let isShift = shiftStage == index + 1
        let canDelete = !isDefault && !isShift
        return VStack(alignment: .leading, spacing: 10) {
            Text("DPI stage \(index + 1)")
                .font(.headline)
            stageValueField(index: index, isInteractive: isInteractive)

            Divider()

            Button {
                onSetDefault(index)
                dismissStageEditor()
            } label: {
                HStack(spacing: 7) {
                    roleIcon(isDefault: true, isShift: false, filled: isDefault, tint: .white)
                    Text(isDefault ? "Default" : "Make Default")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .pointerCursor()

            Divider()

            Button {
                onSetShift(index)
                dismissStageEditor()
            } label: {
                HStack(spacing: 7) {
                    roleIcon(isDefault: false, isShift: true, filled: isShift, tint: .white)
                    Text(isShift ? "DPI Shift" : "Make DPI Shift")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .pointerCursor()

            Divider()

            Button(role: .destructive) {
                onDelete(index)
                dismissStageEditor()
            } label: {
                Label("Delete stage", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .pointerCursor(enabled: canDelete)
            .disabled(!canDelete)

            Text("Dragging snaps to the mouse’s supported DPI values.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 230)
        .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
    }

    @ViewBuilder
    private func stageValueField(index: Int, isInteractive: Bool) -> some View {
        let binding = Binding(
            get: { stages.indices.contains(index) ? stages[index] : "" },
            set: { onTextChange(index, $0) }
        )
        if isInteractive {
            TextField("DPI", text: binding)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .focused($focusedStageIndex, equals: index)
                .onSubmit { onCommitText(index) }
        } else {
            TextField("DPI", text: binding)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .allowsHitTesting(false)
        }
    }

    private var dpiLegend: some View {
        HStack(spacing: 9) {
            legendItem(label: "Default", isDefault: true, isShift: false)
            legendItem(label: "DPI Shift", isDefault: false, isShift: true)
            legendItem(label: "Other", isDefault: false, isShift: false)
        }
    }

    private func legendItem(label: String, isDefault: Bool, isShift: Bool) -> some View {
        HStack(spacing: 3) {
            let tint: Color = isDefault ? .red : (isShift ? .orange : .blue)
            roleIcon(isDefault: isDefault, isShift: isShift, filled: true, tint: tint)
            Text(label)
        }
    }

    @ViewBuilder
    private func roleIcon(isDefault: Bool, isShift: Bool, filled: Bool, tint: Color) -> some View {
        Group {
            if isDefault {
                if filled {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).fill(tint)
                } else {
                    RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(tint, lineWidth: 1.25)
                }
            } else if isShift {
                if filled {
                    DPIStageDiamond().fill(tint)
                } else {
                    DPIStageDiamond().stroke(tint, lineWidth: 1.25)
                }
            } else {
                Circle().fill(tint)
            }
        }
        .frame(width: 14, height: 14)
    }

    private var tickValues: [Int] {
        let minimum = capabilities.minimum ?? 100
        let maximum = capabilities.maximum ?? Int(UInt16.max)
        let firstTick = ((minimum + 999) / 1000) * 1000
        guard firstTick <= maximum else { return [] }
        return Array(stride(from: firstTick, through: maximum, by: 1000))
    }

    private func presentStageEditor(_ index: Int) {
        if let editingStage, editingStage.index != index {
            onCommitText(editingStage.index)
            fadingStage = presentedStage
            presentedStage = DPIStageSelection(index: index)
            popoverContentOpacity = 0
            withAnimation(.easeOut(duration: stageSwitchDuration)) {
                self.editingStage = DPIStageSelection(index: index)
                popoverContentOpacity = 1
            }
            focusedStageIndex = index
            clearFadingStage(after: stageSwitchDuration, index: index)
            return
        }

        if editingStage == nil {
            presentedStage = DPIStageSelection(index: index)
            fadingStage = nil
            popoverContentOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.04)) {
            editingStage = DPIStageSelection(index: index)
        }
    }

    private func dismissStageEditor() {
        if let editingStage {
            onCommitText(editingStage.index)
        }
        withAnimation(.easeOut(duration: 0.04)) {
            editingStage = nil
        }
        presentedStage = nil
        fadingStage = nil
        popoverContentOpacity = 1
    }

    private func clearFadingStage(after duration: TimeInterval, index: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard self.editingStage?.index == index else { return }
            fadingStage = nil
        }
    }

    private func position(for value: Int, width: CGFloat) -> CGFloat {
        let minimum = capabilities.minimum ?? 100
        let maximum = capabilities.maximum ?? Int(UInt16.max)
        guard maximum > minimum else { return width / 2 }
        let logMinimum = log(Double(minimum))
        let logMaximum = log(Double(maximum))
        let fraction = min(
            max(CGFloat((log(Double(max(value, minimum))) - logMinimum) / (logMaximum - logMinimum)), 0),
            1
        )
        return 14 + fraction * max(width - 28, 1)
    }

    private func value(at x: CGFloat, width: CGFloat, index: Int) -> Int? {
        let minimum = capabilities.minimum ?? 100
        let maximum = capabilities.maximum ?? Int(UInt16.max)
        let fraction = min(max((x - 14) / max(width - 28, 1), 0), 1)
        let logMinimum = log(Double(minimum))
        let logMaximum = log(Double(maximum))
        let raw = Int(exp(logMinimum + Double(fraction) * (logMaximum - logMinimum)).rounded())
        let lowerBound = index > 0 ? Int(stages[index - 1]).map { $0 + 1 } : nil
        let upperBound = index + 1 < stages.count ? Int(stages[index + 1]).map { $0 - 1 } : nil
        return capabilities.snappedValue(for: raw, lowerBound: lowerBound, upperBound: upperBound)
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var confirmRestore = false
    @State private var restoreURL: URL?
    @State private var confirmRecoveryRestore = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            TabView {
                ZStack {
                    if model.loadingProfile && model.buttons.isEmpty {
                        loadingProfileState
                    } else if !model.loadingProfile && !model.shouldShowButtonEditor {
                        emptyState
                    } else {
                        buttonsPane
                            .opacity(model.loadingProfile ? 0.72 : 1)
                            .allowsHitTesting(!model.loadingProfile)
                    }
                    if model.loadingProfile && !model.buttons.isEmpty {
                        loadingProfileOverlay
                    }
                }
                .tabItem { Label("Buttons", systemImage: "cursorarrow.click") }
                backupsPane
                    .tabItem { Label("Backups", systemImage: "archivebox") }
                settingsPane
                .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            Divider()
            HStack(alignment: .top) {
                Image(systemName: "info.circle")
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
            }

            // Future expansion: restore the button-press highlighting control
            // here, below the footer/status line, after a reliable Logitech
            // button-event path is available. AppKit only exposed buttons 1–3
            // in testing, and the HID monitor did not provide dependable
            // mappings for the remaining controls.
            // HStack(spacing: 8) {
            //     Spacer()
            //     Button("Highlight presses") {
            //         // Future button-event monitor action.
            //     }
            // }
        }
        .padding(20)
        .frame(minWidth: 960, minHeight: 520)
        .onChange(of: model.profileNumber) { _ in
            model.reloadSelectedProfile()
        }
        .onChange(of: model.selectedDeviceIndex) { _ in
            model.refreshBackups()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.updateInputMonitoringAuthorization()
            }
        }
        .alert("Restore this backup?", isPresented: $confirmRestore) {
            Button("Cancel", role: .cancel) { restoreURL = nil }
            Button("Restore and verify", role: .destructive) {
                if let restoreURL { model.restore(restoreURL) }
                restoreURL = nil
            }
        } message: {
            Text(restoreURL?.lastPathComponent ?? "Selected backup")
        }
        .alert("Restore backups from this save?", isPresented: $confirmRecoveryRestore) {
            Button("Cancel", role: .cancel) {}
            Button("Restore and verify", role: .destructive) {
                model.restoreLastSaveBackups()
            }
        } message: {
            Text("LOPE will restore the exact pre-save sectors captured by the failed operation. Any sector that was already unchanged will be skipped safely.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppConstants.displayName)
                    .font(.title2.weight(.semibold))
            }
            Spacer()
            if !model.devices.isEmpty {
                Picker("Device", selection: Binding(
                    get: { model.selectedDeviceIndex },
                    set: { model.selectDevice($0) })) {
                    ForEach(model.devices) { device in
                        Text(device.title).tag(device.id)
                    }
                }
                .frame(width: 310)
                .disabled(model.devices.isEmpty)
            }
            if model.profiles.count > 1 {
                Picker("Profile", selection: $model.profileNumber) {
                    ForEach(model.profiles) { profile in
                        Text(profile.title).tag(profile.id)
                    }
                }
                .frame(width: 180)
                .disabled(model.busy)
            }
            Button("Refresh", action: model.refresh)
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.busy)
            if model.busy { ProgressView().controlSize(.small) }
        }
    }

    private var loadingProfileOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading profiles from mouse…")
                    .font(.headline)
                Text(model.currentDeviceName.isEmpty ? "Finding Logitech mice and reading onboard data" : "Reading \(model.currentDeviceName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var loadingProfileState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading profiles from mouse…")
                .font(.headline)
            Text(model.currentDeviceName.isEmpty ? "Finding Logitech mice and reading onboard data" : "Reading \(model.currentDeviceName)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "computermouse")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(emptyStateTitle)
                .font(.title3.weight(.medium))
            Text(emptyStateMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560)
            if !model.inputMonitoringAuthorized {
                Button("Open Input Monitoring Settings", action: model.openInputMonitoringSettings)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        if model.devices.isEmpty { return "No editable Logitech mouse detected" }
        if model.isMXSeriesMouse && !model.hasSpecificMouseProfile {
            return "No MX mouse profile descriptor"
        }
        return "No editable onboard profile"
    }

    private var emptyStateMessage: String {
        if model.devices.isEmpty {
            return "The app lists Logitech mice. macOS may also be blocking access even when the mouse is connected."
        }
        if model.isMXSeriesMouse && !model.hasSpecificMouseProfile {
            return "\(model.deviceSummary) is connected, but LOPE does not have a profile JSON for this MX mouse’s button layout yet."
        }
        return "\(model.deviceSummary) is connected, but it does not expose an onboard profile format this app can edit."
    }

    private var buttonsPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Button assignments")
                    .font(.headline)
                Spacer()
                Button("Revert edits") { model.reloadSelectedProfile() }
                Button("Save to mouse", action: model.applyAll)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        !model.hasPendingChanges || model.busy || !model.currentMouseProfile.profileIO.canSave ||
                        (model.hasDPIChanges && !model.canApplyDPI)
                    )
            }
            Text("Change button outputs and DPI together, then save once. The original data is backed up automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !model.recoveryBackups.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("The last save was only partially completed. Exact pre-save backups are available for recovery.")
                        .font(.callout)
                    Spacer()
                    Button("Restore backups from this save") {
                        confirmRecoveryRestore = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            if !model.currentMouseProfile.profileIO.canSave {
                Text("This device is cataloged for read-only inspection until its profile-specific save format is validated.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    profilesEditor
                    Divider()
                    VStack(spacing: 8) {
                        ForEach(model.buttons) { button in
                            buttonRow(button.id)
                        }
                    }
                    Divider()
                    dpiEditor
                }
                .padding(.vertical, 4)
            }
            .id(model.selectedDeviceIndex)

        }
        .padding(.top, 4)
    }

    private func buttonRow(_ buttonID: Int) -> some View {
        Group {
            if let button = model.buttons.first(where: { $0.id == buttonID }) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Button \(button.id)")
                            .font(.body.weight(.medium))
                            .frame(width: 76, alignment: .leading)
                        Text(button.label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Picker("", selection: Binding(
                            get: { model.buttons.first(where: { $0.id == buttonID })?.draftChoice ?? "custom" },
                            set: { choice in
                                guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                                model.selectOutput(buttonIndex: index, choice: choice)
                            })) {
                            ForEach(model.presets) { preset in
                                Text(preset.label).tag(preset.raw)
                            }
                            Text("Custom").tag("custom")
                        }
                        .labelsHidden()
                        .frame(width: 190)
                        if model.showAdvancedFields {
                            TextField("8 hex digits", text: Binding(
                                get: { model.buttons.first(where: { $0.id == buttonID })?.draftRaw ?? "" },
                                set: { raw in
                                    guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                                    model.setRaw(buttonIndex: index, raw: raw)
                                }))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 122)
                        }
                        Spacer()
                    }
                    if model.buttons.first(where: { $0.id == buttonID })?.draftChoice == "custom" {
                        keyboardChordEditor(buttonID)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.clear)
                        .frame(width: 3)
                        .padding(.vertical, 7)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            Color.white.opacity(0.055),
                            lineWidth: 0.5
                        )
                }
            }
        }
    }

    private var profilesEditor: some View {
        GroupBox(model.onboardProfileSummary) {
            VStack(alignment: .leading, spacing: 4) {
                if model.profiles.count > 1 {
                    Text("Disable a profile to keep it out of the mouse’s profile cycle. At least one profile must remain enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Text("Enable Profile(s):")
                            .font(.callout.weight(.medium))
                        ForEach(model.profiles) { profile in
                            profileEnableControl(profile)
                        }
                        Spacer()
                    }
                } else {
                    Text("This mouse has one readable onboard profile; profile cycling and disabling are unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.showAdvancedFields {
                    HStack(spacing: 12) {
                        Text("Sectors:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(model.profiles) { profile in
                            Text("Profile \(profile.id): \(profile.sector)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    private func profileEnableControl(_ profile: ProfileChoice) -> some View {
        let profileID = profile.id
        let label = String(profileID)
        let crcLabel: String
        let crcColor: Color
        let helpText: String
        switch profile.crcValid {
        case true:
            crcLabel = ""
            crcColor = .secondary
            helpText = "Profile \(label) CRC valid"
        case false:
            crcLabel = "Profile invalid"
            crcColor = .red
            helpText = "Profile \(label) CRC invalid"
        case nil:
            crcLabel = ""
            crcColor = .secondary
            helpText = "Profile \(label) CRC not read"
        }
        let enabled = Binding<Bool>(
            get: { model.profileEnabled(profileID) },
            set: { model.setProfileEnabled(profileID: profileID, enabled: $0) }
        )
        return HStack(spacing: 4) {
            Text(label)
            Toggle("", isOn: enabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
            Text(crcLabel)
                .font(.caption)
                .foregroundStyle(crcColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            profileID == model.profileNumber
                ? Color.accentColor.opacity(0.12)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .help(helpText)
    }

    private func keyboardChordEditor(_ buttonID: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Custom keyboard output", systemImage: "keyboard")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("Modifiers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(model.modifierChoices) { modifier in
                    Toggle(modifier.label, isOn: Binding(
                        get: {
                            guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return false }
                            return model.isModifierEnabled(buttonIndex: index, bit: modifier.id)
                        },
                        set: { enabled in
                            guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                            model.setModifier(buttonIndex: index, bit: modifier.id, enabled: enabled)
                        }))
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .disabled({
                            guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return true }
                            return !model.isKeyboardRecord(buttonIndex: index)
                        }())
                }
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Typed key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("A, Tab, or 0x04", text: Binding(
                        get: {
                            guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return "" }
                            return model.keyboardKeyText(buttonIndex: index)
                        },
                        set: { text in
                            guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                            model.setKeyboardKeyText(buttonIndex: index, text: text)
                        }))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 150)
                }

                keyboardChoiceCard(buttonID: buttonID, title: "Function key", systemImage: "f.square")
                keyboardChoiceCard(buttonID: buttonID, title: "Special key", systemImage: "command.square")
                Spacer()
            }
        }
        .padding(.leading, 76)
        .padding(.top, 2)
        .help("Type a key name such as A or F13, choose a function or special key, and add modifiers with the checkboxes.")
    }

    private func keyboardChoiceCard(buttonID: Int, title: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            if title == "Function key" {
                Picker("", selection: Binding(
                    get: {
                        guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return 0 }
                        return model.functionKeyChoice(buttonIndex: index)
                    },
                    set: { number in
                        guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                        model.setFunctionKey(buttonIndex: index, number: number)
                    })) {
                    Text("None").tag(0)
                    ForEach(1...24, id: \.self) { number in
                        Text("F\(number)").tag(number)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 112)
            } else {
                Picker("", selection: Binding(
                    get: {
                        guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return 0 }
                        return model.specialKeyChoice(buttonIndex: index)
                    },
                    set: { key in
                        guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                        model.setSpecialKey(buttonIndex: index, key: key)
                    })) {
                    Text("None").tag(0)
                    ForEach(model.specialKeyboardKeys) { key in
                        Text(key.label).tag(Int(key.id))
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 156)
            }
        }
    }

    private var dpiEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Onboard DPI")
                        .font(.headline)
                    Text("Set the active sensitivity stages for this profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Text("Active stages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        model.setDPIStageCount(model.dpiCount - 1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.title2.weight(.semibold))
                            .frame(width: 38, height: 34)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.dpiCount <= 1)
                    .accessibilityLabel("Remove DPI stage")
                    Text("\(model.dpiCount) of 5")
                        .font(.callout.monospacedDigit())
                        .frame(minWidth: 44)
                    Button {
                        model.setDPIStageCount(model.dpiCount + 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .frame(width: 38, height: 34)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.dpiCount >= 5)
                    .accessibilityLabel("Add DPI stage")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                DPIStageBar(
                    stages: Array(model.dpiStages.prefix(model.dpiCount)),
                    defaultStage: model.defaultStage,
                    shiftStage: model.shiftStage,
                    capabilities: model.dpiCapabilities,
                    isLoading: model.loadingProfile,
                    onDragValue: { index, value in
                        model.setDPIStageValue(index: index, value: value)
                    },
                    onAdjust: { index, direction in
                        model.adjustDPIStage(index: index, direction: direction)
                    },
                    onTextChange: { index, text in
                        model.setDPIStageText(index: index, text: text)
                    },
                    onCommitText: { index in
                        model.commitDPIStageText(index: index)
                    },
                    onSetDefault: { index in
                        model.setDefaultDPIStage(index + 1)
                    },
                    onSetShift: { index in
                        model.setShiftDPIStage(index + 1)
                    },
                    onDelete: { index in
                        model.deleteDPIStage(index: index)
                    }
                )
                .frame(height: 120)
                .zIndex(10)

                if let validation = model.dpiValidationMessage {
                    Label(validation, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Spacer()
        }
        .padding(.top, 4)
    }

    private var backupsPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Backups")
                .font(.headline)
            Text("Save to mouse creates exact binary backups for the selected mouse before any write. JSON is an explicit import/export format; older JSON sidecars remain available as editable files, but new mouse saves do not create them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Save selected profile backup") { model.dumpBackup() }
                Button("Export JSON…") {
                    if let url = model.chooseJSONExport() {
                        model.exportCurrentJSON(to: url)
                    }
                }
                Button("Import JSON…") {
                    if let url = model.chooseJSONBackup() {
                        model.loadEditableBackup(url)
                    }
                }
                Button("Choose another backup…") {
                    restoreURL = model.chooseRestoreBackup()
                    confirmRestore = restoreURL != nil
                }
                Button("Refresh list", action: model.refreshBackups)
            }
            Toggle("Show backups for all mice", isOn: Binding(
                get: { model.showAllBackups },
                set: { model.setShowAllBackups($0) }))
            .toggleStyle(.checkbox)
            Text(model.showAllBackups
                 ? "Showing every backup. Unknown-device files require review before restore or import."
                 : "Showing backups matched to the selected mouse. Legacy files that cannot be matched safely are hidden.")
                .font(.caption)
                .foregroundStyle(.secondary)
            GroupBox("Available backups") {
                if model.backups.isEmpty {
                    Text(model.showAllBackups
                         ? "No backups in \(model.backupDirectoryPath)."
                         : "No backups for the selected mouse in \(model.backupDirectoryPath).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                } else {
                    List {
                        ForEach(model.backups) { backup in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(backup.name)
                                        .font(.callout)
                                        .lineLimit(1)
                                    Text("\(backup.fileTypeLabel) | \(backup.deviceStatusLabel) | \(backup.modifiedAt.formatted(date: .abbreviated, time: .shortened)) | \(ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file))")
                                        .font(.caption)
                                        .foregroundStyle(backup.deviceMatch == .unknown ? .orange : .secondary)
                                }
                                Spacer()
                                if backup.isJSON {
                                    Button("Load") {
                                        model.loadEditableBackup(backup.url)
                                    }
                                } else {
                                    Button("Restore") {
                                        restoreURL = backup.url
                                        confirmRestore = true
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 120, maxHeight: 250)
                }
            }
            Text("Quit G HUB and other mouse remappers while saving. Re-enable them after verifying the onboard behavior.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
            GroupBox("Backups") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backup folder")
                        .font(.callout.weight(.medium))
                    Text(model.backupDirectoryPath)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    HStack {
                        Button("Choose folder…") {
                            if let folder = model.chooseBackupDirectory() {
                                model.setBackupDirectory(folder)
                            }
                        }
                        Button("Use default") { model.resetBackupDirectory() }
                            .disabled(model.backupDirectoryPath == model.defaultBackupDirectoryPath)
                    }
                }
                .padding(4)
            }
            GroupBox("Advanced display") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show raw HID++ fields", isOn: Binding(
                        get: { model.showAdvancedFields },
                        set: { model.setShowAdvancedFields($0) }))
                        .toggleStyle(.checkbox)
                    Text("Shows the 8-digit button records and profile sector numbers. Leave this off for the normal editing view.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }
            Spacer()
        }
        .padding(.top, 4)
    }
}
