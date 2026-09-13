// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import XCTest

@testable import LOPECore

final class AppSupportTests: XCTestCase {
  func testAppearancePreferenceOptions() {
    XCTAssertEqual(AppearancePreference.allCases, [.system, .light, .dark])
    XCTAssertEqual(AppearancePreference.system.label, "System")
    XCTAssertEqual(AppearancePreference.light.label, "Light")
    XCTAssertEqual(AppearancePreference.dark.label, "Dark")
  }

  func testAppConstants() {
    XCTAssertEqual(AppConstants.displayName, "LOPE")
    XCTAssertEqual(AppConstants.shortName, "LOPE")
    XCTAssertEqual(AppConstants.engineName, "lope")
    XCTAssertEqual(AppConstants.appSupportDirectory, "LOPE")
    XCTAssertEqual(AppConstants.defaultsPrefix, "LOPE")
    XCTAssertEqual(AppConstants.lastSelectedDeviceKey, "lastSelectedDevice")
    XCTAssertEqual(AppConstants.backupExtension, "logiob")
    XCTAssertEqual(AppConstants.appearancePreferenceKey, "appearancePreference")
  }

  func testEngineErrorDescriptions() {
    XCTAssertEqual(
      EngineError.unavailable.errorDescription,
      "The bundled HID++ engine could not be found.")
    XCTAssertEqual(EngineError.failed("boom").errorDescription, "boom")
    XCTAssertEqual(EngineError.failed("").errorDescription, "The HID++ engine failed.")
  }

  func testEngineRunnerRunSucceeds() throws {
    let output = try EngineRunner.run(
      executable: URL(fileURLWithPath: "/bin/echo"),
      arguments: ["hello"],
      currentDirectory: FileManager.default.temporaryDirectory
    )
    XCTAssertEqual(output, "hello\n")
  }

  func testEngineRunnerRunThrowsTrimmedFailureMessage() {
    XCTAssertThrowsError(
      try EngineRunner.run(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "echo boom 1>&2; exit 1"],
        currentDirectory: FileManager.default.temporaryDirectory
      )
    ) { error in
      guard case EngineError.failed(let message) = error else {
        XCTFail("expected EngineError.failed, got \(error)")
        return
      }
      XCTAssertEqual(message, "boom")
    }
  }

  private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLines: [String] = []
    var lines: [String] {
      lock.lock()
      defer { lock.unlock() }
      return storedLines
    }
    func add(_ line: String) {
      lock.lock()
      defer { lock.unlock() }
      storedLines.append(line)
    }
  }

  func testEngineRunnerLineProgressReportsLinesAndFinalOutput() throws {
    let collector = LineCollector()
    let output = try EngineRunner.runWithLineProgress(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "printf 'a\\nb\\nc'"],
      currentDirectory: FileManager.default.temporaryDirectory,
      onLine: { line in collector.add(line) }
    )
    XCTAssertEqual(output, "a\nb\nc")
    XCTAssertEqual(collector.lines, ["a", "b", "c"])
  }

  func testEngineRunnerLineProgressThrowsTrimmedFailureMessage() {
    XCTAssertThrowsError(
      try EngineRunner.runWithLineProgress(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "echo bad 1>&2; exit 2"],
        currentDirectory: FileManager.default.temporaryDirectory,
        onLine: { _ in }
      )
    ) { error in
      guard case EngineError.failed(let message) = error else {
        XCTFail("expected EngineError.failed, got \(error)")
        return
      }
      XCTAssertEqual(message, "bad")
    }
  }

  func testRefreshSnapshotAndDeviceEnumerationSnapshotFields() {
    let device = DeviceChoice(
      id: 1, name: "G604", connection: "Wired", productID: "0x1", deviceKey: "k")
    let refresh = RefreshSnapshot(
      devices: [device],
      selectedDeviceIndex: 0,
      profileText: "text",
      profileError: nil,
      dpiText: nil,
      dpiError: "err",
      selectedProfileNumber: 2,
      errorMessage: nil,
      accessWarning: true
    )
    XCTAssertEqual(refresh.devices, [device])
    XCTAssertEqual(refresh.selectedDeviceIndex, 0)
    XCTAssertEqual(refresh.profileText, "text")
    XCTAssertNil(refresh.profileError)
    XCTAssertNil(refresh.dpiText)
    XCTAssertEqual(refresh.dpiError, "err")
    XCTAssertEqual(refresh.selectedProfileNumber, 2)
    XCTAssertNil(refresh.errorMessage)
    XCTAssertTrue(refresh.accessWarning)

    let enumeration = DeviceEnumerationSnapshot(
      devices: [device], selectedDeviceIndex: nil, accessWarning: false, errorMessage: "boom")
    XCTAssertEqual(enumeration.devices, [device])
    XCTAssertNil(enumeration.selectedDeviceIndex)
    XCTAssertFalse(enumeration.accessWarning)
    XCTAssertEqual(enumeration.errorMessage, "boom")
  }
}
