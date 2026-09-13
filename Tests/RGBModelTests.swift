// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

final class RGBModelTests: XCTestCase {
  func testRGBHexConversionAndValidation() {
    let red = RGBColor(hex: "#ff002a")
    XCTAssertEqual(red, RGBColor(red: 255, green: 0, blue: 42))
    XCTAssertEqual(red?.hex, "0xFF002A")
    XCTAssertEqual(RGBColor(hex: "0x123456"), RGBColor(red: 0x12, green: 0x34, blue: 0x56))
    XCTAssertNil(RGBColor(hex: "12345"))
    XCTAssertNil(RGBColor(hex: "0xGG0000"))
  }

  func testRGBEditorLogicPerZoneAndAllZoneEditing() {
    let rgbZones = [
      RGBZoneState(
        id: 0, name: "Primary", current: RGBColor(red: 1, green: 2, blue: 3),
        draft: RGBColor(red: 1, green: 2, blue: 3)),
      RGBZoneState(
        id: 1, name: "Logo", current: RGBColor(red: 4, green: 5, blue: 6),
        draft: RGBColor(red: 4, green: 5, blue: 6)),
    ]
    let blue = LOPECore.RGBColor(red: 0, green: 64, blue: 255)
    let oneZone = RGBEditorLogic.settingColor(in: rgbZones, zoneID: 1, color: blue, allZones: false)
    XCTAssertEqual(oneZone[0].draft, rgbZones[0].draft)
    XCTAssertEqual(oneZone[1].draft, blue)

    let allZones = RGBEditorLogic.settingColor(in: rgbZones, zoneID: 0, color: blue, allZones: true)
    XCTAssertTrue(allZones.allSatisfy({ $0.draft == blue }))
    XCTAssertEqual(
      RGBEditorLogic.settingColor(in: rgbZones, zoneID: 9, color: blue, allZones: true), rgbZones)
  }
}
