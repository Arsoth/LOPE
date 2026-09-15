// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

@MainActor
private func configureG502SpectrumDevice(_ model: AppModel) {
  model.devices = [
    DeviceChoice(
      id: 1,
      name: "Tunable RGB Gaming Mouse G502",
      connection: "Wired",
      productID: "0xC332",
      deviceKey: "test-device"
    )
  ]
  model.selectedDeviceIndex = 1
  model.currentDeviceName = "Tunable RGB Gaming Mouse G502"
  model.profileNumber = 1
  model.profiles = [ProfileChoice(id: 1, sector: "0x0100", enabled: true, crcValid: true)]
  model.baselineProfileEnabled = [1: true]
  model.buttons = (1...11).map { number in
    ButtonRow(
      id: number,
      label: "Button \(number)",
      currentRaw: "FFFFFFFF",
      draftRaw: "FFFFFFFF",
      draftChoice: "FFFFFFFF",
      layer: .normal
    )
  }
  model.dpiCount = 5
  model.dpiStages = ["100", "", "", "", ""]
  model.defaultStage = 1
  model.shiftStage = 1
  model.pollingRateCapabilities = PollingRateCapabilities(supportedRates: [500, 1000])
  model.applyRGBZones(
    [
      ParsedRGBZone(index: 0, color: RGBColor(red: 0, green: 0, blue: 0), mode: .solid),
      ParsedRGBZone(index: 1, color: RGBColor(red: 0, green: 0, blue: 0), mode: .solid),
    ],
    profileFormat: 5
  )
}

@MainActor
final class AppModelReferenceDefaultsTests: XCTestCase {
  func testRestoreReferenceDefaultsReportsStatusWhenDeviceHasNoVerifiedReferenceProfile() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let originalDraft = model.buttons[0].draftRaw

    model.restoreReferenceDefaults()

    XCTAssertEqual(model.buttons[0].draftRaw, originalDraft)
    XCTAssertTrue(model.status.contains("has no verified reference profile yet."))
  }

  func testRestoreReferenceDefaultsLoadsButtonsDPIReportRateAndRGBModes() {
    let model = AppModel(startInitialRefresh: false)
    configureG502SpectrumDevice(model)

    model.restoreReferenceDefaults()

    let expectedButtonRaws: [Int: String] = [
      1: "80010001", 2: "80010002", 3: "80010004", 4: "80010008", 5: "80010010",
      6: "90070000", 7: "90040000", 8: "90030000", 9: "90010000", 10: "90020000",
      11: "900A0000",
    ]
    for (number, raw) in expectedButtonRaws {
      XCTAssertEqual(
        model.buttons.first(where: { $0.id == number })?.draftRaw, raw,
        "button \(number) did not load its reference raw record")
    }

    XCTAssertEqual(model.dpiCount, 4)
    XCTAssertEqual(Array(model.dpiStages.prefix(4)), ["1200", "2400", "3200", "6400"])
    XCTAssertEqual(model.defaultStage, 2)
    XCTAssertEqual(model.shiftStage, 1)

    XCTAssertEqual(model.pollingRateDraft, 1000)

    XCTAssertEqual(model.rgbZones.map(\.draftMode), [.cycle, .cycle])

    XCTAssertTrue(model.status.contains("verified reference profile"))
  }

  func testRestoreReferenceDefaultsSkipsButtonsNotPresentInTheCurrentLayer() {
    let model = AppModel(startInitialRefresh: false)
    configureG502SpectrumDevice(model)
    // Drop button 11 so its reference entry has nothing to match against.
    model.buttons.removeAll { $0.id == 11 }

    model.restoreReferenceDefaults()

    XCTAssertEqual(model.buttons.first(where: { $0.id == 1 })?.draftRaw, "80010001")
    XCTAssertNil(model.buttons.first(where: { $0.id == 11 }))
  }

  func testRestoreReferenceDefaultsSkipsReportRateWhenUnsupportedByDevice() {
    let model = AppModel(startInitialRefresh: false)
    configureG502SpectrumDevice(model)
    model.pollingRateCapabilities = PollingRateCapabilities(supportedRates: [125, 250])

    model.restoreReferenceDefaults()

    XCTAssertNil(model.pollingRateDraft)
  }

  func testRestoreReferenceDefaultsDoesNothingWhenBusy() {
    let model = AppModel(startInitialRefresh: false)
    configureG502SpectrumDevice(model)
    model.busy = true
    let originalDraft = model.buttons[0].draftRaw

    model.restoreReferenceDefaults()

    XCTAssertEqual(model.buttons[0].draftRaw, originalDraft)
  }
}
