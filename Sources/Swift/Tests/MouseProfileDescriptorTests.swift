// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

final class MouseProfileDescriptorTests: XCTestCase {
  private func makeProfileIO(
    supported: Bool = true,
    saveStrategy: String? = "direct-write"
  ) -> MouseProfileDescriptor.ProfileIO {
    var save: [String: String] = [:]
    if let saveStrategy {
      save["strategy"] = saveStrategy
    }
    return MouseProfileDescriptor.ProfileIO(
      supported: supported,
      capability: "0x8100",
      feature: "onboard-profiles",
      load: ["strategy": "read"],
      save: save,
      layout: [:],
      notes: []
    )
  }

  private func makeDescriptor(
    rgbProfile: MouseProfileDescriptor.RGBProfile? = nil,
    dpiRange: MouseProfileDescriptor.DPIRange? = nil,
    generated: Bool? = nil,
    buttons: [MouseProfileDescriptor.Button] = [],
    scrollWheelButtonLabels: [String: String]? = nil,
    profileIO: MouseProfileDescriptor.ProfileIO? = nil,
    referenceProfile: MouseProfileDescriptor.ReferenceProfile? = nil
  ) -> MouseProfileDescriptor {
    MouseProfileDescriptor(
      schemaVersion: 1,
      id: "g604",
      name: "G604",
      match: MouseProfileDescriptor.Match(nameContains: ["G604"], productIDs: ["0xC087"]),
      buttons: buttons,
      scrollWheelButtonLabels: scrollWheelButtonLabels,
      hiddenProfileButtonNumbers: nil,
      dpiRange: dpiRange,
      refreshGuidance: nil,
      profileIO: profileIO ?? makeProfileIO(),
      rgbProfile: rgbProfile,
      referenceProfile: referenceProfile,
      sources: [],
      generated: generated
    )
  }

  private func decodeRGBProfile(json: String) throws -> MouseProfileDescriptor.RGBProfile {
    try JSONDecoder().decode(
      MouseProfileDescriptor.RGBProfile.self, from: Data(json.utf8))
  }

  private func decodeReferenceProfile(json: String) throws
    -> MouseProfileDescriptor.ReferenceProfile
  {
    try JSONDecoder().decode(
      MouseProfileDescriptor.ReferenceProfile.self, from: Data(json.utf8))
  }

  // MARK: DPIRange

  func testDPIRangeProducesCapabilities() {
    let range = MouseProfileDescriptor.DPIRange(minimum: 200, maximum: 8000)
    XCTAssertEqual(range.capabilities.minimum, 200)
    XCTAssertEqual(range.capabilities.maximum, 8000)
  }

  // MARK: Button

  func testButtonLabelWithAndWithoutAliases() {
    let plain = MouseProfileDescriptor.Button(
      number: 1, control: "Left Click", aliases: [], notes: nil)
    let aliased = MouseProfileDescriptor.Button(
      number: 2, control: "DPI Up", aliases: ["Forward", "Alt"], notes: "physical thumb button")
    XCTAssertEqual(plain.label, "Left Click")
    XCTAssertEqual(aliased.label, "DPI Up (Forward, Alt)")
  }

  // MARK: ProfileIO

  func testProfileIOCanSaveReflectsStrategy() {
    XCTAssertTrue(makeProfileIO(saveStrategy: "direct-write").canSave)
    XCTAssertFalse(makeProfileIO(saveStrategy: "read-only").canSave)
    XCTAssertFalse(makeProfileIO(supported: false, saveStrategy: "direct-write").canSave)
    // No "strategy" key at all: save["strategy"] is nil, which is != "read-only".
    XCTAssertTrue(makeProfileIO(saveStrategy: nil).canSave)
  }

