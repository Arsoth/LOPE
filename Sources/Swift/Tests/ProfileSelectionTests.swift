// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

final class ProfileSelectionTests: XCTestCase {
  func testProfileSelectionResolution() {
    let selectionCases: [(Int?, [Int], Int, Int?)] = [
      (nil, [1], 2, 1),  // multi-profile mouse -> one-profile mouse
      (nil, [1, 2], 1, 1),  // one-profile mouse -> multi-profile mouse
      (2, [1, 2], 1, 2),
      (2, [1], 2, 1),  // stale selected slot is not retained
    ]
    for (index, testCase) in selectionCases.enumerated() {
      let actual = ProfileSelection.resolvedProfileNumber(
        selectedProfileNumber: testCase.0,
        availableProfileIDs: testCase.1,
        preferredProfileNumber: testCase.2
      )
      XCTAssertEqual(actual, testCase.3, "profile selection case \(index + 1)")
    }
  }
}
