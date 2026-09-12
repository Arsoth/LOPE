// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import ApplicationServices
import CoreVideo
import CoreGraphics
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

private struct DPIStagePentagon: Shape {
    private let cornerRadius: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let vertices = [
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.38),
            CGPoint(x: rect.minX + rect.width * 0.81, y: rect.maxY),
            CGPoint(x: rect.minX + rect.width * 0.19, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.38)
        ]
        let roundedVertices = vertices.enumerated().map { index, vertex in
            let previous = vertices[(index + vertices.count - 1) % vertices.count]
            let next = vertices[(index + 1) % vertices.count]
            return (
                before: point(on: vertex, toward: previous, distance: cornerRadius),
                after: point(on: vertex, toward: next, distance: cornerRadius),
                vertex: vertex
            )
        }

        var path = Path()
        path.move(to: roundedVertices[0].before)
        for (index, roundedVertex) in roundedVertices.enumerated() {
            if index > 0 {
                path.addLine(to: roundedVertex.before)
            }
            path.addQuadCurve(to: roundedVertex.after, control: roundedVertex.vertex)
        }
        path.addLine(to: roundedVertices[0].before)
        path.closeSubpath()
        return path
    }

    private func point(on vertex: CGPoint, toward other: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = other.x - vertex.x
        let dy = other.y - vertex.y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        let fraction = min(distance, length / 2) / length
        return CGPoint(x: vertex.x + dx * fraction, y: vertex.y + dy * fraction)
    }
}

private enum DPIStagePalette {
    static let shift = Color(red: 0.20, green: 0.52, blue: 0.94)
    static let defaultStage = Color(red: 0.91, green: 0.24, blue: 0.25)
    //static let other = Color(red: 0.72, green: 0.83, blue: 0.20)
    static let other = Color(red: 0.95, green: 0.70, blue: 0.15)
    static let bar = Color(red: 0.42, green: 0.45, blue: 0.50)
}

private func formattedDPIValue(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = .current
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

private enum DPILegendRole: Hashable {
    case defaultStage
    case shift
    case other
}

private struct DPIStageDragUpdate: Equatable {
    let index: Int
    let value: Int
}

private struct DPIStageSelection: Identifiable, Equatable {
    let index: Int

    var id: Int { index }
}

private struct DPIStagePopupFrameKey: PreferenceKey {
    static var defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct DPIStageOutsideClickMonitor: NSViewRepresentable {
    let isActive: Bool
    let excludedFrame: CGRect?
    let onOutsideClick: () -> Void

    final class Coordinator {
        weak var view: NSView?
        var isActive = false
        var excludedFrame: CGRect?
        var onOutsideClick: () -> Void = {}
        var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                guard let self, self.isActive, let view = self.view else { return event }
                let point = view.convert(event.locationInWindow, from: nil)
                if let excludedFrame = self.excludedFrame, excludedFrame.contains(point) {
                    return event
                }
                self.onOutsideClick()
                return event
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
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        update(view, coordinator: context.coordinator)
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        update(nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    private func update(_ view: NSView, coordinator: Coordinator) {
        coordinator.view = view
        coordinator.isActive = isActive
        coordinator.excludedFrame = excludedFrame
        coordinator.onOutsideClick = onOutsideClick
    }
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

private struct CenteredAppModal<Actions: View>: View {
    let title: String
    let message: String
    let symbol: String
    let onDefaultAction: () -> Void
    let onCancel: () -> Void
    let actions: () -> Actions

    init(
        title: String,
        message: String,
        symbol: String = "info.circle",
        onDefaultAction: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {},
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.message = message
        self.symbol = symbol
        self.onDefaultAction = onDefaultAction
        self.onCancel = onCancel
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            HStack {
                Spacer()
                actions()
            }
        }
        .padding(22)
        .frame(width: 430)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, y: 10)
        .background(
            ModalKeyboardHandler(
                onDefaultAction: onDefaultAction,
                onCancel: onCancel
            )
        )
    }
}

private struct ModalKeyboardHandler: NSViewRepresentable {
    let onDefaultAction: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDefaultAction: onDefaultAction, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDefaultAction = onDefaultAction
        context.coordinator.onCancel = onCancel
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onDefaultAction: () -> Void
        var onCancel: () -> Void
        private var monitor: Any?

        init(onDefaultAction: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self.onDefaultAction = onDefaultAction
            self.onCancel = onCancel
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch event.keyCode {
                case 36, 76: // Return and Enter on the numeric keypad.
                    self.onDefaultAction()
                    return nil
                case 53: // Escape.
                    self.onCancel()
                    return nil
                default:
                    return event
                }
            }
        }

        func uninstall() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        deinit {
            uninstall()
        }
    }
}

private struct ScrollViewScrollerInset: NSViewRepresentable {
    let rightInset: CGFloat

    func makeNSView(context: Context) -> ProbeView {
        ProbeView(rightInset: rightInset)
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.rightInset = rightInset
        nsView.configureEnclosingScrollView()
    }

    final class ProbeView: NSView {
        var rightInset: CGFloat

        init(rightInset: CGFloat) {
            self.rightInset = rightInset
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            rightInset = 0
            super.init(coder: coder)
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureEnclosingScrollView()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureEnclosingScrollView()
        }

        override func layout() {
            super.layout()
            configureEnclosingScrollView()
        }

        func configureEnclosingScrollView() {
            guard let scrollView = enclosingScrollView else { return }
            var insets = scrollView.scrollerInsets
            guard insets.right != rightInset else { return }
            insets.right = rightInset
            scrollView.scrollerInsets = insets
        }
    }
}

private struct KeyboardInputMonitor: NSViewRepresentable {
    let isActive: Bool
    let onKeyDown: (NSEvent) -> Void

    final class Coordinator {
        var isActive = false
        var onKeyDown: (NSEvent) -> Void = { _ in }
        var localMonitor: Any?
        var eventTap: CFMachPort?
        var eventTapSource: CFRunLoopSource?
        var eventTapCanSuppressEvents = false

        func update(isActive: Bool, onKeyDown: @escaping (NSEvent) -> Void) {
            self.isActive = isActive
            self.onKeyDown = onKeyDown
            if isActive {
                installLocalMonitor()
                installEventTap()
            } else {
                removeLocalMonitor()
                removeEventTap()
            }
        }

        private func installLocalMonitor() {
            guard localMonitor == nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .keyUp, .flagsChanged]
            ) { [weak self] event in
                guard let self, self.isActive else { return event }
                if event.type == .keyDown {
                    self.onKeyDown(event)
                }
                // Modifier transitions and key-up events are swallowed too,
                // so recording cannot leak a chord into the app.
                return nil
            }
        }

        private func installEventTap() {
            guard eventTap == nil else { return }
            // Accessibility is only needed for an active filtering tap. Keep
            // the fallback passive so users can record from other apps with
            // Input Monitoring alone, without prompting for Accessibility.
            eventTapCanSuppressEvents = AXIsProcessTrusted()
            if !CGPreflightListenEventAccess() {
                _ = CGRequestListenEventAccess()
            }
            let tapOptions: CGEventTapOptions = eventTapCanSuppressEvents ? .defaultTap : .listenOnly
            let eventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue) |
                (CGEventMask(1) << CGEventType.keyUp.rawValue) |
                (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            let coordinatorPointer = Unmanaged.passUnretained(self).toOpaque()
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: tapOptions,
                eventsOfInterest: eventMask,
                callback: { _, type, event, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let coordinator = Unmanaged<Coordinator>
                        .fromOpaque(refcon)
                        .takeUnretainedValue()
                    guard coordinator.isActive else {
                        return Unmanaged.passUnretained(event)
                    }
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let eventTap = coordinator.eventTap {
                            CGEvent.tapEnable(tap: eventTap, enable: true)
                        }
                        return Unmanaged.passUnretained(event)
                    }
                    if type == .keyDown, let nsEvent = NSEvent(cgEvent: event) {
                        coordinator.onKeyDown(nsEvent)
                    }
                    // An active tap stops global shortcuts such as Cmd+Shift+4.
                    // A listen-only tap can still capture the chord, but must
                    // pass it through to the app that owns the shortcut.
                    return coordinator.eventTapCanSuppressEvents
                        ? nil
                        : Unmanaged.passUnretained(event)
                },
                userInfo: coordinatorPointer
            ) else {
                return
            }

            eventTap = tap
            if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
                eventTapSource = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        private func removeLocalMonitor() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
        }

        private func removeEventTap() {
            if let source = eventTapSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                eventTapSource = nil
            }
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: false)
                CFMachPortInvalidate(eventTap)
                self.eventTap = nil
            }
            eventTapCanSuppressEvents = false
        }

        deinit {
            removeLocalMonitor()
            removeEventTap()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.update(isActive: isActive, onKeyDown: onKeyDown)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isActive: isActive, onKeyDown: onKeyDown)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.update(isActive: false, onKeyDown: { _ in })
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

