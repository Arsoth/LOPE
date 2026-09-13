// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

// Covers AppModel+GeneratedProfilesPreferences.swift: switching the
// configuration directory, synthesizing a generated profile for an
// unrecognized mouse, and the two persisted display-preference toggles.
//
// `chooseConfigurationDirectory()` (an `NSOpenPanel` modal) and
// `openBackupDirectoryInFinder()` / `openCustomProfilesDirectoryInFinder()`
// (`NSWorkspace.shared.open`, which really opens a Finder window on the
// developer's desktop — confirmed by hand while investigating this file)
// are intentionally not exercised here: there is no seam to fake the modal
// panel or the Workspace call, and actually invoking them from an
// unattended test run would pop real, visible windows on the machine
// running the suite. Those few lines are left uncovered by design.
@MainActor
final class AppModelGeneratedProfilesPreferencesTests: XCTestCase {
  private let configurationDirectoryDefaultsKey =
    "\(AppConstants.defaultsPrefix).configurationDirectory"

  /// Points `model` at a throwaway directory for the duration of `body`,
  /// then restores both the on-disk state and the `UserDefaults` key
  /// `setConfigurationDirectory` persists to, and resets the process-wide
  /// `MouseProfileCatalog.shared` back to its default. Without this, a
  /// generated-profile write here would leak into the real
  /// `~/Library/Application Support/LOPE` used by every other test.
  private func withIsolatedConfigurationDirectory(
    _ model: AppModel, _ body: (URL) throws -> Void
  ) rethrows {
    let previousValue = UserDefaults.standard.string(forKey: configurationDirectoryDefaultsKey)
    let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lope-generated-profile-test-\(UUID().uuidString)", isDirectory: true)
    model.setConfigurationDirectory(tempDirectory)
    defer {
      try? FileManager.default.removeItem(at: tempDirectory)
      if let previousValue {
        UserDefaults.standard.set(previousValue, forKey: configurationDirectoryDefaultsKey)
      } else {
        UserDefaults.standard.removeObject(forKey: configurationDirectoryDefaultsKey)
      }
      MouseProfileCatalog.reload(customProfilesDirectory: nil)
    }
    try body(tempDirectory)
  }