  func testProfileIODecodeFillsDefaultsForMissingKeys() throws {
    let minimal = """
      { }
      """
    let decoded = try JSONDecoder().decode(
      MouseProfileDescriptor.ProfileIO.self, from: Data(minimal.utf8))
    XCTAssertTrue(decoded.supported)
    XCTAssertEqual(decoded.capability, "unknown")
    XCTAssertEqual(decoded.feature, "")
    XCTAssertEqual(decoded.load, [:])
    XCTAssertEqual(decoded.save, [:])
    XCTAssertEqual(decoded.layout, [:])
    XCTAssertEqual(decoded.notes, [])
  }

  func testProfileIODecodeUsesProvidedValues() throws {
    let full = """
      {
        "supported": false,
        "capability": "0x8100",
        "feature": "onboard-profiles",
        "load": { "strategy": "read" },
        "save": { "strategy": "read-only" },
        "layout": { "format": "4" },
        "notes": ["legacy firmware"]
      }
      """
    let decoded = try JSONDecoder().decode(
      MouseProfileDescriptor.ProfileIO.self, from: Data(full.utf8))
    XCTAssertFalse(decoded.supported)
    XCTAssertEqual(decoded.capability, "0x8100")
    XCTAssertEqual(decoded.save["strategy"], "read-only")
    XCTAssertEqual(decoded.layout["format"], "4")
    XCTAssertEqual(decoded.notes, ["legacy firmware"])
    XCTAssertFalse(decoded.canSave)
  }

  // MARK: RGBProfile

  private static let baseRGBJSON = """
    {
      "supported": true,
      "profileFormats": [4, 5],
      "baseOffset": 208,
      "recordBytes": 11,
      "colorOffset": 1,
      "zones": [ { "index": 0, "name": "Logo" } ],
      "deviceNameContains": ["G604"],
      "productIDs": ["0xC087"],
      "notes": []
    }
    """

  func testRGBProfileDecodeDefaultsForMissingKeys() throws {
    let minimal = """
      { "zones": [] }
      """
    let decoded = try decodeRGBProfile(json: minimal)
    XCTAssertFalse(decoded.supported)
    XCTAssertEqual(decoded.profileFormats, [])
    XCTAssertEqual(decoded.baseOffset, 208)
    XCTAssertEqual(decoded.recordBytes, 11)
    XCTAssertEqual(decoded.colorOffset, 1)
    XCTAssertNil(decoded.deviceNameContains)
    XCTAssertNil(decoded.productIDs)
    XCTAssertEqual(decoded.notes, [])
  }

  func testRGBProfileMatchesByNameOrProductWithRestriction() throws {
    let profile = try decodeRGBProfile(json: Self.baseRGBJSON)
    XCTAssertTrue(profile.matches(deviceName: "Logitech G604", productID: "irrelevant"))
    XCTAssertTrue(profile.matches(deviceName: "Something else", productID: "0xC087"))
    XCTAssertFalse(profile.matches(deviceName: "G Pro", productID: "0x1234"))
  }

  func testRGBProfileMatchesWithoutRestrictionAlwaysTrue() throws {
    let unrestricted = """
      {
        "supported": true,
        "profileFormats": [],
        "baseOffset": 208,
        "recordBytes": 11,
        "colorOffset": 1,
        "zones": [ { "index": 0, "name": "Logo" } ],
        "notes": []
      }
      """
    let profile = try decodeRGBProfile(json: unrestricted)
    XCTAssertTrue(profile.matches(deviceName: "Anything", productID: "Anything"))
  }

  func testRGBProfileSupportsProfileFormat() throws {
    let profile = try decodeRGBProfile(json: Self.baseRGBJSON)
    XCTAssertTrue(profile.supports(profileFormat: nil))
    XCTAssertTrue(profile.supports(profileFormat: 4))
    XCTAssertFalse(profile.supports(profileFormat: 6))

    let unsupported = try decodeRGBProfile(
      json: """
        { "supported": false, "zones": [ { "index": 0, "name": "Logo" } ] }
        """)
    XCTAssertFalse(unsupported.supports(profileFormat: nil))
  }

