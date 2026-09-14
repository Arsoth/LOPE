// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  func setConfigurationDirectory(_ url: URL) {
    configurationDirectory = url
    configurationDirectoryPath = url.path
    backupDirectoryPath = backupDirectory.path
    UserDefaults.standard.set(
      url.path, forKey: "\(AppConstants.defaultsPrefix).configurationDirectory")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    reloadThemes()
    loadThemePreferences()
    MouseProfileCatalog.reload(customProfilesDirectory: customProfilesDirectory)
    refreshBackups()
    status = "LOPE configuration will be saved in \(url.path)."
  }

  func resetConfigurationDirectory() {
    setConfigurationDirectory(defaultConfigurationDirectory)
  }

  /// Turns the live, blindly-editable session for an unrecognized mouse
  /// into a real descriptor in the custom profiles folder: the same button
  /// records already being read, saved under generic "Button N" names the
  /// user can rename later. It ranks below any built-in or hand-authored
  /// descriptor until then (`MouseProfileDescriptor.generated`).
  ///
  /// Deliberately excluded for MX-series mice even when they answer the
  /// onboard-profiles feature query: their button/gesture behavior is
  /// normally managed by host software (Logi Options+), not verified
  /// onboard flash, so a device responding to that read is not by itself
  /// evidence that writing a generated profile back would be safe or do
  /// anything at all. Only a human-authored, hardware-validated descriptor
  /// may enable editing for this device class (see Profiles/README.md).
  @discardableResult
  func createGeneratedProfile() -> URL? {
    guard !busy, !loadingProfile, !profiles.isEmpty, !hasSpecificMouseProfile,
      !isMXSeriesMouse
    else { return nil }

    let selected = devices.first(where: { $0.id == selectedDeviceIndex })
    let productID = selected?.productID ?? ""
    let deviceName = currentDeviceName.isEmpty ? (selected?.name ?? "") : currentDeviceName
    guard !deviceName.isEmpty || !productID.isEmpty else { return nil }

    let buttonNumbers = Set(normalButtonRows.map(\.id) + gShiftButtonRows.map(\.id)).sorted()
    guard !buttonNumbers.isEmpty else {
      status = "No onboard button records have been read yet; choose Refresh first."
      return nil
    }

    let baseIdentifier =
      "auto-"
      + BackupStorage.sanitizedMouseIdentifier(
        deviceName.isEmpty ? productID : deviceName,
        fallback: "mouse"
      )
    let existingIDs = Set(MouseProfileCatalog.shared.profiles.map(\.id))
    var id = baseIdentifier
    var suffix = 2
    while existingIDs.contains(id) {
      id = "\(baseIdentifier)-\(suffix)"
      suffix += 1
    }

    let buttons = buttonNumbers.map {
      MouseProfileDescriptor.Button(number: $0, control: "Button \($0)", aliases: [], notes: nil)
    }
    let dpiRange: MouseProfileDescriptor.DPIRange? = {
      guard let minimum = dpiCapabilities.minimum, let maximum = dpiCapabilities.maximum else {
        return nil
      }
      return MouseProfileDescriptor.DPIRange(minimum: minimum, maximum: maximum)
    }()

    let descriptor = MouseProfileDescriptor(
      schemaVersion: 1,
      id: id,
      name: "\(deviceName.isEmpty ? "Unnamed mouse" : deviceName) (needs button names)",
      match: .init(
        nameContains: deviceName.isEmpty ? [] : [deviceName],
        productIDs: productID.isEmpty ? [] : [productID]
      ),
      buttons: buttons,
      scrollWheelButtonLabels: nil,
      hiddenProfileButtonNumbers: nil,
      dpiRange: dpiRange,
      refreshGuidance: nil,
      profileIO: MouseProfileCatalog.genericProfile.profileIO,
      rgbProfile: nil,
      sources: [],
      generated: true
    )

    let directory = customProfilesDirectory
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("\(id).json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted]
    guard let data = try? encoder.encode(descriptor),
      (try? data.write(to: url, options: .atomic)) != nil
    else {
      status = "Could not write the generated profile to \(directory.path)."
      return nil
    }

    MouseProfileCatalog.reload(customProfilesDirectory: customProfilesDirectory)
    status =
      "Created \(url.lastPathComponent) with generic button names. Rename its controls in the custom profiles folder any time."
    refresh()
    return url
  }

  func setShowAdvancedFields(_ show: Bool) {
    showAdvancedFields = show
    UserDefaults.standard.set(show, forKey: "\(AppConstants.defaultsPrefix).showAdvancedFields")
  }

  func setShowNonStandardKeyboardKeys(_ show: Bool) {
    showNonStandardKeyboardKeys = show
    UserDefaults.standard.set(
      show, forKey: "\(AppConstants.defaultsPrefix).showNonStandardKeyboardKeys")
  }
}
