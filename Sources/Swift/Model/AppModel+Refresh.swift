// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

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
  /// Both permission buttons share this sequence. Keep the OS calls injected
  /// so denial, retries, and opening Settings can be verified without changing
  /// the test runner's real privacy permissions.
  func openInputMonitoringSettings(requestAccess: () -> Void, openSettings: () -> Void) {
    if !inputMonitoringAuthorized {
      inputMonitoringRequestInProgress = true
      defer { inputMonitoringRequestInProgress = false }
      refreshGeneration += 1
      refreshTask?.cancel()
      refreshTask = nil
      knownDevicePollTask?.cancel()
      knownDevicePollTask = nil
      stopLiveDPIPolling()
      busy = false
      loadingProfile = false
      requestAccess()
    }
    // A settings button must still open the pane when access is already
    // granted, just became granted, or a previous request was denied.
    openSettings()
  }

  func refresh() {
    inputMonitoringRequestInProgress = false
    let expectedDevice = knownDisconnectedDevice
    let preferredDeviceIndex =
      devices.contains {
        $0.id == selectedDeviceIndex
      } ? selectedDeviceIndex : -1
    stopKnownDevicePolling(clearDevice: false)
    stopLiveDPIPolling()
    startRefresh(
      preferredDeviceIndex: preferredDeviceIndex,
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
    inputMonitoringRequestInProgress = false
    if selected.isWiredDevice {
      if !inputMonitoringAuthorized {
        presentWiredAccessInstructions(for: selected)
        return
      }
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

  func updateInputMonitoringAuthorization() {
    inputMonitoringAuthorized =
      IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    if inputMonitoringAuthorized {
      if wiredAccessInstructionsPresented {
        wiredAccessInstructionsPresented = false
      }
      wiredAccessDeviceName = nil
      if inputMonitoringRequestInProgress {
        inputMonitoringRequestInProgress = false
        if reconnectMonitorTask == nil {
          startReconnectMonitor()
        }
      }
    }
  }

  func presentWiredAccessInstructions(for device: DeviceChoice? = nil) {
    guard !wiredAccessInstructionsPresented else { return }
    wiredAccessDeviceName = device?.name ?? devices.first(where: { $0.isWiredDevice })?.name
    wiredAccessInstructionsPresented = true
  }

  func publishDevices(_ discovered: [DeviceChoice]) {
    devices = discovered
  }

  func showInputMonitoringRequirement(for device: DeviceChoice) {
    stopLiveDPIPolling()
    busy = false
    loadingProfile = false
    refreshTask = nil
    currentDeviceName = device.name
    deviceSummary = device.title
    resetEditorState()
    status =
      "Input Monitoring is required to read \(device.name). Choose the device again to open System Settings."
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
