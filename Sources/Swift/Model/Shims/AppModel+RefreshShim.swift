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
    guard !inputMonitoringAuthorized else {
      openInputMonitoringSettingsPane()
      return
    }

    // This is the supported HID access request. It registers LOPE with the
    // Input Monitoring privacy pane so the user can enable it there, while
    // keeping the request behind an explicit user action. TCC commits the
    // registration asynchronously, so let that transaction reach the run
    // loop before launching System Settings; otherwise the pane can open
    // before the new disabled row has been materialized.
    _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 250_000_000)
      guard let self else { return }
      updateInputMonitoringAuthorization()
      if inputMonitoringAuthorized {
        status = "Input Monitoring is enabled. Choose Refresh to read the mouse."
        return
      }
      openInputMonitoringSettingsPane()
    }
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
