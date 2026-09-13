// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

/// Points `configurationDirectory` (and therefore `customProfilesDirectory`)
/// at a throwaway temp directory, so profile-editor save tests never touch
/// the real Application Support folder.
@MainActor
private func useTemporaryConfigurationDirectory(on model: AppModel) -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lope-profile-editor-test-" + UUID().uuidString, isDirectory: true)
  model.configurationDirectory = directory
  return directory
}

@MainActor
final class AppModelProfileEditorTests: XCTestCase {
  func testResetProfileEditorDraftSynthesizesDescriptorForUnknownDeviceWithScrollWheelGuess() {
    let model = AppModel(startInitialRefresh: false)
    model.devices = [
      DeviceChoice(
        id: 1, name: "Totally Unknown Mouse", connection: "Wired", productID: "0xFFFF",
        deviceKey: "unknown-test")
    ]
    model.selectedDeviceIndex = 1
    model.currentDeviceName = "Totally Unknown Mouse"
    XCTAssertFalse(model.hasSpecificMouseProfile)

    let normalRows = [
      ButtonRow(
        id: 1, label: "Button 1", currentRaw: "90100000", draftRaw: "90100000",
        draftChoice: "90100000", layer: .normal),
      ButtonRow(
        id: 2, label: "Button 2", currentRaw: "80010002", draftRaw: "80010002",
        draftChoice: "80010002", layer: .normal),
    ]
    model.setButtonRows(normal: normalRows, gShift: [])

    XCTAssertEqual(model.profileEditorID, "Totally-Unknown-Mouse")
    XCTAssertEqual(model.profileEditorName, "Totally Unknown Mouse")
    XCTAssertEqual(model.profileEditorButtonNames[1], "Button 1")
    XCTAssertEqual(model.profileEditorButtonNames[2], "Button 2")
    XCTAssertEqual(model.profileEditorBase?.scrollWheelButtonLabels?["1"], "Scroll down")
    XCTAssertNil(model.profileEditorBase?.scrollWheelButtonLabels?["2"])
    XCTAssertTrue(model.profileEditorBase?.profileIO.canSave ?? false)
  }

  func testResetProfileEditorDraftFallsBackToButtonNumberWhenCatalogHasNoControlName() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    XCTAssertTrue(model.hasSpecificMouseProfile)

    // Button 99 is not part of G502 X's cataloged buttons or scroll-wheel
    // labels, so the editor must fall back to a generic "Button 99" name.
    let normalRows =
      model.buttons + [
        ButtonRow(
          id: 99, label: "Button 99", currentRaw: "FFFFFFFF", draftRaw: "FFFFFFFF",
          draftChoice: "FFFFFFFF", layer: .normal)
      ]
    model.setButtonRows(normal: normalRows, gShift: [])

