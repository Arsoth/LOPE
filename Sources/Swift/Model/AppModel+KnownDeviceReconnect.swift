// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  func startReconnectMonitor() {
    reconnectMonitorTask?.cancel()
    reconnectMonitorTask = Task { @MainActor [weak self] in
      var initialized = false
      var wasReachable = false

      while !Task.isCancelled {
        do {
          try await Task.sleep(
            nanoseconds: AppModelRefreshConfiguration.reconnectPollNanoseconds)
        } catch {
          return
        }
        guard let self, !Task.isCancelled else { return }
        guard !self.busy, !self.waitingForKnownDevice,
          let executable = self.engine
        else { continue }

        let selected = self.devices.first { $0.id == self.selectedDeviceIndex }
        let selectedIndex = selected?.id ?? -1
        let currentDirectory = self.backupDirectory
        let snapshot = await Task.detached(priority: .utility) {
          Self.makeDeviceEnumerationSnapshot(
            executable: executable,
            currentDirectory: currentDirectory,
            preferredDeviceIndex: selectedIndex,
            preferredDeviceKey: nil,
            preferredDevice: selected
          )
        }.value
        guard !Task.isCancelled else { return }
        guard snapshot.errorMessage == nil else { continue }

        guard let selected else {
          if !snapshot.devices.isEmpty {
            self.status = "A Logitech mouse was found; checking its onboard profile…"
            self.startRefresh(
              preferredDeviceIndex: selectedIndex,
              preferredProfileNumber: self.profileNumber)
          }
          continue
        }

        // A KVM can recreate the USB interface, changing the location
        // and registry portions of deviceKey. Product/name matching
        // lets us recognize that same mouse after reconnect without
        // trusting the stale HID identity.
        let matchingDevice = snapshot.devices.first { $0.matchesReconnectIdentity(selected) }
        let reachable = matchingDevice != nil
        let identityChanged = matchingDevice?.deviceKey != selected.deviceKey
        if !initialized {
          initialized = true
          wasReachable = reachable
          continue
        }
        if !reachable {
          wasReachable = false
          continue
        }
        if !wasReachable || identityChanged {
          wasReachable = true
          self.status = "Mouse reconnected; checking live DPI…"
          self.startRefresh(
            preferredDeviceIndex: selected.id,
            preferredProfileNumber: self.profileNumber)
        }
      }
    }
  }

  func hasKnownOnboardProfileCapability(_ device: DeviceChoice) -> Bool {
    guard
      let descriptor = MouseProfileCatalog.shared.matchingProfile(
        deviceName: device.name,
        productID: device.productID
      )
    else { return false }
    return descriptor.profileIO.supported
  }

  func beginKnownDeviceRefresh(_ device: DeviceChoice) {
    guard device.isNonWiredDevice else { return }
    // The failed profile-read task can call this method before its own
    // closure returns. Release that completed task so the next polling tick
    // is allowed to launch a probe.
    refreshTask = nil
    knownDisconnectedDevice = device
    waitingForKnownDevice = true
    knownDevicePollAttempts = 0
    busy = true
    currentDeviceName = device.name
    deviceSummary = "\(device.title) — waiting for the mouse"
    // Keep the loading/profile-derived surface beneath the wake modal. The
    // refresh was already primed with `prepareLoadingEditor`, so clearing
    // it here would make the configure screen jump to an empty state.
    status = knownDeviceRefreshStatus(for: device, expired: false)

    guard knownDevicePollTask == nil else { return }
    let policy = knownDevicePollPolicy
    knownDevicePollTask = Task { @MainActor [weak self] in
      for attempt in 1...policy.maximumAttempts {
        do {
          try await Task.sleep(nanoseconds: policy.intervalNanoseconds)
        } catch {
          return
        }
        guard let self, !Task.isCancelled,
          self.knownDisconnectedDevice == device
        else { return }

        self.knownDevicePollAttempts = attempt
        self.status = self.knownDeviceRefreshStatus(for: device, expired: false)
        guard self.refreshTask == nil else { continue }
        self.startKnownDeviceProbe(device)
      }

      guard let self, !Task.isCancelled,
        self.knownDisconnectedDevice == device
      else { return }
      self.waitingForKnownDevice = false
      self.knownDevicePollTask = nil
      self.busy = false
      self.loadingProfile = false
      self.refreshTask = nil
      let prompt = self.devices.first(where: { $0.isWiredAccessPrompt })
      let remainingDevices = self.devices.filter {
        !$0.isWiredAccessPrompt && !$0.matchesReconnectIdentity(device)
      }
      self.devices = remainingDevices + (prompt.map { [$0] } ?? [])
      if remainingDevices.isEmpty {
        self.selectedDeviceIndex = 0
        self.currentDeviceName = ""
        self.deviceSummary =
          "Wake \(device.name), then choose Refresh, or select another mouse"
      } else {
        self.selectedDeviceIndex = 0
        self.currentDeviceName = ""
        self.deviceSummary = "Choose a Logitech mouse to continue"
      }
      self.resetEditorState()
      self.status = self.knownDeviceRefreshStatus(for: device, expired: true)
    }
  }

  func startKnownDeviceProbe(_ device: DeviceChoice) {
    refreshTask?.cancel()
    stopLiveDPIPolling()
    refreshGeneration += 1
    let generation = refreshGeneration
    let currentDirectory = backupDirectory

    // Keep the wake screen visible while the sleeping mouse is probed.
    // This probe intentionally does not set loadingProfile or replace the
    // editor with loading placeholders; the profile read happens silently
    // until the mouse responds.
    busy = true
    guard let engine else {
      busy = waitingForKnownDevice
      return
    }

    let preferredProfileNumber = profileNumber
    refreshTask = Task { [weak self] in
      let enumeration = await Task.detached(priority: .utility) {
        Self.makeDeviceEnumerationSnapshot(
          executable: engine,
          currentDirectory: currentDirectory,
          preferredDeviceIndex: device.id,
          preferredDeviceKey: device.deviceKey,
          preferredDevice: device
        )
      }.value

      guard !Task.isCancelled, let self,
        self.refreshGeneration == generation,
        self.knownDisconnectedDevice == device
      else { return }

      guard enumeration.errorMessage == nil,
        let selectedIndex = enumeration.selectedDeviceIndex,
        let selected = enumeration.devices.first(where: { $0.id == selectedIndex }),
        selected.matchesReconnectIdentity(device)
      else {
        self.finishKnownDeviceProbe(generation: generation)
        return
      }

      let resolvedSelected = selected.replacingName(
        DeviceChoice.preferredName(reported: selected.name, fallback: device.name))
      let resolvedDevices = enumeration.devices.map {
        $0.deviceKey == resolvedSelected.deviceKey ? resolvedSelected : $0
      }
      self.devices = resolvedDevices
      self.selectedDeviceIndex = selected.id
      self.currentDeviceName = resolvedSelected.name
      self.deviceSummary = "\(resolvedSelected.title) — waiting for the mouse"
      self.rememberSelectedDevice(resolvedSelected)
      let profileReadProgress = self.profileReadProgressHandler(generation: generation)

      let snapshot = await Task.detached(priority: .utility) {
        Self.makeProfileSnapshot(
          executable: engine,
          currentDirectory: currentDirectory,
          devices: resolvedDevices,
          selectedDeviceKey: selected.deviceKey,
          selectedDeviceIndex: selected.id,
          preferredProfileNumber: preferredProfileNumber,
          onLine: profileReadProgress,
          accessWarning: enumeration.accessWarning
        )
      }.value

      guard !Task.isCancelled,
        self.refreshGeneration == generation,
        self.knownDisconnectedDevice == device
      else { return }

      guard snapshot.profileText != nil else {
        self.finishKnownDeviceProbe(generation: generation)
        return
      }
      self.applyRefreshSnapshot(snapshot)
    }
  }

  func finishKnownDeviceProbe(generation: Int) {
    guard refreshGeneration == generation else { return }
    busy = waitingForKnownDevice
    refreshTask = nil
  }

  func stopKnownDevicePolling(clearDevice: Bool) {
    knownDevicePollTask?.cancel()
    knownDevicePollTask = nil
    waitingForKnownDevice = false
    knownDevicePollAttempts = 0
    if clearDevice {
      knownDisconnectedDevice = nil
    }
  }

  func showKnownDeviceUnavailable(
    _ device: DeviceChoice,
    availableDevices: [DeviceChoice] = []
  ) {
    guard device.isNonWiredDevice else {
      presentWiredAccessInstructions(for: device)
      return
    }
    busy = false
    loadingProfile = false
    refreshTask = nil
    knownDisconnectedDevice = device
    waitingForKnownDevice = true
    currentDeviceName = device.name
    deviceSummary = "\(device.title) — waiting for the mouse"
    // `startRefresh` prepared the profile-derived loading surface before
    // discovery. Preserve it under the wake modal while the target mouse
    // is being polled.
    status = knownDeviceRefreshStatus(for: device, expired: false)
    if availableDevices.isEmpty {
      devices = [device]
      selectedDeviceIndex = device.id
    } else {
      devices = availableDevices
      // Keep other detected mice selectable while the known target is
      // being watched. Zero is deliberately not a device ID: the
      // engine's list is one-based, so the picker has no stale target.
      selectedDeviceIndex = 0
    }
    busy = true
    if knownDevicePollTask == nil {
      beginKnownDeviceRefresh(device)
    }
  }

  func knownDeviceRefreshStatus(for device: DeviceChoice, expired: Bool) -> String {
    let guidance = MouseProfileCatalog.shared.matchingProfile(
      deviceName: device.name,
      productID: device.productID
    )?.refreshGuidance
    guard let guidance else {
      return expired
        ? "Still waiting for \(device.name). Move or click it to wake it, then choose Refresh."
        : "Checking for \(device.name)…"
    }
    if expired {
      return "Still waiting for \(device.name). \(guidance.wakeInstructions)"
    }
    return "Checking for \(device.name)…"
  }
}