private struct DPIStageHitTarget: Equatable {
    let index: Int
    let x: CGFloat
}

/// Owns pointer interaction for the entire stage bar. Keeping click arbitration,
/// drag thresholding, and display-linked cursor sampling in one native view avoids
/// competing SwiftUI tap/drag recognizers and keeps the active handle under the
/// physical pointer even while the stage model is being reordered.
private struct DPIStageInteractionLayer: NSViewRepresentable {
    let isActive: Bool
    let targets: [DPIStageHitTarget]
    let onTap: (Int) -> Void
    let onBackgroundClick: () -> Void
    let onDragBegan: (Int, CGFloat) -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        update(view)
        view.setSamplingActive(isActive)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        update(nsView)
    }

    static func dismantleNSView(_ nsView: InteractionView, coordinator: ()) {
        nsView.cancelInteraction()
    }

    private func update(_ view: InteractionView) {
        view.targets = targets
        view.onTap = onTap
        view.onBackgroundClick = onBackgroundClick
        view.onDragBegan = onDragBegan
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.setSamplingActive(isActive)
    }

    final class InteractionView: NSView {
        var targets: [DPIStageHitTarget] = [] {
            didSet { window?.invalidateCursorRects(for: self) }
        }
        var onTap: ((Int) -> Void)?
        var onBackgroundClick: (() -> Void)?
        var onDragBegan: ((Int, CGFloat) -> Void)?
        var onDragChanged: ((CGFloat) -> Void)?
        var onDragEnded: ((CGFloat) -> Void)?

        private let dragThreshold: CGFloat = 5
        private let handleSize = CGSize(width: 84, height: 62)
        private let handleCenterY: CGFloat = 58
        private let trackRange: ClosedRange<CGFloat> = 24...65
        private var mouseDownPoint: CGPoint?
        private var pendingStage: Int?
        private var pendingStageWasHandle = false
        private var isDraggingStage = false
        private var isSamplingActive = false
        private var displayLink: CVDisplayLink?
        private let tickLock = NSLock()
        private var tickQueued = false

        override var isFlipped: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            super.resetCursorRects()
            for target in targets {
                addCursorRect(handleRect(for: target.x), cursor: .pointingHand)
            }
        }

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            mouseDownPoint = point
            pendingStageWasHandle = target(at: point) != nil
            pendingStage = target(at: point)?.index ?? nearestTarget(to: point.x)?.index
            isDraggingStage = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let mouseDownPoint, let pendingStage else { return }
            let point = convert(event.locationInWindow, from: nil)
            let distance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
            guard isDraggingStage || distance >= dragThreshold else { return }

            if !isDraggingStage {
                isDraggingStage = true
                onDragBegan?(pendingStage, point.x)
                startDisplayLink()
            }
            // This gives immediate feedback between display-link callbacks and
            // is also the fallback on systems where a display link is unavailable.
            onDragChanged?(point.x)
        }

        override func mouseUp(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if isDraggingStage {
                onDragChanged?(point.x)
                onDragEnded?(point.x)
            } else if pendingStageWasHandle, let pendingStage {
                onTap?(pendingStage)
            } else {
                onBackgroundClick?()
            }
            cancelInteraction()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard !isHidden, alphaValue > 0 else { return nil }
            let hit = target(at: point) != nil || trackRange.contains(point.y)
            return hit ? self : nil
        }

        func cancelInteraction() {
            stopDisplayLink()
            isSamplingActive = false
            mouseDownPoint = nil
            pendingStage = nil
            pendingStageWasHandle = false
            isDraggingStage = false
        }

        func setSamplingActive(_ active: Bool) {
            guard active != isSamplingActive else { return }
            isSamplingActive = active
            if active {
                startDisplayLink()
            } else {
                stopDisplayLink()
            }
        }

        private func target(at point: CGPoint) -> DPIStageHitTarget? {
            targets.last { handleRect(for: $0.x).contains(point) }
        }

        private func nearestTarget(to x: CGFloat) -> DPIStageHitTarget? {
            targets.min { abs($0.x - x) < abs($1.x - x) }
        }

        private func handleRect(for x: CGFloat) -> CGRect {
            CGRect(
                x: x - handleSize.width / 2,
                y: handleCenterY - handleSize.height / 2,
                width: handleSize.width,
                height: handleSize.height
            )
        }

        private func startDisplayLink() {
            guard displayLink == nil else { return }
            var link: CVDisplayLink?
            guard CVDisplayLinkCreateWithActiveCGDisplays(&link) == kCVReturnSuccess,
                  let link else { return }
            displayLink = link
            CVDisplayLinkSetOutputCallback(
                link,
                { _, _, _, _, _, context in
                    guard let context else { return kCVReturnSuccess }
                    let view = Unmanaged<InteractionView>
                        .fromOpaque(context)
                        .takeUnretainedValue()
                    view.queueTick()
                    return kCVReturnSuccess
                },
                Unmanaged.passUnretained(self).toOpaque()
            )
            CVDisplayLinkStart(link)
        }

        private func stopDisplayLink() {
            if let displayLink {
                CVDisplayLinkStop(displayLink)
                self.displayLink = nil
            }
        }

        private func queueTick() {
            tickLock.lock()
            guard !tickQueued else {
                tickLock.unlock()
                return
            }
            tickQueued = true
            tickLock.unlock()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.tickLock.lock()
                self.tickQueued = false
                self.tickLock.unlock()
                guard self.isSamplingActive, let window = self.window else { return }
                let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
                self.onDragChanged?(self.convert(windowPoint, from: nil).x)
            }
        }

        deinit {
            stopDisplayLink()
        }
    }
}

