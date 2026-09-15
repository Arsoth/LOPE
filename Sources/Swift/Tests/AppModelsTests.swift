// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

final class AppModelsTests: XCTestCase {
  func testWiredAndMXClassification() {
    let wired = DeviceChoice(
      id: 1, name: "G Pro", connection: "Wired", productID: "0xC085", deviceKey: "wired")
    let receiver = DeviceChoice(
      id: 2, name: "G604", connection: "LIGHTSPEED", productID: "0x4085", deviceKey: "receiver")
    let bluetooth = DeviceChoice(
      id: 3, name: "MX Master 3S", connection: "Bluetooth", productID: "0xB034",
      deviceKey: "bluetooth")
    XCTAssertTrue(wired.isWiredDevice)
    XCTAssertFalse(receiver.isWiredDevice)
    // isMXSeriesMouse lives in DeviceClassification.swift; checked here
    // against the same device fixtures rather than duplicating them.
    XCTAssertTrue(
      DeviceClassification.isMXSeriesMouse(name: bluetooth.name, productID: bluetooth.productID))
    XCTAssertTrue(DeviceClassification.isMXSeriesMouse(name: "MX Anywhere 3", productID: ""))
    XCTAssertFalse(DeviceClassification.isMXSeriesMouse(name: "G603", productID: "0xB01C"))
  }

  func testProfileChoiceTitleReflectsEnabledState() {
    let enabled = ProfileChoice(id: 1, sector: "abc", enabled: true, crcValid: true)
    let disabled = ProfileChoice(id: 2, sector: "def", enabled: false, crcValid: nil)
    XCTAssertEqual(enabled.title, "Profile 1")
    XCTAssertEqual(disabled.title, "Profile 2 (disabled)")
  }

  func testButtonLayerLabels() {
    XCTAssertEqual(ButtonLayer.allCases, [.normal, .gShift])
    XCTAssertEqual(ButtonLayer.normal.label, "Normal")
    XCTAssertEqual(ButtonLayer.gShift.label, "G-Shift")
  }

  func testButtonRowDisplayLabelFallsBackWhenBlank() {
    let blank = ButtonRow(
      id: 3, label: "   ", currentRaw: "raw", draftRaw: "raw", draftChoice: "choice",
      layer: .normal)
    let named = ButtonRow(
      id: 4, label: "  Left Click  ", currentRaw: "raw", draftRaw: "raw", draftChoice: "choice",
      layer: .gShift)
    XCTAssertEqual(blank.displayLabel, "Button 3")
    XCTAssertEqual(named.displayLabel, "Left Click")
  }

  func testBackupEntryDeviceMatchLabels() {
    XCTAssertEqual(BackupEntry.DeviceMatch.selected.label, "Selected mouse")
    XCTAssertEqual(BackupEntry.DeviceMatch.other.label, "Different mouse")
    XCTAssertEqual(BackupEntry.DeviceMatch.unknown.label, "Unknown device")
  }

  func testBackupEntryComputedProperties() {
    let jsonURL = URL(fileURLWithPath: "/tmp/backup.json")
    let binaryURL = URL(fileURLWithPath: "/tmp/backup.logiob")
    let date = Date(timeIntervalSince1970: 0)

    let selectedNamed = BackupEntry(
      url: jsonURL, modifiedAt: date, size: 10, deviceMatch: .selected, deviceName: "G604")
    XCTAssertEqual(selectedNamed.id, jsonURL.path)
    XCTAssertEqual(selectedNamed.name, "backup.json")
    XCTAssertTrue(selectedNamed.isJSON)
    XCTAssertEqual(selectedNamed.fileTypeLabel, "Editable JSON")
    XCTAssertEqual(selectedNamed.deviceStatusLabel, "Selected mouse: G604")

    let selectedUnnamed = BackupEntry(
      url: jsonURL, modifiedAt: date, size: 10, deviceMatch: .selected, deviceName: nil)
    XCTAssertEqual(selectedUnnamed.deviceStatusLabel, "Selected mouse")

    let otherNamed = BackupEntry(
      url: binaryURL, modifiedAt: date, size: 20, deviceMatch: .other, deviceName: "G Pro")
    XCTAssertFalse(otherNamed.isJSON)
    XCTAssertEqual(otherNamed.fileTypeLabel, "Exact binary")
    XCTAssertEqual(otherNamed.deviceStatusLabel, "Different mouse: G Pro")

    let otherUnnamed = BackupEntry(
      url: binaryURL, modifiedAt: date, size: 20, deviceMatch: .other, deviceName: nil)
    XCTAssertEqual(otherUnnamed.deviceStatusLabel, "Different mouse")

    let unknown = BackupEntry(
      url: binaryURL, modifiedAt: date, size: 20, deviceMatch: .unknown, deviceName: "Ignored")
    XCTAssertEqual(unknown.deviceStatusLabel, "Unknown device — review before using")
  }

  func testDeviceChoiceIsWiredDeviceIsCaseInsensitive() {
    let wired = DeviceChoice(
      id: 1, name: "G604", connection: "WIRED", productID: "0x1", deviceKey: "wired")
    let notWired = DeviceChoice(
      id: 2, name: "G604", connection: "LIGHTSPEED", productID: "0x1", deviceKey: "receiver")
    XCTAssertTrue(wired.isWiredDevice)
    XCTAssertFalse(notWired.isWiredDevice)
  }

