// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelJSONEditableBackupsTests: XCTestCase {
  private func makeTempJSONURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "lope-json-editable-backup-\(UUID().uuidString).json")
  }

  /// G502 HERO (product 0xC08B) is the only catalog entry whose RGB
  /// capability has no device-name/product restriction of its own, so it is
  /// used whenever a test needs a device that actually advertises RGB
  /// zones. This intentionally does not reuse `configureFixtureDevice`
  /// (a G502 X, which has no RGB) since it is exercising a different
  /// device family.
  private func configureRGBFixtureDevice(_ model: AppModel) {
    model.devices = [
      DeviceChoice(
        id: 1, name: "G502 HERO", connection: "Wired", productID: "0xC08B",
        deviceKey: "rgb-device")
    ]
    model.selectedDeviceIndex = 1
    model.currentDeviceName = "G502 HERO"
    model.profileNumber = 2
    model.profiles = [ProfileChoice(id: 2, sector: "0x0100", enabled: true, crcValid: true)]
    model.baselineProfileEnabled = [2: true]
    model.buttons = [
      ButtonRow(
        id: 1, label: "G1 · Primary click (Left)", currentRaw: "80010001",
        draftRaw: "80010001", draftChoice: "80010001", layer: .normal)
    ]
    model.rgbZones = [
      RGBZoneState(
        id: 0, name: "Primary", current: RGBColor(red: 0, green: 0, blue: 0),
        draft: RGBColor(red: 0, green: 0, blue: 0)),
      RGBZoneState(
        id: 1, name: "Logo", current: RGBColor(red: 0, green: 0, blue: 0),
        draft: RGBColor(red: 0, green: 0, blue: 0)),
    ]
  }

  private func write(_ backup: EditableBackup, to url: URL) throws {
    try JSONEncoder().encode(backup).write(to: url)
  }

  // MARK: - exportCurrentJSON

  func testExportCurrentJSONFailsWithoutAProfileLoaded() {
    let model = AppModel(startInitialRefresh: false)
    let url = makeTempJSONURL()
    model.exportCurrentJSON(to: url)
    XCTAssertEqual(model.status, "Read a Logitech profile before exporting JSON.")
    XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
  }

  func testExportCurrentJSONWritesPresetCustomAndKeyboardOutputLabels() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.buttons = [
      ButtonRow(
        id: 1, label: "G1", currentRaw: "80010002", draftRaw: "80010002",
        draftChoice: "80010002", layer: .normal),
      ButtonRow(
        id: 2, label: "G2", currentRaw: "12345678", draftRaw: "12345678",
        draftChoice: "keystroke", layer: .normal),
      ButtonRow(
        id: 3, label: "G3", currentRaw: "80020104", draftRaw: "80020104",
        draftChoice: "keystroke", layer: .normal),
      ButtonRow(
        id: 4, label: "G4", currentRaw: "80020004", draftRaw: "80020004",
        draftChoice: "keystroke", layer: .normal),
      ButtonRow(
        id: 5, label: "G5", currentRaw: "80020000", draftRaw: "80020000",
        draftChoice: "keystroke", layer: .normal),
      // bytes[3] == 0xFF is not a cataloged keyboard key, so this falls
      // back to a raw hex label instead of a catalog name.
      ButtonRow(
        id: 6, label: "G6", currentRaw: "800200FF", draftRaw: "800200FF",
        draftChoice: "keystroke", layer: .normal),
    ]
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }

    model.exportCurrentJSON(to: url)

    XCTAssertTrue(model.status.contains("Exported profile 2 to"))
    let data = try Data(contentsOf: url)
    let decoded = try JSONDecoder().decode(EditableBackup.self, from: data)
    let outputsByNumber = Dictionary(
      uniqueKeysWithValues: decoded.profile.buttons.map { ($0.number, $0.output) })
    XCTAssertEqual(outputsByNumber[1], "Right click")
    XCTAssertEqual(outputsByNumber[2], "Custom")
    XCTAssertEqual(outputsByNumber[3], "Ctrl + A")
    XCTAssertEqual(outputsByNumber[4], "A")
    // bytes[3] == 0 fails the keyboard-chord guard even though bytes[0..1]
    // match the 0x8002 shape, so this also falls back to "Custom".
    XCTAssertEqual(outputsByNumber[5], "Custom")
    XCTAssertEqual(outputsByNumber[6], "0xFF")
    XCTAssertEqual(decoded.device.name, "G502 X")
    XCTAssertNil(decoded.profile.rgb)
  }

  func testExportCurrentJSONIncludesRGBZonesForACapableDevice() throws {
    let model = AppModel(startInitialRefresh: false)
    configureRGBFixtureDevice(model)
    model.rgbZones = [
      RGBZoneState(
        id: 0, name: "Primary", current: RGBColor(red: 0, green: 0, blue: 0),
        draft: RGBColor(red: 255, green: 0, blue: 0)),
      RGBZoneState(
        id: 1, name: "Logo", current: RGBColor(red: 0, green: 0, blue: 0),
        draft: RGBColor(red: 0, green: 255, blue: 0)),
    ]
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }

    model.exportCurrentJSON(to: url)

    let decoded = try JSONDecoder().decode(EditableBackup.self, from: Data(contentsOf: url))
    let colorsByZone = Dictionary(
      uniqueKeysWithValues: (decoded.profile.rgb ?? []).map { ($0.zone, $0.color) })
    XCTAssertEqual(colorsByZone[0], RGBColor(red: 255, green: 0, blue: 0).hex)
    XCTAssertEqual(colorsByZone[1], RGBColor(red: 0, green: 255, blue: 0).hex)
  }

  func testExportCurrentJSONIncludesDPIAndFiltersRGBZoneOutsideDeviceCapability() throws {
    let model = AppModel(startInitialRefresh: false)
    configureRGBFixtureDevice(model)
    model.dpiCount = 2
    model.dpiStages = ["400", "800", "", "", ""]
    model.defaultStage = 1
    model.shiftStage = 2
    model.rgbZones = [
      RGBZoneState(
        id: 0, name: "Primary", current: RGBColor(red: 0, green: 0, blue: 0),
        draft: RGBColor(red: 255, green: 0, blue: 0)),
      // Not one of G502 HERO's actual RGB zones -- exercises the branch
      // that filters an unsupported zone out of the export instead of
      // including it.
      RGBZoneState(
        id: 99, name: "Unsupported", current: RGBColor(red: 0, green: 0, blue: 0),
        draft: RGBColor(red: 1, green: 2, blue: 3)),
    ]
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }

    model.exportCurrentJSON(to: url)

    let decoded = try JSONDecoder().decode(EditableBackup.self, from: Data(contentsOf: url))
    XCTAssertEqual(decoded.profile.dpi?.stages, [400, 800])
    XCTAssertEqual(decoded.profile.dpi?.defaultStage, 1)
    XCTAssertEqual(decoded.profile.dpi?.shiftStage, 2)
    let zoneIDs = Set((decoded.profile.rgb ?? []).map(\.zone))
    XCTAssertEqual(zoneIDs, [0])
  }

  func testExportCurrentJSONFallsBackToDefaultsWhenDeviceOrProfileIsMissing() throws {
    // Covers the `selectedDevice?.name/productID ?? ...` and
    // `selectedProfile?.enabled ?? false` fallbacks: selectedDeviceIndex
    // does not match any entry in `devices`, and profileNumber does not
    // match any entry in `profiles`, unlike every other export test.
    let model = AppModel(startInitialRefresh: false)
    configureRGBFixtureDevice(model)
    model.selectedDeviceIndex = 999
    model.profileNumber = 7
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }

    model.exportCurrentJSON(to: url)

    let decoded = try JSONDecoder().decode(EditableBackup.self, from: Data(contentsOf: url))
    XCTAssertEqual(decoded.device.name, "G502 HERO")
    XCTAssertEqual(decoded.device.productID, "")
    XCTAssertEqual(decoded.profile.enabled, false)
  }

  func testExportCurrentJSONFailsWhenWriteTargetIsUnwritable() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("lope-missing-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("export.json")
    model.exportCurrentJSON(to: url)
    XCTAssertTrue(model.status.hasPrefix("Could not export JSON:"))
  }

  // MARK: - loadEditableBackup guard rails

  func testLoadEditableBackupNoOpWhenBusy() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.busy = true
    let originalStatus = model.status
    model.loadEditableBackup(makeTempJSONURL())
    XCTAssertEqual(model.status, originalStatus)
  }

  func testLoadEditableBackupFailsWithoutAProfileLoaded() {
    let model = AppModel(startInitialRefresh: false)
    model.profiles = []
    model.loadEditableBackup(makeTempJSONURL())
    XCTAssertEqual(model.status, "Read a Logitech profile before loading JSON.")
  }

  func testLoadEditableBackupFailsWhenFileIsMissing() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.loadEditableBackup(makeTempJSONURL())
    XCTAssertTrue(model.status.hasPrefix("Could not load JSON:"))
  }

  func testLoadEditableBackupFailsWhenJSONIsMalformed() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("not valid json".utf8).write(to: url)
    model.loadEditableBackup(url)
    XCTAssertTrue(model.status.hasPrefix("Could not load JSON:"))
  }

  private func makeBaseBackup(
    profileNumber: Int = 2,
    formatVersion: Int = 1,
    deviceProductID: String = "0x0000",
    profiles: [EditableBackup.ProfileState] = [
      EditableBackup.ProfileState(number: 2, enabled: true)
    ],
    profileEnabled: Bool = true,
    buttons: [EditableBackup.Button] = [],
    dpi: EditableBackup.DPI? = nil,
    rgb: [EditableBackup.Profile.RGB]? = nil
  ) -> EditableBackup {
    EditableBackup(
      formatVersion: formatVersion,
      createdAt: "2026-01-01T00:00:00Z",
      device: EditableBackup.Device(name: "G502 X", productID: deviceProductID),
      profiles: profiles,
      profile: EditableBackup.Profile(
        number: profileNumber, sector: "0x0100", enabled: profileEnabled, buttons: buttons,
        dpi: dpi, rgb: rgb),
      exactBinaryBackup: nil
    )
  }

  func testLoadEditableBackupRejectsUnsupportedFormatVersion() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(makeBaseBackup(formatVersion: 2), to: url)
    model.loadEditableBackup(url)
    XCTAssertEqual(model.status, "Unsupported JSON profile version 2.")
  }

  func testLoadEditableBackupRejectsMismatchedProfileNumber() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(makeBaseBackup(profileNumber: 3), to: url)
    model.loadEditableBackup(url)
    XCTAssertEqual(model.status, "Select Profile 3 before loading this JSON file.")
  }

  func testLoadEditableBackupRejectsDisablingEveryProfile() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        profiles: [EditableBackup.ProfileState(number: 2, enabled: false)],
        profileEnabled: false),
      to: url)
    model.loadEditableBackup(url)
    XCTAssertEqual(
      model.status,
      "The JSON would disable every onboard profile. At least one must remain enabled.")
  }

  func testLoadEditableBackupRejectsUnrecognizedButtonLayer() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        buttons: [
          EditableBackup.Button(
            number: 1, physicalControl: "G1", output: "Left click", raw: "80010001",
            layer: "sideways")
        ]),
      to: url)
    model.loadEditableBackup(url)
    XCTAssertEqual(model.status, "JSON button 1 has an unrecognized layer 'sideways'.")
  }

  func testLoadEditableBackupRejectsButtonNumberNotOnCurrentLayer() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        buttons: [
          EditableBackup.Button(
            number: 99, physicalControl: "Ghost", output: "Left click", raw: "80010001",
            layer: ButtonLayer.normal.rawValue)
        ]),
      to: url)
    model.loadEditableBackup(url)
    XCTAssertEqual(
      model.status,
      "JSON Normal button 99 has no recognized output or 8-digit raw record.")
  }

  func testLoadEditableBackupRejectsUnresolvableOutputAndRaw() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        buttons: [
          EditableBackup.Button(
            number: 1, physicalControl: "G1", output: "Not a real output", raw: "ZZ",
            layer: ButtonLayer.normal.rawValue)
        ]),
      to: url)
    model.loadEditableBackup(url)
    XCTAssertEqual(
      model.status,
      "JSON Normal button 1 has no recognized output or 8-digit raw record.")
  }

  func testLoadEditableBackupRejectsInvalidDPIStageCount() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        dpi: EditableBackup.DPI(
          stages: [400, 800, 1200, 1600, 2000, 2400], defaultStage: 1, shiftStage: 1)),
      to: url)
    model.loadEditableBackup(url)
    XCTAssertEqual(model.status, "The JSON DPI values or stage indexes are invalid.")
  }

  func testLoadEditableBackupRejectsOutOfRangeDPIDefaultStage() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        dpi: EditableBackup.DPI(stages: [400, 800], defaultStage: 5, shiftStage: 1)),
      to: url)
    model.loadEditableBackup(url)
    XCTAssertEqual(model.status, "The JSON DPI values or stage indexes are invalid.")
  }

  func testLoadEditableBackupRejectsRGBWhenDeviceHasNoRGBCapability() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        rgb: [EditableBackup.Profile.RGB(zone: 0, name: "Primary", color: "0xFF0000")]),
      to: url)
    model.loadEditableBackup(url)
    XCTAssertEqual(
      model.status,
      "This JSON contains RGB settings, but the selected device/profile does not advertise writable RGB zones."
    )
  }

  func testLoadEditableBackupRejectsUnknownRGBZone() throws {
    let model = AppModel(startInitialRefresh: false)
    configureRGBFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        deviceProductID: "0xC08B",
        rgb: [EditableBackup.Profile.RGB(zone: 9, name: "Nonexistent", color: "0xFF0000")]),
      to: url)
    model.loadEditableBackup(url)
    XCTAssertEqual(model.status, "The JSON RGB zones or colors are invalid for this device.")
  }

  func testLoadEditableBackupRejectsDuplicateRGBZone() throws {
    let model = AppModel(startInitialRefresh: false)
    configureRGBFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        deviceProductID: "0xC08B",
        rgb: [
          EditableBackup.Profile.RGB(zone: 0, name: "Primary", color: "0xFF0000"),
          EditableBackup.Profile.RGB(zone: 0, name: "Primary", color: "0x00FF00"),
        ]),
      to: url)
    model.loadEditableBackup(url)
    XCTAssertEqual(model.status, "The JSON RGB zones or colors are invalid for this device.")
  }

  func testLoadEditableBackupRejectsInvalidRGBColor() throws {
    let model = AppModel(startInitialRefresh: false)
    configureRGBFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        deviceProductID: "0xC08B",
        rgb: [EditableBackup.Profile.RGB(zone: 0, name: "Primary", color: "not-a-color")]),
      to: url)
    model.loadEditableBackup(url)
    XCTAssertEqual(model.status, "The JSON RGB zones or colors are invalid for this device.")
  }

  // MARK: - loadEditableBackup success paths

  func testLoadEditableBackupSuccessAppliesButtonsDPIProfileStateAndWarnsOnDeviceMismatch() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        deviceProductID: "0xFFFF",
        profiles: [EditableBackup.ProfileState(number: 2, enabled: true)],
        buttons: [
          EditableBackup.Button(
            number: 1, physicalControl: "G1", output: "Right click", raw: "80010002",
            layer: ButtonLayer.normal.rawValue)
        ],
        dpi: EditableBackup.DPI(stages: [400, 800, 1600], defaultStage: 2, shiftStage: 1)
      ),
      to: url)

    model.loadEditableBackup(url)

    XCTAssertEqual(model.buttons[0].draftRaw, "80010002")
    XCTAssertEqual(model.dpiCount, 3)
    XCTAssertEqual(model.dpiStages.prefix(3).map { $0 }, ["400", "800", "1600"])
    XCTAssertEqual(model.defaultStage, 2)
    XCTAssertEqual(model.shiftStage, 1)
    XCTAssertTrue(model.status.contains("Loaded"))
    XCTAssertTrue(model.status.contains("Review it, then choose Save to mouse."))
    XCTAssertTrue(
      model.status.contains("The source device differs, so review the outputs before saving."))
  }

  func testLoadEditableBackupSuccessMatchingDeviceHasNoWarning() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(makeBaseBackup(deviceProductID: "0x0000"), to: url)

    model.loadEditableBackup(url)

    XCTAssertTrue(model.status.hasSuffix("Review it, then choose Save to mouse."))
  }

  func testLoadEditableBackupSuccessEmptyDeviceProductIDHasNoWarning() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(makeBaseBackup(deviceProductID: ""), to: url)

    model.loadEditableBackup(url)

    XCTAssertTrue(model.status.hasSuffix("Review it, then choose Save to mouse."))
  }

  func testLoadEditableBackupSuccessAppliesRGBZonesForCapableDevice() throws {
    let model = AppModel(startInitialRefresh: false)
    configureRGBFixtureDevice(model)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        deviceProductID: "0xC08B",
        rgb: [
          EditableBackup.Profile.RGB(zone: 0, name: "Primary", color: "0xFF0000"),
          EditableBackup.Profile.RGB(zone: 1, name: "Logo", color: "0x00FF00"),
        ]),
      to: url)

    model.loadEditableBackup(url)

    XCTAssertTrue(model.status.contains("Loaded"))
    let primary = model.rgbZones.first(where: { $0.id == 0 })
    let logo = model.rgbZones.first(where: { $0.id == 1 })
    XCTAssertEqual(primary?.draft, RGBColor(hex: "0xFF0000"))
    XCTAssertEqual(logo?.draft, RGBColor(hex: "0x00FF00"))
  }

  func testLoadEditableBackupSuccessOnAlternateLayerUpdatesGShiftRows() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.gShiftButtonRows = [
      ButtonRow(
        id: 1, label: "G1 G-Shift", currentRaw: "80010004", draftRaw: "80010004",
        draftChoice: "80010004", layer: .gShift)
    ]
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        buttons: [
          EditableBackup.Button(
            number: 1, physicalControl: "G1", output: "Right click", raw: "80010002",
            layer: ButtonLayer.gShift.rawValue)
        ]),
      to: url)

    model.loadEditableBackup(url)

    XCTAssertEqual(model.gShiftButtonRows[0].draftRaw, "80010002")
    // The active (normal) layer's rows are untouched (fixture default).
    XCTAssertEqual(model.buttons[0].draftRaw, "80010002")
  }

  func testLoadEditableBackupSuccessOnNormalLayerWhileGShiftIsActiveUpdatesNormalRows() throws {
    // The inverse of the test above: the imported button is on the Normal
    // layer, but the editor's *active* layer is G-Shift, so
    // loadEditableBackup must fall back to `normalButtonRows` rather than
    // the active `buttons` array.
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.gShiftButtonRows = [
      ButtonRow(
        id: 1, label: "G1 G-Shift", currentRaw: "80010004", draftRaw: "80010004",
        draftChoice: "80010004", layer: .gShift)
    ]
    model.selectButtonLayer(.gShift)
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        buttons: [
          EditableBackup.Button(
            number: 1, physicalControl: "G1", output: "Right click", raw: "80010002",
            layer: ButtonLayer.normal.rawValue)
        ]),
      to: url)

    model.loadEditableBackup(url)

    XCTAssertEqual(model.normalButtonRows[0].draftRaw, "80010002")
    // The active (G-Shift) layer's rows are untouched.
    XCTAssertEqual(model.buttons[0].draftRaw, "80010004")
  }

  func testLoadEditableBackupJSONRawFallbackAcceptsAltTabAliasesAndCustomRaw() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.buttons = [
      ButtonRow(
        id: 1, label: "G1", currentRaw: "80010001", draftRaw: "80010001",
        draftChoice: "80010001", layer: .normal),
      ButtonRow(
        id: 2, label: "G2", currentRaw: "80010002", draftRaw: "80010002",
        draftChoice: "80010002", layer: .normal),
      ButtonRow(
        id: 3, label: "G3", currentRaw: "80010004", draftRaw: "80010004",
        draftChoice: "80010004", layer: .normal),
    ]
    let url = makeTempJSONURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try write(
      makeBaseBackup(
        buttons: [
          EditableBackup.Button(
            number: 1, physicalControl: "G1", output: "Alt+Tab", raw: "FFFFFFFF",
            layer: ButtonLayer.normal.rawValue),
          EditableBackup.Button(
            number: 2, physicalControl: "G2", output: "Left Alt+Tab", raw: "FFFFFFFF",
            layer: ButtonLayer.normal.rawValue),
          EditableBackup.Button(
            number: 3, physicalControl: "G3", output: "Custom", raw: "12 34 56 78",
            layer: ButtonLayer.normal.rawValue),
        ]),
      to: url)

    model.loadEditableBackup(url)

    XCTAssertEqual(model.buttons[0].draftRaw, "8002042B")
    XCTAssertEqual(model.buttons[1].draftRaw, "8002042B")
    XCTAssertEqual(model.buttons[2].draftRaw, "12345678")
  }
}
