// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

final class ProfileOutputParserTests: XCTestCase {
  func testAppearancePreferenceOptions() {
    XCTAssertEqual(AppearancePreference.allCases, [.system, .light, .dark])
    XCTAssertEqual(AppearancePreference.light.label, "Light")
  }

  func testOnboardProfileCapacityParsing() {
    let cases: [(String, Int?)] = [
      (
        "Onboard profiles for G502 X:\nProfile capacity: 5\nProfile 1 (sector 0x0100, enabled=yes)",
        5
      ),
      ("Profile 1 (sector 0x0100, enabled=yes)", nil),
      ("Profile capacity: nope\nProfile capacity: 0\nProfile capacity: 5 trailing", nil),
      ("Profile capacity: 2\r\nProfile 1 (sector 0x0100, enabled=yes)", 2),
    ]

    for (index, testCase) in cases.enumerated() {
      let actual = ProfileOutputParser.onboardProfileCapacity(in: testCase.0)
      XCTAssertEqual(actual, testCase.1, "profile capacity parser case \(index + 1)")
    }
  }

  func testScrollWheelOutputRecognition() {
    XCTAssertEqual(ProfileOutputParser.scrollWheelOutputLabel("90 10 00 00"), "Scroll down")
    XCTAssertEqual(ProfileOutputParser.scrollWheelOutputLabel("90110000"), "Scroll up")
    XCTAssertTrue(ProfileOutputParser.isScrollWheelOutput("90 10 00 00"))
    XCTAssertFalse(ProfileOutputParser.isScrollWheelOutput("90010000"))
    XCTAssertFalse(ProfileOutputParser.isScrollWheelOutput("FFFFFFFF"))
  }

  func testWiredAccessPromptAndMXClassification() {
    let wired = DeviceChoice(
      id: 1, name: "G Pro", connection: "Wired", productID: "0xC085", deviceKey: "wired")
    let receiver = DeviceChoice(
      id: 2, name: "G604", connection: "LIGHTSPEED", productID: "0x4085", deviceKey: "receiver")
    let bluetooth = DeviceChoice(
      id: 3, name: "MX Master 3S", connection: "Bluetooth", productID: "0xB034",
      deviceKey: "bluetooth")
    let withoutAccess = DeviceChoice.addingWiredAccessPrompt(
      to: [wired, receiver], accessAuthorized: false)
    let withAccess = DeviceChoice.addingWiredAccessPrompt(
      to: [wired, receiver], accessAuthorized: true)

    XCTAssertEqual(withoutAccess.last?.isWiredAccessPrompt, true)
    XCTAssertEqual(withAccess.count, 2)
    XCTAssertTrue(
      DeviceClassification.isMXSeriesMouse(name: bluetooth.name, productID: bluetooth.productID))
    XCTAssertTrue(DeviceClassification.isMXSeriesMouse(name: "MX Anywhere 3", productID: ""))
    XCTAssertFalse(DeviceClassification.isMXSeriesMouse(name: "G603", productID: "0xB01C"))
  }

  func testG604HiddenAndNonProgrammableControlMetadata() {
    let g604Profile = MouseProfileCatalog.shared.profile(deviceName: "G604", productID: "0x4085")
    XCTAssertEqual(g604Profile.hiddenProfileButtonNumbers?.contains(16), true)
    XCTAssertEqual(g604Profile.scrollWheelButtonLabel(for: 14), "Scroll down")
    XCTAssertEqual(g604Profile.scrollWheelButtonLabel(for: 15), "Scroll up")
    XCTAssertEqual(g604Profile.refreshGuidance?.sleepDescription.contains("several minutes"), true)
    XCTAssertFalse(MouseProfileCatalog.shared.profiles.isEmpty)
  }

