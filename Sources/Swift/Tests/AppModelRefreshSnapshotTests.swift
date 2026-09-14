// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelRefreshSnapshotTests: XCTestCase {
  private func makeSnapshot(
    devices: [DeviceChoice] = [],
    selectedDeviceIndex: Int? = nil,
    profileText: String? = nil,
    profileError: String? = nil,
    dpiText: String? = nil,
    dpiError: String? = nil,
    selectedProfileNumber: Int? = nil,
    errorMessage: String? = nil,
    accessWarning: Bool = false
  ) -> RefreshSnapshot {
    RefreshSnapshot(
      devices: devices,
      selectedDeviceIndex: selectedDeviceIndex,
      profileText: profileText,
      profileError: profileError,
      dpiText: dpiText,
      dpiError: dpiError,
      selectedProfileNumber: selectedProfileNumber,
      errorMessage: errorMessage,
      accessWarning: accessWarning
    )
  }

  // MARK: - errorMessage short-circuit

  func testApplyRefreshSnapshotWithErrorMessageClearsDevicesAndReportsFailure() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.busy = true
    model.loadingProfile = true

    model.applyRefreshSnapshot(makeSnapshot(errorMessage: "HID++ transport failed"))

    XCTAssertTrue(model.devices.isEmpty)
    XCTAssertEqual(model.deviceSummary, "Unable to access the Logitech HID++ interface")
    XCTAssertEqual(model.status, "HID++ transport failed")
    XCTAssertFalse(model.busy)
    XCTAssertFalse(model.loadingProfile)
    XCTAssertNil(model.refreshTask)
    XCTAssertTrue(model.profiles.isEmpty)
  }

  // MARK: - No selected device

  func testApplyRefreshSnapshotWithNoSelectedDeviceReportsNoMouseFound() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.applyRefreshSnapshot(makeSnapshot(selectedDeviceIndex: nil, accessWarning: false))

    XCTAssertEqual(model.selectedDeviceIndex, 0)
    XCTAssertEqual(model.currentDeviceName, "")
    XCTAssertEqual(model.deviceSummary, "No editable Logitech mouse found")
    XCTAssertNil(model.onboardProfileCapacity)
    XCTAssertTrue(model.profiles.isEmpty)
    XCTAssertTrue(model.buttons.isEmpty)
    XCTAssertEqual(model.status, "No Logitech mouse was found")
  }

  func testApplyRefreshSnapshotWithAccessWarningAndNoSelectedDeviceMentionsInputMonitoring() {
    let model = AppModel(startInitialRefresh: false)

    model.applyRefreshSnapshot(makeSnapshot(selectedDeviceIndex: nil, accessWarning: true))

    XCTAssertTrue(model.wiredAccessInstructionsPresented)
    XCTAssertTrue(model.status.contains("System Settings"))
    XCTAssertFalse(model.status.contains("No Logitech mouse was found"))

    // Dismissing the app-owned prompt and refreshing again must not create a
    // second permission flow until authorization changes.
    model.wiredAccessInstructionsPresented = false
    model.applyRefreshSnapshot(makeSnapshot(selectedDeviceIndex: nil, accessWarning: true))
    XCTAssertFalse(model.wiredAccessInstructionsPresented)
  }

  func testApplyRefreshSnapshotHidesUnauthorizedWiredDeviceUntilPopupDismisses() {
    let model = AppModel(startInitialRefresh: false)
    let wired = DeviceChoice(
      id: 1, name: "Wired Mouse", connection: "Wired", productID: "0xCCCC", deviceKey: "cccc")
    let wireless = DeviceChoice(
      id: 2, name: "Wireless Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa")

    model.applyRefreshSnapshot(
      makeSnapshot(
        devices: [wired, wireless, .wiredAccessPrompt], selectedDeviceIndex: wireless.id,
        accessWarning: true))

    XCTAssertTrue(model.wiredAccessInstructionsPresented)
    XCTAssertFalse(model.devices.contains(where: { $0.deviceKey == wired.deviceKey }))
    XCTAssertEqual(model.devices, [wireless, .wiredAccessPrompt])

    model.wiredAccessInstructionsPresented = false

    XCTAssertEqual(model.devices, [wireless, wired, .wiredAccessPrompt])
  }

  // MARK: - Selected device, no profile text

  func testApplyRefreshSnapshotDoesNotWakePollAWiredDevice() {
    let model = AppModel(startInitialRefresh: false)
    let device = DeviceChoice(
      id: 1, name: "G502 X", connection: "Wired", productID: "0x0000", deviceKey: "known-device")

    model.applyRefreshSnapshot(
      makeSnapshot(
        devices: [device], selectedDeviceIndex: 1, profileText: nil,
        profileError: "sleeping", selectedProfileNumber: nil))

    XCTAssertFalse(model.waitingForKnownDevice)
    XCTAssertFalse(model.busy)
    XCTAssertNil(model.knownDevicePollTask)
    XCTAssertTrue(model.status.contains("Choose Refresh"))
  }

  func testApplyRefreshSnapshotBeginsWakePollingForAnyNonWiredDeviceWithReadError() {
    let model = AppModel(startInitialRefresh: false)
    let device = DeviceChoice(
      id: 1, name: "Unrecognized Mouse", connection: "Bluetooth", productID: "0x9999",
      deviceKey: "unknown-device")

    model.applyRefreshSnapshot(
      makeSnapshot(
        devices: [device], selectedDeviceIndex: 1, profileText: nil,
        profileError: "timed out", selectedProfileNumber: nil))

    XCTAssertTrue(model.waitingForKnownDevice)
    XCTAssertTrue(model.busy)
    XCTAssertEqual(model.knownDisconnectedDevice, device)
    model.knownDevicePollTask?.cancel()
  }

  func testApplyRefreshSnapshotWithUnknownDeviceAndProfileErrorReportsAccessWarning() {
    let model = AppModel(startInitialRefresh: false)
    let device = DeviceChoice(
      id: 1, name: "Unrecognized Mouse", connection: "Wired", productID: "0x9999",
      deviceKey: "unknown-device")

    model.applyRefreshSnapshot(
      makeSnapshot(
        devices: [device], selectedDeviceIndex: 1, profileText: nil,
        profileError: "timed out", accessWarning: true))

    XCTAssertEqual(
      model.dpiDetails,
      "This device does not expose an editable onboard profile through HID++ 0x8100.")
    XCTAssertTrue(model.status.contains("macOS is blocking access"))
  }

  func testApplyRefreshSnapshotWithUnknownDeviceAndProfileErrorWithoutAccessWarningAsksToWake() {
    let model = AppModel(startInitialRefresh: false)
    let device = DeviceChoice(
      id: 1, name: "Unrecognized Mouse", connection: "Wired", productID: "0x9999",
      deviceKey: "unknown-device")

    model.applyRefreshSnapshot(
      makeSnapshot(
        devices: [device], selectedDeviceIndex: 1, profileText: nil,
        profileError: "timed out", accessWarning: false))

    XCTAssertTrue(model.status.contains("Choose Refresh"))
    XCTAssertFalse(model.status.contains("Wake it"))
  }

  func testApplyRefreshSnapshotWithUnknownDeviceAndNoProfileErrorReportsNoCompatibleProfile() {
    let model = AppModel(startInitialRefresh: false)
    let device = DeviceChoice(
      id: 1, name: "Unrecognized Mouse", connection: "Wired", productID: "0x9999",
      deviceKey: "unknown-device")

    model.applyRefreshSnapshot(
      makeSnapshot(devices: [device], selectedDeviceIndex: 1, profileText: nil, profileError: nil))

    XCTAssertEqual(
      model.status, "Connected to Unrecognized Mouse, but no compatible onboard profile was found."
    )
  }

  // MARK: - Selected device, profile text present but empty

  func testApplyRefreshSnapshotWithNoReadableProfilesReportsEmptyResult() {
    let model = AppModel(startInitialRefresh: false)
    let device = DeviceChoice(
      id: 1, name: "G502 X", connection: "Wired", productID: "0x0000", deviceKey: "test-device")

    model.applyRefreshSnapshot(
      makeSnapshot(
        devices: [device], selectedDeviceIndex: 1,
        profileText: "Profile capacity: 3\n"))

    XCTAssertTrue(model.profiles.isEmpty)
    XCTAssertTrue(model.buttons.isEmpty)
    XCTAssertEqual(model.status, "The mouse was found, but no onboard profiles were readable.")
  }

  // MARK: - Selected device, full profile read

  func testApplyRefreshSnapshotWithFullProfileAppliesButtonsAndDPIAndReportsSuccess() {
    let model = AppModel(startInitialRefresh: false)
    let device = DeviceChoice(
      id: 1, name: "G502 X", connection: "Wired", productID: "0x0000", deviceKey: "test-device")

    model.applyRefreshSnapshot(
      makeSnapshot(
        devices: [device], selectedDeviceIndex: 1,
        profileText: fakeProfilesOutput(), selectedProfileNumber: 2))

    XCTAssertEqual(model.profileNumber, 2)
    XCTAssertFalse(model.profiles.isEmpty)
    XCTAssertFalse(model.buttons.isEmpty)
    XCTAssertEqual(model.onboardProfileCapacity, 3)
    XCTAssertTrue(model.onboardProfileCapacityWasReported)
    XCTAssertFalse(model.waitingForKnownDevice)
    XCTAssertEqual(model.status, "Onboard Profile read successfully.")
  }

  func testApplyRefreshSnapshotFallsBackToParsedCountWhenCapacityIsNotReported() {
    let model = AppModel(startInitialRefresh: false)
    let device = DeviceChoice(
      id: 1, name: "G502 X", connection: "Wired", productID: "0x0000", deviceKey: "test-device")
    let profileText = """
      Selected profile: 2
      Profile 2 (sector 0x0100, enabled=yes)
        button 1: Left click [80 01 00 02]
      """

    model.applyRefreshSnapshot(
      makeSnapshot(devices: [device], selectedDeviceIndex: 1, profileText: profileText))

    XCTAssertEqual(model.onboardProfileCapacity, model.profiles.count)
    XCTAssertFalse(model.onboardProfileCapacityWasReported)
  }

  func testApplyRefreshSnapshotFallsBackToPreferredProfileNumberWhenSelectedIsUnavailable() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.profileNumber = 2
    let device = model.devices[0]

    model.applyRefreshSnapshot(
      makeSnapshot(
        devices: [device], selectedDeviceIndex: 1,
        profileText: fakeProfilesOutput(selectedProfile: 99), selectedProfileNumber: 99))

    // 99 is not a real profile id, so resolution falls back to the
    // preferred profile number already selected before the refresh.
    XCTAssertEqual(model.profileNumber, 2)
  }

  func testApplyRefreshSnapshotUsesDPIErrorWhenNoDPIDetailsWereParsed() {
    let model = AppModel(startInitialRefresh: false)
    let device = DeviceChoice(
      id: 1, name: "G502 X", connection: "Wired", productID: "0x0000", deviceKey: "test-device")
    let profileText = """
      Selected profile: 2
      Profile 2 (sector 0x0100, enabled=yes)
        button 1: Left click [80 01 00 02]
      """

    model.applyRefreshSnapshot(
      makeSnapshot(
        devices: [device], selectedDeviceIndex: 1, profileText: profileText,
        dpiError: "DPI feature not present"))

    XCTAssertEqual(model.dpiDetails, "DPI feature not present")
  }

  func testApplyRefreshSnapshotReportsAccessWarningForWiredNonMXDevice() {
    let model = AppModel(startInitialRefresh: false)
    let device = DeviceChoice(
      id: 1, name: "G502 X", connection: "Wired", productID: "0x0000", deviceKey: "test-device")

    model.applyRefreshSnapshot(
      makeSnapshot(
        devices: [device], selectedDeviceIndex: 1, profileText: fakeProfilesOutput(),
        accessWarning: true))

    XCTAssertTrue(model.status.contains("Some Logitech interfaces were denied"))
  }

  // MARK: - resetEditorState / prepareLoadingEditor / resetDPIState

  func testResetEditorStateClearsProfileAndDPIAndRGBState() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.onboardProfileCapacity = 4
    model.onboardProfileCapacityWasReported = true
    let black = LOPECore.RGBColor(red: 0, green: 0, blue: 0)
    model.rgbZones = [RGBZoneState(id: 0, name: "Logo", current: black, draft: black)]
    model.baselineRGBColors = [0: black]
    model.rgbEditingAllZones = true

    model.resetEditorState()

    XCTAssertNil(model.onboardProfileCapacity)
    XCTAssertFalse(model.onboardProfileCapacityWasReported)
    XCTAssertTrue(model.profiles.isEmpty)
    XCTAssertTrue(model.buttons.isEmpty)
    XCTAssertTrue(model.normalButtonRows.isEmpty)
    XCTAssertTrue(model.gShiftButtonRows.isEmpty)
    XCTAssertEqual(model.buttonLayer, .normal)
    XCTAssertTrue(model.baselineProfileEnabled.isEmpty)
    XCTAssertTrue(model.keyInputDrafts.isEmpty)
    XCTAssertTrue(model.rgbZones.isEmpty)
    XCTAssertTrue(model.baselineRGBColors.isEmpty)
    XCTAssertFalse(model.rgbEditingAllZones)
    XCTAssertNil(model.liveDPIPollTask)
  }

  func testPrepareLoadingEditorClampsZeroProfileNumberToOne() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.prepareLoadingEditor(profileNumber: 0)

    XCTAssertEqual(model.profileNumber, 1)
    XCTAssertEqual(model.profiles.map(\.id), [1])
    XCTAssertEqual(model.baselineProfileEnabled, [1: true])
    XCTAssertEqual(model.dpiDetails, "Loading DPI capabilities from the mouse…")
  }

  func testPrepareLoadingEditorKeepsPositiveProfileNumber() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.prepareLoadingEditor(profileNumber: 3)

    XCTAssertEqual(model.profileNumber, 3)
    XCTAssertEqual(model.profiles.map(\.id), [3])
  }

  func testResetDPIStateRestoresDefaults() {
    let model = AppModel(startInitialRefresh: false)
    model.dpiStages = ["100", "200", "", "", ""]
    model.dpiCount = 2
    model.defaultStage = 2
    model.shiftStage = 2
    model.dpiCapabilities = DPICapabilities(sensorCount: 2)
    model.pollingRateCapabilities = PollingRateCapabilities(supportedRates: [500], currentRate: 500)
    model.pollingRateDraft = 500
    model.baselinePollingRate = 500

    model.resetDPIState()

    XCTAssertEqual(model.dpiStages, ["", "", "", "", ""])
    XCTAssertEqual(model.dpiCount, 5)
    XCTAssertEqual(model.defaultStage, 1)
    XCTAssertEqual(model.shiftStage, 1)
    XCTAssertEqual(model.dpiCapabilities, DPICapabilities())
    XCTAssertEqual(model.pollingRateCapabilities, PollingRateCapabilities())
    XCTAssertNil(model.pollingRateDraft)
    XCTAssertNil(model.baselinePollingRate)
    XCTAssertEqual(model.baselineDPIStages, ["", "", "", "", ""])
    XCTAssertEqual(model.baselineDPICount, 5)
    XCTAssertEqual(model.baselineDefaultStage, 1)
    XCTAssertEqual(model.baselineShiftStage, 1)
    XCTAssertEqual(model.dpiDetails, "DPI capabilities have not been read.")
  }

  // MARK: - profileReadStatus

  func testProfileReadStatusWarnsAboutMacOSBlockingForNonMXDevice() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    let status = model.profileReadStatus(for: "G502 X", accessWarning: true)

    XCTAssertTrue(status.contains("macOS is blocking access to G502 X"))
  }

  func testProfileReadStatusAsksToWakeMouseWhenNoAccessWarning() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    let status = model.profileReadStatus(for: "G502 X", accessWarning: false)

    XCTAssertTrue(status.contains("Choose Refresh"))
  }

  func testProfileReadStatusIgnoresAccessWarningForMXSeriesMouse() {
    let model = AppModel(startInitialRefresh: false)
    model.devices = [
      DeviceChoice(
        id: 1, name: "MX Master 3S", connection: "Wireless", productID: "0xB034",
        deviceKey: "mx-device")
    ]
    model.selectedDeviceIndex = 1
    model.currentDeviceName = "MX Master 3S"

    let status = model.profileReadStatus(for: "MX Master 3S", accessWarning: true)

    XCTAssertTrue(status.contains("Wake it"))
  }
}
