// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  func startInitialRefresh(cachedDevice: DeviceChoice) {
    let normalizedDevice = cachedDevice.replacingName(
      DeviceChoice.normalizedReportedName(cachedDevice.name))
    // Keep the cached device visible while enumeration is in flight. The
    // normal refresh path enumerates first, so the picker can be replaced by
    // the current device list before any profile read or wake flow starts.
    devices = [normalizedDevice]
    selectedDeviceIndex = normalizedDevice.id
    currentDeviceName = normalizedDevice.name
    deviceSummary = normalizedDevice.title
    startRefresh(
      preferredDeviceIndex: normalizedDevice.id,
      preferredProfileNumber: profileNumber,
      expectedDevice: normalizedDevice
    )
  }

  func startRefresh(
    preferredDeviceIndex: Int,
    preferredProfileNumber: Int,
    expectedDevice: DeviceChoice? = nil
  ) {
    refreshTask?.cancel()
    stopLiveDPIPolling()
    refreshGeneration += 1
    let generation = refreshGeneration
    let currentDirectory = backupDirectory

    busy = true
    loadingProfile = true
    status = "Reading the mouse…"
    guard let engine else {
      busy = false
      loadingProfile = false
      status = EngineError.unavailable.localizedDescription
      return
    }

    // Keep the identified device's physical button layout visible while
    // the slower profile read is in flight. A zero profile lets the
    // engine choose the first enabled slot, so use a valid placeholder
    // number until the read reports the actual slot.
    prepareLoadingEditor(profileNumber: preferredProfileNumber == 0 ? 1 : preferredProfileNumber)

    refreshTask = Task { [weak self] in
      let enumeration = await Task.detached(priority: .userInitiated) {
        Self.makeDeviceEnumerationSnapshot(
          executable: engine,
          currentDirectory: currentDirectory,
          preferredDeviceIndex: preferredDeviceIndex,
          preferredDeviceKey: expectedDevice?.deviceKey,
          preferredDevice: expectedDevice
        )
      }.value

      guard !Task.isCancelled, let self,
        self.refreshGeneration == generation
      else { return }

      guard enumeration.errorMessage == nil,
        let selectedIndex = enumeration.selectedDeviceIndex,
        let selected = enumeration.devices.first(where: { $0.id == selectedIndex })
      else {
        if let expectedDevice, enumeration.errorMessage == nil,
          expectedDevice.isNonWiredDevice
        {
          self.showKnownDeviceUnavailable(expectedDevice, availableDevices: enumeration.devices)
          return
        }
        self.applyRefreshSnapshot(
          RefreshSnapshot(
            devices: enumeration.devices,
            selectedDeviceIndex: nil,
            profileError: nil,
            dpiText: nil,
            dpiError: nil,
            selectedProfileNumber: nil,
            errorMessage: enumeration.errorMessage,
            accessWarning: enumeration.accessWarning
          ))
        return
      }

      // When the refresh is watching a previously known mouse, another
      // connected device must not satisfy the poll. Keep waiting for the
      // requested device until its stable HID identity is enumerable.
      if let expectedDevice, !selected.matchesReconnectIdentity(expectedDevice) {
        self.showKnownDeviceUnavailable(expectedDevice, availableDevices: enumeration.devices)
        return
      }

      // Publish the device list as soon as enumeration completes. The
      // profile read is slower, but the picker can now populate while
      // the button editor remains in its explicit loading state.
      let previousName = self.devices.first(where: { $0.deviceKey == selected.deviceKey })?.name
      self.selectedDeviceIndex = selected.id
      let resolvedSelected = selected.replacingName(
        DeviceChoice.preferredName(
          reported: selected.name,
          fallback: previousName ?? self.currentDeviceName))
      let resolvedDevices = enumeration.devices.map {
        $0.deviceKey == resolvedSelected.deviceKey ? resolvedSelected : $0
      }
      self.publishDevices(resolvedDevices)
      self.currentDeviceName = resolvedSelected.name
      self.deviceSummary = resolvedSelected.title
      if resolvedSelected.isWiredDevice && !self.inputMonitoringAuthorized {
        self.showInputMonitoringRequirement(for: resolvedSelected)
        return
      }
      if expectedDevice != nil {
        self.stopKnownDevicePolling(clearDevice: false)
      }
      self.rememberSelectedDevice(resolvedSelected)
      self.prepareLoadingEditor(
        profileNumber: preferredProfileNumber == 0 ? 1 : preferredProfileNumber)
      self.status = "Found \(selected.displayName). Reading onboard profile…"
      let profileReadProgress = self.profileReadProgressHandler(generation: generation)

      let devicesForProfileRead = self.devices
      let snapshot = await Task.detached(priority: .userInitiated) {
        Self.makeProfileSnapshot(
          executable: engine,
          currentDirectory: currentDirectory,
          devices: devicesForProfileRead,
          selectedDeviceKey: selected.deviceKey,
          selectedDeviceIndex: selected.id,
          preferredProfileNumber: preferredProfileNumber,
          onLine: profileReadProgress,
          accessWarning: enumeration.accessWarning
        )
      }.value

      guard !Task.isCancelled,
        self.refreshGeneration == generation
      else { return }
      self.applyRefreshSnapshot(snapshot)
    }
  }

  func profileReadProgressHandler(generation: Int) -> @Sendable (String) -> Void {
    { [weak self] line in
      guard let response = try? EngineJSON.decode(line).response,
        let capacity = response.profileCapacity
      else { return }
      Task { @MainActor [weak self] in
        guard let self,
          self.refreshGeneration == generation,
          self.loadingProfile
        else { return }
        self.onboardProfileCapacity = capacity
        self.onboardProfileCapacityWasReported = true
      }
    }
  }
}