  func testKnownDeviceRefreshGuidanceAndRetryPolicy() {
    let g603Profile = MouseProfileCatalog.shared.profile(deviceName: "G603", productID: "0xB01C")
    XCTAssertEqual(g603Profile.refreshGuidance?.sleepDescription.contains("3 seconds"), true)
    XCTAssertEqual(OnboardProfileRefreshPolicy.pollIntervalNanoseconds, 1_000_000_000)
    XCTAssertEqual(OnboardProfileRefreshPolicy.maximumPollAttempts, 60)
  }

  func testG203ProductIDCatalogMatch() {
    let g203Profile = MouseProfileCatalog.shared.profile(deviceName: "", productID: "0xC092")
    XCTAssertEqual(g203Profile.id, "g203")
    XCTAssertTrue(g203Profile.profileIO.canSave)
  }

  func testG600RemainsReadOnly() {
    let g600Profile = MouseProfileCatalog.shared.profile(
      deviceName: "G600 MMO", productID: "0xC24A")
    XCTAssertEqual(g600Profile.id, "g600")
    XCTAssertFalse(g600Profile.profileIO.supported)
    XCTAssertFalse(g600Profile.profileIO.canSave)
    XCTAssertEqual(
      g600Profile.profileIO.save["strategy"], "read-only",
      "G600 must remain read-only until all legacy profile features are supported")
  }

  func testProfileSelectionResolution() {
    let selectionCases: [(Int?, [Int], Int, Int?)] = [
      (nil, [1], 2, 1),  // multi-profile mouse -> one-profile mouse
      (nil, [1, 2], 1, 1),  // one-profile mouse -> multi-profile mouse
      (2, [1, 2], 1, 2),
      (2, [1], 2, 1),  // stale selected slot is not retained
    ]
    for (index, testCase) in selectionCases.enumerated() {
      let actual = ProfileSelection.resolvedProfileNumber(
        selectedProfileNumber: testCase.0,
        availableProfileIDs: testCase.1,
        preferredProfileNumber: testCase.2
      )
      XCTAssertEqual(actual, testCase.3, "profile selection case \(index + 1)")
    }
  }

  func testDPIRangeParsingAndSnapping() {
    let rangeCapabilities = DPIOutputParser.parse(
      "DPI sensors: 1\r\nSupported DPI: 400..25600 (step 50)\r\nCurrent sensor 1 DPI: 1600\r\n"
    )
    XCTAssertEqual(rangeCapabilities.minimum, 400)
    XCTAssertEqual(rangeCapabilities.maximum, 25600)
    XCTAssertEqual(rangeCapabilities.step, 50)
    XCTAssertEqual(rangeCapabilities.sensorCount, 1)
    XCTAssertEqual(rangeCapabilities.currentValue, 1600)
    XCTAssertTrue(rangeCapabilities.accepts(1600))
    XCTAssertFalse(rangeCapabilities.accepts(1625))
    XCTAssertEqual(rangeCapabilities.snappedValue(for: 1573), 1550)
  }

  func testDPIDiscreteListParsingAndNeighborConstraints() {
    let listCapabilities = DPIOutputParser.parse("Supported DPI: 800, 1600, 3200\n")
    XCTAssertEqual(listCapabilities.supportedValues, [800, 1600, 3200])
    XCTAssertFalse(listCapabilities.accepts(1200))
    XCTAssertEqual(listCapabilities.snappedValue(for: 1300), 1600)
    XCTAssertEqual(listCapabilities.snappedValue(for: 1800, lowerBound: 1601), 3200)
    XCTAssertEqual(listCapabilities.snappedValue(for: 1800, upperBound: 1599), 800)
  }

  func testExtendedPollingRateParsing() {
    let extendedPolling = PollingRateOutputParser.parse(
      "Report rate feature: 0x8061\nSupported polling rates: 125, 1000, 8000\nCurrent polling rate: 1000 Hz\n"
    )
    XCTAssertEqual(extendedPolling.supportedRates, [125, 1000, 8000])
    XCTAssertEqual(extendedPolling.currentRate, 1000)
    XCTAssertTrue(extendedPolling.accepts(8000))
    XCTAssertFalse(extendedPolling.accepts(500))
  }

