// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  func startLiveDPIPolling() {
    stopLiveDPIPolling()
    guard let executable = engine,
      let selected = devices.first(where: { $0.id == selectedDeviceIndex }),
      !profiles.isEmpty,
      dpiCapabilities.sensorCount != nil
    else { return }

    let deviceID = selected.id
    let deviceKey = selected.deviceKey
    let currentDirectory = backupDirectory
    liveDPIPollTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(
            nanoseconds: AppModelRefreshConfiguration.liveDPIPollNanoseconds)
        } catch {
          return
        }
        guard let self, !Task.isCancelled,
          !self.busy,
          !self.loadingProfile,
          self.selectedDeviceIndex == deviceID,
          self.devices.first(where: { $0.id == deviceID })?.deviceKey == deviceKey,
          !self.profiles.isEmpty
        else { continue }

        let currentDPI = await Task.detached(priority: .utility) {
          Self.readCurrentSensorDPI(
            executable: executable,
            currentDirectory: currentDirectory,
            deviceKey: deviceKey,
            deviceIndex: deviceID
          )
        }.value

        guard !Task.isCancelled,
          let currentDPI,
          !self.busy,
          !self.loadingProfile,
          self.selectedDeviceIndex == deviceID,
          self.devices.first(where: { $0.id == deviceID })?.deviceKey == deviceKey,
          !self.profiles.isEmpty
        else { continue }
        if self.dpiCapabilities.currentValue != currentDPI {
          self.dpiCapabilities.currentValue = currentDPI
        }
      }
    }
  }

  func stopLiveDPIPolling() {
    liveDPIPollTask?.cancel()
    liveDPIPollTask = nil
  }
}

extension AppModel {
  nonisolated static func readCurrentSensorDPI(
    executable: URL,
    currentDirectory: URL,
    deviceKey: String,
    deviceIndex: Int
  ) -> Int? {
    let selector =
      deviceKey.isEmpty
      ? ["--device", String(deviceIndex)]
      : ["--device-key", deviceKey]
    guard
      let output = try? EngineRunner.run(
        executable: executable,
        arguments: selector + ["current-dpi"],
        currentDirectory: currentDirectory
      )
    else { return nil }
    return DPIOutputParser.parse(output).currentValue
  }
}