    XCTAssertEqual(model.profileEditorButtonNames[99], "Button 99")
  }

  func testSaveProfileEditorDraftFallsBackToBaseDPIRangeWhenCapabilitiesUnknown() throws {
    let model = AppModel(startInitialRefresh: false)
    let directory = useTemporaryConfigurationDirectory(on: model)
    defer { try? FileManager.default.removeItem(at: directory) }
    configureFixtureDevice(model)
    model.setButtonRows(normal: model.buttons, gShift: [])
    // Leave a blank control name for button 1 to exercise the
    // "fall back to the existing catalog control" branch.
    model.profileEditorButtonNames[1] = "   "

    let url = model.saveProfileEditorDraft()
    XCTAssertNotNil(url)
    // saveProfileEditorDraft() ends by calling refresh(), which
    // synchronously overwrites `status` once more (there is no bundled
    // engine in this test environment), so the "Saved ..." status text set
    // just before that is not observable here. The file write and catalog
    // reload it performs first are the durable, checkable effects.

    guard let url else { return }
    let data = try Data(contentsOf: url)
    let saved = try JSONDecoder().decode(MouseProfileDescriptor.self, from: data)
    XCTAssertEqual(saved.id, "g502-x")
    XCTAssertEqual(saved.match.nameContains, ["G502 X / X LIGHTSPEED / X PLUS"])
    XCTAssertEqual(saved.match.productIDs, ["0x0000"])
    // No reported DPI capability minimum/maximum -> falls back to the
    // catalog's own dpiRange rather than losing it.
    XCTAssertEqual(saved.dpiRange?.minimum, 100)
    XCTAssertEqual(saved.dpiRange?.maximum, 25600)
    XCTAssertEqual(saved.button(for: 1)?.control, "G1 · Primary click")
    XCTAssertGreaterThan(MouseProfileCatalog.shared.customProfileCount, 0)
  }

  func testSaveProfileEditorDraftWritesReportedDPIRangeAndCustomButtonName() throws {
    let model = AppModel(startInitialRefresh: false)
    let directory = useTemporaryConfigurationDirectory(on: model)
    defer { try? FileManager.default.removeItem(at: directory) }
    configureFixtureDevice(model)
    model.setButtonRows(normal: model.buttons, gShift: [])
    model.dpiCapabilities = DPICapabilities(minimum: 200, maximum: 8000)
    model.profileEditorButtonNames[1] = "Custom primary click"

    let url = model.saveProfileEditorDraft()
    XCTAssertNotNil(url)
    guard let url else { return }
    let data = try Data(contentsOf: url)
    let saved = try JSONDecoder().decode(MouseProfileDescriptor.self, from: data)
    XCTAssertEqual(saved.dpiRange?.minimum, 200)
    XCTAssertEqual(saved.dpiRange?.maximum, 8000)
    XCTAssertEqual(saved.button(for: 1)?.control, "Custom primary click")
  }

  func testSaveProfileEditorDraftRejectsForMXSeriesMouse() {
    let model = AppModel(startInitialRefresh: false)
    let directory = useTemporaryConfigurationDirectory(on: model)
    defer { try? FileManager.default.removeItem(at: directory) }
    model.devices = [
      DeviceChoice(
        id: 1, name: "MX Master 3S", connection: "Bluetooth", productID: "0xB034",
        deviceKey: "mx-test")
    ]
    model.selectedDeviceIndex = 1
    model.currentDeviceName = "MX Master 3S"
    model.setButtonRows(
      normal: [
        ButtonRow(
          id: 1, label: "Button 1", currentRaw: "80010001", draftRaw: "80010001",
          draftChoice: "80010001", layer: .normal)
      ], gShift: [])

    let url = model.saveProfileEditorDraft()
    XCTAssertNil(url)
    XCTAssertEqual(
      model.status,
      "LOPE does not save profiles for MX-series mice; their controls are managed by "
        + "Logi Options+, not onboard memory.")
  }

  func testSaveProfileEditorDraftRejectsWhenProfileIDIsEmpty() {
    let model = AppModel(startInitialRefresh: false)
    let directory = useTemporaryConfigurationDirectory(on: model)
    defer { try? FileManager.default.removeItem(at: directory) }
    configureFixtureDevice(model)
    model.setButtonRows(normal: model.buttons, gShift: [])
    model.profileEditorID = "   "

    let url = model.saveProfileEditorDraft()
    XCTAssertNil(url)
    XCTAssertEqual(model.status, "Enter a profile ID before saving.")
  }

  func testExportProfileEditorDraftRejectsWhenProfileIDIsEmpty() {
    // This exercises only the pre-panel guard in exportProfileEditorDraft():
    // buildProfileEditorDescriptor() returning nil short-circuits before an
    // NSSavePanel is ever created, so this is safe to run headlessly. The
    // rest of the function (and all of importProfileEditorDraft()) is
    // wrapped around `panel.runModal()`, which would show a real modal
    // dialog and block indefinitely with no user present to dismiss it, so
    // it is intentionally left untested here -- matching the same,
    // pre-existing pattern for every other NSOpenPanel/NSSavePanel-based
    // AppModel extension in this codebase (AppModel+JSONEditableBackups.swift,
    // AppModel+GeneratedProfilesPreferences.swift,
    // AppModel+BackupRecovery.swift), none of which mock or test the panel
    // interaction either.
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setButtonRows(normal: model.buttons, gShift: [])
    model.profileEditorID = "   "

    model.exportProfileEditorDraft()

    XCTAssertEqual(model.status, "Enter a profile ID before exporting.")
  }

  func testWriteProfileEditorExportWritesEncodedDescriptorAndReportsSuccess() throws {
    // Covers the logic exportProfileEditorDraft() (Shims/) delegates to
    // once NSSavePanel returns a URL -- exercised here directly with a
    // plain temp URL, no panel involved.
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setButtonRows(normal: model.buttons, gShift: [])
    let descriptor = try XCTUnwrap(model.buildProfileEditorDescriptor())
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("lope-export-test-" + UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: url) }

    let succeeded = model.writeProfileEditorExport(descriptor, to: url)

    XCTAssertTrue(succeeded)
    XCTAssertEqual(model.status, "Exported \(url.lastPathComponent).")
    let data = try Data(contentsOf: url)
    let decoded = try JSONDecoder().decode(MouseProfileDescriptor.self, from: data)
    XCTAssertEqual(decoded.id, descriptor.id)
  }

  func testWriteProfileEditorExportReportsFailureWhenURLIsUnwritable() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setButtonRows(normal: model.buttons, gShift: [])
    guard let descriptor = model.buildProfileEditorDescriptor() else {
      return XCTFail("expected a descriptor")
    }
    // A directory that does not exist, so the write cannot succeed.
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("lope-export-missing-dir-" + UUID().uuidString, isDirectory: true)
      .appendingPathComponent("export.json")

    let succeeded = model.writeProfileEditorExport(descriptor, to: url)

    XCTAssertFalse(succeeded)
    XCTAssertEqual(model.status, "Could not export the profile to \(url.path).")
  }

  func testApplyImportedProfileEditorDraftPopulatesStateFromDescriptor() {
    // Covers the logic importProfileEditorDraft() (Shims/) delegates to
    // once NSOpenPanel returns a URL and the file decodes -- exercised
    // here directly with a plain descriptor/URL, no panel involved.
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.setButtonRows(
      normal: model.buttons
        + [
          ButtonRow(
            id: 2, label: "Button 2", currentRaw: "90100000", draftRaw: "90100000",
            draftChoice: "90100000", layer: .normal),
          ButtonRow(
            id: 3, label: "Button 3", currentRaw: "90100000", draftRaw: "90100000",
            draftChoice: "90100000", layer: .normal),
        ], gShift: [])
    model.profileEditorButtonNames[3] = "Existing name"

    let descriptor = MouseProfileDescriptor(
      schemaVersion: 1,
      id: "imported-profile",
      name: "Imported Profile",
      match: .init(nameContains: [], productIDs: []),
      buttons: [.init(number: 1, control: "Imported Button 1", aliases: [], notes: nil)],
      scrollWheelButtonLabels: ["2": "Imported scroll"],
      hiddenProfileButtonNumbers: nil,
      dpiRange: nil,
      refreshGuidance: nil,
      profileIO: MouseProfileCatalog.genericProfile.profileIO,
      rgbProfile: nil,
      sources: ["https://example.com/imported"],
      generated: false
    )
    let url = URL(fileURLWithPath: "/tmp/imported-profile.json")

    model.applyImportedProfileEditorDraft(descriptor, from: url)

    XCTAssertEqual(model.profileEditorBase?.id, "imported-profile")
    XCTAssertEqual(model.profileEditorID, "imported-profile")
    XCTAssertEqual(model.profileEditorName, "Imported Profile")
    XCTAssertEqual(model.profileEditorSources, "https://example.com/imported")
    // Button 1: named directly by the imported descriptor.
    XCTAssertEqual(model.profileEditorButtonNames[1], "Imported Button 1")
    // Button 2: falls back to the imported scroll-wheel label.
    XCTAssertEqual(model.profileEditorButtonNames[2], "Imported scroll")
    // Button 3: not present in the import, so its prior name is kept.
    XCTAssertEqual(model.profileEditorButtonNames[3], "Existing name")
    XCTAssertEqual(model.status, "Loaded imported-profile.json as a template.")
  }

  func testSaveProfileEditorDraftReportsFailureWhenDirectoryCannotBeCreated() throws {
    let model = AppModel(startInitialRefresh: false)
    let directory = useTemporaryConfigurationDirectory(on: model)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // Block "Custom Profiles" with a plain file so it cannot be created (or
    // written into) as a directory.
    let blockedPath = directory.appendingPathComponent("Custom Profiles")
    try Data("blocked".utf8).write(to: blockedPath)

    configureFixtureDevice(model)
    model.setButtonRows(normal: model.buttons, gShift: [])

    let url = model.saveProfileEditorDraft()
    XCTAssertNil(url)
    XCTAssertTrue(model.status.hasPrefix("Could not write the profile to"))
  }
}
