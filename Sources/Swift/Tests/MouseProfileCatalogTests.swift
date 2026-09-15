// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

final class MouseProfileCatalogTests: XCTestCase {
  // Covers matchingProfile's tie-break: when two descriptors score equal
  // specificity, the one with the lexicographically smaller `id` wins.
  // No shipped descriptor pair ties on specificity, so this installs two
  // throwaway descriptors that both match on the same name token.
  func testMatchingProfileTieBreaksOnLexicallySmallerID() throws {
    defer { MouseProfileCatalog.reload(customProfilesDirectory: nil) }

    let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lope-catalog-tiebreak-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    func makeDescriptor(id: String) -> MouseProfileDescriptor {
      MouseProfileDescriptor(
        schemaVersion: 1,
        id: id,
        name: "Tie Break Mouse \(id)",
        match: .init(nameContains: ["Tie Break Mouse"], productIDs: []),
        buttons: [],
        scrollWheelButtonLabels: nil,
        hiddenProfileButtonNumbers: nil,
        dpiRange: nil,
        refreshGuidance: nil,
        profileIO: MouseProfileCatalog.genericProfile.profileIO,
        rgbProfile: nil,
        sources: []
      )
    }

    for descriptor in [makeDescriptor(id: "zzz-tie-break"), makeDescriptor(id: "aaa-tie-break")] {
      let data = try JSONEncoder().encode(descriptor)
      try data.write(to: tempDirectory.appendingPathComponent("\(descriptor.id).json"))
    }
    MouseProfileCatalog.reload(customProfilesDirectory: tempDirectory)

    let winner = MouseProfileCatalog.shared.matchingProfile(
      deviceName: "Tie Break Mouse", productID: "")
    XCTAssertEqual(winner?.id, "aaa-tie-break")
  }

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

  func testBaseG502ProfileProvidesWritableRGBCapability() {
    let g502 = MouseProfileCatalog.shared.profile(
      deviceName: "Tunable RGB Gaming Mouse G502", productID: "0xC332")

    XCTAssertEqual(g502.id, "g502-proteus-spectrum")
    XCTAssertEqual(g502.name, "G502 Proteus Spectrum")
    XCTAssertTrue(g502.profileIO.canSave)
    XCTAssertEqual(
      g502.rgbCapabilities(
        deviceName: "Tunable RGB Gaming Mouse G502", productID: "0xC332", profileFormat: 5
      )?.zones.map(\.name),
      ["DPI", "Logo"])
    XCTAssertNotNil(
      g502.rgbCapabilities(
        deviceName: "Tunable RGB Gaming Mouse G502", productID: "0xC332", profileFormat: 2))
  }

  func testG502ProductIDOutranksLegacyG5NameSubstring() {
    let spectrum = MouseProfileCatalog.shared.profile(deviceName: "G502", productID: "0xC332")
    let hero = MouseProfileCatalog.shared.profile(deviceName: "G502", productID: "0xC08B")

    XCTAssertEqual(spectrum.id, "g502-proteus-spectrum")
    XCTAssertEqual(hero.id, "g502-hero")
  }

  func testG502ProteusCoreIsSeparateAndHasNoRGBCapability() {
    let core = MouseProfileCatalog.shared.profile(
      deviceName: "G502 Proteus Core", productID: "0xC07D")

    XCTAssertEqual(core.id, "g502-proteus-core")
    XCTAssertEqual(core.name, "G502 Proteus Core")
    XCTAssertTrue(core.profileIO.canSave)
    XCTAssertNil(
      core.rgbCapabilities(deviceName: "G502 Proteus Core", productID: "0xC07D", profileFormat: 5))
  }
}
