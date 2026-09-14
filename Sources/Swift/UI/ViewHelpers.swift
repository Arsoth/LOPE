// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import SwiftUI

private struct PointingHandCursorModifier: ViewModifier {
  let enabled: Bool

  func body(content: Content) -> some View {
    content.overlay {
      CursorRectView(cursor: enabled ? .pointingHand : .arrow)
        .allowsHitTesting(false)
    }
  }
}

extension View {
  /// Adds a view-owned pointing-hand cursor region without changing layout or
  /// competing with cursor regions belonging to neighboring controls.
  func pointingHandCursor(enabled: Bool = true) -> some View {
    modifier(PointingHandCursorModifier(enabled: enabled))
  }
}

private struct CursorRectView: NSViewRepresentable {
  let cursor: NSCursor

  func makeNSView(context: Context) -> CursorNSView {
    CursorNSView(cursor: cursor)
  }

  func updateNSView(_ nsView: CursorNSView, context: Context) {
    nsView.cursor = cursor
  }

  final class CursorNSView: NSView {
    var cursor: NSCursor {
      didSet {
        window?.invalidateCursorRects(for: self)
      }
    }

    init(cursor: NSCursor) {
      self.cursor = cursor
      super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
      cursor = .arrow
      super.init(coder: coder)
    }

    override func resetCursorRects() {
      super.resetCursorRects()
      addCursorRect(bounds, cursor: cursor)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      nil
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
