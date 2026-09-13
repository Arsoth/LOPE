// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import ApplicationServices
import CoreGraphics
import CoreVideo
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
      CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.38),
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

func formattedDPIValue(_ value: Int) -> String {
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

extension View {
  func pointerCursor(enabled: Bool = true) -> some View {
    modifier(PointerCursorModifier(enabled: enabled))
  }
}

struct CenteredAppModal<Actions: View>: View {
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
        case 36, 76:  // Return and Enter on the numeric keypad.
          self.onDefaultAction()
          return nil
        case 53:  // Escape.
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

struct ScrollViewScrollerInset: NSViewRepresentable {
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

struct KeyboardInputMonitor: NSViewRepresentable {
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
      let eventMask =
        (CGEventMask(1) << CGEventType.keyDown.rawValue)
        | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
      let coordinatorPointer = Unmanaged.passUnretained(self).toOpaque()
      guard
        let tap = CGEvent.tapCreate(
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
        )
      else {
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

struct EscapeKeyMonitor: NSViewRepresentable {
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
        let link
      else { return }
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

struct DPIStageBar: View {
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

        ForEach(Array(stages.enumerated()).filter { Int($0.element) != nil }, id: \.offset) {
          item in
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
          stages.indices.contains(editingStage.index)
        {
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
                stages.indices.contains(fadingStage.index)
              {
                stagePopover(index: fadingStage.index, isInteractive: false)
                  .opacity(1 - popoverContentOpacity)
                  .allowsHitTesting(false)
              }
              if let presentedStage,
                stages.indices.contains(presentedStage.index)
              {
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
    let x =
      draggingStage == index
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
          roleIcon(
            isDefault: true, isShift: false, filled: isDefault, tint: DPIStagePalette.defaultStage)
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
    .background(
      Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
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
      let x =
        draggingStage == index
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
      let candidate = value(at: x, width: width)
    else {
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
