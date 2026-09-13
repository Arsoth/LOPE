// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import SwiftUI

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
