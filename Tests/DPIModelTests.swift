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
}
