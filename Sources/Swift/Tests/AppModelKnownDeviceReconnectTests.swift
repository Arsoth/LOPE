// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

// Covers AppModel+KnownDeviceReconnect.swift. `startReconnectMonitor` and
// `startKnownDeviceProbe` both read `AppModel.engine` directly (unlike
// AppModel+DeviceDiscovery.swift's functions, which take an explicit
// `executable` parameter, and unlike `runEngine`, which honors
// `engineRunnerOverride`), so exercising their HID++-reachable branches
// requires a real file at one of `engine`'s resolution candidates. This
// file installs a throwaway script at `bin/lope` (the Makefile's own build
// output location for the CLI core, already gitignored) for the duration
// of the tests that need it, and removes it again in `tearDown`.
@MainActor
final class AppModelKnownDeviceReconnectTests: XCTestCase {
  private var temporaryDirectories: [URL] = []
  private var createdBinDirectory = false

  private static let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  private static let binDirectory = repoRoot.appendingPathComponent("bin", isDirectory: true)
  private static let engineURL = binDirectory.appendingPathComponent("lope")

  override func tearDown() {
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: Self.engineURL)
    if createdBinDirectory {
      try? fileManager.removeItem(at: Self.binDirectory)
    }
    createdBinDirectory = false
    for directory in temporaryDirectories {
      try? fileManager.removeItem(at: directory)
    }
    temporaryDirectories.removeAll()
    super.tearDown()
  }

  private func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lope-known-device-test-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    temporaryDirectories.append(url)
    return url
  }

  /// Installs a throwaway script at the `bin/lope` location `AppModel.engine`
  /// falls back to when no bundled resource or `./lope` symlink is present
  /// (exactly the case in the `swift test` sandbox). Refuses to clobber a
  /// real build artifact left behind by a concurrent `make`/`rebuild-signed.sh`.
  private func installFakeEngine(_ body: String) {
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: Self.binDirectory.path) {
      try! fileManager.createDirectory(at: Self.binDirectory, withIntermediateDirectories: true)
      createdBinDirectory = true
    }
    precondition(
      !fileManager.fileExists(atPath: Self.engineURL.path),
      "bin/lope already exists; refusing to overwrite a real build artifact")
    let helpers = """
      emit_device() { printf '{"contract_version":1,"ok":true,"kind":"device_list","vendor_interface_count":1,"devices":[{"index":%s,"vendor_id":1133,"product_id":%s,"device_number":1,"request_device_number":1,"protocol":4.5,"name":"%s","connection":"%s","device_key":"%s"}],"device_count":1}\\n' "$1" "$4" "$3" "$2" "$5"; }
      emit_profile() { printf '{"contract_version":1,"ok":true,"kind":"profiles","device":{"index":1,"vendor_id":1133,"product_id":%s,"device_number":1,"request_device_number":1,"protocol":4.5,"name":"%s","connection":"Wireless","device_key":"%s"},"profile_capacity":1,"headers":[{"number":1,"sector":256,"enabled":true}],"selected_profile":{"number":1,"sector":256,"enabled":true,"memory":3,"format":1,"macro_format":0,"profile_capacity":1,"button_capacity":5,"sector_count":1,"sector_size":256,"shift_flags":0,"crc_checked":true,"crc_valid":true,"layouts":{"buttons":true,"gshift":false,"dpi":false,"rgb":false},"buttons":[{"number":1,"layer":"normal","raw":[128,1,0,1],"description":"Left click"}],"dpi_stages":[],"dpi_default_stage":0,"dpi_shift_stage":0,"rgb_zones":[]},"dpi":null,"report_rate":null}\\n' "$1" "$2" "$3"; }
      """
    let script = "#!/bin/sh\n" + helpers + "\n" + body + "\n"
    try! script.write(to: Self.engineURL, atomically: true, encoding: .utf8)
    try! fileManager.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: Self.engineURL.path)
  }

  private func makeModel() -> AppModel {
    let model = AppModel(startInitialRefresh: false)
    model.configurationDirectory = makeTemporaryDirectory()
    // `startKnownDeviceProbe`/`startReconnectMonitor` launch the fake engine
    // with `backupDirectory` as its working directory; `Process` requires
    // that directory to already exist.
    try! FileManager.default.createDirectory(
      at: model.backupDirectory, withIntermediateDirectories: true)
    return model
  }

  // MARK: - hasKnownOnboardProfileCapability

  func testHasKnownOnboardProfileCapabilityIsTrueForSupportedCatalogDevice() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    XCTAssertTrue(model.hasKnownOnboardProfileCapability(device))
  }

  func testHasKnownOnboardProfileCapabilityIsFalseForMatchedButUnsupportedDevice() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 2, name: "G600 MMO", connection: "Wired", productID: "0xC24A", deviceKey: "aaaa-0002")
    XCTAssertTrue(
      MouseProfileCatalog.shared.matchingProfile(
        deviceName: device.name, productID: device.productID) != nil,
      "test relies on G600 matching a catalog entry")
    XCTAssertFalse(model.hasKnownOnboardProfileCapability(device))
  }

  func testHasKnownOnboardProfileCapabilityIsFalseForUnmatchedDevice() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 3, name: "Totally Unknown Widget", connection: "Wireless", productID: "0xFFFF",
      deviceKey: "aaaa-0003")
    XCTAssertNil(
      MouseProfileCatalog.shared.matchingProfile(
        deviceName: device.name, productID: device.productID))
    XCTAssertFalse(model.hasKnownOnboardProfileCapability(device))
  }

  // MARK: - knownDeviceRefreshStatus

  func testStatusFooterHidesWakeStatusWhileKnownDeviceModalIsVisible() {
    let model = makeModel()
    model.status = "Checking for G603 LIGHTSPEED…"
    model.waitingForKnownDevice = true

    XCTAssertEqual(model.statusFooterText, "")
  }

  func testStatusFooterShowsStatusOutsideKnownDeviceModal() {
    let model = makeModel()
    model.status = "Onboard Profile read successfully."

    XCTAssertEqual(model.statusFooterText, model.status)
  }

  func testKnownDeviceRefreshStatusUsesGuidanceWhenNotExpired() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    XCTAssertEqual(
      model.knownDeviceRefreshStatus(for: device, expired: false),
      "Checking for \(device.name)…"
    )
  }

  func testKnownDeviceRefreshStatusUsesGuidanceWhenExpired() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    let guidance = MouseProfileCatalog.shared.matchingProfile(
      deviceName: device.name, productID: device.productID)!.refreshGuidance!

    XCTAssertEqual(
      model.knownDeviceRefreshStatus(for: device, expired: true),
      "Still waiting for \(device.name). \(guidance.wakeInstructions)")
  }

  func testKnownDeviceRefreshStatusFallsBackWhenCatalogHasNoGuidance() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 2, name: "G600 MMO", connection: "Bluetooth", productID: "0xC24A", deviceKey: "aaaa-0002")
    XCTAssertNil(
      MouseProfileCatalog.shared.matchingProfile(
        deviceName: device.name, productID: device.productID)?.refreshGuidance,
      "test relies on G600 having no refresh guidance")

    XCTAssertEqual(
      model.knownDeviceRefreshStatus(for: device, expired: false),
      "Checking for \(device.name)…")
  }

  // MARK: - beginKnownDeviceRefresh

  func testBeginKnownDeviceRefreshSetsWaitingStateAndSchedulesPolling() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")

    model.beginKnownDeviceRefresh(device)
    defer {
      model.knownDevicePollTask?.cancel()
      model.knownDevicePollTask = nil
    }

    XCTAssertEqual(model.knownDisconnectedDevice, device)
    XCTAssertTrue(model.waitingForKnownDevice)
    XCTAssertEqual(model.knownDevicePollAttempts, 0)
    XCTAssertEqual(model.currentDeviceName, device.name)
    XCTAssertEqual(model.deviceSummary, "\(device.title) — waiting for the mouse")
    XCTAssertEqual(model.status, model.knownDeviceRefreshStatus(for: device, expired: false))
    XCTAssertNotNil(model.knownDevicePollTask)
  }

  func testBeginKnownDeviceRefreshDoesNotApplyToWiredDevice() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G502 X", connection: "Wired", productID: "0x0000", deviceKey: "wired")

    model.beginKnownDeviceRefresh(device)

    XCTAssertFalse(model.waitingForKnownDevice)
    XCTAssertFalse(model.busy)
    XCTAssertNil(model.knownDevicePollTask)
    XCTAssertNil(model.knownDisconnectedDevice)
  }

  func testBeginKnownDeviceRefreshDoesNotReplaceAnInFlightPollTask() {
    let model = makeModel()
    let firstDevice = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    let secondDevice = DeviceChoice(
      id: 2, name: "G600 MMO", connection: "Bluetooth", productID: "0xC24A", deviceKey: "aaaa-0002")

    model.beginKnownDeviceRefresh(firstDevice)
    defer {
      model.knownDevicePollTask?.cancel()
      model.knownDevicePollTask = nil
    }
    XCTAssertNotNil(model.knownDevicePollTask)

    // A second call while a poll task is already running must not crash or
    // leave polling state cleared, even though the visible device fields
    // still track whichever device was passed most recently.
    model.beginKnownDeviceRefresh(secondDevice)
    XCTAssertNotNil(model.knownDevicePollTask)
    XCTAssertEqual(model.knownDisconnectedDevice, secondDevice)
  }

  func testBeginKnownDeviceRefreshPollLoopStopsWhenDeviceChangesMidWait() async {
    // Covers the first per-attempt guard's `else { return }`: by the time
    // the 1-second poll interval elapses, `knownDisconnectedDevice` no
    // longer matches the device the loop was tracking, so it must bail
    // out instead of probing.
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    model.beginKnownDeviceRefresh(device)
    model.knownDisconnectedDevice = DeviceChoice(
      id: 2, name: "Different Mouse", connection: "Wired", productID: "0xFFFF",
      deviceKey: "aaaa-0002")

    try? await Task.sleep(nanoseconds: 1_300_000_000)

    XCTAssertEqual(model.knownDevicePollAttempts, 0)
    XCTAssertTrue(model.busy)
    model.knownDevicePollTask?.cancel()
  }

  func testBeginKnownDeviceRefreshPollLoopSkipsProbeWhileBusy() async {
    // Busy belongs to the whole wake/recovery operation. A completed probe
    // may run between poll intervals, but the operation remains busy.
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    model.beginKnownDeviceRefresh(device)
    model.busy = true

    try? await Task.sleep(nanoseconds: 1_300_000_000)

    XCTAssertEqual(model.knownDevicePollAttempts, 1)
    model.knownDevicePollTask?.cancel()
  }

  func testBeginKnownDeviceRefreshPollLoopProbesMatchingDeviceWhenNotBusy() async {
    // Covers the success path through both guards: the poll loop actually
    // invokes startKnownDeviceProbe(), which spawns the (fake) engine --
    // observed here via a counter file rather than the `busy` flag, since
    // the probe's own async chain can reset `busy` again before this test
    // gets a chance to check it.
    let counterFile = makeTemporaryDirectory().appendingPathComponent("count")
    installFakeEngine(
      """
      printf '.' >> "\(counterFile.path)"
      exit 1
      """)
    let model = makeModel()
    model.knownDevicePollPolicy = (intervalNanoseconds: 10_000_000, maximumAttempts: 1)
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    model.beginKnownDeviceRefresh(device)

    try? await Task.sleep(nanoseconds: 1_300_000_000)

    XCTAssertEqual(model.knownDevicePollAttempts, 1)
    let attempts = (try? String(contentsOf: counterFile)) ?? ""
    XCTAssertFalse(attempts.isEmpty, "expected the poll loop to have probed the fake engine")
    model.knownDevicePollTask?.cancel()
    model.refreshTask?.cancel()
  }

  func testBeginKnownDeviceRefreshPollLoopGivesUpAfterMaximumAttempts() async {
    // Covers the tail after the for loop runs out of attempts without a
    // match: the poll task is dropped and the status switches to its
    // expired wording, but `waitingForKnownDevice` stays true so the wake
    // modal keeps showing a Retry option instead of disappearing. Shrinks
    // the policy so the test does not have to wait out the real ~60-second
    // default.
    let model = makeModel()
    model.knownDevicePollPolicy = (intervalNanoseconds: 10_000_000, maximumAttempts: 2)
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")

    model.beginKnownDeviceRefresh(device)
    await model.knownDevicePollTask?.value

    XCTAssertTrue(model.waitingForKnownDevice)
    XCTAssertTrue(model.knownDeviceWakeExpired)
    XCTAssertFalse(model.busy)
    XCTAssertNil(model.knownDevicePollTask)
    XCTAssertEqual(model.status, model.knownDeviceRefreshStatus(for: device, expired: true))
    XCTAssertEqual(model.knownDisconnectedDevice, device)
    XCTAssertEqual(model.currentDeviceName, device.name)
  }

  func testBeginKnownDeviceRefreshExpirationKeepsOtherDevices() async {
    // The device picker and current-device fields must survive expiration
    // unchanged: giving up polling no longer tears down the picker, since
    // Retry needs the same device/picker state the dialog was already
    // showing.
    let model = makeModel()
    model.knownDevicePollPolicy = (intervalNanoseconds: 10_000_000, maximumAttempts: 1)
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    let other = DeviceChoice(
      id: 2, name: "Other Mouse", connection: "Wireless", productID: "0xEEEE",
      deviceKey: "eeee-0002")
    model.devices = [device, other]

    model.beginKnownDeviceRefresh(device)
    await model.knownDevicePollTask?.value

    XCTAssertEqual(model.devices, [device, other])
    XCTAssertEqual(model.deviceSummary, "\(device.title) — waiting for the mouse")
    XCTAssertEqual(model.currentDeviceName, device.name)
  }

  // MARK: - retryKnownDeviceWake

  func testRetryKnownDeviceWakeRestartsPollingAfterExpiration() async {
    let model = makeModel()
    model.knownDevicePollPolicy = (intervalNanoseconds: 10_000_000, maximumAttempts: 1)
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")

    model.beginKnownDeviceRefresh(device)
    await model.knownDevicePollTask?.value
    XCTAssertTrue(model.knownDeviceWakeExpired, "test relies on the first poll loop expiring")

    model.retryKnownDeviceWake()
    defer {
      model.knownDevicePollTask?.cancel()
      model.knownDevicePollTask = nil
    }

    XCTAssertFalse(model.knownDeviceWakeExpired)
    XCTAssertTrue(model.waitingForKnownDevice)
    XCTAssertEqual(model.knownDevicePollAttempts, 0)
    XCTAssertTrue(model.busy)
    XCTAssertEqual(model.status, model.knownDeviceRefreshStatus(for: device, expired: false))
    XCTAssertNotNil(model.knownDevicePollTask)
  }

  func testRetryKnownDeviceWakeIsNoOpWhenNotExpired() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    model.beginKnownDeviceRefresh(device)
    defer {
      model.knownDevicePollTask?.cancel()
      model.knownDevicePollTask = nil
    }
    XCTAssertNotNil(model.knownDevicePollTask, "test relies on the poll loop still being active")

    model.retryKnownDeviceWake()

    XCTAssertFalse(model.knownDeviceWakeExpired)
    XCTAssertNotNil(
      model.knownDevicePollTask,
      "a non-expired retry call must not disturb the already-running poll loop")
  }

  func testRetryKnownDeviceWakeIsNoOpWithoutAKnownDisconnectedDevice() {
    let model = makeModel()

    model.retryKnownDeviceWake()

    XCTAssertFalse(model.knownDeviceWakeExpired)
    XCTAssertFalse(model.waitingForKnownDevice)
    XCTAssertNil(model.knownDevicePollTask)
  }

  func testBeginKnownDeviceRefreshSkipsProbeWhenRefreshIsAlreadyInFlight() async {
    let model = makeModel()
    model.knownDevicePollPolicy = (intervalNanoseconds: 10_000_000, maximumAttempts: 1)
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")

    model.beginKnownDeviceRefresh(device)
    model.refreshTask = Task {}
    await model.knownDevicePollTask?.value

    XCTAssertEqual(model.knownDevicePollAttempts, 1)
    XCTAssertTrue(model.waitingForKnownDevice)
    XCTAssertTrue(model.knownDeviceWakeExpired)
    XCTAssertNil(model.refreshTask)
  }

  func testBeginKnownDeviceRefreshPollLoopStopsWhenCancelledDuringSleep() async {
    // Covers the do/catch around Task.sleep: cancelling the poll task
    // while it is still waiting out the interval makes Task.sleep throw
    // CancellationError, which the catch block turns into a plain return.
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    model.beginKnownDeviceRefresh(device)
    let task = model.knownDevicePollTask

    task?.cancel()
    await task?.value

    XCTAssertEqual(model.knownDevicePollAttempts, 0)
  }

  // MARK: - finishKnownDeviceProbe

  func testFinishKnownDeviceProbeResetsBusyWhenGenerationMatches() {
    let model = makeModel()
    model.refreshGeneration = 3
    model.busy = true
    model.refreshTask = Task {}

    model.finishKnownDeviceProbe(generation: 3)

    XCTAssertFalse(model.busy)
    XCTAssertNil(model.refreshTask)
  }

  func testFinishKnownDeviceProbeIsNoOpWhenGenerationIsStale() {
    let model = makeModel()
    model.refreshGeneration = 5
    model.busy = true
    let placeholder = Task<Void, Never> {}
    model.refreshTask = placeholder

    model.finishKnownDeviceProbe(generation: 3)

    XCTAssertTrue(model.busy)
    XCTAssertNotNil(model.refreshTask)
  }

  // MARK: - stopKnownDevicePolling

  func testStopKnownDevicePollingClearsPollingStateButKeepsDeviceByDefault() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    model.knownDevicePollTask = Task {}
    model.waitingForKnownDevice = true
    model.knownDevicePollAttempts = 4
    model.knownDeviceWakeExpired = true
    model.knownDisconnectedDevice = device

    model.stopKnownDevicePolling(clearDevice: false)

    XCTAssertNil(model.knownDevicePollTask)
    XCTAssertFalse(model.waitingForKnownDevice)
    XCTAssertEqual(model.knownDevicePollAttempts, 0)
    XCTAssertFalse(model.knownDeviceWakeExpired)
    XCTAssertEqual(model.knownDisconnectedDevice, device)
  }

  func testStopKnownDevicePollingClearsDeviceWhenRequested() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    model.knownDevicePollTask = Task {}
    model.knownDisconnectedDevice = device

    model.stopKnownDevicePolling(clearDevice: true)

    XCTAssertNil(model.knownDisconnectedDevice)
  }

  // MARK: - showKnownDeviceUnavailable

  func testShowKnownDeviceUnavailableWithNoAvailableDevicesKeepsCachedDeviceVisible() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    model.busy = true
    model.loadingProfile = true
    model.refreshTask = Task {}

    model.showKnownDeviceUnavailable(device)
    defer {
      model.knownDevicePollTask?.cancel()
      model.knownDevicePollTask = nil
    }

    XCTAssertTrue(model.busy)
    XCTAssertFalse(model.loadingProfile)
    XCTAssertNil(model.refreshTask)
    XCTAssertEqual(model.knownDisconnectedDevice, device)
    XCTAssertTrue(model.waitingForKnownDevice)
    XCTAssertEqual(model.currentDeviceName, device.name)
    XCTAssertEqual(model.devices, [device])
    XCTAssertEqual(model.selectedDeviceIndex, device.id)
    XCTAssertEqual(model.status, model.knownDeviceRefreshStatus(for: device, expired: false))
    XCTAssertNotNil(model.knownDevicePollTask)
  }

  func testShowKnownDeviceUnavailableWithAvailableDevicesKeepsListAndResetsSelectionToZero() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    let other = DeviceChoice(
      id: 9, name: "Other Mouse", connection: "Wireless", productID: "0xEEEE",
      deviceKey: "eeee-0009")

    model.showKnownDeviceUnavailable(device, availableDevices: [device, other])
    defer {
      model.knownDevicePollTask?.cancel()
      model.knownDevicePollTask = nil
    }

    XCTAssertEqual(model.devices, [device, other])
    XCTAssertEqual(model.selectedDeviceIndex, 0)
  }

  func testShowKnownDeviceUnavailableDoesNotRestartPollingWhenAlreadyPolling() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G603 LIGHTSPEED", connection: "Wireless", productID: "0xB01C",
      deviceKey: "aaaa-0001")
    model.knownDevicePollTask = Task {}

    model.showKnownDeviceUnavailable(device)
    defer {
      model.knownDevicePollTask?.cancel()
      model.knownDevicePollTask = nil
    }

    XCTAssertEqual(model.status, model.knownDeviceRefreshStatus(for: device, expired: false))
    XCTAssertNotNil(model.knownDevicePollTask)
  }

  func testShowKnownDeviceUnavailableKeepsWiredPermissionFlowPassive() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G502 X", connection: "Wired", productID: "0x0000", deviceKey: "wired")

    model.showKnownDeviceUnavailable(device)

    XCTAssertFalse(model.wiredAccessInstructionsPresented)
    XCTAssertFalse(model.waitingForKnownDevice)
    XCTAssertNil(model.knownDevicePollTask)
    XCTAssertTrue(model.status.contains("Input Monitoring"))
  }

  // MARK: - startKnownDeviceProbe

  func testStartKnownDeviceProbeReturnsBusyFalseWhenEngineUnavailable() {
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-0001")
    model.knownDisconnectedDevice = device
    model.busy = false

    model.startKnownDeviceProbe(device)

    XCTAssertFalse(model.busy)
    XCTAssertNil(model.refreshTask)
  }

  func testStartKnownDeviceProbeAppliesSnapshotWhenDeviceRespondsWithMatchingKey() async {
    installFakeEngine(
      """
      if [ "$1" = "list" ]; then
        emit_device 1 Wireless "Recon Mouse" 43690 aaaa-0001
      else
        emit_profile 43690 "Recon Mouse" aaaa-0001
      fi
      exit 0
      """)
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-0001")
    model.knownDisconnectedDevice = device
    model.startKnownDeviceProbe(device)
    await model.refreshTask?.value

    XCTAssertFalse(model.busy)
    XCTAssertNil(model.refreshTask)
    XCTAssertEqual(model.currentDeviceName, "Recon Mouse")
    XCTAssertEqual(model.devices.map(\.deviceKey), ["aaaa-0001"])
  }

  func testStartKnownDeviceProbeAcceptsPairedIdentityWhenReceiverKeyChanges() async {
    installFakeEngine(
      """
      if [ "$1" = "list" ]; then
        emit_device 3 Wireless "Paired Logitech Mouse - Lightspeed" 16517 aaaa-0003
      else
        emit_profile 16517 "G604" aaaa-0003
      fi
      exit 0
      """)
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "G604", connection: "Wireless", productID: "0x4085", deviceKey: "aaaa-0001")
    model.knownDisconnectedDevice = device
    model.waitingForKnownDevice = true

    model.startKnownDeviceProbe(device)
    await model.refreshTask?.value

    XCTAssertEqual(model.currentDeviceName, "G604")
    XCTAssertEqual(model.devices.first?.name, "G604")
    XCTAssertFalse(model.busy)
  }

  func testStartKnownDeviceProbeFinishesWhenReportedDeviceKeyDoesNotMatch() async {
    installFakeEngine(
      """
      if [ "$1" = "list" ]; then
        emit_device 1 Wireless "Other Mouse" 48059 aaaa-9999
      else
        emit_profile 48059 "Other Mouse" aaaa-9999
      fi
      exit 0
      """)
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-0001")
    model.knownDisconnectedDevice = device
    model.refreshGeneration = 0

    model.startKnownDeviceProbe(device)
    await model.refreshTask?.value

    // A device sharing the list position but reporting a different identity
    // never satisfies the paired-device match, so the probe must finish
    // without touching devices/currentDeviceName.
    XCTAssertFalse(model.busy)
    XCTAssertNil(model.refreshTask)
    XCTAssertEqual(model.currentDeviceName, "")
  }

  func testStartKnownDeviceProbeFinishesWhenProfileReadNeverSucceeds() async {
    installFakeEngine(
      """
      if [ "$1" = "list" ]; then
        emit_device 1 Wireless "Recon Mouse" 43690 aaaa-0001
        exit 0
      fi
      echo "profile read failed" 1>&2
      exit 1
      """)
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-0001")
    model.knownDisconnectedDevice = device
    model.startKnownDeviceProbe(device)
    await model.refreshTask?.value

    XCTAssertFalse(model.busy)
    XCTAssertNil(model.refreshTask)
  }

  func testStartKnownDeviceProbeIgnoresStaleGeneration() async {
    installFakeEngine(
      """
      if [ "$1" = "list" ]; then
        emit_device 1 Wireless "Recon Mouse" 43690 aaaa-0001
      else
        emit_profile 43690 "Recon Mouse" aaaa-0001
      fi
      exit 0
      """)
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-0001")
    model.knownDisconnectedDevice = device
    model.startKnownDeviceProbe(device)
    // startKnownDeviceProbe captures `refreshGeneration` synchronously before
    // returning; bumping it again immediately (before the background probe's
    // first suspension point resolves) simulates another refresh having
    // superseded this one, and must make the probe's result a no-op.
    model.refreshGeneration += 1
    await model.refreshTask?.value

    XCTAssertTrue(
      model.busy, "a superseded probe must not clear busy out from under the newer refresh")
    XCTAssertEqual(model.currentDeviceName, "")
  }

  func testStartKnownDeviceProbeIgnoresResultWhenKnownDisconnectedDeviceChanged() async {
    installFakeEngine(
      """
      if [ "$1" = "list" ]; then
        emit_device 1 Wireless "Recon Mouse" 43690 aaaa-0001
      else
        emit_profile 43690 "Recon Mouse" aaaa-0001
      fi
      exit 0
      """)
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-0001")
    let otherDevice = DeviceChoice(
      id: 2, name: "Different Mouse", connection: "Wireless", productID: "0xBBBB",
      deviceKey: "bbbb-0002")
    model.knownDisconnectedDevice = device

    model.startKnownDeviceProbe(device)
    // The user (or another poll) moved on to a different known-disconnected
    // device while this probe's HID read was still in flight.
    model.knownDisconnectedDevice = otherDevice
    await model.refreshTask?.value

    XCTAssertTrue(model.busy)
    XCTAssertEqual(model.currentDeviceName, "")
  }

  // MARK: - startReconnectMonitor

  func testStartReconnectMonitorCancelsAPreviousMonitorPromptly() async {
    let model = makeModel()

    model.startReconnectMonitor()
    let firstTask = model.reconnectMonitorTask

    let start = Date()
    model.startReconnectMonitor()
    await firstTask?.value
    let elapsed = Date().timeIntervalSince(start)

    XCTAssertLessThan(
      elapsed, 1.0, "cancelling the superseded monitor must not wait out its poll interval")
    model.reconnectMonitorTask?.cancel()
  }

  func testStartReconnectMonitorSkipsPollingWhileBusy() async {
    let counterFile = makeTemporaryDirectory().appendingPathComponent("count")
    installFakeEngine(
      """
      printf '.' >> "\(counterFile.path)"
      exit 0
      """)
    let model = makeModel()
    model.busy = true

    model.startReconnectMonitor()
    try? await Task.sleep(nanoseconds: 2_300_000_000)
    model.reconnectMonitorTask?.cancel()

    let attempts = (try? String(contentsOf: counterFile)) ?? ""
    XCTAssertTrue(attempts.isEmpty, "a busy model must not invoke the engine while polling")
  }

  func testStartReconnectMonitorContinuesLoopingWhenEngineIsUnavailable() async {
    let model = makeModel()

    model.startReconnectMonitor()
    try? await Task.sleep(nanoseconds: 2_300_000_000)

    // No bundled/`bin/lope` engine exists in the test sandbox, so every
    // iteration's `guard ... let executable = self.engine else { continue }`
    // must keep the loop alive rather than exiting or crashing.
    XCTAssertNotNil(model.reconnectMonitorTask)
    XCTAssertEqual(model.status, "Connect a Logitech mouse, then choose Refresh.")
    model.reconnectMonitorTask?.cancel()
  }

  func testStartReconnectMonitorContinuesWhenDeviceListReadFails() async {
    installFakeEngine(
      """
      echo "temporary device-list failure" 1>&2
      exit 1
      """)
    let model = makeModel()

    model.startReconnectMonitor()
    try? await Task.sleep(nanoseconds: 2_300_000_000)

    XCTAssertNotNil(model.reconnectMonitorTask)
    XCTAssertEqual(model.status, "Connect a Logitech mouse, then choose Refresh.")
    model.reconnectMonitorTask?.cancel()
  }

  func testStartReconnectMonitorStartsRefreshWhenNoDeviceWasSelected() async {
    installFakeEngine(
      """
      if [ "$1" = "list" ]; then
        emit_device 1 Wireless "Recon Mouse" 43690 aaaa-0001
      else
        emit_profile 43690 "Recon Mouse" aaaa-0001
      fi
      exit 0
      """)
    let model = makeModel()
    XCTAssertTrue(model.devices.isEmpty)

    model.startReconnectMonitor()
    await waitUntil(timeout: 5) {
      model.refreshTask != nil || model.devices.contains(where: { $0.name == "Recon Mouse" })
    }
    // The reconnect monitor's discovery hands off to startRefresh(), which
    // runs its own background task; let it settle before asserting.
    await model.refreshTask?.value
    model.reconnectMonitorTask?.cancel()

    XCTAssertEqual(model.currentDeviceName, "")
    XCTAssertEqual(model.selectedDeviceIndex, 0)
    XCTAssertTrue(model.devices.contains(where: { $0.name == "Recon Mouse" }))
    XCTAssertEqual(model.status, "Choose a Logitech mouse to continue.")
    XCTAssertFalse(model.busy)
  }

  func testStartReconnectMonitorIgnoresADeviceThatDisappearsAfterCalibration() async {
    let modeFile = makeTemporaryDirectory().appendingPathComponent("mode")
    try! "present".write(to: modeFile, atomically: true, encoding: .utf8)
    installFakeEngine(
      """
      mode=$(cat "\(modeFile.path)" 2>/dev/null || echo gone)
      if [ "$1" = "list" ]; then
        if [ "$mode" = "present" ]; then
          emit_device 1 Wireless "Recon Mouse" 43690 aaaa-0001
        fi
      else
        emit_profile 43690 "Recon Mouse" aaaa-0001
      fi
      exit 0
      """)
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-0001")
    model.devices = [device]
    model.selectedDeviceIndex = device.id

    model.startReconnectMonitor()
    // Iteration 1 only calibrates `wasReachable`; it never changes status.
    try? await Task.sleep(nanoseconds: 2_300_000_000)
    try! "gone".write(to: modeFile, atomically: true, encoding: .utf8)
    // Iteration 2 observes the device is now unreachable and must not start
    // a refresh.
    try? await Task.sleep(nanoseconds: 2_300_000_000)
    model.reconnectMonitorTask?.cancel()

    XCTAssertEqual(model.status, "Connect a Logitech mouse, then choose Refresh.")
    XCTAssertNil(model.refreshTask)
  }

  func testStartReconnectMonitorMarksDeviceUnreachableThenDetectsItsReturn() async {
    // Covers the `!reachable` branch (wasReachable flips to false while
    // already initialized) by using a non-matching device rather than an
    // empty list, so the device-read retry loop in
    // AppModel+DeviceDiscovery.swift never engages and the timing stays
    // predictable. The middle "unreachable" phase is otherwise invisible
    // from the outside, so the third phase proves it actually ran: if
    // wasReachable had not been reset to false, the device's return would
    // not be treated as a reconnect.
    let modeFile = makeTemporaryDirectory().appendingPathComponent("mode")
    try! "present".write(to: modeFile, atomically: true, encoding: .utf8)
    installFakeEngine(
      """
      mode=$(cat "\(modeFile.path)" 2>/dev/null || echo present)
      if [ "$1" = "list" ]; then
        if [ "$mode" = "absent" ]; then
          emit_device 1 Wireless "Other Widget" 48059 bbbb-0001
        else
          emit_device 1 Wireless "Recon Mouse" 43690 aaaa-0001
        fi
      else
        emit_profile 43690 "Recon Mouse" aaaa-0001
      fi
      exit 0
      """)
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-0001")
    model.devices = [device]
    model.selectedDeviceIndex = device.id

    model.startReconnectMonitor()
    // Iteration 1 only calibrates `wasReachable` to true (the fake engine
    // reports the matching device).
    try? await Task.sleep(nanoseconds: 2_300_000_000)
    // Iteration 2 sees a different device instead of the selected one, so
    // matching fails and `wasReachable` must flip to false.
    try! "absent".write(to: modeFile, atomically: true, encoding: .utf8)
    try? await Task.sleep(nanoseconds: 2_300_000_000)
    // Iteration 3: the original device is visible again. Whether this
    // reads as a reconnect depends entirely on `wasReachable` actually
    // having been set to false in iteration 2: if it had incorrectly
    // stayed true, `!wasReachable || identityChanged` would be false
    // (the key is unchanged), `startRefresh` would never run, and
    // `status`/`currentDeviceName` would stay at their untouched
    // defaults instead of reflecting the (fake) read that follows.
    try! "present".write(to: modeFile, atomically: true, encoding: .utf8)
    try? await Task.sleep(nanoseconds: 2_300_000_000)
    await model.refreshTask?.value
    model.reconnectMonitorTask?.cancel()

    XCTAssertEqual(model.currentDeviceName, "Recon Mouse")
    XCTAssertNotEqual(model.status, "Connect a Logitech mouse, then choose Refresh.")
  }

  func testStartReconnectMonitorDetectsIdentityChangeAfterCalibration() async {
    let modeFile = makeTemporaryDirectory().appendingPathComponent("mode")
    try! "1".write(to: modeFile, atomically: true, encoding: .utf8)
    installFakeEngine(
      """
      mode=$(cat "\(modeFile.path)" 2>/dev/null || echo 1)
      if [ "$1" = "list" ]; then
        emit_device 1 Wireless "Recon Mouse" 43690 "aaaa-000$mode"
      else
        emit_profile 43690 "Recon Mouse" "aaaa-000$mode"
      fi
      exit 0
      """)
    let model = makeModel()
    let device = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-0001")
    model.devices = [device]
    model.selectedDeviceIndex = device.id

    model.startReconnectMonitor()
    // Iteration 1 calibrates against key "...0001" (mode file holds "1").
    try? await Task.sleep(nanoseconds: 2_300_000_000)
    // A KVM-style reconnect: same product/name, new HID identity.
    try! "2".write(to: modeFile, atomically: true, encoding: .utf8)
    try? await Task.sleep(nanoseconds: 2_300_000_000)
    await model.refreshTask?.value
    model.reconnectMonitorTask?.cancel()

    XCTAssertFalse(model.busy)
    XCTAssertEqual(model.currentDeviceName, "Recon Mouse")
  }
}