private struct DPIStageBar: View {
    let stages: [String]
    let defaultStage: Int
    let shiftStage: Int
    let capabilities: DPICapabilities
    let isLoading: Bool
    let validationMessage: String?
    let onDragValue: (Int, Int) -> Int
    let onDragEnded: () -> Void
    let onAdjust: (Int, DPICapabilities.AdjustmentDirection) -> Void
    let onTextChange: (Int, String) -> Void
    let onCommitText: (Int) -> Void
    let onSetDefault: (Int) -> Void
    let onSetShift: (Int) -> Void
    let onDelete: (Int) -> Void

    @State private var editingStage: DPIStageSelection?
    @State private var presentedStage: DPIStageSelection?
    @State private var fadingStage: DPIStageSelection?
    @State private var draggingStage: Int?
    @State private var activeDragX: CGFloat?
    @State private var lastDragUpdate: DPIStageDragUpdate?
    @State private var popupFrame: CGRect?
    @State private var popoverContentOpacity = 1.0
    @FocusState private var focusedStageIndex: Int?

    private let stageSwitchDuration: TimeInterval = 0.08
    // Reserve symmetric space for localized endpoint values up to 999,999.
    private let endpointLabelWidth: CGFloat = 56
    private let trackToEndpointSpacing: CGFloat = 12
    private let endpointCenterAdjustment: CGFloat = 4.5

    private var trackInset: CGFloat {
        endpointLabelWidth + trackToEndpointSpacing
    }

    private let validationIconSize: CGFloat = 14

