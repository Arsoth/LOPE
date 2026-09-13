// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  func startInitialRefresh(cachedDevice: DeviceChoice) {
    refreshTask?.cancel()
    stopLiveDPIPolling()
    refreshGeneration += 1
    let generation = refreshGeneration
    let currentDirectory = backupDirectory
    let preferredProfileNumber = profileNumber

    busy = true
    loadingProfile = true
    currentDeviceName = cachedDevice.name
    deviceSummary = cachedDevice.title
    status = "Reading \(cachedDevice.name)…"
    guard let engine else {
      busy = false
      loadingProfile = false
      status = EngineError.unavailable.localizedDescription
      return
    }

    // Keep the cached device visible while the targeted read is in flight.
    // The full device list is refreshed after this read succeeds.
    devices = [cachedDevice]
    selectedDeviceIndex = cachedDevice.id
    prepareLoadingEditor(profileNumber: preferredProfileNumber == 0 ? 1 : preferredProfileNumber)
    let profileReadProgress = profileReadProgressHandler(generation: generation)

    refreshTask = Task { [weak self] in
      let snapshot = await Task.detached(priority: .userInitiated) {
        Self.makeProfileSnapshot(
          executable: engine,
          currentDirectory: currentDirectory,
          devices: [cachedDevice],
          selectedDeviceKey: cachedDevice.deviceKey,
          selectedDeviceIndex: cachedDevice.id,
          preferredProfileNumber: preferredProfileNumber,
          onLine: profileReadProgress
        )
      }.value

      guard !Task.isCancelled, let self,
        self.refreshGeneration == generation
      else { return }

      // A stale cached key should not prevent the normal discovery path
      // from finding a newly connected mouse.
      guard snapshot.profileText != nil else {
        if self.hasKnownOnboardProfileCapability(cachedDevice) {
          self.beginKnownDeviceRefresh(cachedDevice)
        } else {
          self.startRefresh(
            preferredDeviceIndex: cachedDevice.id,
            preferredProfileNumber: preferredProfileNumber
          )
        }
        return
      }

      self.applyRefreshSnapshot(snapshot)
      self.startBackgroundDeviceEnumeration(
        executable: engine,
        currentDirectory: currentDirectory,
        cachedDevice: cachedDevice,
        generation: generation
      )
    }
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
          preferredDeviceKey: expectedDevice?.deviceKey
        )
      }.value

      guard !Task.isCancelled, let self,
        self.refreshGeneration == generation
      else { return }

      guard enumeration.errorMessage == nil,
        let selectedIndex = enumeration.selectedDeviceIndex,
        let selected = enumeration.devices.first(where: { $0.id == selectedIndex })
      else {
        if let expectedDevice, enumeration.errorMessage == nil {
          self.showKnownDeviceUnavailable(expectedDevice, availableDevices: enumeration.devices)
          return
        }
        self.applyRefreshSnapshot(
          RefreshSnapshot(
            devices: enumeration.devices,
            selectedDeviceIndex: nil,
            profileText: nil,
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
      if let expectedDevice, selected.deviceKey != expectedDevice.deviceKey {
        self.showKnownDeviceUnavailable(expectedDevice, availableDevices: enumeration.devices)
        return
      }

      // Publish the device list as soon as enumeration completes. The
      // profile read is slower, but the picker can now populate while
      // the button editor remains in its explicit loading state.
      self.devices = enumeration.devices
      self.selectedDeviceIndex = selected.id
      self.currentDeviceName = selected.name
      self.deviceSummary = selected.title
      if expectedDevice != nil {
        self.stopKnownDevicePolling(clearDevice: false)
      }
      self.rememberSelectedDevice(selected)
      self.prepareLoadingEditor(
        profileNumber: preferredProfileNumber == 0 ? 1 : preferredProfileNumber)
      self.status = "Found \(selected.name). Reading onboard profile…"
      let profileReadProgress = self.profileReadProgressHandler(generation: generation)

      let snapshot = await Task.detached(priority: .userInitiated) {
        Self.makeProfileSnapshot(
          executable: engine,
          currentDirectory: currentDirectory,
          devices: enumeration.devices,
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
      guard let capacity = Self.onboardProfileCapacity(in: line) else { return }
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
      let profileText = try runProfileReadWithRetry(
        executable: executable,
        arguments: arguments,
        currentDirectory: currentDirectory,
        onLine: onLine
      )
      let selectedProfileNumber = Self.selectedProfileNumber(in: profileText)
      return RefreshSnapshot(
        devices: devices, selectedDeviceIndex: selectedDeviceIndex,
        profileText: profileText, profileError: nil, dpiText: nil,
        dpiError: nil, selectedProfileNumber: selectedProfileNumber,
        errorMessage: nil, accessWarning: accessWarning
      )
    } catch {
      return RefreshSnapshot(
        devices: devices, selectedDeviceIndex: selectedDeviceIndex,
        profileText: nil, profileError: errorMessage(for: error), dpiText: nil,
        dpiError: nil, selectedProfileNumber: nil, errorMessage: nil,
        accessWarning: accessWarning
      )
    }
  }

  nonisolated static func runProfileReadWithRetry(
    executable: URL,
    arguments: [String],
    currentDirectory: URL,
    onLine: @escaping @Sendable (String) -> Void
  ) throws -> String {
    var lastError: Error?

    for attempt in 0..<AppModelRefreshConfiguration.profileReadAttempts {
      do {
        let output = try EngineRunner.runWithLineProgress(
          executable: executable,
          arguments: arguments,
          currentDirectory: currentDirectory,
          onLine: onLine
        )
        // run_profiles historically returned success after emitting
        // headers when the selected sector read timed out. Require
        // this marker so a transient G603 wake-up failure is retried
        // instead of being presented as a mouse with no profile.
        if selectedProfileNumber(in: output) != nil {
          return output
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

    throw lastError ?? EngineError.failed("The selected onboard profile could not be read.")
  }

  nonisolated static func errorMessage(for error: Error) -> String {
    error.localizedDescription
  }
}