  func testRGBProfileCanEditRequiresValidLayout() throws {
    let valid = try decodeRGBProfile(json: Self.baseRGBJSON)
    XCTAssertTrue(valid.canEdit)

    let notSupported = try decodeRGBProfile(
      json: """
        { "supported": false, "zones": [ { "index": 0, "name": "Logo" } ] }
        """)
    XCTAssertFalse(notSupported.canEdit)

    let noZones = try decodeRGBProfile(
      json: """
        { "supported": true, "zones": [] }
        """)
    XCTAssertFalse(noZones.canEdit)

    let negativeOffset = try decodeRGBProfile(
      json: """
        {
          "supported": true, "baseOffset": -1, "recordBytes": 11, "colorOffset": 1,
          "zones": [ { "index": 0, "name": "Logo" } ]
        }
        """)
    XCTAssertFalse(negativeOffset.canEdit)

    let tooFewRecordBytes = try decodeRGBProfile(
      json: """
        {
          "supported": true, "baseOffset": 0, "recordBytes": 3, "colorOffset": 1,
          "zones": [ { "index": 0, "name": "Logo" } ]
        }
        """)
    XCTAssertFalse(tooFewRecordBytes.canEdit)

    let colorOffsetOutOfRange = try decodeRGBProfile(
      json: """
        {
          "supported": true, "baseOffset": 0, "recordBytes": 11, "colorOffset": 11,
          "zones": [ { "index": 0, "name": "Logo" } ]
        }
        """)
    XCTAssertFalse(colorOffsetOutOfRange.canEdit)

    let colorRunPastRecord = try decodeRGBProfile(
      json: """
        {
          "supported": true, "baseOffset": 0, "recordBytes": 5, "colorOffset": 3,
          "zones": [ { "index": 0, "name": "Logo" } ]
        }
        """)
    XCTAssertFalse(colorRunPastRecord.canEdit)
  }

  // MARK: MouseProfileDescriptor

  func testIsGeneratedDefaultsToFalse() {
    XCTAssertFalse(makeDescriptor(generated: nil).isGenerated)
    XCTAssertFalse(makeDescriptor(generated: false).isGenerated)
    XCTAssertTrue(makeDescriptor(generated: true).isGenerated)
  }

  func testInitialDPICapabilitiesFallsBackWhenRangeMissing() {
    XCTAssertFalse(makeDescriptor(dpiRange: nil).initialDPICapabilities.hasKnownValues)
    let withRange = makeDescriptor(
      dpiRange: MouseProfileDescriptor.DPIRange(minimum: 400, maximum: 8000))
    XCTAssertEqual(withRange.initialDPICapabilities.minimum, 400)
  }

  func testButtonLookupByNumber() {
    let descriptor = makeDescriptor(
      buttons: [
        MouseProfileDescriptor.Button(number: 1, control: "Left Click", aliases: [], notes: nil),
        MouseProfileDescriptor.Button(number: 2, control: "Right Click", aliases: [], notes: nil),
      ])
    XCTAssertEqual(descriptor.button(for: 2)?.control, "Right Click")
    XCTAssertNil(descriptor.button(for: 99))
  }

  func testScrollWheelButtonLabelLookup() {
    let withLabels = makeDescriptor(scrollWheelButtonLabels: ["12": "Scroll Left"])
    XCTAssertEqual(withLabels.scrollWheelButtonLabel(for: 12), "Scroll Left")
    XCTAssertNil(withLabels.scrollWheelButtonLabel(for: 13))

    let withoutLabels = makeDescriptor(scrollWheelButtonLabels: nil)
    XCTAssertNil(withoutLabels.scrollWheelButtonLabel(for: 12))
  }

