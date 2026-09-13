// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

final class MouseProfileCatalogTests: XCTestCase {
  func testG604HiddenAndNonProgrammableControlMetadata() {
    let g604Profile = MouseProfileCatalog.shared.profile(deviceName: "G604", productID: "0x4085")
    XCTAssertEqual(g604Profile.hiddenProfileButtonNumbers?.contains(16), true)
    XCTAssertEqual(g604Profile.scrollWheelButtonLabel(for: 14), "Scroll down")
    XCTAssertEqual(g604Profile.scrollWheelButtonLabel(for: 15), "Scroll up")
    XCTAssertEqual(g604Profile.refreshGuidance?.sleepDescription.contains("several minutes"), true)
    XCTAssertFalse(MouseProfileCatalog.shared.profiles.isEmpty)
  }

  func testKnownDeviceRefreshGuidanceAndRetryPolicy() {
    let g603Profile = MouseProfileCatalog.shared.profile(deviceName: "G603", productID: "0xB01C")
    XCTAssertEqual(g603Profile.refreshGuidance?.sleepDescription.contains("3 seconds"), true)
    // OnboardProfileRefreshPolicy lives in RefreshGuidance.swift; checked
    // here alongside the catalog lookup that consumes it.
    XCTAssertEqual(OnboardProfileRefreshPolicy.pollIntervalNanoseconds, 1_000_000_000)
    XCTAssertEqual(OnboardProfileRefreshPolicy.maximumPollAttempts, 60)
  }

  func testG203ProductIDCatalogMatch() {
    let g203Profile = MouseProfileCatalog.shared.profile(deviceName: "", productID: "0xC092")
    XCTAssertEqual(g203Profile.id, "g203")
    XCTAssertTrue(g203Profile.profileIO.canSave)
  }

  func testG600RemainsReadOnly() {
    let g600Profile = MouseProfileCatalog.shared.profile(
      deviceName: "G600 MMO", productID: "0xC24A")
    XCTAssertEqual(g600Profile.id, "g600")
    XCTAssertFalse(g600Profile.profileIO.supported)
    XCTAssertFalse(g600Profile.profileIO.canSave)
    XCTAssertEqual(
      g600Profile.profileIO.save["strategy"], "read-only",
      "G600 must remain read-only until all legacy profile features are supported")
  }

  func testG502RGBCapabilityGating() {
    let g502 = MouseProfileCatalog.shared.profile(deviceName: "G502 HERO", productID: "0xC08B")
    let g502RGB = g502.rgbCapabilities(
      deviceName: "G502 HERO", productID: "0xC08B", profileFormat: 5)
    XCTAssertEqual(g502RGB?.zones.map(\.name), ["Primary", "Logo"])
    XCTAssertNil(
      g502.rgbCapabilities(deviceName: "G502 HERO", productID: "0xC08B", profileFormat: 7))

    let unsupported = MouseProfileCatalog.shared.profile(
      deviceName: "G603 LIGHTSPEED", productID: "0xB01C")
    XCTAssertNil(
      unsupported.rgbCapabilities(
        deviceName: "G603 LIGHTSPEED", productID: "0xB01C", profileFormat: 5))
  }
}
