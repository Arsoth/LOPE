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
          preferredDeviceKey: cachedDevice.deviceKey
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
        let selected = enumeration.devices.first(where: { $0.deviceKey == cachedDevice.deviceKey })
      else {
        guard let fallback = enumeration.devices.first(where: { !$0.isWiredAccessPrompt }) else {
          self.devices = []
          self.selectedDeviceIndex = 0
          self.currentDeviceName = ""
          self.deviceSummary = "No editable Logitech mouse found"
          self.resetEditorState()
          self.status =
            enumeration.accessWarning
            ? "macOS denied access to one or more Logitech HID++ interfaces. Enable Input Monitoring, then choose Refresh."
            : "No Logitech mouse was found."
          return
        }

        // The cached mouse disappeared while the list was refreshed.
        // Hand the newly selected device through the normal full read
        // so the editor never shows one mouse's profile for another.
        self.devices = enumeration.devices
        self.selectedDeviceIndex = fallback.id
        self.startRefresh(preferredDeviceIndex: fallback.id, preferredProfileNumber: 0)
        return
      }

      self.devices = enumeration.devices
      self.selectedDeviceIndex = selected.id
      self.currentDeviceName = selected.name
      self.deviceSummary = selected.title
      self.rememberSelectedDevice(selected)
      self.refreshBackups()
    }
  }
}

extension AppModel {
  nonisolated static func makeDeviceEnumerationSnapshot(
    executable: URL,
    currentDirectory: URL,
    preferredDeviceIndex: Int,
    preferredDeviceKey: String?
  ) -> DeviceEnumerationSnapshot {
    do {
      let list = try runDeviceListWithRetry(
        executable: executable,
        currentDirectory: currentDirectory
      )
      let discovered = parseDeviceChoices(list)
      let accessAuthorized =
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
      let displayedDevices = DeviceChoice.addingWiredAccessPrompt(
        to: discovered,
        accessAuthorized: accessAuthorized
      )
      let accessWarning = list.contains("macOS denied HID access")
      let selectedIndex =
        (preferredDeviceKey.flatMap { key in
          discovered.first(where: { $0.deviceKey == key })
        } ?? discovered.first(where: { $0.id == preferredDeviceIndex }) ?? discovered.first)?.id
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