    // Match the warning icon center to the center of the minimum endpoint
    // label, accounting for the label's small visual offset.
    private var validationLeadingInset: CGFloat {
        trackInset / 2 - endpointCenterAdjustment - validationIconSize / 2
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if editingStage != nil {
                    EscapeKeyMonitor(onEscape: dismissStageEditor)
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                }

                Capsule()
                    .fill(DPIStagePalette.bar)
                    .frame(height: 4)
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.12), lineWidth: 0.5)
                    }
                    .frame(width: max(proxy.size.width - trackInset * 2, 1))
                    .position(x: proxy.size.width / 2, y: 43)

                ForEach(tickValues, id: \.self) { value in
                    Rectangle()
                        .fill(.secondary.opacity(0.52))
                        .frame(width: 1, height: 10)
                        .position(x: position(for: value, width: proxy.size.width), y: 43)
                }

                ForEach(Array(stages.enumerated()).filter { Int($0.element) != nil }, id: \.offset) { item in
                    stageHandle(index: item.offset, text: item.element, width: proxy.size.width)
                }

                DPIStageInteractionLayer(
                    isActive: draggingStage != nil,
                    targets: interactionTargets(width: proxy.size.width),
                    onTap: { index in
                        presentStageEditor(index)
                    },
                    onBackgroundClick: {
                        if editingStage != nil {
                            dismissStageEditor()
                        }
                    },
                    onDragBegan: { index, x in
                        if editingStage != nil {
                            dismissStageEditor()
                        }
                        draggingStage = index
                        lastDragUpdate = nil
                        updateDrag(at: x, width: proxy.size.width)
                    },
                    onDragChanged: { x in
                        updateDrag(at: x, width: proxy.size.width)
                    },
                    onDragEnded: { x in
                        updateDrag(at: x, width: proxy.size.width)
                        finishDrag()
                    }
                )
                .frame(width: proxy.size.width, height: 86)
                .position(x: proxy.size.width / 2, y: 43)
                .zIndex(30)

                ZStack {
                    HStack(spacing: 0) {
                        Text(capabilities.minimum.map(formattedDPIValue) ?? formattedDPIValue(100))
                            .frame(width: trackInset, alignment: .center)
                            .offset(x: -endpointCenterAdjustment)
                        Spacer()
                        Text(capabilities.maximum.map(formattedDPIValue) ?? formattedDPIValue(65535))
                            .frame(width: trackInset, alignment: .center)
                            .offset(x: endpointCenterAdjustment)
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: proxy.size.width)
                    .position(x: proxy.size.width / 2, y: 43)
                }

                dpiLegend
                    .position(x: proxy.size.width / 2, y: 93)

                if let validationMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .frame(width: validationIconSize, height: validationIconSize)
                        Text(validationMessage)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.body)
                    .foregroundStyle(.orange)
                    .frame(
                        width: max(proxy.size.width - validationLeadingInset, 1),
                        alignment: .leading
                    )
                    .position(
                        x: validationLeadingInset + max(proxy.size.width - validationLeadingInset, 1) / 2,
                        y: 93
                    )
                    .allowsHitTesting(false)
                    .zIndex(4)
                }

            }
            // Keep one bubble alive while moving between stages. Replacing
            // separate per-stage popovers was the source of the occasional
            // remove/insert flicker and focus handoff.
            .overlay(alignment: .bottomLeading) {
                if !isLoading,
                   let editingStage,
                   stages.indices.contains(editingStage.index) {
                    let value = Int(stages[editingStage.index]) ?? capabilities.minimum ?? 800
                    let popoverWidth: CGFloat = 230
                    let markerX = position(for: value, width: proxy.size.width)
                    let popoverX = min(
                        max(markerX - popoverWidth / 2, 0),
                        max(proxy.size.width - popoverWidth, 0)
                    )
                    // Keep the arrow clear of the rounded bottom corners when
                    // a stage is close to either end of the track. A small
                    // offset is preferable to letting the arrow straddle the
                    // curve and makes the anchor read as intentional.
                    let arrowEdgeClearance: CGFloat = 36
                    let arrowX = min(
                        max(markerX - popoverX, arrowEdgeClearance),
                        popoverWidth - arrowEdgeClearance
                    )
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
                            .offset(x: arrowX - popoverWidth / 2)
                    }
                    .frame(width: 230)
                    .background {
                        GeometryReader { popupProxy in
                            Color.clear.preference(
                                key: DPIStagePopupFrameKey.self,
                                value: popupProxy.frame(in: .named("dpiBar"))
                            )
                        }
                    }
                    .compositingGroup()
                    .offset(
                        x: popoverX,
                        y: -(proxy.size.height - 24)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                    .zIndex(100)
                }
            }
            .coordinateSpace(name: "dpiBar")
            .overlay {
                DPIStageOutsideClickMonitor(
                    isActive: editingStage != nil,
                    excludedFrame: popupFrame,
                    onOutsideClick: dismissStageEditor
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .allowsHitTesting(false)
            }
            .onPreferenceChange(DPIStagePopupFrameKey.self) { frame in
                popupFrame = frame
            }
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
        let displayValue = parsedValue.map(formattedDPIValue) ?? "Enter DPI"
        let positionValue = parsedValue ?? capabilities.minimum ?? 800
        let isDefault = defaultStage == index + 1
        let isShift = shiftStage == index + 1
        let x = draggingStage == index
            ? (activeDragX ?? position(for: positionValue, width: width))
            : position(for: positionValue, width: width)

        return Button {
            guard draggingStage == nil else { return }
            presentStageEditor(index)
        } label: {
            ZStack(alignment: .topLeading) {
                ZStack {
                    stageShape(isDefault: isDefault, isShift: isShift)
                        .frame(width: 30, height: 30)
                    Text("\(index + 1)")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 34, height: 34)
                .position(x: 42, y: 16)
                Text(displayValue)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(parsedValue == nil ? .orange : .primary)
                    .lineLimit(1)
                    .frame(width: 84)
                    .position(x: 42, y: 45)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.04), value: displayValue)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 84, height: 62)
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .pointerCursor()
        .accessibilityLabel("DPI stage \(index + 1)")
        .accessibilityValue(parsedValue.map { "\(formattedDPIValue($0)) DPI" } ?? "Invalid value")
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
        .position(x: x, y: 58)
        .zIndex(draggingStage == index ? 20 : 2)
    }

    @ViewBuilder
    private func stageShape(isDefault: Bool, isShift: Bool) -> some View {
        if isDefault {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DPIStagePalette.defaultStage)
        } else if isShift {
            DPIStagePentagon()
                .fill(DPIStagePalette.shift)
        } else {
            Circle()
                .fill(DPIStagePalette.other)
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
                    roleIcon(isDefault: true, isShift: false, filled: isDefault, tint: DPIStagePalette.defaultStage)
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
                    roleIcon(isDefault: false, isShift: true, filled: isShift, tint: DPIStagePalette.shift)
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
        HStack(spacing: 7) {
            ForEach(legendOrder, id: \.self) { role in
                legendItem(role)
            }
        }
    }

    private func legendItem(_ role: DPILegendRole) -> some View {
        let label: String
        let isDefault: Bool
        let isShift: Bool
        let tint: Color

        switch role {
        case .defaultStage:
            label = "Default"
            isDefault = true
            isShift = false
            tint = DPIStagePalette.defaultStage
        case .shift:
            label = "DPI Shift"
            isDefault = false
            isShift = true
            tint = DPIStagePalette.shift
        case .other:
            label = "Other"
            isDefault = false
            isShift = false
            tint = DPIStagePalette.other
        }

        return HStack(spacing: 3) {
            roleIcon(isDefault: isDefault, isShift: isShift, filled: true, tint: tint)
            Text(label)
        }
    }

    private var legendOrder: [DPILegendRole] {
        let lowerRole: DPILegendRole = defaultStage <= shiftStage ? .defaultStage : .shift
        let upperRole: DPILegendRole = defaultStage <= shiftStage ? .shift : .defaultStage
        let lowerStage = min(defaultStage, shiftStage)
        let upperStage = max(defaultStage, shiftStage)
        var beforeCount = 0
        var betweenCount = 0
        var afterCount = 0

        for (index, text) in stages.enumerated() where Int(text) != nil {
            let stage = index + 1
            guard stage != defaultStage, stage != shiftStage else { continue }
            if stage < lowerStage {
                beforeCount += 1
            } else if stage > upperStage {
                afterCount += 1
            } else {
                betweenCount += 1
            }
        }

        if betweenCount > beforeCount, betweenCount > afterCount {
            return [lowerRole, .other, upperRole]
        }
        if beforeCount > betweenCount, beforeCount > afterCount {
            return [.other, lowerRole, upperRole]
        }
        // After is the fallback for ties, including one Other stage on each
        // outside of the two role stages.
        return [lowerRole, upperRole, .other]
    }

    private func interactionTargets(width: CGFloat) -> [DPIStageHitTarget] {
        stages.enumerated().compactMap { index, text in
            guard let value = Int(text) else { return nil }
            let x = draggingStage == index
                ? (activeDragX ?? position(for: value, width: width))
                : position(for: value, width: width)
            return DPIStageHitTarget(index: index, x: x)
        }
    }

    private func setActiveDragX(_ x: CGFloat, width: CGFloat) {
        let inset = trackInset
        let rightEdge = max(width - inset, inset)
        let clampedX = min(max(x, inset), rightEdge)
        guard activeDragX != clampedX else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            activeDragX = clampedX
        }
    }

    private func updateDrag(at x: CGFloat, width: CGFloat) {
        guard let index = draggingStage,
              let candidate = value(at: x, width: width) else {
            return
        }
        setActiveDragX(x, width: width)
        let update = DPIStageDragUpdate(index: index, value: candidate)
        guard lastDragUpdate != update else { return }
        let updatedIndex = onDragValue(index, candidate)
        draggingStage = updatedIndex
        lastDragUpdate = DPIStageDragUpdate(index: updatedIndex, value: candidate)
    }

    private func finishDrag() {
        onDragEnded()
        withAnimation(.easeOut(duration: 0.08)) {
            draggingStage = nil
            activeDragX = nil
        }
        lastDragUpdate = nil
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
                    DPIStagePentagon().fill(tint)
                } else {
                    DPIStagePentagon().stroke(tint, lineWidth: 1.25)
                }
            } else {
                if filled {
                    Circle().fill(tint)
                } else {
                    Circle().stroke(tint, lineWidth: 1.25)
                }
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
        return trackInset + fraction * max(width - trackInset * 2, 1)
    }

    private func value(at x: CGFloat, width: CGFloat) -> Int? {
        let minimum = capabilities.minimum ?? 100
        let maximum = capabilities.maximum ?? Int(UInt16.max)
        let fraction = min(max((x - trackInset) / max(width - trackInset * 2, 1), 0), 1)
        let logMinimum = log(Double(minimum))
        let logMaximum = log(Double(maximum))
        let raw = Int(exp(logMinimum + Double(fraction) * (logMaximum - logMinimum)).rounded())
        return capabilities.snappedValue(for: raw)
    }
}

