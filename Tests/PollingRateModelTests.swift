// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

final class PollingRateModelTests: XCTestCase {
  func testExtendedPollingRateParsing() {
    let extendedPolling = PollingRateOutputParser.parse(
      "Report rate feature: 0x8061\nSupported polling rates: 125, 1000, 8000\nCurrent polling rate: 1000 Hz\n"
    )
    XCTAssertEqual(extendedPolling.supportedRates, [125, 1000, 8000])
    XCTAssertEqual(extendedPolling.currentRate, 1000)
    XCTAssertTrue(extendedPolling.accepts(8000))
    XCTAssertFalse(extendedPolling.accepts(500))
  }

  func testLegacyPollingRateParsing() {
    let legacyPolling = PollingRateOutputParser.parse(
      "Report rate feature: 0x8060\nSupported polling rates: 125, 250, 333, 1000\nCurrent polling rate: 333 Hz\n"
    )
    XCTAssertEqual(legacyPolling.supportedRates, [125, 250, 333, 1000])
    XCTAssertEqual(legacyPolling.currentRate, 333)
  }
}
