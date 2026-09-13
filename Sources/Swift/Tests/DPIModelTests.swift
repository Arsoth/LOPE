// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

final class DPIModelTests: XCTestCase {
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

  func testDPIEditorValidationRejectsOutOfRangeCountAndStageWidth() {
    let listCapabilities = DPIOutputParser.parse("Supported DPI: 800, 1600, 3200\n")
    XCTAssertEqual(
      DPIEditorValidation.message(
        stages: ["800", "", "", "", ""], count: 0, defaultStage: 1, shiftStage: 1,
        capabilities: listCapabilities),
      "Choose between one and five DPI stages.")
    XCTAssertEqual(
      DPIEditorValidation.message(
        stages: ["800", "", "", "", ""], count: 6, defaultStage: 1, shiftStage: 1,
        capabilities: listCapabilities),
      "Choose between one and five DPI stages.")
    XCTAssertEqual(
      DPIEditorValidation.message(
        stages: ["800", "1600"], count: 2, defaultStage: 1, shiftStage: 1,
        capabilities: listCapabilities),
      "Choose between one and five DPI stages.")
  }

  func testDPIEditorValidationRejectsOutOfProtocolRangeValue() {
    let openCapabilities = DPICapabilities()
    XCTAssertEqual(
      DPIEditorValidation.message(
        stages: ["99", "", "", "", ""], count: 1, defaultStage: 1, shiftStage: 1,
        capabilities: openCapabilities),
      "DPI stage 1 must be between 100 and 65535.")
  }

  func testDPIEditorValidationRejectsOutOfRangeDefaultOrShiftStage() {
    let listCapabilities = DPIOutputParser.parse("Supported DPI: 800, 1600, 3200\n")
    XCTAssertEqual(
      DPIEditorValidation.message(
        stages: ["800", "1600", "", "", ""], count: 2, defaultStage: 3, shiftStage: 1,
        capabilities: listCapabilities),
      "Default and DPI Shift must refer to active stages.")
    XCTAssertEqual(
      DPIEditorValidation.message(
        stages: ["800", "1600", "", "", ""], count: 2, defaultStage: 1, shiftStage: 0,
        capabilities: listCapabilities),
      "Default and DPI Shift must refer to active stages.")
  }

  func testDPICapabilitiesHasKnownValues() {
    XCTAssertFalse(DPICapabilities().hasKnownValues)
    XCTAssertTrue(DPICapabilities(supportedValues: [800]).hasKnownValues)
    XCTAssertTrue(DPICapabilities(minimum: 100, maximum: 200).hasKnownValues)
  }

  func testDPICapabilitiesExplicitMinimumOverridesInferredValue() {
    let capabilities = DPICapabilities(supportedValues: [800, 1600], minimum: 500)
    XCTAssertEqual(capabilities.minimum, 500)
    XCTAssertEqual(capabilities.maximum, 1600)
  }

  func testDPICapabilitiesDisplayTextCombinations() {
    XCTAssertEqual(DPICapabilities().displayText, "")

    let full = DPICapabilities(
      supportedValues: [800, 1600], sensorCount: 2, currentValue: 800, errorMessage: "oops")
    XCTAssertEqual(
      full.displayText,
      "DPI sensors: 2\nSupported DPI: 800, 1600\nCurrent sensor 1 DPI: 800\nDPI error: oops")

    let rangeNoStep = DPICapabilities(minimum: 400, maximum: 800, step: nil)
    XCTAssertEqual(rangeNoStep.displayText, "Supported DPI: 400..800")

    let rangeWithStep = DPICapabilities(minimum: 400, maximum: 800, step: 50)
    XCTAssertEqual(rangeWithStep.displayText, "Supported DPI: 400..800 (step 50)")
  }

  func testDPICapabilitiesAcceptsOpenRangeWithoutCapabilityData() {
    let capabilities = DPICapabilities()
    XCTAssertTrue(capabilities.accepts(12345))
    XCTAssertFalse(capabilities.accepts(50))
    XCTAssertFalse(capabilities.accepts(Int(UInt16.max) + 1))
  }

  func testDPICapabilitiesAcceptsRangeOutsideBoundsOrOffStep() {
    let capabilities = DPICapabilities(minimum: 400, maximum: 800, step: 50)
    XCTAssertFalse(capabilities.accepts(300))
    XCTAssertFalse(capabilities.accepts(425))
    XCTAssertTrue(capabilities.accepts(450))
  }

  func testDPICapabilitiesSnappedValueReturnsNilWhenBoundsCross() {
    let capabilities = DPICapabilities(minimum: 400, maximum: 800, step: 50)
    XCTAssertNil(capabilities.snappedValue(for: 500, lowerBound: 900))
  }

  func testDPICapabilitiesSnappedValueWithoutStepClampsDirectly() {
    let capabilities = DPICapabilities(minimum: 100, maximum: 6000)
    XCTAssertEqual(capabilities.snappedValue(for: 5000), 5000)
    XCTAssertEqual(capabilities.snappedValue(for: 50), 100)
    XCTAssertEqual(capabilities.snappedValue(for: 9000), 6000)
  }

  func testDPICapabilitiesAdjustedValueWithDiscreteList() {
    let capabilities = DPICapabilities(supportedValues: [800, 1600, 3200])
    XCTAssertEqual(capabilities.adjustedValue(from: 800, direction: .increase), 1600)
    XCTAssertEqual(capabilities.adjustedValue(from: 3200, direction: .increase), nil)
    XCTAssertEqual(capabilities.adjustedValue(from: 3200, direction: .decrease), 1600)
    XCTAssertEqual(capabilities.adjustedValue(from: 800, direction: .decrease), nil)
    XCTAssertNil(
      capabilities.adjustedValue(from: 800, direction: .increase, upperBound: 1000))
  }

  func testDPICapabilitiesAdjustedValueWithSteppedRange() {
    let capabilities = DPICapabilities(minimum: 400, maximum: 800, step: 50)
    XCTAssertEqual(capabilities.adjustedValue(from: 400, direction: .increase), 450)
    XCTAssertEqual(capabilities.adjustedValue(from: 450, direction: .decrease), 400)
  }

  func testDPICapabilitiesAdjustedValueWithoutStepUsesDefaultIncrement() {
    let capabilities = DPICapabilities(minimum: 100, maximum: 6000)
    XCTAssertEqual(capabilities.adjustedValue(from: 500, direction: .increase), 600)
    XCTAssertEqual(capabilities.adjustedValue(from: 500, direction: .decrease), 400)
  }

  func testDPIOutputParserIgnoresUnknownLinesAndParsesErrorMessage() {
    let capabilities = DPIOutputParser.parse(
      "Unrelated line\nDPI error: sensor offline\n"
    )
    XCTAssertEqual(capabilities.errorMessage, "sensor offline")
    XCTAssertTrue(capabilities.supportedValues.isEmpty)
  }

  func testDPIOutputParserParsesRangeWithoutStepDetail() {
    let capabilities = DPIOutputParser.parse("Supported DPI: 400..800\n")
    XCTAssertEqual(capabilities.minimum, 400)
    XCTAssertEqual(capabilities.maximum, 800)
    XCTAssertNil(capabilities.step)
  }
}
