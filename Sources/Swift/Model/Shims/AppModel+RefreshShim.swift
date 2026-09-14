// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation
import IOKit.hidsystem

// See the note in AppModel+JSONEditableBackupsShim.swift: everything under
// Sources/Swift/Model/Shims/ wraps a real, unmockable AppKit modal dialog
// or NSWorkspace call and is excluded from the Swift coverage gate.

@MainActor
extension AppModel {
  func openInputMonitoringSettings() {
    updateInputMonitoringAuthorization()
    openInputMonitoringSettings(
      requestAccess: {
        // Apple documents this explicit request for IOHIDManager/IOHIDDevice
        // access (macOS 10.15+). Run it in the GUI process, without opening
        // unrelated HID interfaces or waiting for a helper invocation.
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        updateInputMonitoringAuthorization()
      },
      openSettings: { openInputMonitoringSettingsPane() }
    )
  }

  private func openInputMonitoringSettingsPane() {
    let candidates = [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent",
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
