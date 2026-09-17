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
      deviceSummary = L10n.text("Unable to access the Logitech HID++ interface")
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
      deviceSummary = L10n.text("No editable Logitech mouse found")
      onboardProfileCapacity = nil
      profiles = []
      buttons = []
      resetEditorState()
      status =
        snapshot.accessWarning
        ? L10n.text(
          "A wired Logitech mouse needs Input Monitoring. Choose a wireless mouse, or enable access in System Settings."
        )
        : devices.contains(where: { $0.isWiredDevice }) && !inputMonitoringAuthorized
          ? L10n.text(
            "A wired Logitech mouse needs Input Monitoring. Select it to enable access in System Settings."
          )
          : !devices.isEmpty
            ? L10n.text("Choose a Logitech mouse to continue.")
            : L10n.text("No Logitech mouse was found")
      return
    }

    selectedDeviceIndex = selected.id
    currentDeviceName = selected.name
    deviceSummary = selected.title
    rememberSelectedDevice(selected)
    refreshBackups()

    guard let profileResponse = snapshot.profileResponse else {
      if selected.isNonWiredDevice && snapshot.profileError != nil {
        beginKnownDeviceRefresh(selected)
        return
      }
      resetEditorState()
      dpiDetails = L10n.text(
        "This device does not expose an editable onboard profile through HID++ 0x8100."
      )
      if snapshot.profileError != nil {
        status = profileReadStatus(
          for: selected.displayName,
          accessWarning: snapshot.accessWarning && selected.isWiredDevice
        )
      } else {
        status =
          L10n.text(
            "Connected to {device}, but no compatible onboard profile was found.",
            replacements: ["device": selected.displayName]
          )
      }
      return
    }

    let parsed = parseProfiles(profileResponse)
    let reportedCapacity = profileResponse.profileCapacity
    profiles = parsed.choices
    rgbZones.removeAll()
    baselineRGBColors.removeAll()
    rgbEditingAllZones = false
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
      status = L10n.text("The mouse was found, but no onboard profiles were readable.")
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
    if let dpi = profileResponse.dpi {
      applyStructuredDPI(dpi, profile: profileResponse.selectedProfile)
    }
    pollingRateCapabilities = profileResponse.reportRate?.capabilities ?? PollingRateCapabilities()
    pollingRateDraft = pollingRateCapabilities.currentRate
    baselinePollingRate = pollingRateCapabilities.currentRate
    if dpiDetails.isEmpty {
      dpiDetails = snapshot.dpiError ?? L10n.text("DPI capabilities could not be read.")
    }
    stopKnownDevicePolling(clearDevice: true)
    startLiveDPIPolling()
    scheduleInitialBackups(for: selected, profileNumbers: profiles.map(\.id))
    status =
      snapshot.accessWarning && selected.isWiredDevice && !isMXSeriesMouse
      ? L10n.text(
        "Some Logitech interfaces were denied by macOS. Enable Input Monitoring, then Refresh.")
      : L10n.text("Onboard Profile read successfully.")
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
        sector: L10n.text("Loading…"),
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
    dpiDetails = L10n.text("Loading DPI capabilities from the mouse…")
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
    dpiDetails = L10n.text("DPI capabilities have not been read.")
  }

  func profileReadStatus(for deviceName: String, accessWarning: Bool) -> String {
    if accessWarning && !isMXSeriesMouse {
      return
        L10n.text(
          "macOS is blocking access to {device}. Enable Input Monitoring, then choose Refresh.",
          replacements: ["device": deviceName]
        )
    }
    if devices.first(where: { $0.id == selectedDeviceIndex })?.isWiredDevice == true {
      return L10n.text(
        "Couldn’t read {device}’s onboard profile. Choose Refresh to try again.",
        replacements: ["device": deviceName]
      )
    }
    return
      L10n.text(
        "Couldn’t read {device}’s onboard profile. Is the mouse turned on and awake? Wake it, then choose Refresh.",
        replacements: ["device": deviceName]
      )
  }
}
