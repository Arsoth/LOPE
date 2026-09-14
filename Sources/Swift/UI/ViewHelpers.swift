// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import SwiftUI

private struct PointingHandCursorModifier: ViewModifier {
  let enabled: Bool
  let circleDiameter: CGFloat?

  func body(content: Content) -> some View {
    content.onContinuousHover { phase in
      guard enabled else { return }
      switch phase {
      case .active(let location):
        let isInsideCircle: Bool
        if let circleDiameter {
          let radius = circleDiameter / 2
          isInsideCircle = hypot(location.x - radius, location.y - radius) <= radius
        } else {
          isInsideCircle = true
        }
        (isInsideCircle ? NSCursor.pointingHand : NSCursor.arrow).set()
      case .ended:
        NSCursor.arrow.set()
      }
    }
  }
}

extension View {
  /// Adds a view-owned pointing-hand cursor region without changing layout or
  /// competing with cursor regions belonging to neighboring controls.
  func pointingHandCursor(enabled: Bool = true) -> some View {
    modifier(PointingHandCursorModifier(enabled: enabled, circleDiameter: nil))
  }

  /// Adds a pointing-hand cursor only inside a circular interaction region.
  func pointingHandCursor(circleDiameter: CGFloat, enabled: Bool = true) -> some View {
    modifier(PointingHandCursorModifier(enabled: enabled, circleDiameter: circleDiameter))
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
