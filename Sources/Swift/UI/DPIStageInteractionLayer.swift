// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import CoreVideo
import SwiftUI

struct DPIStageOutsideClickMonitor: NSViewRepresentable {
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

struct DPIStageHitTarget: Equatable {
  let index: Int
  let x: CGFloat
  let role: DPILegendRole
}

/// Owns pointer interaction for the entire stage bar. Keeping click arbitration,
/// drag thresholding, and display-linked cursor sampling in one native view avoids
/// competing SwiftUI tap/drag recognizers and keeps the active handle under the
/// physical pointer even while the stage model is being reordered.

struct DPIStageInteractionLayer: NSViewRepresentable {
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
    var targets: [DPIStageHitTarget] = []
    var onTap: ((Int) -> Void)?
    var onBackgroundClick: (() -> Void)?
    var onDragBegan: ((Int, CGFloat) -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: ((CGFloat) -> Void)?

    private let dragThreshold: CGFloat = 5
    // Matches the visible badge (the circle/rounded-rect/pentagon icon drawn
    // in `stageHandle`), not the button's full frame, which also spans the
    // DPI value label below the badge. The label is not a drag/click target.
    private let badgeSize: CGFloat = 34
    private let badgeCenterY: CGFloat = 43
    private let trackRange: ClosedRange<CGFloat> = 24...65
    private var mouseDownPoint: CGPoint?
    private var pendingStage: Int?
    private var pendingStageWasHandle = false
    private var isDraggingStage = false
    private var isSamplingActive = false
    private var displayLink: CVDisplayLink?
    private let tickLock = NSLock()
    private var tickQueued = false
    private var hoverTrackingArea: NSTrackingArea?
    private var isShowingPointingHand = false

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Cursor rects (`resetCursorRects`/`addCursorRect`) and `.cursorUpdate`
    // tracking areas both only re-evaluate the cursor when the pointer
    // *enters* a registered region; neither reacts as the pointer glides
    // between a handle and the bare track within this one large view. A
    // `.mouseMoved` tracking area gets a callback on every move so the
    // handles can show a pointing hand exactly while over them.
    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      if let hoverTrackingArea {
        removeTrackingArea(hoverTrackingArea)
      }
      let area = NSTrackingArea(
        rect: bounds,
        options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
        owner: self,
        userInfo: nil
      )
      addTrackingArea(area)
      hoverTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
      super.mouseMoved(with: event)
      updateHoverCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
      super.mouseExited(with: event)
      setPointingHand(false)
    }

    private func updateHoverCursor(at point: CGPoint) {
      setPointingHand(target(at: point) != nil)
    }

    private func setPointingHand(_ showPointingHand: Bool) {
      guard showPointingHand != isShowingPointingHand else { return }
      isShowingPointingHand = showPointingHand
      (showPointingHand ? NSCursor.pointingHand : NSCursor.arrow).set()
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
      targets.last { contains(point, target: $0) }
    }

    private func nearestTarget(to x: CGFloat) -> DPIStageHitTarget? {
      targets.min { abs($0.x - x) < abs($1.x - x) }
    }

    private func contains(_ point: CGPoint, target: DPIStageHitTarget) -> Bool {
      let rect = badgeRect(for: target.x)
      guard rect.contains(point) else { return false }
      switch target.role {
      case .other:
        let radius = rect.width / 2
        return hypot(point.x - rect.midX, point.y - rect.midY) <= radius
      case .shift:
        return DPIStagePentagon().path(in: rect).cgPath.contains(point)
      case .defaultStage:
        // A 4pt corner radius on a 34pt square clips a sliver few pointers
        // will ever land on; the bounding square is a fine approximation.
        return true
      }
    }

    private func badgeRect(for x: CGFloat) -> CGRect {
      CGRect(
        x: x - badgeSize / 2,
        y: badgeCenterY - badgeSize / 2,
        width: badgeSize,
        height: badgeSize
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
