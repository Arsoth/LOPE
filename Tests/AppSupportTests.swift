// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

final class AppSupportTests: XCTestCase {
  func testAppearancePreferenceOptions() {
    XCTAssertEqual(AppearancePreference.allCases, [.system, .light, .dark])
    XCTAssertEqual(AppearancePreference.light.label, "Light")
  }
}
