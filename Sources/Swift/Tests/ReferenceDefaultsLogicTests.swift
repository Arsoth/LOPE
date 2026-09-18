// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

final class ReferenceDefaultsLogicTests: XCTestCase {
  private func makeReference(
    buttons: [MouseProfileDescriptor.ReferenceProfile.Button] = [],
    dpi: MouseProfileDescriptor.ReferenceProfile.DPI? = nil,
    reportRateHz: Int? = nil,
    rgbZones: [MouseProfileDescriptor.ReferenceProfile.RGBZone]? = nil
  ) -> MouseProfileDescriptor.ReferenceProfile {
    MouseProfileDescriptor.ReferenceProfile(
      source: .verifiedFactoryReset,
      buttons: buttons,
      dpi: dpi,
      reportRateHz: reportRateHz,
      rgbZones: rgbZones,
      notes: []
    )
  }

  func testButtonRawByNumberIndexesByButtonNumber() {
    let reference = makeReference(buttons: [
      .init(number: 1, raw: "80010001"),
      .init(number: 6, raw: "90070000"),
    ])
    XCTAssertEqual(
      ReferenceDefaultsLogic.buttonRawByNumber(reference), [1: "80010001", 6: "90070000"])
  }

  func testResolvedDPIRequiresOnboardEditingSupport() {
    let dpi = MouseProfileDescriptor.ReferenceProfile.DPI(
      stages: [1200, 2400], defaultStage: 2, shiftStage: 1)
    let reference = makeReference(dpi: dpi)
    XCTAssertNil(ReferenceDefaultsLogic.resolvedDPI(reference, canEditOnboardDPI: false))
    XCTAssertEqual(
      ReferenceDefaultsLogic.resolvedDPI(reference, canEditOnboardDPI: true)?.stages, [1200, 2400])
  }

  func testResolvedDPIRejectsMissingOrOutOfBoundsData() {
    XCTAssertNil(ReferenceDefaultsLogic.resolvedDPI(makeReference(), canEditOnboardDPI: true))

    let tooManyStages = MouseProfileDescriptor.ReferenceProfile.DPI(
      stages: [1, 2, 3, 4, 5, 6], defaultStage: 1, shiftStage: 1)
    XCTAssertNil(
      ReferenceDefaultsLogic.resolvedDPI(
        makeReference(dpi: tooManyStages), canEditOnboardDPI: true))

    let defaultOutOfBounds = MouseProfileDescriptor.ReferenceProfile.DPI(
      stages: [1200, 2400], defaultStage: 3, shiftStage: 1)
    XCTAssertNil(
      ReferenceDefaultsLogic.resolvedDPI(
        makeReference(dpi: defaultOutOfBounds), canEditOnboardDPI: true))

    let shiftOutOfBounds = MouseProfileDescriptor.ReferenceProfile.DPI(
      stages: [1200, 2400], defaultStage: 1, shiftStage: 0)
    XCTAssertNil(
      ReferenceDefaultsLogic.resolvedDPI(
        makeReference(dpi: shiftOutOfBounds), canEditOnboardDPI: true))
  }

  func testResolvedReportRateRequiresProfileSupport() {
    let reference = makeReference(reportRateHz: 1000)
    XCTAssertNil(
      ReferenceDefaultsLogic.resolvedReportRateHz(reference, profileSupportedRates: [125, 500]))
    XCTAssertEqual(
      ReferenceDefaultsLogic.resolvedReportRateHz(reference, profileSupportedRates: [500, 1000]),
      1000)
    XCTAssertNil(
      ReferenceDefaultsLogic.resolvedReportRateHz(makeReference(), profileSupportedRates: [1000]))
  }

  func testRGBZoneUpdatesResolvesKnownModeNamesAndOptionalColor() {
    let reference = makeReference(rgbZones: [
      .init(index: 0, mode: "cycle", color: nil),
      .init(index: 1, mode: "not-a-real-mode", color: "AABBCC"),
    ])
    let updates = ReferenceDefaultsLogic.rgbZoneUpdates(reference)
    XCTAssertEqual(updates.count, 2)
    XCTAssertEqual(updates[0].index, 0)
    XCTAssertEqual(updates[0].mode, .cycle)
    XCTAssertNil(updates[0].color)
    XCTAssertEqual(updates[1].index, 1)
    XCTAssertNil(updates[1].mode)
    XCTAssertEqual(updates[1].color, RGBColor(hex: "AABBCC"))
  }

  func testRGBZoneUpdatesIsEmptyWhenNoZonesRecorded() {
    XCTAssertEqual(ReferenceDefaultsLogic.rgbZoneUpdates(makeReference()).count, 0)
  }
}
