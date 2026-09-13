// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelParsingTests: XCTestCase {
  func testNormalAndGShiftProfileOutputLayersParseSeparately() {
    let layeredModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(layeredModel)
    let layeredText = """
      Profile 2 (sector 0x0100, enabled=yes)
        button 1: Left click [80010001]
        G-Shift button 1: Right click [80010002]
      """
    let parsedLayers = layeredModel.parseProfiles(layeredText)
    XCTAssertEqual(parsedLayers.rowsByProfile[2]?.first?.layer, .normal)
    XCTAssertEqual(parsedLayers.gShiftRowsByProfile[2]?.first?.layer, .gShift)
  }
}