  func testLegacyPollingRateParsing() {
    let legacyPolling = PollingRateOutputParser.parse(
      "Report rate feature: 0x8060\nSupported polling rates: 125, 250, 333, 1000\nCurrent polling rate: 333 Hz\n"
    )
    XCTAssertEqual(legacyPolling.supportedRates, [125, 250, 333, 1000])
    XCTAssertEqual(legacyPolling.currentRate, 333)
  }

  func testDPIEditorValidationAcceptsValidStages() {
    let listCapabilities = DPIOutputParser.parse("Supported DPI: 800, 1600, 3200\n")
    let validStages = ["800", "1600", "3200", "", ""]
    let validMessage = DPIEditorValidation.message(
      stages: validStages,
      count: 3,
      defaultStage: 2,
      shiftStage: 1,
      capabilities: listCapabilities
    )
    XCTAssertNil(validMessage, "valid DPI stages were rejected")
  }

  func testDPIEditorValidationRejectsInvalidStages() {
    let listCapabilities = DPIOutputParser.parse("Supported DPI: 800, 1600, 3200\n")
    let invalidCases: [([String], Int, String)] = [
      (["800", "", "", "", ""], 2, "Enter a numeric value for DPI stage 2."),
      (["800", "800", "", "", ""], 2, "DPI stages may not overlap."),
      (["800", "1200", "", "", ""], 2, "DPI stage 2 is not supported by this mouse."),
    ]
    for (stages, count, expected) in invalidCases {
      let message = DPIEditorValidation.message(
        stages: stages,
        count: count,
        defaultStage: 1,
        shiftStage: 1,
        capabilities: listCapabilities
      )
      XCTAssertEqual(message, expected)
    }
  }

