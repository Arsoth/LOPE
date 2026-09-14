// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelRefreshLifecycleTests: XCTestCase {
  override func tearDown() {
    FakeEngineEnvironment.clearAll()
    super.tearDown()
  }

  private func fixtureDevice(deviceKey: String = "abc123ef") -> DeviceChoice {
    DeviceChoice(
      id: 1, name: "G502 X", connection: "Wired", productID: "0x0000", deviceKey: deviceKey)
  }

  /// `startInitialRefresh`/`startRefresh` can internally re-dispatch to
  /// another top-level method that reads `AppModel.engine` fresh (e.g. the
  /// stale-cached-key fallback, or a known-device probe fired from a poll
  /// loop) -- unlike the single Task body case, that second read happens
  /// later, asynchronously. Keeping the working directory swapped for the
  /// whole async operation (not just the synchronous entry call) makes sure
  /// `engine` still resolves at that later point too.
  private func withFakeEngineDirectory<T>(
    _ path: String, _ operation: () async -> T
  ) async -> T {
    let original = FileManager.default.currentDirectoryPath
    FileManager.default.changeCurrentDirectoryPath(path)
    defer { FileManager.default.changeCurrentDirectoryPath(original) }
    return await operation()
  }

  // MARK: - errorMessage(for:)

  func testErrorMessageForwardsLocalizedDescription() {
    XCTAssertEqual(
      AppModel.errorMessage(for: EngineError.failed("boom")), "boom")
    XCTAssertEqual(
      AppModel.errorMessage(for: EngineError.unavailable),
      EngineError.unavailable.localizedDescription)
  }

  // MARK: - makeProfileSnapshot / runProfileReadWithRetry

  func testMakeProfileSnapshotReturnsSnapshotOnFirstSuccess() {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let engine = FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_OUTPUT", fakeProfilesOutput())
    defer { FakeEngineEnvironment.clearAll() }

    let snapshot = AppModel.makeProfileSnapshot(
      executable: engine,
      currentDirectory: tempDir,
      devices: [fixtureDevice()],
      selectedDeviceKey: "abc123ef",
      selectedDeviceIndex: 1,
      preferredProfileNumber: 2
    )

    XCTAssertNotNil(snapshot.profileText)
    XCTAssertEqual(snapshot.selectedProfileNumber, 2)
    XCTAssertNil(snapshot.profileError)
    XCTAssertNil(snapshot.errorMessage)
  }

  func testMakeProfileSnapshotRetriesUntilSelectedProfileMarkerAppears() {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let engine = FakeEngine.write(to: tempDir)
    let counterURL = tempDir.appendingPathComponent("profiles-counter")
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_COUNTER", counterURL.path)
    // The first two attempts return header-only output (no "Selected
    // profile:" marker), matching a transient HID++ timeout; the retry loop
    // must keep trying rather than treating that as success.
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_FAIL_UNTIL", "2")
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_FAIL_OUTPUT", "Profile capacity: 3\n")
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_FAIL_EXIT", "0")
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_OUTPUT", fakeProfilesOutput())
    defer { FakeEngineEnvironment.clearAll() }

    let snapshot = AppModel.makeProfileSnapshot(
      executable: engine,
      currentDirectory: tempDir,
      devices: [fixtureDevice()],
      selectedDeviceKey: "abc123ef",
      selectedDeviceIndex: 1,
      preferredProfileNumber: 2
    )

    XCTAssertNotNil(snapshot.profileText)
    XCTAssertEqual(snapshot.selectedProfileNumber, 2)
    XCTAssertEqual((try? String(contentsOf: counterURL, encoding: .utf8)), "3")
  }

  func testMakeProfileSnapshotReturnsProfileErrorAfterExhaustingRetries() {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let engine = FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_EXIT", "1")
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_OUTPUT", "engine offline")
    defer { FakeEngineEnvironment.clearAll() }

    let snapshot = AppModel.makeProfileSnapshot(
      executable: engine,
      currentDirectory: tempDir,
      devices: [fixtureDevice()],
      selectedDeviceKey: "abc123ef",
      selectedDeviceIndex: 1,
      preferredProfileNumber: 2
    )

    XCTAssertNil(snapshot.profileText)
    XCTAssertEqual(snapshot.profileError, "engine offline")
  }

  func testMakeProfileSnapshotOmitsProfileFlagWhenPreferredProfileIsZero() {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let engine = FakeEngine.write(to: tempDir)
    let logURL = tempDir.appendingPathComponent("args.log")
    FakeEngineEnvironment.set("LOPE_TEST_ARGS_LOG", logURL.path)
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_OUTPUT", fakeProfilesOutput())
    defer { FakeEngineEnvironment.clearAll() }

    _ = AppModel.makeProfileSnapshot(
      executable: engine,
      currentDirectory: tempDir,
      devices: [fixtureDevice()],
      selectedDeviceKey: "abc123ef",
      selectedDeviceIndex: 1,
      preferredProfileNumber: 0
    )

    let loggedArgs = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    XCTAssertFalse(loggedArgs.contains("--profile"), loggedArgs)
  }

  func testMakeProfileSnapshotUsesSpecificPairedModelNameFromProfileOutput() {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let engine = FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set(
      "LOPE_TEST_PROFILES_OUTPUT",
      "Onboard profiles for Paired Logitech Mouse - Lightspeed:\nDevice: G604\n"
        + fakeProfilesOutput())
    defer { FakeEngineEnvironment.clearAll() }

    let generic = DeviceChoice(
      id: 1, name: "Paired Logitech Mouse - Lightspeed", connection: "Wireless",
      productID: "0x4085", deviceKey: "abc123ef")
    let snapshot = AppModel.makeProfileSnapshot(
      executable: engine,
      currentDirectory: tempDir,
      devices: [generic],
      selectedDeviceKey: generic.deviceKey,
      selectedDeviceIndex: generic.id,
      preferredProfileNumber: 1
    )

    XCTAssertEqual(snapshot.devices.first?.name, "G604")
  }

  // MARK: - startInitialRefresh

  func testStartInitialRefreshReportsEngineUnavailable() {
    let model = AppModel(startInitialRefresh: false)
    let cached = fixtureDevice()

    model.startInitialRefresh(cachedDevice: cached)

    XCTAssertFalse(model.busy)
    XCTAssertFalse(model.loadingProfile)
    XCTAssertEqual(model.status, EngineError.unavailable.localizedDescription)
    XCTAssertEqual(model.currentDeviceName, cached.name)
    XCTAssertNil(model.refreshTask)
  }

  func testStartInitialRefreshAppliesProfileSnapshotOnSuccess() async {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_OUTPUT", fakeProfilesOutput())
    FakeEngineEnvironment.set("LOPE_TEST_LIST_OUTPUT", fakeDeviceListLine() + "\n")
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)
    let cached = fixtureDevice()

    await withFakeEngineDirectory(tempDir.path) {
      model.startInitialRefresh(cachedDevice: cached)
      await waitUntil { !model.profiles.isEmpty }
      await waitUntil { !model.busy }
      // The background device-list refresh runs after the profile read
      // succeeds; wait for it while the fake engine is still reachable so
      // it settles before the working directory is restored.
      await waitUntil { model.devices.contains(where: { $0.deviceKey == "abc123ef" }) }
    }

    XCTAssertFalse(model.loadingProfile)
    XCTAssertEqual(model.status, "Onboard Profile read successfully.")
    model.stopLiveDPIPolling()
  }

  func testStartInitialRefreshFallsBackToFullDiscoveryWhenCachedKeyIsStale() async {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    let counterURL = tempDir.appendingPathComponent("profiles-counter")
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_COUNTER", counterURL.path)
    // Fail every attempt made while probing the stale cached key (5 of
    // them), then succeed once the normal discovery path retries with a
    // freshly enumerated device.
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_FAIL_UNTIL", "5")
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_FAIL_EXIT", "1")
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_FAIL_OUTPUT", "not yet awake")
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_OUTPUT", fakeProfilesOutput())
    FakeEngineEnvironment.set("LOPE_TEST_LIST_OUTPUT", fakeDeviceListLine() + "\n")
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)
    // The wired stale-key fallback takes the full-discovery branch instead
    // of sleeping-mouse recovery.
    let cached = DeviceChoice(
      id: 1, name: "Unrecognized Mouse", connection: "Wired", productID: "0x9999",
      deviceKey: "stale-key")

    await withFakeEngineDirectory(tempDir.path) {
      model.startInitialRefresh(cachedDevice: cached)
      await waitUntil(timeout: 5) { !model.busy }
    }

    XCTAssertEqual(model.status, "Choose a Logitech mouse to continue.")
    XCTAssertEqual(model.currentDeviceName, "")
    XCTAssertTrue(model.devices.contains(where: { $0.name == "G502 X" }))
  }

  func testStartInitialRefreshBeginsKnownDevicePollingWhenCachedKeyIsStaleForACatalogedDevice()
    async
  {
    // A non-wired cached mouse must hand off to beginKnownDeviceRefresh()
    // (the "wait for it to wake up" path) instead of silently selecting
    // another device during full discovery.
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_OUTPUT", "not yet awake")
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_EXIT", "1")
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)
    let cached = DeviceChoice(
      id: 1, name: "G603", connection: "Wireless", productID: "0xB01C",
      deviceKey: "abc123ef")

    await withFakeEngineDirectory(tempDir.path) {
      model.startInitialRefresh(cachedDevice: cached)
      await waitUntil(timeout: 5) { model.waitingForKnownDevice }
    }

    XCTAssertEqual(model.knownDisconnectedDevice, cached)
    XCTAssertNotNil(model.knownDevicePollTask)
    model.knownDevicePollTask?.cancel()
    model.knownDevicePollTask = nil
  }

  func testStartInitialRefreshUsesProfileOneWhenPreferredProfileNumberIsZero() async {
    // prepareLoadingEditor(profileNumber:) runs synchronously before the
    // async profile read, so its 0 -> 1 fallback is observable right after
    // the call returns -- but only once past the `guard let engine` check,
    // hence the fake engine here (a real device response isn't needed).
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)
    model.profileNumber = 0

    await withFakeEngineDirectory(tempDir.path) {
      model.startInitialRefresh(cachedDevice: fixtureDevice())
      XCTAssertEqual(model.profileNumber, 1)
    }
    model.refreshTask?.cancel()
  }

  // MARK: - startRefresh

  func testStartRefreshReportsEngineUnavailable() {
    let model = AppModel(startInitialRefresh: false)

    model.startRefresh(preferredDeviceIndex: 1, preferredProfileNumber: 1)

    XCTAssertFalse(model.busy)
    XCTAssertFalse(model.loadingProfile)
    XCTAssertEqual(model.status, EngineError.unavailable.localizedDescription)
    XCTAssertNil(model.refreshTask)
  }

  func testStartRefreshAppliesProfileSnapshotOnSuccess() async {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_LIST_OUTPUT", fakeDeviceListLine() + "\n")
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_OUTPUT", fakeProfilesOutput())
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)

    await withFakeEngineDirectory(tempDir.path) {
      model.startRefresh(preferredDeviceIndex: 1, preferredProfileNumber: 2)
      await waitUntil { !model.profiles.isEmpty }
      await waitUntil { !model.busy }
    }

    XCTAssertEqual(model.status, "Onboard Profile read successfully.")
    XCTAssertEqual(model.currentDeviceName, "G502 X")
    model.stopLiveDPIPolling()
  }

  func testStartRefreshUsesProfileOneWhenPreferredProfileNumberIsZero() async {
    // Covers both `preferredProfileNumber == 0 ? 1 : ...` fallbacks in
    // startRefresh(): the first (synchronous, before device enumeration)
    // and the second (after a device is actually found), unlike every
    // other startRefresh test, which always passes a real profile number.
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_LIST_OUTPUT", fakeDeviceListLine() + "\n")
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_OUTPUT", fakeProfilesOutput())
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)

    await withFakeEngineDirectory(tempDir.path) {
      model.startRefresh(preferredDeviceIndex: 1, preferredProfileNumber: 0)
      XCTAssertEqual(model.profileNumber, 1)
      await waitUntil { !model.profiles.isEmpty }
      await waitUntil { !model.busy }
    }

    XCTAssertEqual(model.status, "Onboard Profile read successfully.")
    model.stopLiveDPIPolling()
  }

  func testStartRefreshReportsEnumerationFailure() async {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_LIST_EXIT", "1")
    FakeEngineEnvironment.set("LOPE_TEST_LIST_OUTPUT", "device list unavailable")
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)

    await withFakeEngineDirectory(tempDir.path) {
      model.startRefresh(preferredDeviceIndex: 1, preferredProfileNumber: 1)
      await waitUntil(timeout: 5) { !model.busy }
    }

    XCTAssertEqual(model.status, "device list unavailable")
    XCTAssertTrue(model.devices.isEmpty)
  }

  func testStartRefreshReportsNoMouseFoundWhenListIsEmpty() async {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)

    await withFakeEngineDirectory(tempDir.path) {
      model.startRefresh(preferredDeviceIndex: 1, preferredProfileNumber: 1)
      await waitUntil(timeout: 5) { !model.busy }
    }

    XCTAssertEqual(model.status, "No Logitech mouse was found")
  }

  func testStartRefreshShowsKnownDeviceUnavailableWhenExpectedDeviceVanishes() async {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)
    let expected = DeviceChoice(
      id: 1, name: "G603", connection: "Wireless", productID: "0xB01C", deviceKey: "deadbeef")

    await withFakeEngineDirectory(tempDir.path) {
      model.startRefresh(
        preferredDeviceIndex: 1, preferredProfileNumber: 1, expectedDevice: expected)
      await waitUntil(timeout: 5) { model.waitingForKnownDevice }
    }

    XCTAssertEqual(model.knownDisconnectedDevice, expected)
    model.knownDevicePollTask?.cancel()
    model.stopKnownDevicePolling(clearDevice: true)
  }

  func testStartRefreshShowsKnownDeviceUnavailableWhenSelectedDeviceKeyDiffers() async {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    // Discovery finds a real device, but its key does not match the one
    // being watched for -- e.g. a different mouse connected in the meantime.
    FakeEngineEnvironment.set(
      "LOPE_TEST_LIST_OUTPUT", fakeDeviceListLine(deviceKey: "1234abcd") + "\n")
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)
    let expected = DeviceChoice(
      id: 1, name: "G603", connection: "Wireless", productID: "0xB01C", deviceKey: "deadbeef")

    await withFakeEngineDirectory(tempDir.path) {
      model.startRefresh(
        preferredDeviceIndex: 1, preferredProfileNumber: 1, expectedDevice: expected)
      await waitUntil(timeout: 5) { model.waitingForKnownDevice }
    }

    XCTAssertEqual(model.knownDisconnectedDevice, expected)
    // Discovery did find a (different) device, unlike the "vanished" case,
    // so it should be visible in the picker while the target is awaited.
    XCTAssertTrue(model.devices.contains(where: { $0.deviceKey == "1234abcd" }))
    model.knownDevicePollTask?.cancel()
    model.stopKnownDevicePolling(clearDevice: true)
  }

  func testStartRefreshWithMatchingExpectedDeviceStopsKnownDevicePollingAndSucceeds() async {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_LIST_OUTPUT", fakeDeviceListLine() + "\n")
    FakeEngineEnvironment.set("LOPE_TEST_PROFILES_OUTPUT", fakeProfilesOutput())
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)
    let expected = fixtureDevice()
    model.waitingForKnownDevice = true

    await withFakeEngineDirectory(tempDir.path) {
      model.startRefresh(
        preferredDeviceIndex: 1, preferredProfileNumber: 2, expectedDevice: expected)
      await waitUntil { !model.profiles.isEmpty }
      await waitUntil { !model.busy }
    }

    XCTAssertFalse(model.waitingForKnownDevice)
    XCTAssertEqual(model.status, "Onboard Profile read successfully.")
    model.stopLiveDPIPolling()
  }

  // MARK: - profileReadProgressHandler

  func testProfileReadProgressHandlerUpdatesCapacityWhileLoading() async {
    let model = AppModel(startInitialRefresh: false)
    model.loadingProfile = true
    let generation = model.refreshGeneration
    let handler = model.profileReadProgressHandler(generation: generation)

    handler("Profile capacity: 4")

    await waitUntil { model.onboardProfileCapacity == 4 }
    XCTAssertTrue(model.onboardProfileCapacityWasReported)
  }

  func testProfileReadProgressHandlerIgnoresLinesWithoutCapacity() async {
    let model = AppModel(startInitialRefresh: false)
    model.loadingProfile = true
    let handler = model.profileReadProgressHandler(generation: model.refreshGeneration)

    handler("Selected profile: 1")
    try? await Task.sleep(nanoseconds: 50_000_000)

    XCTAssertNil(model.onboardProfileCapacity)
  }

  func testProfileReadProgressHandlerIgnoresStaleGeneration() async {
    let model = AppModel(startInitialRefresh: false)
    model.loadingProfile = true
    let handler = model.profileReadProgressHandler(generation: model.refreshGeneration)
    model.refreshGeneration += 1

    handler("Profile capacity: 9")
    try? await Task.sleep(nanoseconds: 50_000_000)

    XCTAssertNil(model.onboardProfileCapacity)
  }
}
