// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import IOKit.hidsystem

@MainActor
extension AppModel {
  func startBackgroundDeviceEnumeration(
    executable: URL,
    currentDirectory: URL,
    cachedDevice: DeviceChoice,
    generation: Int
  ) {
    refreshTask = Task { [weak self] in
      let enumeration = await Task.detached(priority: .utility) {
        Self.makeDeviceEnumerationSnapshot(
          executable: executable,
          currentDirectory: currentDirectory,
          preferredDeviceIndex: cachedDevice.id,
          preferredDeviceKey: cachedDevice.deviceKey,
          preferredDevice: cachedDevice
        )
      }.value

      guard !Task.isCancelled, let self,
        self.refreshGeneration == generation
      else { return }

      self.refreshTask = nil
      if let errorMessage = enumeration.errorMessage {
        self.status =
          "Loaded \(cachedDevice.name). The device list could not be refreshed: \(errorMessage)"
        return
      }
      guard
        let selected = enumeration.devices.first(where: {
          $0.matchesReconnectIdentity(cachedDevice)
        })
      else {
        // The cached mouse disappeared while the list was refreshed. Keep
        // every other device visible, but wait for an explicit selection so
        // the old profile cannot be silently applied to the first new mouse.
        self.publishDevices(enumeration.devices)
        self.selectedDeviceIndex = 0
        self.currentDeviceName = ""
        let hasSelectableDevice = enumeration.devices.contains(where: { !$0.isWiredAccessPrompt })
        self.deviceSummary =
          hasSelectableDevice
          ? "Choose a Logitech mouse to continue"
          : "No editable Logitech mouse found"
        self.resetEditorState()
        if enumeration.accessWarning {
          self.status =
            "A wired Logitech mouse needs Input Monitoring. Choose a wireless mouse, or enable access in System Settings."
        } else if hasSelectableDevice {
          self.status = "Choose a Logitech mouse to continue."
        } else {
          self.status = "No Logitech mouse was found."
        }
        return
      }

      let preservedName =
        self.devices
        .first(where: { $0.deviceKey == cachedDevice.deviceKey })?.name ?? cachedDevice.name
      self.selectedDeviceIndex = selected.id
      let resolvedSelected = selected.replacingName(
        DeviceChoice.preferredName(reported: selected.name, fallback: preservedName))
      let resolvedDevices = enumeration.devices.map {
        $0.deviceKey == resolvedSelected.deviceKey ? resolvedSelected : $0
      }
      self.publishDevices(resolvedDevices)
      self.currentDeviceName = resolvedSelected.name
      self.deviceSummary = resolvedSelected.title
      self.rememberSelectedDevice(resolvedSelected)
      self.refreshBackups()
    }
  }
}

extension AppModel {
  nonisolated static func makeDeviceEnumerationSnapshot(
    executable: URL,
    currentDirectory: URL,
    preferredDeviceIndex: Int,
    preferredDeviceKey: String?,
    preferredDevice: DeviceChoice? = nil
  ) -> DeviceEnumerationSnapshot {
    do {
      let list = try runDeviceListWithRetry(
        executable: executable,
        currentDirectory: currentDirectory
      )
      let discovered = parseDeviceChoices(list)
      let accessWarning = list.localizedCaseInsensitiveContains("macOS denied HID access")
      let accessAuthorized =
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
      let displayedDevices = DeviceChoice.addingWiredAccessPrompt(
        to: discovered,
        accessAuthorized: accessAuthorized,
        accessWarning: accessWarning
      )
      let selectedIndex: Int?
      if let preferredDeviceKey,
        let keyMatch = discovered.first(where: { $0.deviceKey == preferredDeviceKey })
      {
        selectedIndex = keyMatch.id
      } else if let preferredDevice,
        let identityMatch = discovered.first(where: { $0.matchesReconnectIdentity(preferredDevice) }
        )
      {
        // Receiver/KVM reconnects can recreate the HID key. If the paired
        // model identity still matches, use it even when its list position
        // changed.
        selectedIndex = identityMatch.id
      } else if preferredDeviceIndex >= 0 {
        selectedIndex = discovered.first(where: { $0.id == preferredDeviceIndex })?.id
      } else {
        selectedIndex = nil
      }
      return DeviceEnumerationSnapshot(
        devices: displayedDevices,
        selectedDeviceIndex: selectedIndex,
        accessWarning: accessWarning,
        errorMessage: nil
      )
    } catch {
      return DeviceEnumerationSnapshot(
        devices: [],
        selectedDeviceIndex: nil,
        accessWarning: false,
        errorMessage: errorMessage(for: error)
      )
    }
  }

  nonisolated static func runDeviceListWithRetry(
    executable: URL,
    currentDirectory: URL
  ) throws -> String {
    var lastError: Error?

    for attempt in 0..<AppModelRefreshConfiguration.deviceReadAttempts {
      do {
        let output = try EngineRunner.run(
          executable: executable,
          arguments: ["list"],
          currentDirectory: currentDirectory
        )
        if !parseDeviceChoices(output).isEmpty
          || attempt == AppModelRefreshConfiguration.deviceReadAttempts - 1
        {
          return output
        }
        lastError = EngineError.failed("The Logitech device list was empty.")
      } catch {
        lastError = error
      }

      if attempt < AppModelRefreshConfiguration.deviceReadAttempts - 1 {
        Thread.sleep(forTimeInterval: AppModelRefreshConfiguration.deviceReadRetryDelay)
      }
    }

    throw lastError ?? EngineError.failed("The Logitech device list could not be read.")
  }

  func loadLastSelectedDevice() -> DeviceChoice? {
    let key = "\(AppConstants.defaultsPrefix).\(AppConstants.lastSelectedDeviceKey)"
    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(DeviceChoice.self, from: data)
  }

  func rememberSelectedDevice(_ device: DeviceChoice) {
    let key = "\(AppConstants.defaultsPrefix).\(AppConstants.lastSelectedDeviceKey)"
    guard let data = try? JSONEncoder().encode(device) else { return }
    UserDefaults.standard.set(data, forKey: key)
  }
}
