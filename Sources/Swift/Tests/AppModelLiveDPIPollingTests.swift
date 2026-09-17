// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelLiveDPIPollingTests: XCTestCase {
  override func tearDown() {
    FakeEngineEnvironment.clearAll()
    super.tearDown()
  }

  // MARK: - startLiveDPIPolling guard branches

  func testStartLiveDPIPollingDoesNothingWhenEngineUnavailable() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = DPICapabilities(sensorCount: 1)

    // No fake engine is on the search path here, so `engine` resolves to
    // nil, matching every other test in this suite that does not opt into
    // ProcessDirectory.withCurrentDirectory.
    model.startLiveDPIPolling()

    XCTAssertNil(model.liveDPIPollTask)
  }

  func testStartLiveDPIPollingDoesNothingWhenSelectedDeviceIsMissing() {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)

    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = DPICapabilities(sensorCount: 1)
    model.selectedDeviceIndex = 999

    ProcessDirectory.withCurrentDirectory(tempDir.path) {
      model.startLiveDPIPolling()
    }

    XCTAssertNil(model.liveDPIPollTask)
  }

  func testStartLiveDPIPollingDoesNothingWhenProfilesAreEmpty() {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)

    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.profiles = []
    model.dpiCapabilities = DPICapabilities(sensorCount: 1)

    ProcessDirectory.withCurrentDirectory(tempDir.path) {
      model.startLiveDPIPolling()
    }

    XCTAssertNil(model.liveDPIPollTask)
  }

  func testStartLiveDPIPollingDoesNothingWhenSensorCountIsUnknown() {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)

    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    // Fixture leaves dpiCapabilities at its default, sensorCount == nil.

    ProcessDirectory.withCurrentDirectory(tempDir.path) {
      model.startLiveDPIPolling()
    }

    XCTAssertNil(model.liveDPIPollTask)
  }

  // MARK: - startLiveDPIPolling loop behavior

  func testStartLiveDPIPollingUpdatesCurrentValueFromEngineOutput() async {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_CURRENT_DPI_OUTPUT", fakeStructuredCurrentDPIOutput(1600))
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = DPICapabilities(sensorCount: 1)

    ProcessDirectory.withCurrentDirectory(tempDir.path) {
      model.startLiveDPIPolling()
    }
    XCTAssertNotNil(model.liveDPIPollTask)

    await waitUntil { model.dpiCapabilities.currentValue == 1600 }

    model.stopLiveDPIPolling()
    XCTAssertNil(model.liveDPIPollTask)
  }

  func testStartLiveDPIPollingSkipsUpdatesWhileBusy() async {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_CURRENT_DPI_OUTPUT", fakeStructuredCurrentDPIOutput(1600))
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = DPICapabilities(sensorCount: 1)

    ProcessDirectory.withCurrentDirectory(tempDir.path) {
      model.startLiveDPIPolling()
    }
    await waitUntil { model.dpiCapabilities.currentValue == 1600 }

    model.busy = true
    FakeEngineEnvironment.set("LOPE_TEST_CURRENT_DPI_OUTPUT", fakeStructuredCurrentDPIOutput(1800))
    // One full poll interval (500ms) plus margin: the busy guard should
    // make every tick `continue` before the value is re-read.
    try? await Task.sleep(nanoseconds: 800_000_000)
    XCTAssertEqual(model.dpiCapabilities.currentValue, 1600)

    model.busy = false
    await waitUntil { model.dpiCapabilities.currentValue == 1800 }

    model.stopLiveDPIPolling()
  }

  func testStartLiveDPIPollingSkipsUpdatesWhenSelectedDeviceChanges() async {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_CURRENT_DPI_OUTPUT", fakeStructuredCurrentDPIOutput(1600))
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = DPICapabilities(sensorCount: 1)
    model.devices.append(
      DeviceChoice(
        id: 2, name: "G603", connection: "Wireless", productID: "0xB01C", deviceKey: "other"))

    ProcessDirectory.withCurrentDirectory(tempDir.path) {
      model.startLiveDPIPolling()
    }

    // Switch the active device before the first tick fires; the poll loop
    // captured the original device id and must not apply reads meant for it
    // to whatever is now selected.
    model.selectedDeviceIndex = 2
    try? await Task.sleep(nanoseconds: 800_000_000)
    XCTAssertNil(model.dpiCapabilities.currentValue)

    model.stopLiveDPIPolling()
  }

  func testStartLiveDPIPollingLeavesCurrentValueUnchangedWhenReadFails() async {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_CURRENT_DPI_EXIT", "1")
    defer { FakeEngineEnvironment.clearAll() }

    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.dpiCapabilities = DPICapabilities(sensorCount: 1)

    ProcessDirectory.withCurrentDirectory(tempDir.path) {
      model.startLiveDPIPolling()
    }
    try? await Task.sleep(nanoseconds: 800_000_000)
    XCTAssertNil(model.dpiCapabilities.currentValue)

    model.stopLiveDPIPolling()
  }

  func testStopLiveDPIPollingCancelsAndClearsTask() {
    let model = AppModel(startInitialRefresh: false)
    model.stopLiveDPIPolling()
    XCTAssertNil(model.liveDPIPollTask)
  }

  // MARK: - readCurrentSensorDPI

  func testReadCurrentSensorDPIUsesDeviceKeySelectorWhenAvailable() {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let engine = FakeEngine.write(to: tempDir)
    let logURL = tempDir.appendingPathComponent("args.log")
    FakeEngineEnvironment.set("LOPE_TEST_ARGS_LOG", logURL.path)
    FakeEngineEnvironment.set("LOPE_TEST_CURRENT_DPI_OUTPUT", fakeStructuredCurrentDPIOutput(800))
    defer { FakeEngineEnvironment.clearAll() }

    let result = AppModel.readCurrentSensorDPI(
      executable: engine,
      currentDirectory: tempDir,
      deviceKey: "abc123",
      deviceIndex: 7
    )

    XCTAssertEqual(result, 800)
    let loggedArgs = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    XCTAssertTrue(loggedArgs.contains("--device-key abc123 current-dpi"), loggedArgs)
  }

  func testReadCurrentSensorDPIFallsBackToDeviceIndexSelectorWhenKeyIsEmpty() {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let engine = FakeEngine.write(to: tempDir)
    let logURL = tempDir.appendingPathComponent("args.log")
    FakeEngineEnvironment.set("LOPE_TEST_ARGS_LOG", logURL.path)
    FakeEngineEnvironment.set("LOPE_TEST_CURRENT_DPI_OUTPUT", fakeStructuredCurrentDPIOutput(800))
    defer { FakeEngineEnvironment.clearAll() }

    let result = AppModel.readCurrentSensorDPI(
      executable: engine,
      currentDirectory: tempDir,
      deviceKey: "",
      deviceIndex: 7
    )

    XCTAssertEqual(result, 800)
    let loggedArgs = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    XCTAssertTrue(loggedArgs.contains("--device 7 current-dpi"), loggedArgs)
  }

  func testReadCurrentSensorDPIReturnsNilWhenEngineFails() {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let engine = FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_CURRENT_DPI_EXIT", "1")
    defer { FakeEngineEnvironment.clearAll() }

    let result = AppModel.readCurrentSensorDPI(
      executable: engine,
      currentDirectory: tempDir,
      deviceKey: "abc123",
      deviceIndex: 7
    )

    XCTAssertNil(result)
  }

  func testReadCurrentSensorDPIReturnsNilWhenOutputIsUnparsable() {
    let tempDir = TestTempDirectory.make()
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let engine = FakeEngine.write(to: tempDir)
    FakeEngineEnvironment.set("LOPE_TEST_CURRENT_DPI_OUTPUT", "garbage, no matching line\n")
    defer { FakeEngineEnvironment.clearAll() }

    let result = AppModel.readCurrentSensorDPI(
      executable: engine,
      currentDirectory: tempDir,
      deviceKey: "abc123",
      deviceIndex: 7
    )

    XCTAssertNil(result)
  }
}
