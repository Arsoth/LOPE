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

  func testVerifiedPollingRatePrefixAndErrorMessageParsing() {
    let verified = PollingRateOutputParser.parse(
      "Verified polling rate: 500 Hz\nReport rate error: sensor busy\n"
    )
    XCTAssertEqual(verified.currentRate, 500)
    XCTAssertEqual(verified.errorMessage, "sensor busy")
  }

  func testSupportedRatesWithHzSuffixAreParsed() {
    let withHzSuffix = PollingRateOutputParser.parse(
      "Supported polling rates: 125 Hz, 500 Hz, 1000 Hz\n"
    )
    XCTAssertEqual(withHzSuffix.supportedRates, [125, 500, 1000])
  }

  func testInitFiltersNonPositiveRatesAndDeduplicates() {
    let capabilities = PollingRateCapabilities(supportedRates: [1000, 0, -125, 1000, 500])
    XCTAssertEqual(capabilities.supportedRates, [500, 1000])
  }

  func testHasKnownRates() {
    XCTAssertFalse(PollingRateCapabilities().hasKnownRates)
    XCTAssertTrue(PollingRateCapabilities(supportedRates: [1000]).hasKnownRates)
  }

  func testProfileSupportedRatesExcludesConnectionLevelRates() {
    let capabilities = PollingRateCapabilities(supportedRates: [125, 500, 1000, 4000, 8000])
    XCTAssertEqual(capabilities.profileSupportedRates, [125, 500, 1000])
  }

  func testAccepts() {
    let capabilities = PollingRateCapabilities(supportedRates: [125, 1000])
    XCTAssertTrue(capabilities.accepts(125))
    XCTAssertFalse(capabilities.accepts(250))
  }

  func testDisplayTextCombinations() {
    XCTAssertEqual(PollingRateCapabilities().displayText, "")

    let full = PollingRateCapabilities(
      supportedRates: [125, 1000], currentRate: 1000, errorMessage: "boom")
    XCTAssertEqual(
      full.displayText,
      "Supported polling rates: 125, 1000\nCurrent polling rate: 1000 Hz\nPolling-rate error: boom"
    )

    let rateOnly = PollingRateCapabilities(currentRate: 500)
    XCTAssertEqual(rateOnly.displayText, "Current polling rate: 500 Hz")
  }
}
