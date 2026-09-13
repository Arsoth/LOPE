// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

final class AppModelsTests: XCTestCase {
  func testWiredAccessPromptAndMXClassification() {
    let wired = DeviceChoice(
      id: 1, name: "G Pro", connection: "Wired", productID: "0xC085", deviceKey: "wired")
    let receiver = DeviceChoice(
      id: 2, name: "G604", connection: "LIGHTSPEED", productID: "0x4085", deviceKey: "receiver")
    let bluetooth = DeviceChoice(
      id: 3, name: "MX Master 3S", connection: "Bluetooth", productID: "0xB034",
      deviceKey: "bluetooth")
    let withoutAccess = DeviceChoice.addingWiredAccessPrompt(
      to: [wired, receiver], accessAuthorized: false)
    let withAccess = DeviceChoice.addingWiredAccessPrompt(
      to: [wired, receiver], accessAuthorized: true)

    XCTAssertEqual(withoutAccess.last?.isWiredAccessPrompt, true)
    XCTAssertEqual(withAccess.count, 2)
    // isMXSeriesMouse lives in DeviceClassification.swift; checked here
    // against the same device fixtures rather than duplicating them.
    XCTAssertTrue(
      DeviceClassification.isMXSeriesMouse(name: bluetooth.name, productID: bluetooth.productID))
    XCTAssertTrue(DeviceClassification.isMXSeriesMouse(name: "MX Anywhere 3", productID: ""))
    XCTAssertFalse(DeviceClassification.isMXSeriesMouse(name: "G603", productID: "0xB01C"))
  }
}