extension AppModel {
  nonisolated static func makeProfileSnapshot(
    executable: URL,
    currentDirectory: URL,
    devices: [DeviceChoice],
    selectedDeviceKey: String,
    selectedDeviceIndex: Int,
    preferredProfileNumber: Int,
    onLine: @escaping @Sendable (String) -> Void = { _ in },
    accessWarning: Bool = false
  ) -> RefreshSnapshot {
    do {
      // The engine keeps one HID context for this combined read. The
      // previous implementation launched separate processes for headers,
      // profile data, and DPI, repeating feature discovery each time.
      // A missing --profile lets the engine choose the first enabled
      // slot. Passing --profile 0 is invalid because explicit profile
      // numbers are one-based.
      var arguments = [
        "--device-key", selectedDeviceKey,
        "--summary-only",
        "--with-dpi",
        "--with-report-rate",
      ]
      if preferredProfileNumber > 0 {
        arguments += ["--profile", String(preferredProfileNumber)]
      }
      arguments.append("profiles")
      let structured = try runProfileReadWithRetry(
        executable: executable,
        arguments: arguments,
        currentDirectory: currentDirectory,
        onLine: onLine
      )
      let selectedProfileNumber = structured.response.selectedProfile?.number
      let resolvedDevices = devices.map { device in
        guard device.deviceKey == selectedDeviceKey,
          let reportedName = structured.response.device?.name
        else { return device }
        return device.replacingName(
          DeviceChoice.preferredName(reported: reportedName, fallback: device.name))
      }
      return RefreshSnapshot(
        devices: resolvedDevices, selectedDeviceIndex: selectedDeviceIndex,
        profileError: nil, dpiText: nil, dpiError: nil,
        selectedProfileNumber: selectedProfileNumber, errorMessage: nil,
        accessWarning: accessWarning, profileResponse: structured.response
      )
    } catch {
      return RefreshSnapshot(
        devices: devices, selectedDeviceIndex: selectedDeviceIndex,
        profileError: errorMessage(for: error), dpiText: nil,
        dpiError: nil, selectedProfileNumber: nil, errorMessage: nil,
        accessWarning: accessWarning, profileResponse: nil
      )
    }
  }

  nonisolated static func runProfileReadWithRetry(
    executable: URL,
    arguments: [String],
    currentDirectory: URL,
    onLine: @escaping @Sendable (String) -> Void
  ) throws -> EngineJSONCommandResult {
    var lastError: Error?

    for attempt in 0..<AppModelRefreshConfiguration.profileReadAttempts {
      do {
        let processResult = try EngineRunner.runStructuredWithLineProgress(
          executable: executable,
          arguments: arguments + ["--format", "json"],
          currentDirectory: currentDirectory,
          onLine: onLine
        )
        let structured: EngineJSONCommandResult
        do {
          structured = try EngineJSON.decode(processResult.output)
        } catch {
          if processResult.terminationStatus != 0 {
            throw EngineError.failed(
              processResult.output.trimmingCharacters(in: .whitespacesAndNewlines))
          }
          throw error
        }
        guard processResult.terminationStatus == 0 else {
          _ = try EngineJSON.validate(structured, expectedKind: "profiles")
          throw EngineError.failed(
            "The HID++ engine exited with status \(processResult.terminationStatus).")
        }
        let validated = try EngineJSON.validate(structured, expectedKind: "profiles")
        if validated.response.selectedProfile != nil {
          return validated
        }
        lastError = EngineError.failed("The selected onboard profile was not returned.")
      } catch {
        lastError = error
      }

      if attempt < AppModelRefreshConfiguration.profileReadAttempts - 1 {
        // Each attempt launches a fresh HID context, but only for the
        // selected device key. This gives macOS time to finish the
        // interface handoff without re-enumerating every mouse.
        Thread.sleep(forTimeInterval: AppModelRefreshConfiguration.profileReadRetryDelay)
      }
    }

    // `?? EngineError.failed(...)` is unreachable: `profileReadAttempts`
    // (AppModel+Refresh.swift) is a fixed constant > 0, so the loop above
    // always runs at least once, and every iteration that doesn't already
    // `return` sets `lastError` before falling through here.
    throw lastError!
  }

  nonisolated static func errorMessage(for error: Error) -> String {
    error.localizedDescription
  }
}
