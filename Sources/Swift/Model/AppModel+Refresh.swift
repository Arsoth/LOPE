// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation
import IOKit.hidsystem

enum AppModelRefreshConfiguration {
  static let deviceReadAttempts = 3
  static let deviceReadRetryDelay: TimeInterval = 0.2
  static let profileReadAttempts = 5
  static let profileReadRetryDelay: TimeInterval = 0.25
  static let reconnectPollNanoseconds: UInt64 = 2_000_000_000
  // The live query is current-sensor-only, but still starts a short-lived engine
  // process and HID context. Two reads per second are responsive without making
  // the mouse or receiver handle unnecessary traffic.
  static let liveDPIPollNanoseconds: UInt64 = 500_000_000
}

@MainActor
extension AppModel {
  func refresh() {
    let expectedDevice = knownDisconnectedDevice
    stopKnownDevicePolling(clearDevice: false)
    stopLiveDPIPolling()
    startRefresh(
      preferredDeviceIndex: selectedDeviceIndex,
      preferredProfileNumber: profileNumber,
      expectedDevice: expectedDevice
    )
  }

  func initialRefresh() {
    guard let cachedDevice = loadLastSelectedDevice() else {
      refresh()
      return
    }
    startInitialRefresh(cachedDevice: cachedDevice)
  }

  func selectDevice(_ index: Int) {
    guard let selected = devices.first(where: { $0.id == index }) else { return }
    if selected.isWiredAccessPrompt {
      wiredAccessInstructionsPresented = true
      return
    }
    guard selectedDeviceIndex != index else { return }
    stopKnownDevicePolling(clearDevice: true)
    recoveryBackups.removeAll()
    recoveryDeviceKey = nil
    selectedDeviceIndex = index
    rememberSelectedDevice(selected)
    // Profile numbers are device-local. Reusing the previous mouse's
    // selection can target a disabled/partially provisioned slot on the
    // newly selected mouse, so let the engine choose its first enabled
    // profile and report that actual slot back to the UI.
    currentDeviceName = selected.name
    deviceSummary = selected.title
    refreshBackups()
    startRefresh(preferredDeviceIndex: index, preferredProfileNumber: 0)
  }

  func openInputMonitoringSettings() {
    updateInputMonitoringAuthorization()
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

  func updateInputMonitoringAuthorization() {
    inputMonitoringAuthorized =
      IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
  }

  func reloadSelectedProfile() {
    guard !busy, !profiles.isEmpty else { return }
    // Profile changes use the same enumerating, retrying path as the
    // Refresh button. The old one-shot read could return only the profile
    // header after a transient HID++ timeout and leave the editor empty.
    refresh()
  }

  func reloadSelectedProfileContents() {
    do {
      let profileText = try runEngine([
        "--summary-only",
        "--with-report-rate",
        "--profile", String(profileNumber),
        "profiles",
      ])
      let parsed = parseProfiles(profileText)
      setButtonRows(
        normal: parsed.rowsByProfile[profileNumber] ?? parsed.rowsByProfile.values.first ?? [],
        gShift: parsed.gShiftRowsByProfile[profileNumber] ?? parsed.gShiftRowsByProfile.values.first
          ?? []
      )
      applyRGBZones(
        parsed.rgbByProfile[profileNumber] ?? [],
        profileFormat: parsed.profileFormatsByProfile[profileNumber]
      )
      loadDPI(profileText: profileText)
      parsePollingRate(profileText)
      status = "Reloaded profile \(profileNumber)."
    } catch {
      status = error.localizedDescription
    }
  }
}
