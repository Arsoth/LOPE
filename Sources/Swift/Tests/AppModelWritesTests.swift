// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

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
    configureFixtureDevice(rejectedDPIModel)
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
    configureFixtureDevice(rejectedCombinedModel)
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

  func testSupportedPollingRateChangeIsStagedForProfileSave() {
    let pollingModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(pollingModel)
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
}
