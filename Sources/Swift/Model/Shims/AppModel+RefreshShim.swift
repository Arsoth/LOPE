// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation
import IOKit.hid
import IOKit.hidsystem

// See the note in AppModel+JSONEditableBackupsShim.swift: everything under
// Sources/Swift/Model/Shims/ wraps a real, unmockable AppKit modal dialog
// or NSWorkspace call and is excluded from the Swift coverage gate.

@MainActor
extension AppModel {
  func openInputMonitoringSettings() {
    updateInputMonitoringAuthorization()
    guard !inputMonitoringAuthorized else {
      openInputMonitoringSettingsPane()
      return
    }
    guard !inputMonitoringRequestInProgress else { return }

    inputMonitoringRequestInProgress = true
    refreshGeneration += 1
    refreshTask?.cancel()
    refreshTask = nil
    knownDevicePollTask?.cancel()
    knownDevicePollTask = nil
    stopLiveDPIPolling()
    busy = false
    loadingProfile = false

    // This is the supported HID access request. It registers LOPE with the
    // Input Monitoring privacy pane so the user can enable it there, while
    // keeping the request behind an explicit user action. Wait for any
    // already-running helper invocation to finish first: TCC can otherwise
    // attribute the new client to the bundled `lope` process instead of the
    // GUI that the user explicitly asked to register.
    Task { @MainActor [weak self] in
      await EngineRunner.waitUntilIdle()
      guard let self, !Task.isCancelled else { return }
      _ = materializeInputMonitoringClient()
      _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
      try? await Task.sleep(nanoseconds: 250_000_000)
      guard !Task.isCancelled else { return }
      updateInputMonitoringAuthorization()
      if inputMonitoringAuthorized {
        status = "Input Monitoring is enabled. Choose Refresh to read the mouse."
        return
      }
      openInputMonitoringSettingsPane()
    }
  }

  /// `IOHIDRequestAccess` is the explicit registration API, but the protected
  /// HID operation itself is `IOHIDManagerOpen`/`IOHIDDeviceOpen`. Exercise
  /// both paths from the GUI once, only after the user clicks this button, so
  /// TCC materializes LOPE rather than the bundled command-line helper.
  private func materializeInputMonitoringClient() -> Bool {
    let options = IOOptionBits(kIOHIDOptionsTypeNone)
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, options)
    let matching =
      NSDictionary(object: 0x046D, forKey: kIOHIDVendorIDKey as NSString)
      as CFDictionary
    IOHIDManagerSetDeviceMatching(manager, matching)
    let managerResult = IOHIDManagerOpen(manager, options)
    var deviceOpened = false

    if let devices = IOHIDManagerCopyDevices(manager) {
      var references = [UnsafeRawPointer?](repeating: nil, count: CFSetGetCount(devices))
      CFSetGetValues(devices, &references)
      for reference in references {
        guard let reference else { continue }
        let device = Unmanaged<IOHIDDevice>.fromOpaque(reference).takeUnretainedValue()
        if IOHIDDeviceOpen(device, options) == kIOReturnSuccess {
          deviceOpened = true
          _ = IOHIDDeviceClose(device, options)
          break
        }
      }
    }
    _ = IOHIDManagerClose(manager, options)
    return managerResult == kIOReturnSuccess || deviceOpened
  }

  private func openInputMonitoringSettingsPane() {
    let candidates = [
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
      "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
    ]
    for value in candidates {
      if let url = URL(string: value), NSWorkspace.shared.open(url) {
        status = "Enable Input Monitoring for this app, then return and choose Refresh."
        return
      }
    }
    status =
      "Open System Settings > Privacy & Security > Input Monitoring, enable this app, then choose Refresh."
  }
}
