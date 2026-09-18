// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelEditingTests: XCTestCase {
  func testPrimaryClickValidationPrefersRuntimeMouseName() {
    let presetModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(presetModel)
    // primaryClickValidationMessage lives in AppModel+Writes.swift; this
    // fixture is shared here because the rest of the test exercises
    // selectOutput's normalization, which is Editing's concern.
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
    configureFixtureDevice(rawModel)
    rawModel.setRaw(buttonIndex: 0, raw: "80 01 00 01")
    XCTAssertEqual(rawModel.buttons[0].draftRaw, ProfileWriteValidation.primaryClickRaw)
  }

  func testContinuousDPIStageDragTracksSnappedValue() {
    let dpiDragModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(dpiDragModel)
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
    configureFixtureDevice(dpiDragModel)
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
    configureFixtureDevice(dpiDragModel)
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

  func testGShiftEditsAreRetainedAcrossLayerSwitchingAndForwardedToWriteEngine() {
    let layeredModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(layeredModel)
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
}