  func testBackupStorageDirectoryAndFilenameHandling() throws {
    let fileManager = FileManager.default
    let testRoot = fileManager.temporaryDirectory
      .appendingPathComponent("lope-backup-storage-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: testRoot) }

    let g502Directory = BackupStorage.modelDirectory(
      root: testRoot, mouseIdentifier: "G502 X/PLUS")
    let legacyDirectory = testRoot.appendingPathComponent("legacy", isDirectory: true)
    let hiddenDirectory = testRoot.appendingPathComponent(".hidden", isDirectory: true)
    try fileManager.createDirectory(at: g502Directory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true)

    let first = BackupStorage.uniqueBackupURL(
      root: testRoot,
      mouseIdentifier: "G502 X/PLUS",
      prefix: "profile-1-save",
      fileExtension: "logiob",
      timestamp: "20260912-120000"
    )
    XCTAssertEqual(
      first.path,
      testRoot
        .appendingPathComponent("G502-X-PLUS", isDirectory: true)
        .appendingPathComponent("G502-X-PLUS-profile-1-save-20260912-120000.logiob")
        .path
    )
    XCTAssertEqual(
      BackupStorage.mouseIdentifier(fromBackupFilename: first.lastPathComponent), "G502-X-PLUS")

    try Data([0x01]).write(to: first)
    let second = BackupStorage.uniqueBackupURL(
      root: testRoot,
      mouseIdentifier: "G502 X/PLUS",
      prefix: "profile-1-save",
      fileExtension: "logiob",
      timestamp: "20260912-120000"
    )
    XCTAssertEqual(second.lastPathComponent, "G502-X-PLUS-profile-1-save-20260912-120000-2.logiob")

    let legacy = legacyDirectory.appendingPathComponent("legacy.bin")
    let json = g502Directory.appendingPathComponent("G502-X-PLUS-profile-1-export.json")
    let hidden = hiddenDirectory.appendingPathComponent("hidden.logiob")
    try Data([0x02]).write(to: legacy)
    try Data([0x03]).write(to: json)
    try Data([0x04]).write(to: hidden)
    let discovered = Set(BackupStorage.backupURLs(in: testRoot).map { $0.standardizedFileURL })
    let expectedBackups = Set([first, legacy, json].map { $0.standardizedFileURL })
    XCTAssertEqual(discovered, expectedBackups)
    XCTAssertNil(
      BackupStorage.mouseIdentifier(fromBackupFilename: "profile-1-save-20260912-120000.logiob"))
    XCTAssertEqual(BackupStorage.restoreArguments(for: first), ["restore", first.path, "--yes"])

    let expectedDocuments = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    XCTAssertEqual(BackupStorage.documentsDirectory(fileManager: fileManager), expectedDocuments)
  }

  func testRGBHexConversionAndValidation() {
    let red = RGBColor(hex: "#ff002a")
    XCTAssertEqual(red, RGBColor(red: 255, green: 0, blue: 42))
    XCTAssertEqual(red?.hex, "0xFF002A")
    XCTAssertEqual(RGBColor(hex: "0x123456"), RGBColor(red: 0x12, green: 0x34, blue: 0x56))
    XCTAssertNil(RGBColor(hex: "12345"))
    XCTAssertNil(RGBColor(hex: "0xGG0000"))
  }

  func testRGBProfileOutputParsing() {
    let parsedRGBLine = ProfileOutputParser.rgbZone(
      from: "  RGB zone 2: A1B2C3 (mode 0x01)"
    )
    XCTAssertEqual(parsedRGBLine?.index, 1)
    XCTAssertEqual(parsedRGBLine?.color, RGBColor(red: 0xA1, green: 0xB2, blue: 0xC3))
    XCTAssertEqual(
      ProfileOutputParser.profileFormat(from: "  format: 0x05, macro format: 0x01"), 5)
    XCTAssertNil(ProfileOutputParser.rgbZone(from: "RGB zone 0: AABBCC (mode 0x01)"))
  }

  func testRGBEditorLogicPerZoneAndAllZoneEditing() {
    let rgbZones = [
      RGBZoneState(
        id: 0, name: "Primary", current: RGBColor(red: 1, green: 2, blue: 3),
        draft: RGBColor(red: 1, green: 2, blue: 3)),
      RGBZoneState(
        id: 1, name: "Logo", current: RGBColor(red: 4, green: 5, blue: 6),
        draft: RGBColor(red: 4, green: 5, blue: 6)),
    ]
    let blue = LOPECore.RGBColor(red: 0, green: 64, blue: 255)
    let oneZone = RGBEditorLogic.settingColor(in: rgbZones, zoneID: 1, color: blue, allZones: false)
    XCTAssertEqual(oneZone[0].draft, rgbZones[0].draft)
    XCTAssertEqual(oneZone[1].draft, blue)

    let allZones = RGBEditorLogic.settingColor(in: rgbZones, zoneID: 0, color: blue, allZones: true)
    XCTAssertTrue(allZones.allSatisfy({ $0.draft == blue }))
    XCTAssertEqual(
      RGBEditorLogic.settingColor(in: rgbZones, zoneID: 9, color: blue, allZones: true), rgbZones)
  }

  func testG502RGBCapabilityGating() {
    let g502 = MouseProfileCatalog.shared.profile(deviceName: "G502 HERO", productID: "0xC08B")
    let g502RGB = g502.rgbCapabilities(
      deviceName: "G502 HERO", productID: "0xC08B", profileFormat: 5)
    XCTAssertEqual(g502RGB?.zones.map(\.name), ["Primary", "Logo"])
    XCTAssertNil(
      g502.rgbCapabilities(deviceName: "G502 HERO", productID: "0xC08B", profileFormat: 7))

    let unsupported = MouseProfileCatalog.shared.profile(
      deviceName: "G603 LIGHTSPEED", productID: "0xB01C")
    XCTAssertNil(
      unsupported.rgbCapabilities(
        deviceName: "G603 LIGHTSPEED", productID: "0xB01C", profileFormat: 5))
  }
}
