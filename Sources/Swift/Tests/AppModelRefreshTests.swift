// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelRefreshTests: XCTestCase {
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
        profileText: nil,
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

  func testSelectDevicePresentsWiredAccessInstructionsForPromptEntry() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.devices.append(.wiredAccessPrompt)
    let previousIndex = model.selectedDeviceIndex

    model.selectDevice(DeviceChoice.wiredAccessPromptID)

    XCTAssertTrue(model.wiredAccessInstructionsPresented)
    XCTAssertEqual(model.selectedDeviceIndex, previousIndex)
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
    model.engineRunnerOverride = { _ in fakeProfilesOutput() }

    model.reloadSelectedProfileContents()

    XCTAssertFalse(model.buttons.isEmpty)
    XCTAssertEqual(model.status, "Reloaded profile 2.")
  }

  func testReloadSelectedProfileContentsReportsEngineError() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.engineRunnerOverride = { _ in throw EngineError.failed("engine offline") }

    model.reloadSelectedProfileContents()

    XCTAssertEqual(model.status, "engine offline")
  }
}
