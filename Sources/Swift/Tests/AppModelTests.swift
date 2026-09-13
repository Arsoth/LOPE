// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelTests: XCTestCase {
  func testProvisionalMouseDataSuppressesDPIValidationWarning() {
    let provisionalModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(provisionalModel)
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
}
