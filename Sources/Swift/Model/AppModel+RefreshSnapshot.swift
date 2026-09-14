// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  func applyRefreshSnapshot(_ snapshot: RefreshSnapshot) {
    defer {
      // A failed read for a non-wired mouse transitions directly into the
      // wake/recovery poll. Keep the operation busy until that poll either
      // reconnects the mouse or reaches its timeout.
      busy = waitingForKnownDevice
      loadingProfile = false
      refreshTask = nil
    }

    if let errorMessage = snapshot.errorMessage {
      publishDevices([])
      resetEditorState()
      deviceSummary = "Unable to access the Logitech HID++ interface"
      status = errorMessage
      return
    }

    let selectedSnapshotDevice = snapshot.selectedDeviceIndex.flatMap { selectedIndex in
      snapshot.devices.first(where: { $0.id == selectedIndex })
    }
    publishDevices(snapshot.devices)
    guard let selected = selectedSnapshotDevice
    else {
      selectedDeviceIndex = 0
      currentDeviceName = ""
      deviceSummary = "No editable Logitech mouse found"
      onboardProfileCapacity = nil
      profiles = []
      buttons = []
      resetEditorState()
      status =
        snapshot.accessWarning
        ? "A wired Logitech mouse needs Input Monitoring. Choose a wireless mouse, or enable access in System Settings."
        : devices.contains(where: { !$0.isWiredAccessPrompt })
          ? "Choose a Logitech mouse to continue."
          : "No Logitech mouse was found"
      return
    }

    selectedDeviceIndex = selected.id
    currentDeviceName = selected.name
    deviceSummary = selected.title
    rememberSelectedDevice(selected)
    refreshBackups()

    guard let profileText = snapshot.profileText else {
      if selected.isNonWiredDevice && snapshot.profileError != nil {
        beginKnownDeviceRefresh(selected)
        return
      }
      resetEditorState()
      dpiDetails = "This device does not expose an editable onboard profile through HID++ 0x8100."
      if snapshot.profileError != nil {
        status = profileReadStatus(
          for: selected.name, accessWarning: snapshot.accessWarning && selected.isWiredDevice)
      } else {
        status = "Connected to \(selected.name), but no compatible onboard profile was found."
      }
      return
    }

    let parsed = parseProfiles(profileText)
    profiles = parsed.choices
    rgbZones.removeAll()
    baselineRGBColors.removeAll()
    rgbEditingAllZones = false
    let reportedCapacity = Self.onboardProfileCapacity(in: profileText)
    onboardProfileCapacity = reportedCapacity ?? parsed.choices.count
    onboardProfileCapacityWasReported = reportedCapacity != nil
    baselineProfileEnabled = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.enabled) })
    keyInputDrafts.removeAll()
    resetDPIState()
    if profiles.isEmpty {
      buttons = []
      normalButtonRows = []
      gShiftButtonRows = []
      buttonLayer = .normal
      status = "The mouse was found, but no onboard profiles were readable."
      return
    }
    // `resolvedProfileNumber` only returns nil when `availableProfileIDs`
    // is empty (see ProfileSelection.swift), which the `profiles.isEmpty`
    // guard above already ruled out, so it always returns a member of
    // `profiles.map(\.id)` here -- force-unwrapping documents that
    // guarantee instead of a `?? profiles[0].id` fallback that could never
    // actually run.
    profileNumber =
      ProfileSelection.resolvedProfileNumber(
        selectedProfileNumber: snapshot.selectedProfileNumber,
        availableProfileIDs: profiles.map(\.id),
        preferredProfileNumber: profileNumber
      )!
    // `parseProfiles` unconditionally seeds `rows[id]`/`gShiftRows[id]`/
    // `rgb[id]` to `[]` for every profile it discovers (see
    // AppModel+Parsing.swift), and `profileNumber` above is always one of
    // those discovered ids, so each dictionary already has an entry here
    // -- force-unwrapping documents that instead of an unreachable `?? []`.
    setButtonRows(
      normal: parsed.rowsByProfile[profileNumber]!,
      gShift: parsed.gShiftRowsByProfile[profileNumber]!
    )
    applyRGBZones(
      parsed.rgbByProfile[profileNumber]!,
      profileFormat: parsed.profileFormatsByProfile[profileNumber]
    )
    dpiDetails = ""
    parseDPI(profileText)
    parsePollingRate(profileText)
    if dpiDetails.isEmpty {
      dpiDetails = snapshot.dpiError ?? "DPI capabilities could not be read."
    }
    stopKnownDevicePolling(clearDevice: true)
    startLiveDPIPolling()
    scheduleInitialBackups(for: selected, profileNumbers: profiles.map(\.id))
    status =
      snapshot.accessWarning && selected.isWiredDevice && !isMXSeriesMouse
      ? "Some Logitech interfaces were denied by macOS. Enable Input Monitoring, then Refresh."
      : "Onboard Profile read successfully."
  }

  func resetEditorState() {
    stopLiveDPIPolling()
    onboardProfileCapacity = nil
    onboardProfileCapacityWasReported = false
    profiles = []
    buttons = []
    normalButtonRows = []
    gShiftButtonRows = []
    buttonLayer = .normal
    baselineProfileEnabled.removeAll()
    keyInputDrafts.removeAll()
    rgbZones.removeAll()
    baselineRGBColors.removeAll()
    rgbEditingAllZones = false
    resetDPIState()
  }

  func prepareLoadingEditor(profileNumber placeholderProfileNumber: Int) {
    let placeholderNumber = max(placeholderProfileNumber, 1)
    onboardProfileCapacity = nil
    onboardProfileCapacityWasReported = false
    profiles = [
      ProfileChoice(
        id: placeholderNumber,
        sector: "Loading…",
        enabled: true,
        crcValid: nil
      )
    ]
    profileNumber = placeholderNumber
    baselineProfileEnabled = [placeholderNumber: true]
    keyInputDrafts.removeAll()
    setButtonRows(normal: loadingButtonRows(), gShift: [])
    rgbZones.removeAll()
    baselineRGBColors.removeAll()
    rgbEditingAllZones = false
    resetDPIState()
    dpiCapabilities = currentMouseProfile.initialDPICapabilities
    dpiDetails = "Loading DPI capabilities from the mouse…"
  }

  func resetDPIState() {
    dpiStages = ["", "", "", "", ""]
    dpiCount = 5
    defaultStage = 1
    shiftStage = 1
    dpiCapabilities = DPICapabilities()
    pollingRateCapabilities = PollingRateCapabilities()
    pollingRateDraft = nil
    baselinePollingRate = nil
    baselineDPIStages = ["", "", "", "", ""]
    baselineDPICount = 5
    baselineDefaultStage = 1
    baselineShiftStage = 1
    dpiDetails = "DPI capabilities have not been read."
  }

  func profileReadStatus(for deviceName: String, accessWarning: Bool) -> String {
    if accessWarning && !isMXSeriesMouse {
      return
        "macOS is blocking access to \(deviceName). Enable Input Monitoring, then choose Refresh."
    }
    if devices.first(where: { $0.id == selectedDeviceIndex })?.isWiredDevice == true {
      return "Couldn’t read \(deviceName)’s onboard profile. Choose Refresh to try again."
    }
    return
      "Couldn’t read \(deviceName)’s onboard profile. Is the mouse turned on and awake? Wake it, then choose Refresh."
  }
}
