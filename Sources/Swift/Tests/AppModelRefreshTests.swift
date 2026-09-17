// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelRefreshTests: XCTestCase {
  func testInputMonitoringSettingsRetriesDeniedRequestAndAlwaysOpensPane() {
    let model = AppModel(startInitialRefresh: false)
    model.inputMonitoringAuthorized = false
    model.inputMonitoringRequestInProgress = true
    model.busy = true
    model.loadingProfile = true
    let refreshTask = Task<Void, Never> {}
    let devicePollTask = Task<Void, Never> {}
    let dpiPollTask = Task<Void, Never> {}
    model.refreshTask = refreshTask
    model.knownDevicePollTask = devicePollTask
    model.liveDPIPollTask = dpiPollTask
    var events: [String] = []

    for _ in 0..<2 {
      model.openInputMonitoringSettings(
        requestAccess: {
          XCTAssertTrue(model.inputMonitoringRequestInProgress)
          events.append("request")
        },
        openSettings: {
          XCTAssertFalse(model.inputMonitoringRequestInProgress)
          events.append("open")
        })
    }

    XCTAssertEqual(events, ["request", "open", "request", "open"])
    XCTAssertTrue(refreshTask.isCancelled)
    XCTAssertTrue(devicePollTask.isCancelled)
    XCTAssertTrue(dpiPollTask.isCancelled)
    XCTAssertNil(model.refreshTask)
    XCTAssertNil(model.knownDevicePollTask)
    XCTAssertNil(model.liveDPIPollTask)
    XCTAssertFalse(model.busy)
    XCTAssertFalse(model.loadingProfile)
    XCTAssertFalse(model.inputMonitoringRequestInProgress)
  }

  func testInputMonitoringSettingsOpensPaneWhenRequestGrantsAccess() {
    let model = AppModel(startInitialRefresh: false)
    model.inputMonitoringAuthorized = false
    var opened = false
    model.openInputMonitoringSettings(
      requestAccess: { model.inputMonitoringAuthorized = true },
      openSettings: { opened = true })
    XCTAssertTrue(opened)
    XCTAssertFalse(model.inputMonitoringRequestInProgress)
  }

  func testInputMonitoringSettingsAlreadyAuthorizedOnlyOpensPane() {
    let model = AppModel(startInitialRefresh: false)
    model.inputMonitoringAuthorized = true
    var opened = false
    model.openInputMonitoringSettings(
      requestAccess: { XCTFail("Already authorized") },
      openSettings: { opened = true })
    XCTAssertTrue(opened)
  }

  func testSleepingDeviceTransitionKeepsUnderlyingProfileSurface() {
    let sleepingModel = AppModel(startInitialRefresh: false)
    sleepingModel.devices = [
      DeviceChoice(
        id: 1,
        name: "G603",
        connection: "Wireless",
        productID: "0xB01C",
        deviceKey: "sleeping-device"
      )
    ]
    sleepingModel.selectedDeviceIndex = 1
    sleepingModel.currentDeviceName = "G603"
    sleepingModel.buttons = [
      ButtonRow(
        id: 1,
        label: "G1 · Primary click",
        currentRaw: "80010001",
        draftRaw: "80010001",
        draftChoice: "80010001",
        layer: .normal
      )
    ]
    sleepingModel.profiles = [
      ProfileChoice(
        id: 1,
        sector: "0x0100",
        enabled: true,
        crcValid: nil
      )
    ]
    sleepingModel.applyRefreshSnapshot(
      RefreshSnapshot(
        devices: sleepingModel.devices,
        selectedDeviceIndex: 1,
        profileError: "sleeping",
        dpiText: nil,
        dpiError: nil,
        selectedProfileNumber: nil,
        errorMessage: nil,
        accessWarning: false
      ))
    XCTAssertTrue(sleepingModel.waitingForKnownDevice)
    XCTAssertTrue(sleepingModel.busy)
    XCTAssertFalse(sleepingModel.buttons.isEmpty)
    XCTAssertFalse(sleepingModel.profiles.isEmpty)
    sleepingModel.knownDevicePollTask?.cancel()
  }

  override func tearDown() {
    FakeEngineEnvironment.clearAll()
    super.tearDown()
  }

  private let lastSelectedDeviceDefaultsKey =
    "\(AppConstants.defaultsPrefix).\(AppConstants.lastSelectedDeviceKey)"

  // MARK: - refresh()

  func testRefreshReportsEngineUnavailableAndClearsPollingState() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.refresh()

    XCTAssertEqual(model.status, EngineError.unavailable.localizedDescription)
    XCTAssertFalse(model.busy)
    XCTAssertFalse(model.loadingProfile)
    XCTAssertNil(model.liveDPIPollTask)
    XCTAssertFalse(model.waitingForKnownDevice)
  }

  func testRefreshPassesKnownDisconnectedDeviceAsExpectedDevice() async {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    // Discovery finds a different device than the one being watched for, so
    // a successful pass-through of `knownDisconnectedDevice` as the
    // expected device is observable via the known-device-unavailable path.
    FakeEngineEnvironment.set(
      "LOPE_TEST_LIST_OUTPUT", fakeDeviceListLine(deviceKey: "1234abcd") + "\n")
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)
    let expected = DeviceChoice(
      id: 1, name: "G603", connection: "Wireless", productID: "0xB01C", deviceKey: "deadbeef")
    model.knownDisconnectedDevice = expected
    model.selectedDeviceIndex = 1
    model.profileNumber = 1

    let originalDirectory = FileManager.default.currentDirectoryPath
    FileManager.default.changeCurrentDirectoryPath(tempDir.path)
    model.refresh()
    await waitUntil(timeout: 5) { model.waitingForKnownDevice }
    FileManager.default.changeCurrentDirectoryPath(originalDirectory)

    XCTAssertEqual(model.knownDisconnectedDevice, expected)
    model.knownDevicePollTask?.cancel()
    model.stopKnownDevicePolling(clearDevice: true)
  }

  // MARK: - initialRefresh()

  func testInitialRefreshCallsRefreshWhenNoDeviceWasCached() {
    let defaults = UserDefaults.standard
    let previousValue = defaults.data(forKey: lastSelectedDeviceDefaultsKey)
    defaults.removeObject(forKey: lastSelectedDeviceDefaultsKey)
    defer {
      if let previousValue {
        defaults.set(previousValue, forKey: lastSelectedDeviceDefaultsKey)
      } else {
        defaults.removeObject(forKey: lastSelectedDeviceDefaultsKey)
      }
    }
    let model = AppModel(startInitialRefresh: false)

    model.initialRefresh()

    XCTAssertEqual(model.status, EngineError.unavailable.localizedDescription)
    XCTAssertEqual(model.currentDeviceName, "")
  }

  func testInitialRefreshUsesCachedDeviceWhenAvailable() {
    let defaults = UserDefaults.standard
    let previousValue = defaults.data(forKey: lastSelectedDeviceDefaultsKey)
    defer {
      if let previousValue {
        defaults.set(previousValue, forKey: lastSelectedDeviceDefaultsKey)
      } else {
        defaults.removeObject(forKey: lastSelectedDeviceDefaultsKey)
      }
    }
    let model = AppModel(startInitialRefresh: false)
    let cached = DeviceChoice(
      id: 1, name: "G502 X", connection: "Wired", productID: "0x0000", deviceKey: "abc123ef")
    model.rememberSelectedDevice(cached)

    model.initialRefresh()

    // startInitialRefresh's engine-unavailable branch sets currentDeviceName
    // from the cached device before bailing out, proving the cached value
    // (not the no-device `refresh()` path) was used.
    XCTAssertEqual(model.currentDeviceName, "G502 X")
    XCTAssertEqual(model.devices, [cached])
    XCTAssertEqual(model.status, EngineError.unavailable.localizedDescription)
  }

  // MARK: - selectDevice(_:)

  func testSelectDeviceIgnoresUnknownIndex() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let previousIndex = model.selectedDeviceIndex

    model.selectDevice(999)

    XCTAssertEqual(model.selectedDeviceIndex, previousIndex)
  }

  func testSelectDevicePresentsWiredAccessInstructionsForBlockedWiredDevice() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.inputMonitoringAuthorized = false

    model.selectDevice(model.selectedDeviceIndex)

    XCTAssertTrue(model.wiredAccessInstructionsPresented)
    XCTAssertEqual(model.wiredAccessDeviceName, "G502 X")
    XCTAssertEqual(model.selectedDeviceIndex, 1)
  }

  func testPresentWiredAccessInstructionsUsesFirstWiredDeviceAndDoesNotReplaceIt() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.presentWiredAccessInstructions()
    model.presentWiredAccessInstructions(
      for: DeviceChoice(
        id: 2, name: "Other Wired Mouse", connection: "Wired", productID: "0x1234",
        deviceKey: "other"))

    XCTAssertTrue(model.wiredAccessInstructionsPresented)
    XCTAssertEqual(model.wiredAccessDeviceName, "G502 X")
  }

  func testShowInputMonitoringRequirementLeavesRealDeviceSelected() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.showInputMonitoringRequirement(for: model.devices[0])

    XCTAssertEqual(model.selectedDeviceIndex, 1)
    XCTAssertEqual(model.deviceSummary, "G502 X — Wired")
    XCTAssertFalse(model.loadingProfile)
    XCTAssertFalse(model.busy)
    XCTAssertFalse(model.status.contains("Allow wired mice"))
    XCTAssertTrue(model.status.contains("Input Monitoring"))
  }

  func testSelectDeviceIgnoresReselectingTheCurrentDevice() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.recoveryBackups = [URL(fileURLWithPath: "/tmp/should-remain")]

    model.selectDevice(model.selectedDeviceIndex)

    XCTAssertEqual(model.recoveryBackups, [URL(fileURLWithPath: "/tmp/should-remain")])
  }

  func testSelectDeviceSwitchesDeviceAndStartsRefresh() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.devices.append(
      DeviceChoice(
        id: 2, name: "G603", connection: "Wireless", productID: "0xB01C", deviceKey: "other"))
    model.recoveryBackups = [URL(fileURLWithPath: "/tmp/stale-recovery")]
    model.recoveryDeviceKey = "stale-key"

    model.selectDevice(2)

    XCTAssertEqual(model.selectedDeviceIndex, 2)
    XCTAssertEqual(model.currentDeviceName, "G603")
    XCTAssertTrue(model.recoveryBackups.isEmpty)
    XCTAssertNil(model.recoveryDeviceKey)
    // startRefresh's engine-unavailable guard fires immediately in tests.
    XCTAssertEqual(model.status, EngineError.unavailable.localizedDescription)
  }

  // MARK: - updateInputMonitoringAuthorization()

  func testUpdateInputMonitoringAuthorizationReflectsCurrentAccess() {
    let model = AppModel(startInitialRefresh: false)

    model.updateInputMonitoringAuthorization()

    XCTAssertEqual(
      model.inputMonitoringAuthorized,
      IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)
  }

  // MARK: - reloadSelectedProfile()

  func testReloadSelectedProfileDoesNothingWhileBusy() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.busy = true
    model.status = "unchanged"

    model.reloadSelectedProfile()

    XCTAssertEqual(model.status, "unchanged")
  }

  func testReloadSelectedProfileDoesNothingWhenNoProfilesAreLoaded() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.profiles = []
    model.status = "unchanged"

    model.reloadSelectedProfile()

    XCTAssertEqual(model.status, "unchanged")
  }

  func testReloadSelectedProfileDelegatesToRefresh() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)

    model.reloadSelectedProfile()

    XCTAssertEqual(model.status, EngineError.unavailable.localizedDescription)
  }

  // MARK: - reloadSelectedProfileContents()

  func testReloadSelectedProfileContentsAppliesEngineOutput() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.engineRunnerOverride = { _ in fakeStructuredProfilesOutput() }

    model.reloadSelectedProfileContents()

    XCTAssertFalse(model.buttons.isEmpty)
    XCTAssertEqual(model.status, "Reloaded profile 2.")
  }

  func testReloadSelectedProfileContentsHandlesUnavailableOptionalCapabilities() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let output = fakeStructuredProfilesOutput()
      .replacingOccurrences(
        of:
          #""dpi":{"requested":true,"available":true,"sensor_count":1,"supported_values":[400,800,1600],"current_sensor_dpi":800,"error":""},"#,
        with: #""dpi":null,"#
      )
      .replacingOccurrences(
        of:
          #""report_rate":{"requested":true,"available":true,"feature_id":32864,"rates":[{"hertz":125,"wire_value":8},{"hertz":500,"wire_value":2},{"hertz":1000,"wire_value":1}],"current_valid":true,"current_hertz":500,"error":""}"#,
        with: #""report_rate":null"#)
    model.engineRunnerOverride = { _ in output }

    model.reloadSelectedProfileContents()

    XCTAssertEqual(model.status, "Reloaded profile 2.")
    XCTAssertEqual(model.dpiDetails, "DPI capabilities have not been read.")
    XCTAssertNil(model.pollingRateCapabilities.currentRate)
  }

  func testReloadSelectedProfileContentsReportsMissingSelectedProfile() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.engineRunnerOverride = { _ in fakeStructuredProfilesWithoutSelectionOutput() }

    model.reloadSelectedProfileContents()

    XCTAssertEqual(model.status, "The selected onboard profile was not returned.")
  }

  func testReloadSelectedProfileContentsReportsEngineError() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.engineRunnerOverride = { _ in throw EngineError.failed("engine offline") }

    model.reloadSelectedProfileContents()

    XCTAssertEqual(model.status, "engine offline")
  }
}
