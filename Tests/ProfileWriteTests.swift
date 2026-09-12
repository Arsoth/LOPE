// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class ProfileWriteTests: XCTestCase {
  func testPrimaryClickRawRecordRecognition() {
    XCTAssertTrue(ProfileWriteValidation.isPrimaryClick(raw: "80010001"))
    XCTAssertTrue(ProfileWriteValidation.isPrimaryClick(raw: "80 01 00 01"))
    XCTAssertTrue(ProfileWriteValidation.isPrimaryClick(raw: "80010001".lowercased()))
    XCTAssertFalse(ProfileWriteValidation.isPrimaryClick(raw: "FFFFFFFF"))
    XCTAssertFalse(ProfileWriteValidation.isPrimaryClick(raw: "80010002"))
  }

  func testMissingPrimaryClickMessageIsActionableAndProfileSpecific() {
    let invalidMessage = ProfileWriteValidation.missingPrimaryClickMessage(
      profileNumber: 2,
      profileName: "G502 X",
      buttonRaws: ["80010002", "FFFFFFFF"]
    )
    XCTAssertEqual(
      invalidMessage,
      "Profile 2 on G502 X has no primary click assigned. Choose “Left click” for one of its buttons, then save again."
    )
  }

  func testInaccessibleGShiftPrimaryClickWarningIsActionable() {
    let inaccessibleGShiftMessage = ProfileWriteValidation.inaccessibleGShiftPrimaryClickMessage(
      profileNumber: 2,
      profileName: "G502 X",
      normalButtonRaws: ["80010002", "FFFFFFFF"],
      gShiftButtonRaws: ["80010001"]
    )
    XCTAssertEqual(
      inaccessibleGShiftMessage,
      "Profile 2 on G502 X has primary click assigned only on the G-Shift layer, but no Normal-layer button activates G-Shift. Assign G-Shift to a Normal button or add a primary click to the Normal layer, then save again."
    )

    let boundGShiftMessage = ProfileWriteValidation.inaccessibleGShiftPrimaryClickMessage(
      profileNumber: 2,
      profileName: "G502 X",
      normalButtonRaws: ["900B0000"],
      gShiftButtonRaws: ["80010001"]
    )
    XCTAssertNil(boundGShiftMessage, "bound G-Shift button was incorrectly treated as inaccessible")
  }

  func testPrimaryClickValidationPrefersRuntimeMouseName() {
    let presetModel = AppModel(startInitialRefresh: false)
    Self.configure(presetModel)
    XCTAssertEqual(
      presetModel.primaryClickValidationMessage,
      "Profile 2 on G502 X has no primary click assigned. Choose “Left click” for one of its buttons, then save again."
    )

    guard let leftClick = presetModel.presets.first(where: { $0.label == "Left click" }) else {
      XCTFail("Left click preset is missing")
      return
    }
    presetModel.selectOutput(buttonIndex: 0, choice: leftClick.raw)
    XCTAssertEqual(presetModel.buttons[0].draftRaw, ProfileWriteValidation.primaryClickRaw)
  }

  func testRawPrimaryClickAssignmentIsNormalized() {
    let rawModel = AppModel(startInitialRefresh: false)
    Self.configure(rawModel)
    rawModel.setRaw(buttonIndex: 0, raw: "80 01 00 01")
    XCTAssertEqual(rawModel.buttons[0].draftRaw, ProfileWriteValidation.primaryClickRaw)
  }

  func testProvisionalMouseDataSuppressesDPIValidationWarning() {
    let provisionalModel = AppModel(startInitialRefresh: false)
    Self.configure(provisionalModel)
    XCTAssertNotNil(
      provisionalModel.dpiValidationMessage,
      "baseline DPI validation fixture unexpectedly became valid")

    provisionalModel.loadingProfile = true
    XCTAssertTrue(provisionalModel.isProvisionalMouseData)
    XCTAssertNil(provisionalModel.dpiValidationMessage)

    provisionalModel.loadingProfile = false
    provisionalModel.waitingForKnownDevice = true
    XCTAssertTrue(provisionalModel.isProvisionalMouseData)
    XCTAssertNil(provisionalModel.dpiValidationMessage)
  }

  func testImportedJSONPrimaryClickOutputIsResolved() throws {
    let importedModel = AppModel(startInitialRefresh: false)
    Self.configure(importedModel)
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

  func testContinuousDPIStageDragTracksSnappedValue() {
    let dpiDragModel = AppModel(startInitialRefresh: false)
    Self.configure(dpiDragModel)
    dpiDragModel.dpiCapabilities = DPICapabilities(
      supportedValues: [400, 800, 1200, 1600, 2400, 3200, 4000],
      minimum: 400,
      maximum: 4000
    )
    dpiDragModel.dpiCount = 3
    dpiDragModel.dpiStages = ["400", "1200", "2400", "", ""]
    dpiDragModel.defaultStage = 2
    dpiDragModel.shiftStage = 1

    let firstDragIndex = dpiDragModel.moveDPIStageDuringDrag(index: 1, value: 1600)
    XCTAssertEqual(firstDragIndex, 1)
    XCTAssertEqual(dpiDragModel.dpiStages.prefix(3).map({ Int($0) }), [400, 1600, 2400])
  }

  func testDPIStageCrossingPreservesOrderAndDefaultShiftAssignment() {
    let dpiDragModel = AppModel(startInitialRefresh: false)
    Self.configure(dpiDragModel)
    dpiDragModel.dpiCapabilities = DPICapabilities(
      supportedValues: [400, 800, 1200, 1600, 2400, 3200, 4000],
      minimum: 400,
      maximum: 4000
    )
    dpiDragModel.dpiCount = 3
    dpiDragModel.dpiStages = ["400", "1200", "2400", "", ""]
    dpiDragModel.defaultStage = 2
    dpiDragModel.shiftStage = 1

    let firstDragIndex = dpiDragModel.moveDPIStageDuringDrag(index: 1, value: 1600)
    let crossedForwardIndex = dpiDragModel.moveDPIStageDuringDrag(
      index: firstDragIndex, value: 3200)
    XCTAssertEqual(crossedForwardIndex, 2)
    XCTAssertEqual(dpiDragModel.dpiStages.prefix(3).map({ Int($0) }), [400, 2400, 3200])
    XCTAssertEqual(dpiDragModel.defaultStage, 3)
    XCTAssertEqual(dpiDragModel.shiftStage, 1)

    let crossedBackwardIndex = dpiDragModel.moveDPIStageDuringDrag(
      index: crossedForwardIndex, value: 800)
    XCTAssertEqual(crossedBackwardIndex, 1)
    XCTAssertEqual(dpiDragModel.dpiStages.prefix(3).map({ Int($0) }), [400, 800, 2400])
    XCTAssertEqual(dpiDragModel.defaultStage, 2)
  }

  func testDPIDragCompletionRepairsStrictStageOrdering() {
    let dpiDragModel = AppModel(startInitialRefresh: false)
    Self.configure(dpiDragModel)
    dpiDragModel.dpiCapabilities = DPICapabilities(
      supportedValues: [400, 800, 1200, 1600, 2400, 3200, 4000],
      minimum: 400,
      maximum: 4000
    )
    dpiDragModel.dpiCount = 3
    dpiDragModel.dpiStages = ["400", "800", "800", "", ""]
    dpiDragModel.finishDPIStageDrag()
    let finishedDPIValues = dpiDragModel.dpiStages.prefix(3).compactMap(Int.init)
    XCTAssertEqual(finishedDPIValues, [400, 800, 1200])
    XCTAssertTrue(zip(finishedDPIValues, finishedDPIValues.dropFirst()).allSatisfy({ $0 < $1 }))
  }

  func testButtonOnlySaveRejectsBeforeInvokingWriteEngine() {
    let rejectedButtonsModel = AppModel(startInitialRefresh: false)
    Self.configure(rejectedButtonsModel)
    var rejectedButtonCalls = [[String]]()
    rejectedButtonsModel.engineRunnerOverride = { arguments in
      rejectedButtonCalls.append(arguments)
      return ""
    }
    rejectedButtonsModel.buttons[0].draftRaw = "FFFFFFFF"
    rejectedButtonsModel.applyButtons()
    XCTAssertTrue(rejectedButtonCalls.isEmpty)
    XCTAssertTrue(rejectedButtonsModel.status.contains("Profile 2"))
    XCTAssertTrue(rejectedButtonsModel.status.contains("Left click"))
  }

  func testDPIOnlySaveRejectsBeforeInvokingWriteEngine() {
    let rejectedDPIModel = AppModel(startInitialRefresh: false)
    Self.configure(rejectedDPIModel)
    rejectedDPIModel.dpiCount = 1
    rejectedDPIModel.dpiStages = ["800", "", "", "", ""]
    rejectedDPIModel.baselineDPICount = 5
    rejectedDPIModel.baselineDPIStages = ["", "", "", "", ""]
    var rejectedDPICalls = [[String]]()
    rejectedDPIModel.engineRunnerOverride = { arguments in
      rejectedDPICalls.append(arguments)
      return ""
    }
    rejectedDPIModel.applyDPI()
    XCTAssertTrue(rejectedDPICalls.isEmpty)
  }

  func testCombinedSaveRejectsBeforeInvokingWriteEngine() {
    let rejectedCombinedModel = AppModel(startInitialRefresh: false)
    Self.configure(rejectedCombinedModel)
    rejectedCombinedModel.buttons[0].draftRaw = "FFFFFFFF"
    rejectedCombinedModel.profiles[0].enabled = false
    rejectedCombinedModel.baselineProfileEnabled = [2: true]
    var rejectedCombinedCalls = [[String]]()
    rejectedCombinedModel.engineRunnerOverride = { arguments in
      rejectedCombinedCalls.append(arguments)
      return ""
    }
    rejectedCombinedModel.applyAll()
    XCTAssertTrue(rejectedCombinedCalls.isEmpty)
  }

  func testValidPrimaryClickAssignmentInvokesWriteEngine() {
    let validModel = AppModel(startInitialRefresh: false)
    Self.configure(validModel)
    validModel.buttons[0].draftRaw = ProfileWriteValidation.primaryClickRaw
    var validCalls = [[String]]()
    validModel.engineRunnerOverride = { arguments in
      validCalls.append(arguments)
      return "Verified sector 0x0100"
    }
    validModel.applyButtons()
    XCTAssertTrue(validCalls.contains(where: { $0.contains("apply") }))
  }

  func testSupportedPollingRateChangeIsStagedForProfileSave() {
    let pollingModel = AppModel(startInitialRefresh: false)
    Self.configure(pollingModel)
    pollingModel.pollingRateCapabilities = PollingRateCapabilities(
      supportedRates: [125, 500],
      currentRate: 125
    )
    var pollingCalls = [[String]]()
    pollingModel.engineRunnerOverride = { arguments in
      pollingCalls.append(arguments)
      return "Supported polling rates: 125, 500\nVerified polling rate: 500 Hz\n"
    }
    pollingModel.applyPollingRate(500)
    XCTAssertTrue(pollingCalls.isEmpty)
    XCTAssertEqual(pollingModel.pollingRateDraft, 500)
    XCTAssertTrue(pollingModel.hasPollingRateChanges)
    XCTAssertTrue(pollingModel.hasPendingChanges)

    pollingModel.applyPollingRate(1000)
    XCTAssertTrue(
      pollingCalls.isEmpty, "unsupported polling rate was forwarded to the write engine")
    XCTAssertEqual(pollingModel.pollingRateDraft, 500)
  }

  func testNormalAndGShiftProfileOutputLayersParseSeparately() {
    let layeredModel = AppModel(startInitialRefresh: false)
    Self.configure(layeredModel)
    let layeredText = """
      Profile 2 (sector 0x0100, enabled=yes)
        button 1: Left click [80010001]
        G-Shift button 1: Right click [80010002]
      """
    let parsedLayers = layeredModel.parseProfiles(layeredText)
    XCTAssertEqual(parsedLayers.rowsByProfile[2]?.first?.layer, .normal)
    XCTAssertEqual(parsedLayers.gShiftRowsByProfile[2]?.first?.layer, .gShift)
  }

  func testGShiftEditsAreRetainedAcrossLayerSwitchingAndForwardedToWriteEngine() {
    let layeredModel = AppModel(startInitialRefresh: false)
    Self.configure(layeredModel)
    let normalRows = layeredModel.buttons
    let gShiftRows = [
      ButtonRow(
        id: 1,
        label: "G1 · Primary click (Left)",
        currentRaw: "80010002",
        draftRaw: "80010002",
        draftChoice: "80010002",
        layer: .gShift
      )
    ]
    layeredModel.setButtonRows(normal: normalRows, gShift: gShiftRows)
    layeredModel.setRaw(layer: .normal, buttonIndex: 0, raw: ProfileWriteValidation.primaryClickRaw)
    layeredModel.selectButtonLayer(.gShift)
    layeredModel.setRaw(buttonIndex: 0, raw: "80010004")
    layeredModel.selectButtonLayer(.normal)
    XCTAssertEqual(layeredModel.gShiftButtonRows[0].draftRaw, "80010004")
    XCTAssertEqual(layeredModel.buttons[0].draftRaw, ProfileWriteValidation.primaryClickRaw)

    var layeredCalls = [[String]]()
    layeredModel.engineRunnerOverride = { arguments in
      layeredCalls.append(arguments)
      return "Verified sector 0x0100"
    }
    layeredModel.applyButtons()
    XCTAssertTrue(layeredCalls.contains(where: { $0.contains("gshift:1:80010004") }))
  }

  func testSleepingDeviceTransitionKeepsUnderlyingProfileSurface() {
    let sleepingModel = AppModel(startInitialRefresh: false)
    sleepingModel.devices = [
      DeviceChoice(
        id: 1,
        name: "G603",
        connection: "Wireless",
        productID: "0xB01C",
        deviceKey: "sleeping-device"
      )
    ]
    sleepingModel.selectedDeviceIndex = 1
    sleepingModel.currentDeviceName = "G603"
    sleepingModel.buttons = [
      ButtonRow(
        id: 1,
        label: "G1 · Primary click",
        currentRaw: "80010001",
        draftRaw: "80010001",
        draftChoice: "80010001",
        layer: .normal
      )
    ]
    sleepingModel.profiles = [
      ProfileChoice(
        id: 1,
        sector: "0x0100",
        enabled: true,
        crcValid: nil
      )
    ]
    sleepingModel.applyRefreshSnapshot(
      RefreshSnapshot(
        devices: sleepingModel.devices,
        selectedDeviceIndex: 1,
        profileText: nil,
        profileError: "sleeping",
        dpiText: nil,
        dpiError: nil,
        selectedProfileNumber: nil,
        errorMessage: nil,
        accessWarning: false
      ))
    XCTAssertTrue(sleepingModel.waitingForKnownDevice)
    XCTAssertFalse(sleepingModel.buttons.isEmpty)
    XCTAssertFalse(sleepingModel.profiles.isEmpty)
    sleepingModel.knownDevicePollTask?.cancel()
  }

  private static func configure(_ model: AppModel) {
    model.devices = [
      DeviceChoice(
        id: 1,
        name: "G502 X",
        connection: "Wired",
        productID: "0x0000",
        deviceKey: "test-device"
      )
    ]
    model.selectedDeviceIndex = 1
    model.currentDeviceName = "G502 X / X LIGHTSPEED / X PLUS"
    model.profileNumber = 2
    model.profiles = [
      ProfileChoice(
        id: 2,
        sector: "0x0100",
        enabled: true,
        crcValid: true
      )
    ]
    model.baselineProfileEnabled = [2: true]
    model.buttons = [
      ButtonRow(
        id: 1,
        label: "G1 · Primary click (Left)",
        currentRaw: "80010002",
        draftRaw: "80010002",
        draftChoice: "80010002",
        layer: .normal
      )
    ]
  }
}
