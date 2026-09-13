// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

// Covers AppModel+DeviceDiscovery.swift. `runDeviceListWithRetry`,
// `makeDeviceEnumerationSnapshot`, and `startBackgroundDeviceEnumeration`
// all take their engine `executable` as an explicit parameter rather than
// reading `AppModel.engine`, so they can be exercised end-to-end against a
// small fake CLI script instead of real HID hardware — no need to touch
// `engineRunnerOverride` (which only wires up `AppModel.runEngine`, a
// different call path this file's functions do not use).
@MainActor
final class AppModelDeviceDiscoveryTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func tearDown() {
    for directory in temporaryDirectories {
      try? FileManager.default.removeItem(at: directory)
    }
    temporaryDirectories.removeAll()
    super.tearDown()
  }

  private func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lope-device-discovery-test-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    temporaryDirectories.append(url)
    return url
  }

  /// Writes an executable shell script standing in for the `lope` CLI.
  /// `body` is inlined verbatim as the script's implementation.
  private func makeFakeEngine(_ body: String) -> URL {
    let directory = makeTemporaryDirectory()
    let url = directory.appendingPathComponent("fake-lope")
    let script = "#!/bin/sh\n" + body + "\n"
    try! script.write(to: url, atomically: true, encoding: .utf8)
    try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
  }

  private func deviceListLine(
    id: Int, connection: String = "Wireless", name: String, productID: String, key: String
  ) -> String {
    "[\(id)] \(connection)  \(name) (HID++ 4.5, product \(productID), key \(key))"
  }

  // MARK: - runDeviceListWithRetry

  func testRunDeviceListWithRetrySucceedsImmediatelyWithNonEmptyList() throws {
    let counterFile = makeTemporaryDirectory().appendingPathComponent("count")
    let line = deviceListLine(id: 1, name: "Recon Mouse", productID: "0xAAAA", key: "aaaa-0001")
    let engine = makeFakeEngine(
      """
      printf '.' >> "\(counterFile.path)"
      echo '\(line)'
      exit 0
      """)

    let output = try AppModel.runDeviceListWithRetry(
      executable: engine, currentDirectory: makeTemporaryDirectory())
    XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), line)
    let attempts = (try? String(contentsOf: counterFile)) ?? ""
    XCTAssertEqual(attempts.count, 1, "expected a single attempt when the first list succeeds")
  }

  func testRunDeviceListWithRetryReturnsLastAttemptEvenWhenListStaysEmpty() throws {
    let counterFile = makeTemporaryDirectory().appendingPathComponent("count")
    let engine = makeFakeEngine(
      """
      printf '.' >> "\(counterFile.path)"
      exit 0
      """)

    let output = try AppModel.runDeviceListWithRetry(
      executable: engine, currentDirectory: makeTemporaryDirectory())
    XCTAssertEqual(output, "")
    let attempts = (try? String(contentsOf: counterFile)) ?? ""
    XCTAssertEqual(
      attempts.count, AppModelRefreshConfiguration.deviceReadAttempts,
      "an empty (but successful) list is retried until the final attempt, which is returned anyway"
    )
  }

  func testRunDeviceListWithRetryThrowsAfterExhaustingAttempts() throws {
    let counterFile = makeTemporaryDirectory().appendingPathComponent("count")
    let engine = makeFakeEngine(
      """
      printf '.' >> "\(counterFile.path)"
      echo "synthetic engine failure" 1>&2
      exit 1
      """)

    XCTAssertThrowsError(
      try AppModel.runDeviceListWithRetry(
        executable: engine, currentDirectory: makeTemporaryDirectory())
    ) { error in
      XCTAssertTrue(error.localizedDescription.contains("synthetic engine failure"))
    }
    let attempts = (try? String(contentsOf: counterFile)) ?? ""
    XCTAssertEqual(attempts.count, AppModelRefreshConfiguration.deviceReadAttempts)
  }

  func testRunDeviceListWithRetryRecoversAfterTransientFailures() throws {
    let counterFile = makeTemporaryDirectory().appendingPathComponent("count")
    let line = deviceListLine(id: 1, name: "Recon Mouse", productID: "0xAAAA", key: "aaaa-0001")
    // Fails on the first two attempts, then succeeds on the third — well
    // within deviceReadAttempts (3), so the retry loop must recover.
    let engine = makeFakeEngine(
      """
      printf '.' >> "\(counterFile.path)"
      count=$(wc -c < "\(counterFile.path)")
      if [ "$count" -lt 3 ]; then
        echo "still warming up" 1>&2
        exit 1
      fi
      echo '\(line)'
      exit 0
      """)

    let output = try AppModel.runDeviceListWithRetry(
      executable: engine, currentDirectory: makeTemporaryDirectory())
    XCTAssertEqual(output.trimmingCharacters(in: .whitespacesAndNewlines), line)
  }

  // MARK: - makeDeviceEnumerationSnapshot

  func testMakeDeviceEnumerationSnapshotPrefersKeyThenIndexThenFirst() {
    let lineA = deviceListLine(id: 1, name: "Mouse A", productID: "0xAAAA", key: "aaaa-a1")
    let lineB = deviceListLine(id: 2, name: "Mouse B", productID: "0xBBBB", key: "bbbb-b2")
    let engine = makeFakeEngine("echo '\(lineA)'; echo '\(lineB)'; exit 0")
    let directory = makeTemporaryDirectory()

    let byKey = AppModel.makeDeviceEnumerationSnapshot(
      executable: engine, currentDirectory: directory, preferredDeviceIndex: 1,
      preferredDeviceKey: "bbbb-b2")
    XCTAssertEqual(byKey.selectedDeviceIndex, 2, "an explicit key match wins even over the index")

    let byIndex = AppModel.makeDeviceEnumerationSnapshot(
      executable: engine, currentDirectory: directory, preferredDeviceIndex: 1,
      preferredDeviceKey: nil)
    XCTAssertEqual(byIndex.selectedDeviceIndex, 1)

    let byFirst = AppModel.makeDeviceEnumerationSnapshot(
      executable: engine, currentDirectory: directory, preferredDeviceIndex: 999,
      preferredDeviceKey: nil)
    XCTAssertEqual(byFirst.selectedDeviceIndex, 1, "falls back to the first discovered device")
    XCTAssertEqual(byFirst.devices.count, 2)
  }

  func testMakeDeviceEnumerationSnapshotDetectsAccessWarningText() {
    let line = deviceListLine(id: 1, name: "Mouse A", productID: "0xAAAA", key: "aaaa-000a")
    let engine = makeFakeEngine(
      """
      echo '\(line)'
      echo "macOS denied HID access to one interface" 1>&2
      exit 0
      """)
    let snapshot = AppModel.makeDeviceEnumerationSnapshot(
      executable: engine, currentDirectory: makeTemporaryDirectory(), preferredDeviceIndex: 0,
      preferredDeviceKey: nil)
    XCTAssertTrue(snapshot.accessWarning)
    XCTAssertNil(snapshot.errorMessage)
  }

  func testMakeDeviceEnumerationSnapshotReturnsErrorMessageOnFailure() {
    let engine = makeFakeEngine(
      """
      echo "engine is unavailable" 1>&2
      exit 1
      """)
    let snapshot = AppModel.makeDeviceEnumerationSnapshot(
      executable: engine, currentDirectory: makeTemporaryDirectory(), preferredDeviceIndex: 0,
      preferredDeviceKey: nil)
    XCTAssertTrue(snapshot.devices.isEmpty)
    XCTAssertNil(snapshot.selectedDeviceIndex)
    XCTAssertFalse(snapshot.accessWarning)
    XCTAssertEqual(snapshot.errorMessage, "engine is unavailable")
  }

  // MARK: - loadLastSelectedDevice / rememberSelectedDevice

  func testRememberAndLoadLastSelectedDeviceRoundTrips() {
    let key = "\(AppConstants.defaultsPrefix).\(AppConstants.lastSelectedDeviceKey)"
    let previousValue = UserDefaults.standard.data(forKey: key)
    defer {
      if let previousValue {
        UserDefaults.standard.set(previousValue, forKey: key)
      } else {
        UserDefaults.standard.removeObject(forKey: key)
      }
    }

    let model = AppModel(startInitialRefresh: false)
    let device = DeviceChoice(
      id: 3, name: "Remembered Mouse", connection: "Wireless", productID: "0xCCCC",
      deviceKey: "remembered-key")
    model.rememberSelectedDevice(device)
    XCTAssertEqual(model.loadLastSelectedDevice(), device)
  }

  func testLoadLastSelectedDeviceReturnsNilWhenNothingStored() {
    let key = "\(AppConstants.defaultsPrefix).\(AppConstants.lastSelectedDeviceKey)"
    let previousValue = UserDefaults.standard.data(forKey: key)
    UserDefaults.standard.removeObject(forKey: key)
    defer {
      if let previousValue { UserDefaults.standard.set(previousValue, forKey: key) }
    }

    let model = AppModel(startInitialRefresh: false)
    XCTAssertNil(model.loadLastSelectedDevice())
  }

  // MARK: - startBackgroundDeviceEnumeration

  func testStartBackgroundDeviceEnumerationUpdatesStateOnMatch() async {
    let cachedDevice = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-0001")
    let line = deviceListLine(
      id: 1, name: cachedDevice.name, productID: cachedDevice.productID,
      key: cachedDevice.deviceKey)
    let engine = makeFakeEngine("echo '\(line)'; exit 0")

    let model = AppModel(startInitialRefresh: false)
    model.startBackgroundDeviceEnumeration(
      executable: engine, currentDirectory: makeTemporaryDirectory(), cachedDevice: cachedDevice,
      generation: model.refreshGeneration)
    await model.refreshTask?.value

    XCTAssertEqual(model.devices.map(\.deviceKey), [cachedDevice.deviceKey])
    XCTAssertEqual(model.selectedDeviceIndex, 1)
    XCTAssertEqual(model.currentDeviceName, cachedDevice.name)
    XCTAssertEqual(model.deviceSummary, cachedDevice.title)
    XCTAssertNil(model.refreshTask)
  }

  func testStartBackgroundDeviceEnumerationFallsBackWhenCachedDeviceIsGone() async {
    let cachedDevice = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-9999")
    let fallbackLine = deviceListLine(
      id: 5, name: "Other Mouse", productID: "0xDDDD", key: "dddd-0005")
    let engine = makeFakeEngine("echo '\(fallbackLine)'; exit 0")

    let model = AppModel(startInitialRefresh: false)
    model.startBackgroundDeviceEnumeration(
      executable: engine, currentDirectory: makeTemporaryDirectory(), cachedDevice: cachedDevice,
      generation: model.refreshGeneration)
    await model.refreshTask?.value

    XCTAssertEqual(model.devices.map(\.deviceKey), ["dddd-0005"])
    XCTAssertEqual(model.selectedDeviceIndex, 5)
    // Falling back hands off to startRefresh(), which (with no bundled
    // engine reachable through AppModel.engine in the test environment)
    // synchronously reports the engine as unavailable — observable proof
    // that the fallback path really did call startRefresh().
    XCTAssertEqual(model.status, EngineError.unavailable.localizedDescription)
  }

  func testStartBackgroundDeviceEnumerationClearsStateWhenNoDevicesRemain() async {
    let cachedDevice = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-9999")
    let engine = makeFakeEngine("exit 0")

    let model = AppModel(startInitialRefresh: false)
    model.startBackgroundDeviceEnumeration(
      executable: engine, currentDirectory: makeTemporaryDirectory(), cachedDevice: cachedDevice,
      generation: model.refreshGeneration)
    await model.refreshTask?.value

    XCTAssertTrue(model.devices.isEmpty)
    XCTAssertEqual(model.selectedDeviceIndex, 0)
    XCTAssertEqual(model.currentDeviceName, "")
    XCTAssertEqual(model.deviceSummary, "No editable Logitech mouse found")
    XCTAssertEqual(model.status, "No Logitech mouse was found.")
  }

  func testStartBackgroundDeviceEnumerationReportsErrorMessage() async {
    let cachedDevice = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-0001")
    let engine = makeFakeEngine(
      """
      echo "device list unreadable" 1>&2
      exit 1
      """)

    let model = AppModel(startInitialRefresh: false)
    model.startBackgroundDeviceEnumeration(
      executable: engine, currentDirectory: makeTemporaryDirectory(), cachedDevice: cachedDevice,
      generation: model.refreshGeneration)
    await model.refreshTask?.value

    XCTAssertTrue(model.status.contains(cachedDevice.name))
    XCTAssertTrue(model.status.contains("could not be refreshed"))
    XCTAssertTrue(model.status.contains("device list unreadable"))
  }

  func testStartBackgroundDeviceEnumerationIgnoresStaleGeneration() async {
    let cachedDevice = DeviceChoice(
      id: 1, name: "Recon Mouse", connection: "Wireless", productID: "0xAAAA",
      deviceKey: "aaaa-0001")
    let line = deviceListLine(
      id: 1, name: cachedDevice.name, productID: cachedDevice.productID,
      key: cachedDevice.deviceKey)
    let engine = makeFakeEngine("echo '\(line)'; exit 0")

    let model = AppModel(startInitialRefresh: false)
    model.refreshGeneration = 5
    model.startBackgroundDeviceEnumeration(
      executable: engine, currentDirectory: makeTemporaryDirectory(), cachedDevice: cachedDevice,
      // A stale generation: the enumeration finishes, but the model has
      // since moved on to a newer refresh, so the result must be dropped.
      generation: 1)
    await model.refreshTask?.value

    XCTAssertTrue(model.devices.isEmpty)
    XCTAssertEqual(model.currentDeviceName, "")
  }
}
