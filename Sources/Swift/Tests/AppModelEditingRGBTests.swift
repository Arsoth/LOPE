// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

// Mirrors AppModel+EditingRGB.swift. The shared fixture device (G502 X) has
// no RGB profile of its own, so these tests point the model at devices that
// do (base G502 and G502 HERO, format 4/5, Primary/Logo zones) to exercise
// the capability-gated paths.
@MainActor
final class AppModelEditingRGBTests: XCTestCase {
  private func configureRGBCapableDevice(_ model: AppModel) {
    configureFixtureDevice(model)
    model.devices = [
      DeviceChoice(
        id: 1,
        name: "G502 HERO",
        connection: "Wired",
        productID: "0xC07D",
        deviceKey: "test-device"
      )
    ]
    model.selectedDeviceIndex = 1
    model.currentDeviceName = "G502 HERO"
  }

  func testApplyRGBZonesWithoutCapabilityClearsState() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    // G502 X (the shared fixture device) does not advertise an RGB profile.
    model.rgbZones = [
      RGBZoneState(
        id: 0, name: "Stale", current: LOPECore.RGBColor(red: 1, green: 2, blue: 3),
        draft: LOPECore.RGBColor(red: 1, green: 2, blue: 3))
    ]
    model.rgbEditingAllZones = true
    model.baselineRGBColors = [0: LOPECore.RGBColor(red: 1, green: 2, blue: 3)]

    model.applyRGBZones(
      [ParsedRGBZone(index: 0, color: LOPECore.RGBColor(red: 9, green: 9, blue: 9))],
      profileFormat: 5)

