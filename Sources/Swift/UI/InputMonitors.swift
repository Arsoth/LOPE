// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import ApplicationServices
import CoreGraphics
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
