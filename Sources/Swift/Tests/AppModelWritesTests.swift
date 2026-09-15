// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

/// Rejected-write tests assert the CLI process boundary is never touched.
/// Sharing one recorder keeps that necessarily-unreached body in a single
/// place instead of duplicating (and permanently under-covering) it once per
/// rejected-write test.
@MainActor
private final class RecordingEngine {
  private(set) var calls: [[String]] = []

  func run(_ arguments: [String]) throws -> String {
    calls.append(arguments)
    return ""
  }
}

/// `G300` is cataloged read-only (see Profiles/g300.json): its legacy
/// mode-switch layout has no writer yet. Using a real cataloged device
/// exercises the same `currentMouseProfile.profileIO.canSave` path
/// production code takes, without needing a synthetic descriptor.
@MainActor
private func configureReadOnlyFixtureDevice(_ model: AppModel) {
  model.devices = [
    DeviceChoice(
      id: 1,
      name: "G300",
      connection: "Wired",
      productID: "0xC246",
      deviceKey: "test-g300"
    )
  ]
  model.selectedDeviceIndex = 1
  model.currentDeviceName = "G300"
  model.profileNumber = 1
  model.profiles = [
    ProfileChoice(id: 1, sector: "0x0100", enabled: true, crcValid: true)
  ]
  model.baselineProfileEnabled = [1: true]
  model.buttons = [
    ButtonRow(
      id: 1,
      label: "Button 1",
      currentRaw: "80010002",
      draftRaw: "80010002",
      draftChoice: "80010002",
      layer: .normal
    )
  ]
}

/// A minimal writable descriptor used to exercise `canEditOnboardDPI`/
/// `canEditProfileState` combinations no bundled catalog profile happens to
/// have (a device that can save but has one specific field disabled).
/// Writing it into a throwaway custom-profiles directory and reloading the
/// shared catalog is the same mechanism `saveProfileEditorDraft()` uses in
/// production, so it is a faithful way to test these branches rather than a
/// shortcut around them.
private func makeStandardDescriptor(
  id: String,
  nameContains: [String],
  saveOverrides: [String: String] = [:]
) -> MouseProfileDescriptor {
  var save: [String: String] = ["strategy": "standard-hidpp20-sector-write"]
  for (key, value) in saveOverrides { save[key] = value }
  return MouseProfileDescriptor(
    schemaVersion: 1,
    id: id,
    name: id,
    match: .init(nameContains: nameContains, productIDs: []),
    buttons: [.init(number: 1, control: "Primary click", aliases: [], notes: nil)],
    scrollWheelButtonLabels: nil,
    hiddenProfileButtonNumbers: nil,
    dpiRange: nil,
    refreshGuidance: nil,
    profileIO: .init(
      supported: true,
      capability: "test",
      feature: "0x8100",
      load: [:],
      save: save,
      layout: [:],
      notes: []
    ),
    rgbProfile: nil,
    sources: [],
    generated: nil
  )
}

@MainActor
private func installCustomProfile(_ descriptor: MouseProfileDescriptor, on model: AppModel) throws {
  let tempDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("lope-writes-test-config-" + UUID().uuidString, isDirectory: true)
  model.configurationDirectory = tempDirectory
  let customDirectory = model.customProfilesDirectory
  try FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)
  let url = customDirectory.appendingPathComponent("\(descriptor.id).json")
  try JSONEncoder().encode(descriptor).write(to: url)
  MouseProfileCatalog.reload(customProfilesDirectory: customDirectory)
}

@MainActor
final class AppModelWritesTests: XCTestCase {
  func testImportedJSONPrimaryClickOutputIsResolved() throws {
    let importedModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(importedModel)
    let jsonURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lope-profile-write-test-" + String(ProcessInfo.processInfo.processIdentifier) + ".json"
    )
    defer { try? FileManager.default.removeItem(at: jsonURL) }