struct ContentView: View {
    private enum AppTab: Hashable {
        case configure
        case backups
        case profileEditor
        case settings
    }

    @StateObject private var model = AppModel()
    @State private var selectedTab: AppTab = .configure
    @State private var confirmRestore = false
    @State private var restoreURL: URL?
    @State private var confirmRecoveryRestore = false
    @State private var presentedRGBZoneID: Int?
    @State private var primaryClickModalPresented = false
    @Environment(\.scenePhase) private var scenePhase

    private var preferredColorScheme: ColorScheme {
        model.isDarkAppearance ? .dark : .light
    }

    private static let darkAppBackground = Color(nsColor: .windowBackgroundColor)

    private var appBackground: Color {
        model.isDarkAppearance
            ? Self.darkAppBackground
            : Color(red: 0.965, green: 0.965, blue: 0.95)
    }

    var body: some View {
        ZStack {
            // Keep Settings on the standard macOS ⌘, shortcut even though the
            // tab itself is represented by a TabView item.
            Button("Settings") {
                selectedTab = .settings
            }
            .keyboardShortcut(",", modifiers: [.command])
            .opacity(0)
            .frame(width: 0, height: 0)

            VStack(alignment: .leading, spacing: 14) {
                if selectedTab != .settings {
                    header
                        .padding(.horizontal, 20)
                    Divider()
                        .padding(.horizontal, 20)
                }
                TabView(selection: $selectedTab) {
                    ZStack {
                        if model.loadingProfile && model.buttons.isEmpty {
                            loadingProfileState
                    } else if model.waitingForKnownDevice {
                        knownDeviceWakeState
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
                    .tabItem { Label("Configure", systemImage: "cursorarrow.click").pointerCursor() }
                    .tag(AppTab.configure)
                    backupsPane
                        .tabItem { Label("Backups", systemImage: "archivebox").pointerCursor() }
                        .tag(AppTab.backups)
                    profileEditorPane
                        .tabItem { Label("Profile Editor", systemImage: "square.and.pencil").pointerCursor() }
                        .tag(AppTab.profileEditor)
                    settingsPane
                        .tabItem { Label("Settings", systemImage: "gearshape").pointerCursor() }
                        .tag(AppTab.settings)
                }
                Divider()
                    .padding(.horizontal, 20)
                HStack(alignment: .top) {
                    Image(systemName: "info.circle")
                    Text(model.status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer()
                }
                .padding(.horizontal, 20)

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
        }
        .padding(.vertical, 20)
        .frame(minWidth: 960, minHeight: 520)
        .background(appBackground)
        .preferredColorScheme(preferredColorScheme)
        .overlay {
            if primaryClickModalPresented {
                ZStack {
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()
                        .onTapGesture { primaryClickModalPresented = false }
                        .pointerCursor()
                    CenteredAppModal(
                        title: "Primary click required",
                        message: model.primaryClickValidationMessage ?? "Choose “Left click” for the primary-click button, then save again.",
                        symbol: "exclamationmark.triangle",
                        onDefaultAction: { primaryClickModalPresented = false },
                        onCancel: { primaryClickModalPresented = false }
                    ) {
                        Button("Return to editor", role: .cancel) {
                            primaryClickModalPresented = false
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .pointerCursor()
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: primaryClickModalPresented)
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
        .alert("Allow wired mice", isPresented: $model.wiredAccessInstructionsPresented) {
            Button("Open Input Monitoring Settings", action: model.openInputMonitoringSettings)
                .pointerCursor()
            Button("Cancel", role: .cancel) {}
                .pointerCursor()
        } message: {
            Text("LOPE can use wireless and receiver-connected mice without this permission. To read and edit a wired mouse, enable LOPE in System Settings > Privacy & Security > Input Monitoring, then return and choose Refresh.")
        }
        .alert("Restore this backup?", isPresented: $confirmRestore) {
            Button("Cancel", role: .cancel) { restoreURL = nil }
                .pointerCursor()
            Button("Restore and verify", role: .destructive) {
                if let restoreURL { model.restore(restoreURL) }
                restoreURL = nil
            }
            .pointerCursor()
        } message: {
            Text(restoreURL?.lastPathComponent ?? "Selected backup")
        }
        .alert("Restore backups from this save?", isPresented: $confirmRecoveryRestore) {
            Button("Cancel", role: .cancel) {}
                .pointerCursor()
            Button("Restore and verify", role: .destructive) {
                model.restoreLastSaveBackups()
            }
            .pointerCursor()
        } message: {
            Text("LOPE will restore the exact pre-save sectors captured by the failed operation. Any sector that was already unchanged will be skipped safely.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            if !model.devices.isEmpty {
                Text("Device")
                    .font(.callout.weight(.medium))
                Picker("", selection: Binding(
                    get: { model.selectedDeviceIndex },
                    set: { model.selectDevice($0) })) {
                    ForEach(model.devices) { device in
                        Text(device.title).tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .disabled(model.devices.isEmpty)
                .pointerCursor(enabled: !model.devices.isEmpty)
            }
            Button("Refresh", action: model.refresh)
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.busy)
                .pointerCursor(enabled: !model.busy)
            if model.busy { ProgressView().controlSize(.small) }
            Spacer()
            Button("Revert edits") { model.reloadSelectedProfile() }
                .pointerCursor()
            Button("Save to mouse", action: saveToMouse)
                .buttonStyle(.borderedProminent)
                .disabled(
                    !model.hasPendingChanges || model.busy || !model.currentMouseProfile.profileIO.canSave ||
                    (model.hasDPIChanges && !model.canApplyDPI)
                )
                .pointerCursor(enabled: model.hasPendingChanges && !model.busy && model.currentMouseProfile.profileIO.canSave &&
                    (!model.hasDPIChanges || model.canApplyDPI))
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
                    .pointerCursor()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var knownDeviceWakeState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "computermouse.fill")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text("Wake \(model.currentDeviceName)")
                .font(.title3.weight(.medium))
            if let guidance = model.knownDeviceRefreshGuidance {
                Text(guidance.sleepDescription)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text(guidance.wakeInstructions)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }
            Text("Checking for the mouse in the background…")
                .font(.callout)
                .foregroundStyle(.secondary)
            ProgressView()
                .controlSize(.small)
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
                    .pointerCursor()
                }
                .padding(8)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
            }
            if !model.currentMouseProfile.profileIO.canSave {
                Text("This device is cataloged for read-only inspection until its profile-specific save format is validated.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 20)
            }
            if !model.hasSpecificMouseProfile {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.secondary)
                    Text("LOPE doesn't recognize this mouse, so buttons below are shown by number only.")
                        .font(.callout)
                    Spacer()
                    Button("Create profile") { model.createGeneratedProfile() }
                        .buttonStyle(.bordered)
                        .pointerCursor()
                }
                .padding(8)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    profilesEditor
                    if model.hasGShiftLayer {
                        HStack(spacing: 10) {
                            Text("Button assignments")
                                .font(.callout.weight(.medium))
                            Text("G-Shift assignments apply while holding the mouse’s G-Shift button.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                    }
                    Divider()
                    VStack(spacing: 8) {
                        ForEach(model.buttons) { button in
                            buttonRow(button.id)
                        }
                    }
                    Divider()
                    if model.canEditOnboardDPI {
                        dpiEditor
                    } else {
                        Text("Onboard DPI editing is unavailable for this legacy profile path.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    if model.shouldShowRGBEditor {
                        Divider()
                        rgbEditor
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
                .background(ScrollViewScrollerInset(rightInset: 3))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(model.selectedDeviceIndex)

        }
        .padding(.top, 4)
    }

    private func buttonRow(_ buttonID: Int) -> some View {
        Group {
            if let button = model.buttons.first(where: { $0.id == buttonID }) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(button.displayLabel)
                            .font(.body.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                            .help(button.displayLabel)
                        if button.draftChoice == "keystroke" {
                            if model.showNonStandardKeyboardKeys {
                                let buttonIndex = model.buttons.firstIndex(where: { $0.id == buttonID }) ?? 0
                                if model.keyboardKeyChoice(buttonIndex: buttonIndex) != 0 {
                                    keyboardModifierControls(buttonID)
                                } else {
                                    keyboardRecordingControl(buttonID)
                                }
                                keyboardChoiceCard(buttonID: buttonID)
                            } else {
                                keyboardRecordingControl(buttonID)
                            }
                        }
                        Picker("", selection: Binding(
                            get: { model.buttons.first(where: { $0.id == buttonID })?.draftChoice ?? "keystroke" },
                            set: { choice in
                                guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                                model.selectOutput(buttonIndex: index, choice: choice)
                            })) {
                            ForEach(model.presets.prefix(1)) { preset in
                                Text(preset.label).tag(preset.raw)
                            }
                            Text("Keystroke").tag("keystroke")
                            ForEach(model.presets.dropFirst()) { preset in
                                Text(preset.label).tag(preset.raw)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190, alignment: .trailing)
                        .pointerCursor()
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
                    }
                    // Keep preset rows the same height as keystroke rows. The
                    // keystroke controls are 26 pt tall, while a native
                    // Picker can otherwise make preset rows a little shorter.
                    .frame(height: 26)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func saveToMouse() {
        let canAttemptSave = model.hasPendingChanges &&
            !model.busy &&
            model.currentMouseProfile.profileIO.canSave &&
            (!model.hasDPIChanges || model.canApplyDPI)
        guard canAttemptSave else {
            model.applyAll()
            return
        }

        if model.primaryClickValidationMessage != nil {
            primaryClickModalPresented = true
        } else {
            model.applyAll()
        }
    }

    private var profilesEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(model.onboardProfileSummary)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 12)
                if model.profiles.count > 1 {
                    Text("Profile:")
                        .font(.callout.weight(.medium))
                    Picker("Profile", selection: $model.profileNumber) {
                        ForEach(model.profiles) { profile in
                            Text(profile.title).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .disabled(model.busy)
                    .pointerCursor(enabled: !model.busy)
                    Spacer(minLength: 0)
                        .frame(width: 6)
                    Text("Enable:")
                        .font(.callout.weight(.medium))
                    ForEach(model.profiles) { profile in
                        profileEnableControl(profile)
                    }
                }
                if model.hasGShiftLayer {
                    Picker("Button layer", selection: Binding(
                        get: { model.buttonLayer },
                        set: { model.selectButtonLayer($0) }
                    )) {
                        ForEach(ButtonLayer.allCases, id: \.self) { layer in
                            Text(layer.label).tag(layer)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    .pointerCursor()
                }
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Keep the loading placeholder as tall as the populated profile bar.
        // The picker and enable controls are intentionally hidden until the
        // profile read completes, which would otherwise make this bar jump.
        .frame(minHeight: 36)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 0.5)
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
        return HStack(spacing: 2) {
            Text(label)
                .font(.caption)
            Toggle("", isOn: enabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .disabled(model.busy || !model.canEditProfileState)
                .pointerCursor(enabled: !model.busy && model.canEditProfileState)
            Text(crcLabel)
                .font(.caption)
                .foregroundStyle(crcColor)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(
            profileID == model.profileNumber
                ? Color.accentColor.opacity(0.12)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .help(helpText)
    }

    private func keyboardRecordingControl(_ buttonID: Int) -> some View {
        HStack(spacing: 4) {
            KeyboardInputMonitor(
                isActive: model.recordingKeyboardButtonID == buttonID,
                onKeyDown: { event in
                    guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }),
                          let usage = model.keyboardUsage(for: event) else { return }
                    var modifier: UInt8 = 0
                    if event.modifierFlags.contains(.control) { modifier |= 0x01 }
                    if event.modifierFlags.contains(.shift) { modifier |= 0x02 }
                    if event.modifierFlags.contains(.option) { modifier |= 0x04 }
                    if event.modifierFlags.contains(.command) { modifier |= 0x08 }
                    model.recordKeyboardEvent(buttonIndex: index, keyCode: usage, modifier: modifier)
                })
                .frame(width: 0, height: 0)
            keyboardRecordingBox(buttonID)
        }
        .help("Click the input box to capture a key and its modifiers. The X cancels recording.")
    }

    private func keyboardModifierControls(_ buttonID: Int) -> some View {
        let buttonIndex = model.buttons.firstIndex(where: { $0.id == buttonID }) ?? 0
        return HStack(spacing: 4) {
            keyboardModifierToggle(buttonIndex: buttonIndex, label: "Ctrl", bit: 0x01)
            keyboardModifierToggle(buttonIndex: buttonIndex, label: "Shift", bit: 0x02)
            keyboardModifierToggle(buttonIndex: buttonIndex, label: "Alt", bit: 0x04)
            keyboardModifierToggle(buttonIndex: buttonIndex, label: "Cmd", bit: 0x08)
        }
        .frame(width: 190, height: 26, alignment: .leading)
        .help("Choose the modifiers to send with the selected extended key.")
    }

    private func keyboardModifierToggle(buttonIndex: Int, label: String, bit: UInt8) -> some View {
        Toggle(label, isOn: Binding(
            get: { model.isModifierEnabled(buttonIndex: buttonIndex, bit: bit) },
            set: { model.setModifier(buttonIndex: buttonIndex, bit: bit, enabled: $0) }
        ))
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .font(.caption)
        .fixedSize()
        .help(label)
        .pointerCursor()
    }

    private func keyboardRecordingBox(_ buttonID: Int) -> some View {
        let buttonIndex = model.buttons.firstIndex(where: { $0.id == buttonID }) ?? 0
        let isRecording = model.recordingKeyboardButtonID == buttonID
        let chord = model.keyboardChordText(buttonIndex: buttonIndex)

        return ZStack(alignment: .trailing) {
            Button {
                guard !isRecording else { return }
                model.beginKeyboardRecording(buttonIndex: buttonIndex)
            } label: {
                HStack(spacing: 0) {
                    Text(isRecording ? "Recording..." : (chord.isEmpty ? "Click to record" : chord))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 8)
                .padding(.trailing, isRecording ? 28 : 8)
                .frame(width: 190, height: 26, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .pointerCursor(enabled: !isRecording)

            if isRecording {
                Button {
                    model.cancelKeyboardRecording()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Cancel recording")
                .pointerCursor()
            }
        }
        .frame(width: 190, height: 26, alignment: .leading)
        .background(
            isRecording
                ? Color.accentColor.opacity(0.18)
                : Color.primary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    isRecording ? Color.accentColor : Color.primary.opacity(0.14),
                    lineWidth: isRecording ? 1.5 : 0.75
                )
        }
        .animation(.easeInOut(duration: 0.12), value: isRecording)
    }

    private func keyboardChoiceCard(buttonID: Int) -> some View {
        Picker("Extended key", selection: Binding(
            get: {
                guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return 0 }
                return model.keyboardKeyChoice(buttonIndex: index)
            },
            set: { key in
                guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                model.setKeyboardKeyChoice(buttonIndex: index, key: key)
            })) {
            Text("Use Recorded Key").tag(0)
            ForEach(model.keyboardOutputKeys) { key in
                Text(key.label).tag(Int(key.id))
            }
        }
        .controlSize(.small)
        .labelsHidden()
        .frame(width: 150)
        .help("Insert an extended HID keyboard usage directly.")
        .pointerCursor()
    }

    private var dpiEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Onboard DPI")
                        .font(.headline)
                    Text("Set the active sensitivity stages for this profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text("Active stages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        model.setDPIStageCount(model.dpiCount - 1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.body.weight(.semibold))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.dpiCount <= 1)
                    .pointerCursor(enabled: model.dpiCount > 1)
                    .accessibilityLabel("Remove DPI stage")
                    Text("\(model.dpiCount) of 5")
                        .font(.callout.monospacedDigit())
                        .frame(minWidth: 40)
                    Button {
                        model.setDPIStageCount(model.dpiCount + 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.dpiCount >= 5)
                    .pointerCursor(enabled: model.dpiCount < 5)
                    .accessibilityLabel("Add DPI stage")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                    if let currentDPI = model.dpiCapabilities.currentValue {
                        HStack(spacing: 6) {
                            Text("Live DPI")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formattedDPIValue(currentDPI))
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                    }

                    DPIStageBar(
                        stages: Array(model.dpiStages.prefix(model.dpiCount)),
                        defaultStage: model.defaultStage,
                        shiftStage: model.shiftStage,
                        capabilities: model.dpiCapabilities,
                        isLoading: model.loadingProfile,
                        validationMessage: model.dpiValidationMessage,
                        onDragValue: { index, value in
                            model.moveDPIStageDuringDrag(index: index, value: value)
                        },
                        onDragEnded: {
                            model.finishDPIStageDrag()
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
                    .frame(height: 105)
                    .zIndex(10)
            }
            .padding(8)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .padding(.top, 4)
    }

    private var rgbEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Onboard RGB")
                        .font(.headline)
                    Text("Choose a color for each advertised lighting zone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            VStack(spacing: 6) {
                ForEach(model.rgbZones) { zone in
                    rgbZoneRow(zone)
                }
            }
            Text("Shift-click a zone to edit every advertised zone together.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func rgbZoneRow(_ zone: RGBZoneState) -> some View {
        Button {
            let allZones = NSEvent.modifierFlags.contains(.shift)
            model.beginRGBEdit(zoneID: zone.id, allZones: allZones)
            presentedRGBZoneID = zone.id
        } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(swiftUIColor(zone.draft))
                    .frame(width: 28, height: 24)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.primary.opacity(0.28), lineWidth: 0.75)
                    }
                Text(zone.name)
                    .font(.callout.weight(.medium))
                Spacer()
                Text(zone.draft.hex)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.055), lineWidth: 0.5)
        }
        .help("Click to choose a color. Shift-click to apply the chosen color to all RGB zones.")
        .pointerCursor()
        .popover(
            isPresented: Binding(
                get: { presentedRGBZoneID == zone.id },
                set: { isPresented in
                    if !isPresented {
                        presentedRGBZoneID = nil
                        model.rgbEditingAllZones = false
                    }
                }
            ),
            arrowEdge: .trailing
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.rgbEditingAllZones ? "All RGB zones" : zone.name)
                    .font(.headline)
                ColorPicker("Color", selection: rgbColorBinding(zoneID: zone.id), supportsOpacity: false)
                    .pointerCursor()
                if let current = model.rgbZones.first(where: { $0.id == zone.id })?.draft {
                    Text(current.hex)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(width: 220)
        }
    }

    private func swiftUIColor(_ color: RGBColor) -> Color {
        Color(
            red: Double(color.red) / 255.0,
            green: Double(color.green) / 255.0,
            blue: Double(color.blue) / 255.0
        )
    }

    private func rgbColorBinding(zoneID: Int) -> Binding<Color> {
        Binding(
            get: {
                let color = model.rgbZones.first(where: { $0.id == zoneID })?.draft ??
                    RGBColor(red: 255, green: 255, blue: 255)
                return swiftUIColor(color)
            },
            set: { color in
                let converted = NSColor(color).usingColorSpace(.deviceRGB)
                guard let converted else { return }
                model.setRGBColor(
                    zoneID: zoneID,
                    color: RGBColor(
                        red: UInt8((converted.redComponent * 255.0).rounded()),
                        green: UInt8((converted.greenComponent * 255.0).rounded()),
                        blue: UInt8((converted.blueComponent * 255.0).rounded())
                    )
                )
            }
        )
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
                    .pointerCursor()
                Button("Export JSON…") {
                    if let url = model.chooseJSONExport() {
                        model.exportCurrentJSON(to: url)
                    }
                }
                .pointerCursor()
                Button("Import JSON…") {
                    if let url = model.chooseJSONBackup() {
                        model.loadEditableBackup(url)
                    }
                }
                .pointerCursor()
                Button("Choose another backup…") {
                    restoreURL = model.chooseRestoreBackup()
                    confirmRestore = restoreURL != nil
                }
                .pointerCursor()
                Button("Refresh list", action: model.refreshBackups)
                    .pointerCursor()
                Button("Open in Finder", action: model.openBackupDirectoryInFinder)
                    .pointerCursor()
            }
            Toggle("Show backups for all mice", isOn: Binding(
                get: { model.showAllBackups },
                set: { model.setShowAllBackups($0) }))
            .toggleStyle(.checkbox)
            .pointerCursor()
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
                                    .pointerCursor()
                                } else {
                                    Button("Restore") {
                                        restoreURL = backup.url
                                        confirmRestore = true
                                    }
                                    .pointerCursor()
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 120, maxHeight: 250)
                }
            }
            Text("Quit G HUB and other mouse remappers while saving. Don't bother re-enabling them after ;)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
        .padding(.horizontal, 20)
    }

    private var profileEditorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.loadingProfile && model.buttons.isEmpty {
                loadingProfileState
            } else if !model.shouldShowButtonEditor {
                emptyState
            } else {
                HStack(spacing: 8) {
                    Text("Profile ID")
                        .font(.callout.weight(.medium))
                    TextField("", text: $model.profileEditorID)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 130)
                    Text("Display name")
                        .font(.callout.weight(.medium))
                    TextField("", text: $model.profileEditorName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    Spacer()
                    Button("Import profile…", action: model.importProfileEditorDraft)
                        .pointerCursor()
                    Button("Export profile…", action: model.exportProfileEditorDraft)
                        .pointerCursor()
                }
                .padding(.horizontal, 20)
                Text("Name each control below, then save. The saved profile is matched to \(model.currentDeviceName.isEmpty ? "this mouse" : model.currentDeviceName) by device name and product ID; a file with the same profile ID as a bundled one replaces it. Export produces a complete descriptor, ready to copy into Profiles/ for a pull request once Sources below is filled in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.profileEditorButtonNumbers, id: \.self) { number in
                            HStack(spacing: 10) {
                                Text("Button \(number)")
                                    .frame(width: 90, alignment: .leading)
                                    .foregroundStyle(.secondary)
                                TextField("Control name", text: Binding(
                                    get: { model.profileEditorButtonNames[number] ?? "" },
                                    set: { model.profileEditorButtonNames[number] = $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                        Divider()
                            .padding(.top, 4)
                        Text("Sources (one URL per line)")
                            .font(.callout.weight(.medium))
                        TextEditor(text: $model.profileEditorSources)
                            .font(.system(.callout, design: .monospaced))
                            .frame(height: 70)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(model.selectedDeviceIndex)
                HStack {
                    Spacer()
                    Button("Save as custom profile") { model.saveProfileEditorDraft() }
                        .buttonStyle(.borderedProminent)
                        .pointerCursor()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .padding(.top, 4)
    }

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
            GroupBox("Storage") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Configuration directory")
                        .font(.callout.weight(.medium))
                    Text(model.configurationDirectoryPath)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    Text("Backups and custom mouse profiles are stored in separate subfolders here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Choose directory…") {
                            if let directory = model.chooseConfigurationDirectory() {
                                model.setConfigurationDirectory(directory)
                            }
                        }
                        .pointerCursor()
                        Button("Use default") { model.resetConfigurationDirectory() }
                            .disabled(model.configurationDirectoryPath == model.defaultConfigurationDirectoryPath)
                            .pointerCursor(enabled: model.configurationDirectoryPath != model.defaultConfigurationDirectoryPath)
                    }
                }
                .padding(4)
            }
            GroupBox("Mouse profiles") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.customMouseProfileCount > 0
                         ? "\(model.builtInMouseProfileCount) built-in mice, plus \(model.customMouseProfileCount) custom."
                         : "\(model.builtInMouseProfileCount) built-in mice supported.")
                        .font(.callout)
                    Text("Add your own or override a bundled one by dropping a JSON descriptor into the custom profiles folder. It starts with an example file that shows the format.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open custom profiles folder", action: model.openCustomProfilesDirectoryInFinder)
                        .pointerCursor()
                }
                .padding(4)
            }
            GroupBox("Advanced display") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show raw HID++ fields", isOn: Binding(
                        get: { model.showAdvancedFields },
                        set: { model.setShowAdvancedFields($0) }))
                        .toggleStyle(.checkbox)
                        .pointerCursor()
                    Text("Shows the 8-digit button records and profile sector numbers. Leave this off for the normal editing view.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }
            GroupBox("Keyboard outputs") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show non-standard keyboard keys", isOn: Binding(
                        get: { model.showNonStandardKeyboardKeys },
                        set: { model.setShowNonStandardKeyboardKeys($0) }))
                        .toggleStyle(.checkbox)
                        .pointerCursor()
                    Text("Shows the optional extended-key override for usages such as Insert, F13–F24, and Sleep. Recording captures modifiers automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }
            GroupBox("Appearance") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Color mode", selection: Binding(
                        get: { model.appearancePreference },
                        set: { model.setAppearancePreference($0) }
                    )) {
                        ForEach(AppearancePreference.allCases, id: \.self) { preference in
                            Text(preference.label).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                    .pointerCursor()
                    Text("System follows macOS. Light mode uses a soft off-white background; the DPI colors remain unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }
            Spacer()
        }
        .padding(.top, 4)
        .padding(.horizontal, 20)
    }
}
