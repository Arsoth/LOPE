// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelTests: XCTestCase {
  func testProvisionalMouseDataSuppressesDPIValidationWarning() {
    let provisionalModel = AppModel(startInitialRefresh: false)
    configureFixtureDevice(provisionalModel)
    XCTAssertNotNil(
      provisionalModel.dpiValidationMessage,
      "baseline DPI validation fixture unexpectedly became valid")

    provisionalModel.loadingProfile = true
    XCTAssertTrue(provisionalModel.isProvisionalMouseData)
    XCTAssertNil(provisionalModel.dpiValidationMessage)

    provisionalModel.loadingProfile = false
    provisionalModel.waitingForKnownDevice = true
    XCTAssertTrue(provisionalModel.isProvisionalMouseData)
    XCTAssertNil(provisionalModel.dpiValidationMessage)
  }

  func testBuiltInAndCustomMouseProfileCountsReflectCatalog() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    XCTAssertEqual(model.builtInMouseProfileCount, MouseProfileCatalog.shared.builtInProfileCount)
    XCTAssertEqual(model.customMouseProfileCount, MouseProfileCatalog.shared.customProfileCount)
    XCTAssertGreaterThan(model.builtInMouseProfileCount, 0)
  }

  func testKnownDeviceRefreshGuidanceReflectsDisconnectedDeviceCatalogMatch() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    XCTAssertNil(model.knownDeviceRefreshGuidance)

    model.knownDisconnectedDevice = DeviceChoice(
      id: 9, name: "G604", connection: "Wireless", productID: "0x4085",
      deviceKey: "g604-disconnected"
    )
    XCTAssertNotNil(model.knownDeviceRefreshGuidance)
  }

  func testShouldShowButtonEditorAcrossLoadingProfilesAndMXClassification() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    XCTAssertTrue(model.shouldShowButtonEditor)

    model.loadingProfile = true
    XCTAssertFalse(model.shouldShowButtonEditor)
    model.loadingProfile = false

    model.profiles = []
    XCTAssertFalse(model.shouldShowButtonEditor)
    model.profiles = [ProfileChoice(id: 2, sector: "0x0100", enabled: true, crcValid: true)]

    model.devices = [
      DeviceChoice(
        id: 1, name: "MX Master 3S", connection: "Bluetooth", productID: "0x0000",
        deviceKey: "mx-test")
    ]
    model.currentDeviceName = "MX Master 3S"
    XCTAssertFalse(
      model.shouldShowButtonEditor,
      "an MX mouse without a specific catalog profile should not show generic button rows")
  }

  func testOnboardProfileSummaryAcrossCapacityReportingStates() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.loadingProfile = true
    XCTAssertEqual(model.onboardProfileSummary, "Onboard profiles")
    model.loadingProfile = false

    model.profiles = []
    XCTAssertEqual(model.onboardProfileSummary, "Onboard profiles")

    model.profiles = [ProfileChoice(id: 1, sector: "0x0100", enabled: true, crcValid: true)]
    model.onboardProfileCapacity = nil
    XCTAssertEqual(model.onboardProfileSummary, "Profile 1 (capacity not reported)")

    model.profiles = [
      ProfileChoice(id: 1, sector: "0x0100", enabled: true, crcValid: true),
      ProfileChoice(id: 2, sector: "0x0200", enabled: true, crcValid: true),
    ]
    XCTAssertEqual(
      model.onboardProfileSummary, "Onboard profiles (2 readable; capacity not reported)")

    model.onboardProfileCapacity = 1
    model.onboardProfileCapacityWasReported = true
    XCTAssertEqual(
      model.onboardProfileSummary, "Onboard profiles (2 readable; reported capacity inconsistent)")

    model.onboardProfileCapacity = 5
    model.onboardProfileCapacityWasReported = false
    XCTAssertEqual(
      model.onboardProfileSummary, "Onboard profiles (2 readable; capacity not reported)")

    model.profiles = [ProfileChoice(id: 1, sector: "0x0100", enabled: true, crcValid: true)]
    model.onboardProfileCapacity = 1
    model.onboardProfileCapacityWasReported = false
    XCTAssertEqual(
      model.onboardProfileSummary, "Profile 1 (1 readable; capacity not reported)")

    model.onboardProfileCapacityWasReported = true
    XCTAssertEqual(model.onboardProfileSummary, "Profile 1 of 1")

    model.profiles = [
      ProfileChoice(id: 1, sector: "0x0100", enabled: true, crcValid: true),
      ProfileChoice(id: 2, sector: "0x0200", enabled: true, crcValid: true),
    ]
    model.onboardProfileCapacity = 2
    model.onboardProfileCapacityWasReported = true
    XCTAssertEqual(model.onboardProfileSummary, "Onboard profiles (2 of 2 supported)")
  }

  func testEngineResolvesToNilWithoutBundledOrRelativeBinary() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    XCTAssertNil(model.engine)
  }

  func testResolvedEngineURLReturnsBundledURLWhenProvided() {
    // Covers the pass-through branch in resolvedEngineURL(bundled:), which
    // `engine` above only ever reaches with `bundled: nil` in this test
    // sandbox (there is no real .app bundle to resolve a resource from).
    let model = AppModel(startInitialRefresh: false)
    let bundled = URL(fileURLWithPath: "/tmp/pretend-bundled-lope")
    XCTAssertEqual(model.resolvedEngineURL(bundled: bundled), bundled)
  }

  func testDefaultConfigurationDirectoryPathMatchesDefaultConfigurationDirectory() {
    let model = AppModel(startInitialRefresh: false)
    XCTAssertEqual(
      model.defaultConfigurationDirectoryPath, model.defaultConfigurationDirectory.path)
  }

  func testSetAppearancePreferenceUpdatesDarkModeForEachOption() {
    // `NSApp` is a lazily-set global that is nil until something touches
    // `NSApplication.shared`. A plain SwiftPM test executable (not a
    // bundled .app) never does that on its own, and
    // `applyWindowAppearance` force-unwraps it, so trigger that
    // initialization first rather than crashing the whole test process.
    _ = NSApplication.shared
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let defaultsKey = "\(AppConstants.defaultsPrefix).\(AppConstants.appearancePreferenceKey)"
    defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

    model.setAppearancePreference(.light)
    XCTAssertEqual(model.appearancePreference, .light)
    XCTAssertFalse(model.isDarkAppearance)
    XCTAssertEqual(UserDefaults.standard.string(forKey: defaultsKey), "light")

    model.setAppearancePreference(.dark)
    XCTAssertEqual(model.appearancePreference, .dark)
    XCTAssertTrue(model.isDarkAppearance)

    model.setAppearancePreference(.system)
    XCTAssertEqual(model.appearancePreference, .system)
    let expectedSystemIsDark =
      (NSApp.windows.first?.effectiveAppearance ?? NSApp.effectiveAppearance)
      .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    XCTAssertEqual(model.isDarkAppearance, expectedSystemIsDark)
  }

  func testSetAppearancePreferenceUpdatesEveryOpenWindow() {
    // Covers applyWindowAppearance's `for window in NSApp.windows` loop.
    // `NSWindow` registers itself into `NSApp.windows` on init even without
    // a real app run loop, so a plain instance kept alive for the duration
    // of this test is enough to exercise the loop body.
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = NSView()
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.setAppearancePreference(.dark)

    XCTAssertEqual(window.appearance, NSAppearance(named: .darkAqua))
    XCTAssertEqual(window.contentView?.appearance, NSAppearance(named: .darkAqua))

    model.setAppearancePreference(.light)

    XCTAssertEqual(window.appearance, NSAppearance(named: .aqua))
  }

  func testHasRGBChangesReflectsZoneEdits() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    XCTAssertFalse(model.hasRGBChanges)
    // G502 X has no rgbProfile capability in its catalog descriptor, so the
    // editor should never surface for it regardless of rgbZones content.
    XCTAssertFalse(model.shouldShowRGBEditor)

    model.rgbZones = [
      RGBZoneState(
        id: 0, name: "Zone 1",
        current: RGBColor(red: 0, green: 0, blue: 0),
        draft: RGBColor(red: 255, green: 255, blue: 255)
      )
    ]
    XCTAssertTrue(model.hasRGBChanges)
    XCTAssertFalse(model.shouldShowRGBEditor)
  }

  func testHasRGBChangesReflectsModeOnlyEdits() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.rgbZones = [
      RGBZoneState(
        id: 0, name: "Zone 1",
        current: RGBColor(red: 255, green: 0, blue: 0),
        draft: RGBColor(red: 255, green: 0, blue: 0),
        currentMode: .solid,
        draftMode: .cycle
      )
    ]

    XCTAssertTrue(model.hasRGBChanges)
    XCTAssertTrue(model.hasPendingChanges)
  }

  func testInitWithStartInitialRefreshTrueAppliesAppearanceAndSchedulesBackgroundWork() async {
    // Covers the `if startInitialRefresh` branch in init(): every other
    // test in this file passes startInitialRefresh: false specifically to
    // stay isolated from this branch's background work, so it otherwise
    // has no coverage. Lets it run once here, then tears down the
    // background Task it schedules (which would otherwise keep polling
    // every 2 seconds for the rest of the test run).
    _ = NSApplication.shared
    let model = AppModel(startInitialRefresh: true)
    defer {
      model.reconnectMonitorTask?.cancel()
      model.refreshTask?.cancel()
    }

    let expectedIsDarkAppearance =
      (NSApp.windows.first?.effectiveAppearance ?? NSApp.effectiveAppearance)
      .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    XCTAssertEqual(model.isDarkAppearance, expectedIsDarkAppearance)

    // The appearance/isDarkAppearance assignments happen synchronously in
    // init(); initialRefresh()/startReconnectMonitor() run inside the
    // Task it schedules right after, so give that a moment to start.
    try? await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertNotNil(model.reconnectMonitorTask)
  }

  func testHasProfileChangesTracksEnabledStateDivergingFromBaseline() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    XCTAssertFalse(model.hasProfileChanges)
    model.profiles[0].enabled = false
    XCTAssertTrue(model.hasProfileChanges)
  }
}
