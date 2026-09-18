// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

final class ProfileOutputParserTests: XCTestCase {
  func testOnboardProfileCapacityParsing() {
    let cases: [(String, Int?)] = [
      (
        "Onboard profiles for G502 X:\nProfile capacity: 5\nProfile 1 (sector 0x0100, enabled=yes)",
        5
      ),
      ("Profile 1 (sector 0x0100, enabled=yes)", nil),
      ("Profile capacity: nope\nProfile capacity: 0\nProfile capacity: 5 trailing", nil),
      ("Profile capacity: 2\r\nProfile 1 (sector 0x0100, enabled=yes)", 2),
    ]

    for (index, testCase) in cases.enumerated() {
      let actual = ProfileOutputParser.onboardProfileCapacity(in: testCase.0)
      XCTAssertEqual(actual, testCase.1, "profile capacity parser case \(index + 1)")
    }
  }

  func testScrollWheelOutputRecognition() {
    XCTAssertEqual(ProfileOutputParser.scrollWheelOutputLabel("90 10 00 00"), "Scroll down")
    XCTAssertEqual(ProfileOutputParser.scrollWheelOutputLabel("90110000"), "Scroll up")
    XCTAssertTrue(ProfileOutputParser.isScrollWheelOutput("90 10 00 00"))
    XCTAssertFalse(ProfileOutputParser.isScrollWheelOutput("90010000"))
    XCTAssertFalse(ProfileOutputParser.isScrollWheelOutput("FFFFFFFF"))
  }

  func testRGBProfileOutputParsing() {
    let parsedRGBLine = ProfileOutputParser.rgbZone(
      from: "  RGB zone 2: A1B2C3 (mode 0x01)"
    )
    XCTAssertEqual(parsedRGBLine?.index, 1)
    XCTAssertEqual(parsedRGBLine?.color, RGBColor(red: 0xA1, green: 0xB2, blue: 0xC3))
    XCTAssertEqual(parsedRGBLine?.mode, .solid)
    XCTAssertEqual(
      ProfileOutputParser.rgbZone(from: "  RGB zone 1: 000000 (mode 0x03)")?.mode, .cycle)
    XCTAssertEqual(
      ProfileOutputParser.rgbZone(from: "  RGB zone 1: 000000 (mode 0x99)")?.mode, .disabled)
    XCTAssertEqual(
      ProfileOutputParser.profileFormat(from: "  format: 0x05, macro format: 0x01"), 5)
    XCTAssertNil(ProfileOutputParser.rgbZone(from: "RGB zone 0: AABBCC (mode 0x01)"))
  }
}