  func testRGBCapabilitiesRequiresEditableMatchingSupportedProfile() throws {
    let rgb = try decodeRGBProfile(json: Self.baseRGBJSON)
    let descriptor = makeDescriptor(rgbProfile: rgb)

    XCTAssertNotNil(
      descriptor.rgbCapabilities(deviceName: "G604", productID: "0xC087", profileFormat: 4))
    XCTAssertNil(
      descriptor.rgbCapabilities(deviceName: "Unrelated", productID: "0x0000", profileFormat: 4))
    XCTAssertNil(
      descriptor.rgbCapabilities(deviceName: "G604", productID: "0xC087", profileFormat: 99))

    let noRGB = makeDescriptor(rgbProfile: nil)
    XCTAssertNil(noRGB.rgbCapabilities(deviceName: "G604", productID: "0xC087"))

    let unsupportedRGB = try decodeRGBProfile(
      json: """
        { "supported": false, "zones": [ { "index": 0, "name": "Logo" } ] }
        """)
    let unsupportedDescriptor = makeDescriptor(rgbProfile: unsupportedRGB)
    XCTAssertNil(
      unsupportedDescriptor.rgbCapabilities(deviceName: "G604", productID: "0xC087"))
  }

  // MARK: ReferenceProfile

  func testReferenceProfileDecodeDefaultsForMissingKeys() throws {
    let decoded = try decodeReferenceProfile(json: "{}")
    XCTAssertEqual(decoded.source, .unknown)
    XCTAssertEqual(decoded.buttons, [])
    XCTAssertNil(decoded.dpi)
    XCTAssertNil(decoded.reportRateHz)
    XCTAssertNil(decoded.rgbZones)
    XCTAssertEqual(decoded.notes, [])
  }

  func testReferenceProfileDecodeUsesProvidedValues() throws {
    let decoded = try decodeReferenceProfile(
      json: """
        {
          "source": "verifiedFactoryReset",
          "buttons": [{ "number": 1, "raw": "80010001" }],
          "dpi": { "stages": [1200, 2400], "defaultStage": 2, "shiftStage": 1 },
          "reportRateHz": 1000,
          "rgbZones": [{ "index": 0, "mode": "cycle" }],
          "notes": ["captured from a real reset"]
        }
        """)
    XCTAssertEqual(decoded.source, .verifiedFactoryReset)
    XCTAssertEqual(
      decoded.buttons,
      [
        MouseProfileDescriptor.ReferenceProfile.Button(
          number: 1, raw: "80010001")
      ])
    XCTAssertEqual(decoded.dpi?.stages, [1200, 2400])
    XCTAssertEqual(decoded.dpi?.defaultStage, 2)
    XCTAssertEqual(decoded.dpi?.shiftStage, 1)
    XCTAssertEqual(decoded.reportRateHz, 1000)
    XCTAssertEqual(decoded.rgbZones?.first?.index, 0)
    XCTAssertEqual(decoded.rgbZones?.first?.mode, "cycle")
    XCTAssertNil(decoded.rgbZones?.first?.color)
    XCTAssertEqual(decoded.notes, ["captured from a real reset"])
  }

  func testCanRestoreReferenceProfileRequiresVerifiedSourceAndSaveSupport() throws {
    let verified = try decodeReferenceProfile(json: #"{"source": "verifiedFactoryReset"}"#)
    let userConfig = try decodeReferenceProfile(json: #"{"source": "userConfiguration"}"#)

    let saveable = makeDescriptor(profileIO: makeProfileIO(supported: true))
    let readOnly = makeDescriptor(profileIO: makeProfileIO(saveStrategy: "read-only"))

    XCTAssertTrue(
      makeDescriptor(
        profileIO: makeProfileIO(supported: true), referenceProfile: verified
      ).canRestoreReferenceProfile)
    XCTAssertFalse(
      makeDescriptor(
        profileIO: makeProfileIO(saveStrategy: "read-only"), referenceProfile: verified
      ).canRestoreReferenceProfile)
    XCTAssertFalse(
      makeDescriptor(
        profileIO: makeProfileIO(supported: true), referenceProfile: userConfig
      ).canRestoreReferenceProfile)
    XCTAssertFalse(saveable.canRestoreReferenceProfile)
    XCTAssertFalse(readOnly.canRestoreReferenceProfile)
  }
}
