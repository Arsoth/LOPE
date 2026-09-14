// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import SwiftUI

struct ModalKeyboardHandler: NSViewRepresentable {
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

struct KeyboardInputMonitor: NSViewRepresentable {
  let isActive: Bool
  let onKeyDown: (NSEvent) -> Void

  final class Coordinator {
    var isActive = false
    var onKeyDown: (NSEvent) -> Void = { _ in }
    var localMonitor: Any?

    func update(isActive: Bool, onKeyDown: @escaping (NSEvent) -> Void) {
      self.isActive = isActive
      self.onKeyDown = onKeyDown
      if isActive {
        installLocalMonitor()
      } else {
        removeLocalMonitor()
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

    private func removeLocalMonitor() {
      if let localMonitor {
        NSEvent.removeMonitor(localMonitor)
        self.localMonitor = nil
      }
    }

    deinit {
      removeLocalMonitor()
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
