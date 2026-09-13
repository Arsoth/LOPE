// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

final class ProfileWriteValidationTests: XCTestCase {
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
}