    let imported = EditableBackup(
      formatVersion: 1,
      createdAt: "2026-01-01T00:00:00Z",
      device: EditableBackup.Device(name: "G502 X", productID: "0x0000"),
      profiles: [EditableBackup.ProfileState(number: 2, enabled: true)],
      profile: EditableBackup.Profile(
        number: 2,
        sector: "0x0100",
        enabled: true,
        buttons: [
          EditableBackup.Button(
            number: 1,
            physicalControl: "G1 · Primary click",
            output: "Left click",
            raw: "FFFFFFFF",
            layer: ButtonLayer.normal.rawValue
          )
        ],
        dpi: nil
      ),
      exactBinaryBackup: nil
    )
    let data = try JSONEncoder().encode(imported)
    try data.write(to: jsonURL, options: .atomic)

    importedModel.loadEditableBackup(jsonURL)
    XCTAssertEqual(importedModel.buttons[0].draftRaw, ProfileWriteValidation.primaryClickRaw)
  }

  func testButtonOnlySaveRejectsBeforeInvokingWriteEngine() {
    let rejectedButtonsModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(rejectedButtonsModel)
    let recorder = RecordingEngine()
    rejectedButtonsModel.engineRunnerOverride = recorder.run
    rejectedButtonsModel.buttons[0].draftRaw = "FFFFFFFF"
    rejectedButtonsModel.applyButtons()
    XCTAssertTrue(recorder.calls.isEmpty)
    XCTAssertTrue(rejectedButtonsModel.status.contains("Profile 2"))
    XCTAssertTrue(rejectedButtonsModel.status.contains("Left click"))
  }

  func testApplyButtonsRejectsWhileBusy() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.buttons[0].draftRaw = ProfileWriteValidation.primaryClickRaw
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run
    model.busy = true

    model.applyButtons()

    XCTAssertTrue(recorder.calls.isEmpty)
  }

  func testApplyButtonsRejectsWhenNoButtonChanges() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run
    model.applyButtons()
    XCTAssertTrue(recorder.calls.isEmpty)
    XCTAssertEqual(model.status, "No button changes to apply.")
  }

  func testApplyButtonsRejectsWhenProfileIsReadOnly() {
    let model = AppModel(startInitialRefresh: false)
    configureReadOnlyFixtureDevice(model)
    model.buttons[0].draftRaw = ProfileWriteValidation.primaryClickRaw
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run
    model.applyButtons()
    XCTAssertTrue(recorder.calls.isEmpty)
    XCTAssertTrue(model.status.contains("is cataloged as read-only for onboard profile writes."))
  }

  func testDPIOnlySaveRejectsBeforeInvokingWriteEngine() {
    let rejectedDPIModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(rejectedDPIModel)
    rejectedDPIModel.dpiCount = 1
    rejectedDPIModel.dpiStages = ["800", "", "", "", ""]
    rejectedDPIModel.baselineDPICount = 5
    rejectedDPIModel.baselineDPIStages = ["", "", "", "", ""]
    let recorder = RecordingEngine()
    rejectedDPIModel.engineRunnerOverride = recorder.run
    rejectedDPIModel.applyDPI()
    XCTAssertTrue(recorder.calls.isEmpty)
  }

  func testApplyDPIRejectsWhileBusy() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run
    model.busy = true

    model.applyDPI()

    XCTAssertTrue(recorder.calls.isEmpty)
  }

  func testApplyDPIRejectsWhenProfileIsReadOnly() {
    let model = AppModel(startInitialRefresh: false)
    configureReadOnlyFixtureDevice(model)
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run
    model.applyDPI()
    XCTAssertTrue(recorder.calls.isEmpty)
    XCTAssertTrue(model.status.contains("is cataloged as read-only for onboard profile writes."))
  }

  func testApplyDPIRejectsWhenOnboardDPIUnsupported() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let descriptor = makeStandardDescriptor(
      id: "test-dpi-unsupported-mouse",
      nameContains: ["Test DPI Unsupported Mouse"],
      saveOverrides: ["dpi": "unsupported"]
    )
    try installCustomProfile(descriptor, on: model)
    model.currentDeviceName = "Test DPI Unsupported Mouse"
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run
    model.applyDPI()
    XCTAssertTrue(recorder.calls.isEmpty)
    XCTAssertEqual(model.status, "Onboard DPI editing is unavailable for this legacy profile path.")
  }

  func testApplyDPIRejectsWhenPrimaryClickValidationFails() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    // Scroll-down instead of the fixture's usual primary-click raw, so
    // validatePrimaryClickBeforeWrite() fails and applyDPI() must bail out
    // before ever invoking the engine.
    model.buttons[0].draftRaw = "90100000"
    model.dpiCapabilities = DPICapabilities(
      supportedValues: [400, 800, 1200], minimum: 400, maximum: 1200)
    model.dpiCount = 1
    model.dpiStages = ["800", "", "", "", ""]
    model.defaultStage = 1
    model.shiftStage = 1
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run

    model.applyDPI()

    XCTAssertTrue(recorder.calls.isEmpty)
    XCTAssertTrue(model.status.contains("has no primary click assigned"))
  }

  func testApplyDPISucceedsWithValidStagesInvokesWriteEngine() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.buttons[0].draftRaw = ProfileWriteValidation.primaryClickRaw
    model.dpiCapabilities = DPICapabilities(
      supportedValues: [400, 800, 1200, 1600, 2400, 3200, 4000],
      minimum: 400,
      maximum: 4000
    )
    model.dpiCount = 3
    model.dpiStages = ["400", "1200", "2400", "", ""]
    model.defaultStage = 2
    model.shiftStage = 1
    var calls = [[String]]()
    model.engineRunnerOverride = { arguments in
      calls.append(arguments)
      return "Verified sector 0x0100"
    }
    model.applyDPI()
    guard let applyCall = calls.first(where: { $0.contains("apply") }) else {
      XCTFail("apply was never invoked")
      return
    }
    XCTAssertTrue(applyCall.contains("--dpi"))
    XCTAssertTrue(applyCall.contains("400,1200,2400"))
    XCTAssertTrue(applyCall.contains("--default"))
    XCTAssertTrue(applyCall.contains("2"))
    XCTAssertTrue(model.status.contains("Save operation"))
  }

  func testCombinedSaveRejectsBeforeInvokingWriteEngine() {
    let rejectedCombinedModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(rejectedCombinedModel)
    rejectedCombinedModel.buttons[0].draftRaw = "FFFFFFFF"
    rejectedCombinedModel.profiles[0].enabled = false
    rejectedCombinedModel.baselineProfileEnabled = [2: true]
    let recorder = RecordingEngine()
    rejectedCombinedModel.engineRunnerOverride = recorder.run
    rejectedCombinedModel.applyAll()
    XCTAssertTrue(recorder.calls.isEmpty)
  }

  func testApplyAllRejectsWhenProfileIsReadOnly() {
    let model = AppModel(startInitialRefresh: false)
    configureReadOnlyFixtureDevice(model)
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run
    model.applyAll()
    XCTAssertTrue(recorder.calls.isEmpty)
    XCTAssertTrue(model.status.contains("is cataloged as read-only for onboard profile writes."))
  }

  func testApplyAllRejectsWhenOnboardDPIUnsupportedButChanged() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let descriptor = makeStandardDescriptor(
      id: "test-dpi-unsupported-mouse",
      nameContains: ["Test DPI Unsupported Mouse"],
      saveOverrides: ["dpi": "unsupported"]
    )
    try installCustomProfile(descriptor, on: model)
    model.currentDeviceName = "Test DPI Unsupported Mouse"
    // dpiStages/baselineDPIStages mismatch by default, so a DPI change is
    // already staged without touching either array.
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run
    model.applyAll()
    XCTAssertTrue(recorder.calls.isEmpty)
    XCTAssertEqual(model.status, "Onboard DPI editing is unavailable for this legacy profile path.")
  }

  func testApplyAllRejectsWhenProfileStateUnsupportedButChanged() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let descriptor = makeStandardDescriptor(
      id: "test-profilestate-unsupported-mouse",
      nameContains: ["Test ProfileState Unsupported Mouse"],
      saveOverrides: ["profileState": "unsupported"]
    )
    try installCustomProfile(descriptor, on: model)
    model.currentDeviceName = "Test ProfileState Unsupported Mouse"
    // Align the DPI baseline so only the profile-state change is in play.
    model.baselineDPIStages = model.dpiStages
    model.baselineDPICount = model.dpiCount
    model.baselineDefaultStage = model.defaultStage
    model.baselineShiftStage = model.shiftStage
    model.profiles[0].enabled = false
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run
    model.applyAll()
    XCTAssertTrue(recorder.calls.isEmpty)
    XCTAssertEqual(
      model.status, "Profile enable-state editing is unavailable for this legacy profile path.")
  }

  func testApplyAllRejectsWhenNoChanges() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.baselineDPIStages = model.dpiStages
    model.baselineDPICount = model.dpiCount
    model.baselineDefaultStage = model.defaultStage
    model.baselineShiftStage = model.shiftStage
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run
    model.applyAll()
    XCTAssertTrue(recorder.calls.isEmpty)
    XCTAssertEqual(model.status, "No changes to apply.")
  }

  func testApplyAllRejectsWhileBusy() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.buttons[0].draftRaw = ProfileWriteValidation.primaryClickRaw
    model.busy = true
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run

    model.applyAll()

    XCTAssertTrue(recorder.calls.isEmpty)
  }

  func testApplyAllRejectsWhenPrimaryClickValidationFails() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.baselineDPIStages = model.dpiStages
    model.baselineDPICount = model.dpiCount
    model.baselineDefaultStage = model.defaultStage
    model.baselineShiftStage = model.shiftStage
    // A button change (so applyAll has something to apply) that is not a
    // primary click, so validatePrimaryClickBeforeWrite() fails.
    model.buttons[0].draftRaw = "90100000"
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run

    model.applyAll()

    XCTAssertTrue(recorder.calls.isEmpty)
    XCTAssertTrue(model.status.contains("has no primary click assigned"))
  }

  func testApplyAllWithMultipleProfileStateChangesSortsAndOmitsPollingRateWhenUnchanged() {
    // Covers three related gaps in applyAll(): the profileChanges
    // `.filter`'s `?? $0.enabled` fallback (profile 4 has no
    // baselineProfileEnabled entry at all), the `.sorted` comparator
    // actually running (needs >= 2 changed profiles), and the
    // `pollingRateChanged ? pollingRateDraft : nil` false branch (no
    // polling rate change is staged here, unlike the "every change type"
    // test above).
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.buttons[0].draftRaw = ProfileWriteValidation.primaryClickRaw
    model.baselineDPIStages = model.dpiStages
    model.baselineDPICount = model.dpiCount
    model.baselineDefaultStage = model.defaultStage
    model.baselineShiftStage = model.shiftStage
    model.profiles = [
      ProfileChoice(id: 2, sector: "0x0100", enabled: false, crcValid: true),
      ProfileChoice(id: 3, sector: "0x0110", enabled: true, crcValid: true),
      ProfileChoice(id: 4, sector: "0x0120", enabled: true, crcValid: true),
    ]
    model.baselineProfileEnabled = [2: true, 3: false]
    var calls = [[String]]()
    model.engineRunnerOverride = { arguments in
      calls.append(arguments)
      return "Verified sector 0x0100\nVerified sector 0x0110\nVerified sector 0x0120\n"
    }

    model.applyAll()

    guard let applyCall = calls.first(where: { $0.contains("apply") }) else {
      return XCTFail("apply was never invoked")
    }
    XCTAssertTrue(applyCall.contains("2:disable"))
    XCTAssertTrue(applyCall.contains("3:enable"))
    XCTAssertFalse(applyCall.contains { $0.hasPrefix("4:") })
    XCTAssertFalse(applyCall.contains("--report-rate"))
  }

  func testApplyAllRejectsWhenDPIStagesInvalidBeforeSaving() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let recorder = RecordingEngine()
    model.engineRunnerOverride = recorder.run
    model.applyAll()
    XCTAssertTrue(recorder.calls.isEmpty)
    XCTAssertEqual(model.status, "Enter one to five numeric DPI stages before saving.")
  }

  func testApplyAllWithEveryChangeTypeInvokesWriteEngineWithFullArguments() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.buttons[0].draftRaw = ProfileWriteValidation.primaryClickRaw
    model.dpiCapabilities = DPICapabilities(
      supportedValues: [400, 800, 1200, 1600, 2400, 3200, 4000],
      minimum: 400,
      maximum: 4000
    )
    model.dpiCount = 3
    model.dpiStages = ["400", "1200", "2400", "", ""]
    model.defaultStage = 2
    model.shiftStage = 1
    model.pollingRateDraft = 500
    model.baselinePollingRate = 125
    model.rgbZones = [
      RGBZoneState(
        id: 0, name: "Zone 1",
        current: RGBColor(red: 255, green: 0, blue: 0),
        draft: RGBColor(red: 0, green: 255, blue: 0)
      )
    ]
    model.profiles[0].enabled = false
    var calls = [[String]]()
    model.engineRunnerOverride = { arguments in
      calls.append(arguments)
      return "Verified sector 0x0100\nVerified sector 0x0110\nLive default DPI: 800\n"
    }
    model.applyAll()
    guard let applyCall = calls.first(where: { $0.contains("apply") }) else {
      XCTFail("apply was never invoked")
      return
    }
    XCTAssertTrue(applyCall.contains("--dpi"))
    XCTAssertTrue(applyCall.contains("--report-rate"))
    XCTAssertTrue(applyCall.contains("500"))
    XCTAssertTrue(applyCall.contains("--rgb-change"))
    XCTAssertTrue(applyCall.contains("1:00FF00"))
    XCTAssertTrue(applyCall.contains("--profile-state-change"))
    XCTAssertTrue(applyCall.contains("2:disable"))
    XCTAssertTrue(applyCall.contains("--button-change"))
    XCTAssertTrue(applyCall.contains("normal:1:80010001"))
    XCTAssertTrue(model.status.contains("Save operation"))
    XCTAssertTrue(model.status.contains("RGB colors were read back from the profile summary."))
    XCTAssertTrue(model.status.contains("Live default DPI: 800"))
  }

  func testApplyAllWithOnlyRGBModeChangeInvokesWriteEngineWithModeArgument() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.buttons[0].draftRaw = ProfileWriteValidation.primaryClickRaw
    model.baselineDPIStages = model.dpiStages
    model.baselineDPICount = model.dpiCount
    model.rgbZones = [
      RGBZoneState(
        id: 0, name: "Zone 1",
        current: RGBColor(red: 255, green: 0, blue: 0),
        draft: RGBColor(red: 255, green: 0, blue: 0),
        currentMode: .solid,
        draftMode: .cycle
      )
    ]
    var calls = [[String]]()
    model.engineRunnerOverride = { arguments in
      calls.append(arguments)
      return "Verified sector 0x0100\n"
    }
    model.applyAll()
    guard let applyCall = calls.first(where: { $0.contains("apply") }) else {
      XCTFail("apply was never invoked")
      return
    }
    XCTAssertTrue(applyCall.contains("--rgb-mode-change"))
    XCTAssertTrue(applyCall.contains("1:03"))
    XCTAssertFalse(applyCall.contains("--rgb-change"))
    XCTAssertTrue(model.status.contains("RGB colors were read back from the profile summary."))
  }

  func testValidPrimaryClickAssignmentInvokesWriteEngine() {
    let validModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(validModel)
    validModel.buttons[0].draftRaw = ProfileWriteValidation.primaryClickRaw
    var validCalls = [[String]]()
    validModel.engineRunnerOverride = { arguments in
      validCalls.append(arguments)
      return "Verified sector 0x0100"
    }
    validModel.applyButtons()
    XCTAssertTrue(validCalls.contains(where: { $0.contains("apply") }))
  }

  func testPrimaryClickValidationFallsBackToCurrentDeviceNameWhenSelectedDeviceIsMissing() {
    // Covers primaryClickValidationMessage's `: currentDeviceName` branch,
    // taken when the live `devices` list has no entry matching
    // `selectedDeviceIndex` (runtimeMouseName is nil) -- every other
    // validation test resolves a real device name from `devices`.
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.selectedDeviceIndex = 999
    model.buttons[0].draftRaw = "90100000"

    XCTAssertEqual(
      model.primaryClickValidationMessage,
      "Profile 2 on G502 X / X LIGHTSPEED / X PLUS has no primary click assigned. Choose "
        + "\u{201C}Left click\u{201D} for one of its buttons, then save again."
    )
  }

  func testPrimaryClickValidationWarnsWhenPrimaryClickOnlyOnInaccessibleGShiftLayer() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.gShiftButtonRows = [
      ButtonRow(
        id: 2,
        label: "G2",
        currentRaw: "80010001",
        draftRaw: "80010001",
        draftChoice: "80010001",
        layer: .gShift
      )
    ]
    XCTAssertEqual(
      model.primaryClickValidationMessage,
      "Profile 2 on G502 X has primary click assigned only on the G-Shift layer, but no "
        + "Normal-layer button activates G-Shift. Assign G-Shift to a Normal button or add a "
        + "primary click to the Normal layer, then save again."
    )
  }

  func testFailedSaveWithBackupsPopulatesRecoveryStateAndFilteredSummary() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.buttons[0].draftRaw = ProfileWriteValidation.primaryClickRaw
    let backupPath = "/tmp/lope-test-backups/g502-x-profile-2-save-1.logiob"
    let failureMessage = """
      Save operation profile-2-save-1 failed.
      Preflight checks passed.
      Planned 2 sector write(s).
      Backup saved: \(backupPath) (sha256 abcd1234)
      Backup saved: \(backupPath) (sha256 abcd1234)
      Writing sector 0x0100...
      Verified sector 0x0100
      Sector 0x0110 was not verified after write.
      Save operation stopped before any sector write completed for the remaining profile(s).
      Unrelated diagnostic noise that should be filtered out.
      """
    model.engineRunnerOverride = { _ in
      throw EngineError.failed(failureMessage)
    }
    model.applyButtons()
    XCTAssertEqual(model.recoveryBackups, [URL(fileURLWithPath: backupPath)])
    XCTAssertEqual(model.recoveryDeviceKey, "test-device")
    XCTAssertTrue(model.status.contains("Save operation profile-2-save-1 failed."))
    XCTAssertTrue(model.status.contains("Verified sector 0x0100"))
    XCTAssertTrue(
      model.status.contains(
        "Use \u{2018}Restore backups from this save\u{2019} to recover the pre-save sectors."))
    XCTAssertFalse(model.status.contains("Unrelated diagnostic noise"))
  }

  func testFailedSaveSkipsBackupSavedLineWithNoPath() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.buttons[0].draftRaw = ProfileWriteValidation.primaryClickRaw
    let backupPath = "/tmp/lope-test-backups/g502-x-profile-2-save-1.logiob"
    let failureMessage = """
      Save operation profile-2-save-1 failed.
      Backup saved:
      Backup saved: \(backupPath) (sha256 abcd1234)
      Save operation stopped before any sector write completed for the remaining profile(s).
      """
    model.engineRunnerOverride = { _ in
      throw EngineError.failed(failureMessage)
    }

    model.applyButtons()

    XCTAssertEqual(model.recoveryBackups, [URL(fileURLWithPath: backupPath)])
  }

  func testFailedSaveWithoutBackupsFallsBackToRawErrorDetails() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.buttons[0].draftRaw = ProfileWriteValidation.primaryClickRaw
    model.engineRunnerOverride = { _ in
      throw EngineError.failed("The mouse disconnected mid-write.")
    }
    model.applyButtons()
    XCTAssertTrue(model.recoveryBackups.isEmpty)
    XCTAssertNil(model.recoveryDeviceKey)
    XCTAssertEqual(model.status, "The mouse disconnected mid-write.")
  }

  func testApplyPollingRateRejectsWhileBusy() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.pollingRateCapabilities = PollingRateCapabilities(
      supportedRates: [125, 500], currentRate: 125)
    model.busy = true

    model.applyPollingRate(500)

    XCTAssertNil(model.pollingRateDraft)
  }

  func testSupportedPollingRateChangeIsStagedForProfileSave() {
    let pollingModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(pollingModel)
    pollingModel.pollingRateCapabilities = PollingRateCapabilities(
      supportedRates: [125, 500],
      currentRate: 125
    )
    let recorder = RecordingEngine()
    pollingModel.engineRunnerOverride = recorder.run
    pollingModel.applyPollingRate(500)
    XCTAssertTrue(recorder.calls.isEmpty)
    XCTAssertEqual(pollingModel.pollingRateDraft, 500)
    XCTAssertTrue(pollingModel.hasPollingRateChanges)
    XCTAssertTrue(pollingModel.hasPendingChanges)

    pollingModel.applyPollingRate(1000)
    XCTAssertTrue(
      recorder.calls.isEmpty, "unsupported polling rate was forwarded to the write engine")
    XCTAssertEqual(pollingModel.pollingRateDraft, 500)
  }
}