    XCTAssertTrue(model.rgbZones.isEmpty)
    XCTAssertTrue(model.baselineRGBColors.isEmpty)
    XCTAssertFalse(model.rgbEditingAllZones)
  }

  func testApplyRGBZonesPopulatesOnlyDescriptorZonesFromParsedInput() {
    let model = AppModel(startInitialRefresh: false)
    configureRGBCapableDevice(model)

    let primary = LOPECore.RGBColor(red: 0x10, green: 0x20, blue: 0x30)
    let logo = LOPECore.RGBColor(red: 0x40, green: 0x50, blue: 0x60)
    model.applyRGBZones(
      [
        ParsedRGBZone(index: 0, color: primary),
        ParsedRGBZone(index: 1, color: logo),
        // Not a descriptor zone for this device; must be dropped silently.
        ParsedRGBZone(index: 9, color: LOPECore.RGBColor(red: 1, green: 1, blue: 1)),
      ],
      profileFormat: 5
    )

    XCTAssertEqual(model.rgbZones.map(\.id), [0, 1])
    XCTAssertEqual(model.rgbZones.map(\.name), ["Primary", "Logo"])
    XCTAssertEqual(model.rgbZones.first(where: { $0.id == 0 })?.current, primary)
    XCTAssertEqual(model.rgbZones.first(where: { $0.id == 0 })?.draft, primary)
    XCTAssertEqual(model.baselineRGBColors, [0: primary, 1: logo])
  }

  func testApplyRGBZonesPopulatesBaseG502Zones() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.devices = [
      DeviceChoice(
        id: 1,
        name: "G502",
        connection: "Wired",
        productID: "0xC08B",
        deviceKey: "test-device"
      )
    ]
    model.selectedDeviceIndex = 1
    model.currentDeviceName = "G502"

    let primary = LOPECore.RGBColor(red: 0x10, green: 0x20, blue: 0x30)
    let logo = LOPECore.RGBColor(red: 0x40, green: 0x50, blue: 0x60)
    model.applyRGBZones(
      [
        ParsedRGBZone(index: 0, color: primary),
        ParsedRGBZone(index: 1, color: logo),
      ],
      profileFormat: 5
    )

    XCTAssertTrue(model.shouldShowRGBEditor)
    XCTAssertEqual(model.rgbZones.map(\.name), ["Primary", "Logo"])
  }

  func testApplyRGBZonesSkipsDescriptorZonesMissingFromParsedInput() {
    let model = AppModel(startInitialRefresh: false)
    configureRGBCapableDevice(model)

    let logo = LOPECore.RGBColor(red: 0x40, green: 0x50, blue: 0x60)
    // Only the Logo zone (index 1) was parsed; Primary (index 0) is absent.
    model.applyRGBZones([ParsedRGBZone(index: 1, color: logo)], profileFormat: 5)

    XCTAssertEqual(model.rgbZones.map(\.id), [1])
    XCTAssertEqual(model.baselineRGBColors, [1: logo])
  }

  func testApplyRGBZonesRejectsUnsupportedProfileFormat() {
    let model = AppModel(startInitialRefresh: false)
    configureRGBCapableDevice(model)

    model.applyRGBZones(
      [ParsedRGBZone(index: 0, color: LOPECore.RGBColor(red: 1, green: 2, blue: 3))],
      profileFormat: 7)

    XCTAssertTrue(model.rgbZones.isEmpty)
  }

  func testBeginRGBEditIgnoresUnknownZone() {
    let model = AppModel(startInitialRefresh: false)
    configureRGBCapableDevice(model)
    model.rgbZones = [
      RGBZoneState(
        id: 0, name: "Primary", current: LOPECore.RGBColor(red: 1, green: 2, blue: 3),
        draft: LOPECore.RGBColor(red: 1, green: 2, blue: 3))
    ]
    let statusBefore = model.status

    model.beginRGBEdit(zoneID: 42, allZones: true)

    XCTAssertFalse(model.rgbEditingAllZones)
    XCTAssertEqual(model.status, statusBefore)
  }

  func testBeginRGBEditSingleZoneDoesNotAnnounceAllZonesMessage() {
    let model = AppModel(startInitialRefresh: false)
    configureRGBCapableDevice(model)
    model.rgbZones = [
      RGBZoneState(
        id: 0, name: "Primary", current: LOPECore.RGBColor(red: 1, green: 2, blue: 3),
        draft: LOPECore.RGBColor(red: 1, green: 2, blue: 3))
    ]
    let statusBefore = model.status

    model.beginRGBEdit(zoneID: 0, allZones: false)

    XCTAssertFalse(model.rgbEditingAllZones)
    XCTAssertEqual(model.status, statusBefore)
  }

  func testBeginRGBEditAllZonesAnnouncesStatusAndSetsFlag() {
    let model = AppModel(startInitialRefresh: false)
    configureRGBCapableDevice(model)
    model.rgbZones = [
      RGBZoneState(
        id: 0, name: "Primary", current: LOPECore.RGBColor(red: 1, green: 2, blue: 3),
        draft: LOPECore.RGBColor(red: 1, green: 2, blue: 3)),
      RGBZoneState(
        id: 1, name: "Logo", current: LOPECore.RGBColor(red: 4, green: 5, blue: 6),
        draft: LOPECore.RGBColor(red: 4, green: 5, blue: 6)),
    ]

    model.beginRGBEdit(zoneID: 1, allZones: true)

    XCTAssertTrue(model.rgbEditingAllZones)
    XCTAssertEqual(
      model.status, "Editing all RGB zones. Choose a color for every advertised zone.")
  }

  func testSetRGBColorUpdatesOnlyTargetZoneWhenNotEditingAllZones() {
    let model = AppModel(startInitialRefresh: false)
    configureRGBCapableDevice(model)
    model.rgbZones = [
      RGBZoneState(
        id: 0, name: "Primary", current: LOPECore.RGBColor(red: 1, green: 2, blue: 3),
        draft: LOPECore.RGBColor(red: 1, green: 2, blue: 3)),
      RGBZoneState(
        id: 1, name: "Logo", current: LOPECore.RGBColor(red: 4, green: 5, blue: 6),
        draft: LOPECore.RGBColor(red: 4, green: 5, blue: 6)),
    ]
    model.beginRGBEdit(zoneID: 0, allZones: false)

    let chosen = LOPECore.RGBColor(red: 0xAA, green: 0xBB, blue: 0xCC)
    model.setRGBColor(zoneID: 0, color: chosen)

    XCTAssertEqual(model.rgbZones.first(where: { $0.id == 0 })?.draft, chosen)
    XCTAssertEqual(
      model.rgbZones.first(where: { $0.id == 1 })?.draft,
      LOPECore.RGBColor(red: 4, green: 5, blue: 6))
  }

  func testSetRGBColorUpdatesAllZonesWhenEditingAllZones() {
    let model = AppModel(startInitialRefresh: false)
    configureRGBCapableDevice(model)
    model.rgbZones = [
      RGBZoneState(
        id: 0, name: "Primary", current: LOPECore.RGBColor(red: 1, green: 2, blue: 3),
        draft: LOPECore.RGBColor(red: 1, green: 2, blue: 3)),
      RGBZoneState(
        id: 1, name: "Logo", current: LOPECore.RGBColor(red: 4, green: 5, blue: 6),
        draft: LOPECore.RGBColor(red: 4, green: 5, blue: 6)),
    ]
    model.beginRGBEdit(zoneID: 0, allZones: true)

    let chosen = LOPECore.RGBColor(red: 0xAA, green: 0xBB, blue: 0xCC)
    model.setRGBColor(zoneID: 0, color: chosen)

    XCTAssertEqual(model.rgbZones.map(\.draft), [chosen, chosen])
  }
}