  func testSetConfigurationDirectoryUpdatesPathsUserDefaultsAndStatus() {
    let model = AppModel(startInitialRefresh: false)
    withIsolatedConfigurationDirectory(model) { tempDirectory in
      XCTAssertEqual(model.configurationDirectory, tempDirectory)
      XCTAssertEqual(model.configurationDirectoryPath, tempDirectory.path)
      XCTAssertEqual(model.backupDirectoryPath, model.backupDirectory.path)
      XCTAssertEqual(
        UserDefaults.standard.string(forKey: configurationDirectoryDefaultsKey),
        tempDirectory.path)
      XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.path))
      XCTAssertTrue(FileManager.default.fileExists(atPath: model.backupDirectory.path))
      XCTAssertTrue(model.status.contains(tempDirectory.path))
    }
  }

  func testResetConfigurationDirectoryRestoresDefault() {
    let model = AppModel(startInitialRefresh: false)
    withIsolatedConfigurationDirectory(model) { _ in
      model.resetConfigurationDirectory()
      XCTAssertEqual(model.configurationDirectory, model.defaultConfigurationDirectory)
      XCTAssertEqual(model.configurationDirectoryPath, model.defaultConfigurationDirectoryPath)
    }
  }

  func testCreateGeneratedProfileRejectsWhileBusyLoadingOrWithoutProfiles() {
    let model = AppModel(startInitialRefresh: false)
    model.devices = [
      DeviceChoice(
        id: 1, name: "Unclassified Test Mouse", connection: "Wired", productID: "0xFEED",
        deviceKey: "unclassified")
    ]
    model.selectedDeviceIndex = 1
    model.currentDeviceName = "Unclassified Test Mouse"
    model.normalButtonRows = [
      ButtonRow(
        id: 1, label: "Button 1", currentRaw: "FFFFFFFF", draftRaw: "FFFFFFFF",
        draftChoice: "FFFFFFFF", layer: .normal)
    ]
    model.profiles = [ProfileChoice(id: 1, sector: "0x0100", enabled: true, crcValid: true)]

    model.busy = true
    XCTAssertNil(model.createGeneratedProfile())
    model.busy = false

    model.loadingProfile = true
    XCTAssertNil(model.createGeneratedProfile())
    model.loadingProfile = false

    let savedProfiles = model.profiles
    model.profiles = []
    XCTAssertNil(model.createGeneratedProfile())
    model.profiles = savedProfiles

    // A device the catalog already recognizes specifically (G502 X) must
    // never be offered a generated, generically-named replacement.
    model.currentDeviceName = "G502 X"
    XCTAssertNil(model.createGeneratedProfile())
  }

  func testCreateGeneratedProfileRejectsUnidentifiedDeviceOrMissingButtons() {
    let model = AppModel(startInitialRefresh: false)
    model.profiles = [ProfileChoice(id: 1, sector: "0x0100", enabled: true, crcValid: true)]

    // No selected device at all: both name and product ID are empty.
    XCTAssertNil(model.createGeneratedProfile())

    model.devices = [
      DeviceChoice(
        id: 1, name: "Buttonless Test Mouse", connection: "Wired", productID: "0xF00D",
        deviceKey: "buttonless")
    ]
    model.selectedDeviceIndex = 1
    model.currentDeviceName = "Buttonless Test Mouse"
    // Identified, but no onboard button records have been captured yet.
    XCTAssertNil(model.createGeneratedProfile())
    XCTAssertTrue(model.status.contains("No onboard button records"))
  }

  func testCreateGeneratedProfileWritesDescriptorWithDPIRangeAndUnionOfButtonLayers() throws {
    let model = AppModel(startInitialRefresh: false)
    try withIsolatedConfigurationDirectory(model) { _ in
      model.devices = [
        DeviceChoice(
          id: 1, name: "Totally Unknown Test Mouse", connection: "Wired", productID: "0xABCD",
          deviceKey: "unknown-mouse")
      ]
      model.selectedDeviceIndex = 1
      model.currentDeviceName = "Totally Unknown Test Mouse"
      model.profiles = [ProfileChoice(id: 1, sector: "0x0100", enabled: true, crcValid: true)]
      model.normalButtonRows = [
        ButtonRow(
          id: 1, label: "Button 1", currentRaw: "FFFFFFFF", draftRaw: "FFFFFFFF",
          draftChoice: "FFFFFFFF", layer: .normal)
      ]
      model.gShiftButtonRows = [
        ButtonRow(
          id: 5, label: "Button 5 (G-Shift)", currentRaw: "FFFFFFFF", draftRaw: "FFFFFFFF",
          draftChoice: "FFFFFFFF", layer: .gShift)
      ]
      model.dpiCapabilities = DPICapabilities(minimum: 200, maximum: 8000)

      guard let url = model.createGeneratedProfile() else {
        XCTFail("expected a generated profile to be written")
        return
      }
      defer { try? FileManager.default.removeItem(at: url) }

      XCTAssertEqual(url.deletingLastPathComponent(), model.customProfilesDirectory)
      let data = try Data(contentsOf: url)
      let descriptor = try JSONDecoder().decode(MouseProfileDescriptor.self, from: data)
      XCTAssertTrue(descriptor.id.hasPrefix("auto-"))
      XCTAssertEqual(descriptor.buttons.map(\.number).sorted(), [1, 5])
      XCTAssertEqual(descriptor.match.nameContains, ["Totally Unknown Test Mouse"])
      XCTAssertEqual(descriptor.match.productIDs, ["0xABCD"])
      XCTAssertEqual(descriptor.dpiRange?.minimum, 200)
      XCTAssertEqual(descriptor.dpiRange?.maximum, 8000)
      XCTAssertEqual(descriptor.generated, true)
      XCTAssertEqual(descriptor.profileIO, MouseProfileCatalog.genericProfile.profileIO)
      // createGeneratedProfile() sets a "Created <file>…" status message,
      // but its own call to refresh() immediately re-enters startRefresh(),
      // which overwrites status again before this call returns (there is
      // no bundled engine in the test environment). The write itself, and
      // the descriptor's contents, are what this test verifies.
      XCTAssertEqual(model.status, EngineError.unavailable.localizedDescription)

      // The catalog reload after a successful write makes the device its
      // own best (if generated) match, so a second, unrelated device whose
      // name collides with the sanitized identifier gets a "-2" suffix
      // instead of overwriting the first file.
      let existingIDs = Set(MouseProfileCatalog.shared.profiles.map(\.id))
      XCTAssertTrue(existingIDs.contains(descriptor.id))
    }
  }

  func testCreateGeneratedProfileAppendsSuffixWhenIdentifierAlreadyExists() throws {
    let model = AppModel(startInitialRefresh: false)
    try withIsolatedConfigurationDirectory(model) { tempDirectory in
      let deviceName = "Collision Test Mouse"
      let baseID = "auto-\(BackupStorage.sanitizedMouseIdentifier(deviceName))"

      // Seed a descriptor whose id collides with the one this device would
      // generate, but whose match criteria never fire for it, so it does
      // not also make `hasSpecificMouseProfile` true and block the call.
      let collidingDescriptor = MouseProfileDescriptor(
        schemaVersion: 1,
        id: baseID,
        name: "Unrelated pre-existing descriptor",
        match: .init(nameContains: [], productIDs: []),
        buttons: [.init(number: 1, control: "Button 1", aliases: [], notes: nil)],
        scrollWheelButtonLabels: nil,
        hiddenProfileButtonNumbers: nil,
        dpiRange: nil,
        refreshGuidance: nil,
        profileIO: MouseProfileCatalog.genericProfile.profileIO,
        rgbProfile: nil,
        sources: []
      )
      let customDirectory = model.customProfilesDirectory
      try FileManager.default.createDirectory(
        at: customDirectory, withIntermediateDirectories: true)
      try JSONEncoder().encode(collidingDescriptor).write(
        to: customDirectory.appendingPathComponent("colliding.json"))
      MouseProfileCatalog.reload(customProfilesDirectory: customDirectory)
      XCTAssertTrue(MouseProfileCatalog.shared.profiles.map(\.id).contains(baseID))

      model.devices = [
        DeviceChoice(
          id: 1, name: deviceName, connection: "Wired", productID: "0xC011",
          deviceKey: "collision-mouse")
      ]
      model.selectedDeviceIndex = 1
      model.currentDeviceName = deviceName
      model.profiles = [ProfileChoice(id: 1, sector: "0x0100", enabled: true, crcValid: true)]
      model.normalButtonRows = [
        ButtonRow(
          id: 1, label: "Button 1", currentRaw: "FFFFFFFF", draftRaw: "FFFFFFFF",
          draftChoice: "FFFFFFFF", layer: .normal)
      ]

      guard let url = model.createGeneratedProfile() else {
        XCTFail("expected a generated profile to be written despite the id collision")
        return
      }
      XCTAssertEqual(url.lastPathComponent, "\(baseID)-2.json")
      _ = tempDirectory
    }
  }

  func testCreateGeneratedProfileReportsFailureWhenCustomProfilesDirectoryCannotBeCreated() {
    let model = AppModel(startInitialRefresh: false)
    withIsolatedConfigurationDirectory(model) { _ in
      let customDirectory = model.customProfilesDirectory
      try? FileManager.default.removeItem(at: customDirectory)
      // Occupy the custom-profiles path with a plain file so the write
      // path's own `createDirectory` and `Data.write` calls both fail.
      XCTAssertTrue(FileManager.default.createFile(atPath: customDirectory.path, contents: Data()))

      model.devices = [
        DeviceChoice(
          id: 1, name: "Blocked Directory Mouse", connection: "Wired", productID: "0xBEEF",
          deviceKey: "blocked-mouse")
      ]
      model.selectedDeviceIndex = 1
      model.currentDeviceName = "Blocked Directory Mouse"
      model.profiles = [ProfileChoice(id: 1, sector: "0x0100", enabled: true, crcValid: true)]
      model.normalButtonRows = [
        ButtonRow(
          id: 1, label: "Button 1", currentRaw: "FFFFFFFF", draftRaw: "FFFFFFFF",
          draftChoice: "FFFFFFFF", layer: .normal)
      ]

      XCTAssertNil(model.createGeneratedProfile())
      XCTAssertTrue(model.status.contains("Could not write"))
    }
  }

  func testSetShowAdvancedFieldsTogglesAndPersists() {
    let key = "\(AppConstants.defaultsPrefix).showAdvancedFields"
    let previousValue = UserDefaults.standard.object(forKey: key)
    defer {
      if let previousValue {
        UserDefaults.standard.set(previousValue, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
    }

    let model = AppModel(startInitialRefresh: false)
    model.setShowAdvancedFields(true)
    XCTAssertTrue(model.showAdvancedFields)
    XCTAssertTrue(UserDefaults.standard.bool(forKey: key))

    model.setShowAdvancedFields(false)
    XCTAssertFalse(model.showAdvancedFields)
    XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
  }

  func testSetShowNonStandardKeyboardKeysTogglesAndPersists() {
    let key = "\(AppConstants.defaultsPrefix).showNonStandardKeyboardKeys"
    let previousValue = UserDefaults.standard.object(forKey: key)
    defer {
      if let previousValue {
        UserDefaults.standard.set(previousValue, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
    }

    let model = AppModel(startInitialRefresh: false)
    model.setShowNonStandardKeyboardKeys(true)
    XCTAssertTrue(model.showNonStandardKeyboardKeys)
    XCTAssertTrue(UserDefaults.standard.bool(forKey: key))

    model.setShowNonStandardKeyboardKeys(false)
    XCTAssertFalse(model.showNonStandardKeyboardKeys)
    XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
  }
}