  func testPairedGenericNameIsReplacedBySpecificModelIdentity() {
    let generic = DeviceChoice(
      id: 1, name: "Paired Logitech Mouse - Lightspeed", connection: "Wireless",
      productID: "0x4085", deviceKey: "paired")

    XCTAssertTrue(generic.isGenericPairedName)
    XCTAssertEqual(DeviceChoice.preferredName(reported: "G604", fallback: generic.name), "G604")
    XCTAssertEqual(
      DeviceChoice.preferredName(
        reported: "Paired Logitech Mouse - Lightspeed", fallback: "G604"),
      "G604")
    XCTAssertFalse(
      DeviceChoice(
        id: 1, name: "G604", connection: "Wireless", productID: "0x4085", deviceKey: "paired"
      ).isGenericPairedName)
  }

  func testPreferredNameRemovesGenericWirelessGamingMouseSuffix() {
    XCTAssertEqual(
      DeviceChoice.preferredName(
        reported: "G604 Wireless Gaming Mouse", fallback: "G604"),
      "G604")
    XCTAssertEqual(
      DeviceChoice.preferredName(
        reported: "G603 wireless gaming mouse", fallback: "G603"),
      "G603")
  }

  func testPreferredNameCanonicalizesG502MarketingLabelsAndVariants() {
    XCTAssertEqual(
      DeviceChoice.preferredName(
        reported: "Tunable RGB Gaming Mouse G502", fallback: "G502"),
      "G502")
    XCTAssertEqual(
      DeviceChoice.preferredName(
        reported: "Tunable RGB Gaming Mouse G502 X LIGHTSPEED", fallback: "G502"),
      "G502 X LIGHTSPEED")
    XCTAssertEqual(
      DeviceChoice.preferredName(
        reported: "G502 X PLUS Wireless Gaming Mouse", fallback: "G502"),
      "G502 X PLUS")
  }

  func testPairedIdentityMatchesWhenReceiverKeyChanges() {
    let previous = DeviceChoice(
      id: 1, name: "G604", connection: "Wireless", productID: "0x4085", deviceKey: "old-key")
    let reconnected = DeviceChoice(
      id: 3, name: "Paired Logitech Mouse - Lightspeed", connection: "Wireless",
      productID: "0x4085", deviceKey: "new-key")
    let different = DeviceChoice(
      id: 3, name: "G502 X", connection: "Wireless", productID: "0x4085", deviceKey: "new-key")

    XCTAssertTrue(reconnected.matchesReconnectIdentity(previous))
    XCTAssertFalse(different.matchesReconnectIdentity(previous))
  }

  func testEditableBackupRoundTripsThroughJSON() throws {
    let json = """
      {
        "formatVersion": 1,
        "createdAt": "2026-01-01T00:00:00Z",
        "device": { "name": "G604", "productID": "0xC087" },
        "profiles": [ { "number": 1, "enabled": true } ],
        "profile": {
          "number": 1,
          "sector": "deadbeef",
          "enabled": true,
          "buttons": [
            {
              "number": 1,
              "physicalControl": "Left Click",
              "output": "Left Click",
              "raw": "01",
              "layer": "normal"
            }
          ],
          "dpi": { "stages": [800, 1600], "defaultStage": 1, "shiftStage": 2 },
          "rgb": [ { "zone": 0, "name": "Logo", "color": "#FF0000" } ]
        },
        "exactBinaryBackup": "base64data"
      }
      """
    let decoded = try JSONDecoder().decode(EditableBackup.self, from: Data(json.utf8))
    XCTAssertEqual(decoded.formatVersion, 1)
    XCTAssertEqual(decoded.device.name, "G604")
    XCTAssertEqual(decoded.profiles.first?.number, 1)
    XCTAssertEqual(decoded.profile.buttons.first?.physicalControl, "Left Click")
    XCTAssertEqual(decoded.profile.dpi?.stages, [800, 1600])
    XCTAssertEqual(decoded.profile.rgb?.first?.color, "#FF0000")
    XCTAssertEqual(decoded.exactBinaryBackup, "base64data")

    // Encode and decode again to exercise the synthesized Encodable side
    // alongside Button's custom Decodable initializer.
    let reencoded = try JSONEncoder().encode(decoded)
    let roundTripped = try JSONDecoder().decode(EditableBackup.self, from: reencoded)
    XCTAssertEqual(roundTripped.profile.buttons.first?.raw, "01")
  }

  func testEditableBackupOptionalFieldsCanBeAbsent() throws {
    let json = """
      {
        "formatVersion": 1,
        "createdAt": "2026-01-01T00:00:00Z",
        "device": { "name": "G604", "productID": "0xC087" },
        "profiles": [],
        "profile": {
          "number": 1,
          "enabled": false,
          "buttons": []
        }
      }
      """
    let decoded = try JSONDecoder().decode(EditableBackup.self, from: Data(json.utf8))
    XCTAssertNil(decoded.profile.sector)
    XCTAssertNil(decoded.profile.dpi)
    XCTAssertNil(decoded.profile.rgb)
    XCTAssertNil(decoded.exactBinaryBackup)
  }

  func testEditableBackupButtonExplicitInit() {
    let button = EditableBackup.Button(
      number: 5, physicalControl: "Middle Click", output: "Middle Click", raw: "02",
      layer: "gShift")
    XCTAssertEqual(button.number, 5)
    XCTAssertEqual(button.layer, "gShift")
  }
}
