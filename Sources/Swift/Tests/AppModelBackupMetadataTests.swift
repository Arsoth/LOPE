// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelBackupMetadataTests: XCTestCase {
  private func makeTempConfigurationDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lope-backup-metadata-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  /// Builds a minimal binary backup package matching the "LOGIOB02" header
  /// `backupDeviceMetadata` inspects: an 8-byte magic, two padding bytes,
  /// a big-endian vendor ID, and a big-endian product ID.
  private func makeBinaryBackupData(vendorID: UInt16, productID: UInt16) -> Data {
    var data = Data("LOGIOB02".utf8)
    data.append(contentsOf: [0x00, 0x00])
    data.append(UInt8(vendorID >> 8))
    data.append(UInt8(vendorID & 0xFF))
    data.append(UInt8(productID >> 8))
    data.append(UInt8(productID & 0xFF))
    while data.count < 20 { data.append(0x00) }
    return data
  }

  private func writeEditableBackupJSON(
    to url: URL, deviceName: String, productID: String
  ) throws {
    let backup = EditableBackup(
      formatVersion: 1,
      createdAt: "2026-01-01T00:00:00Z",
      device: EditableBackup.Device(name: deviceName, productID: productID),
      profiles: [EditableBackup.ProfileState(number: 2, enabled: true)],
      profile: EditableBackup.Profile(
        number: 2, sector: "0x0100", enabled: true, buttons: [], dpi: nil),
      exactBinaryBackup: nil
    )
    try JSONEncoder().encode(backup).write(to: url)
  }

  // MARK: - setShowAllBackups / applyBackupFilter

  func testSetShowAllBackupsTogglesFilteredList() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let selected = BackupEntry(
      url: URL(fileURLWithPath: "/tmp/selected.logiob"),
      modifiedAt: Date(), size: 10, deviceMatch: .selected, deviceName: "G502 X")
    let other = BackupEntry(
      url: URL(fileURLWithPath: "/tmp/other.logiob"),
      modifiedAt: Date(), size: 10, deviceMatch: .other, deviceName: "G604")
    model.discoveredBackups = [selected, other]

    model.setShowAllBackups(false)
    XCTAssertEqual(model.backups.map(\.id), [selected.id])

    model.setShowAllBackups(true)
    XCTAssertEqual(Set(model.backups.map(\.id)), Set([selected.id, other.id]))
  }

  // MARK: - refreshBackups / backupDeviceMetadata / backupDeviceMatch

  func testRefreshBackupsClassifiesJSONBinaryAndUnknownEntries() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let directory = try makeTempConfigurationDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    model.configurationDirectory = directory
    try FileManager.default.createDirectory(
      at: model.backupDirectory, withIntermediateDirectories: true)

    // JSON backup whose device metadata matches the selected mouse by
    // product ID.
    let matchingJSON = model.backupDirectory.appendingPathComponent("matching.json")
    try writeEditableBackupJSON(to: matchingJSON, deviceName: "G502 X", productID: "0x0000")

    // JSON backup for a different, unrelated mouse.
    let otherJSON = model.backupDirectory.appendingPathComponent("other.json")
    try writeEditableBackupJSON(to: otherJSON, deviceName: "G604", productID: "0x4085")

    // JSON backup with empty device metadata entirely -> unknown.
    let blankJSON = model.backupDirectory.appendingPathComponent("blank.json")
    try writeEditableBackupJSON(to: blankJSON, deviceName: "", productID: "")

    // Malformed JSON -> decode fails -> nil metadata -> unknown.
    let malformedJSON = model.backupDirectory.appendingPathComponent("malformed.json")
    try Data("not json".utf8).write(to: malformedJSON)

    // Binary backup matching by product ID.
    let matchingBinary = model.backupDirectory.appendingPathComponent(
      "unrelated-name-profile-1-initial-20260101-000000.logiob")
    try makeBinaryBackupData(vendorID: 0x046D, productID: 0x0000).write(to: matchingBinary)

    // Binary backup matching only via the mouse-family filename fallback
    // (product ID differs, but the G502-X family token match succeeds).
    let familyBinary = model.backupDirectory.appendingPathComponent(
      "G502-X-PLUS-profile-1-initial-20260101-000000.logiob")
    try makeBinaryBackupData(vendorID: 0x046D, productID: 0x0001).write(to: familyBinary)

    // Binary backup for a different vendor entirely -> nil metadata -> unknown.
    let wrongVendorBinary = model.backupDirectory.appendingPathComponent(
      "wrong-vendor-profile-1-initial-20260101-000000.logiob")
    try makeBinaryBackupData(vendorID: 0x1234, productID: 0x0000).write(to: wrongVendorBinary)

    // Binary backup too short to contain a header -> nil metadata -> unknown.
    let truncatedBinary = model.backupDirectory.appendingPathComponent("truncated.logiob")
    try Data([0x01, 0x02]).write(to: truncatedBinary)

    // A different, non-matching binary backup -> "other".
    let differentProductBinary = model.backupDirectory.appendingPathComponent(
      "g604-profile-1-initial-20260101-000000.logiob")
    try makeBinaryBackupData(vendorID: 0x046D, productID: 0x4085).write(to: differentProductBinary)

    model.refreshBackups()

    func match(for url: URL) -> BackupEntry.DeviceMatch? {
      model.discoveredBackups.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }
      )?.deviceMatch
    }

    XCTAssertEqual(match(for: matchingJSON), .selected)
    XCTAssertEqual(match(for: otherJSON), .other)
    XCTAssertEqual(match(for: blankJSON), .unknown)
    XCTAssertEqual(match(for: malformedJSON), .unknown)
    XCTAssertEqual(match(for: matchingBinary), .selected)
    XCTAssertEqual(match(for: familyBinary), .selected)
    XCTAssertEqual(match(for: wrongVendorBinary), .unknown)
    XCTAssertEqual(match(for: truncatedBinary), .unknown)
    XCTAssertEqual(match(for: differentProductBinary), .other)

    // applyBackupFilter ran as part of refreshBackups(): only the
    // ".selected" entries are visible until "show all" is toggled on.
    let visibleURLs = Set(model.backups.map { $0.url.standardizedFileURL })
    let expectedSelectedURLs = Set(
      [matchingJSON, matchingBinary, familyBinary].map { $0.standardizedFileURL })
    XCTAssertEqual(visibleURLs, expectedSelectedURLs)
  }

  func testRefreshBackupsReturnsUnknownWhenNoDeviceSelected() throws {
    let model = AppModel(startInitialRefresh: false)
    let directory = try makeTempConfigurationDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    model.configurationDirectory = directory
    try FileManager.default.createDirectory(
      at: model.backupDirectory, withIntermediateDirectories: true)
    // No devices configured, so selectedDeviceIndex matches nothing.
    let json = model.backupDirectory.appendingPathComponent("orphan.json")
    try writeEditableBackupJSON(to: json, deviceName: "G502 X", productID: "0x0000")

    model.refreshBackups()

    XCTAssertEqual(model.discoveredBackups.first?.deviceMatch, .unknown)
  }

  // MARK: - sanitizedMouseIdentifier / backupTimestamp

  func testSanitizedMouseIdentifierDelegatesToBackupStorage() {
    let model = AppModel(startInitialRefresh: false)
    XCTAssertEqual(
      model.sanitizedMouseIdentifier("G502 X/PLUS"),
      BackupStorage.sanitizedMouseIdentifier("G502 X/PLUS"))
    XCTAssertEqual(
      model.sanitizedMouseIdentifier("!!!", fallback: "fallback-mouse"), "fallback-mouse")
  }

  func testBackupTimestampFormatsFixedDate() {
    let model = AppModel(startInitialRefresh: false)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let components = DateComponents(
      year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5)
    let date = calendar.date(from: components)!
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    XCTAssertEqual(model.backupTimestamp(date), formatter.string(from: date))
  }

  // MARK: - selectedMouseFileIdentifier / editableJSONExportName

  func testSelectedMouseFileIdentifierUsesSelectedDeviceWhenAvailable() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    XCTAssertEqual(model.selectedMouseFileIdentifier(), "G502-X")
  }

  func testSelectedMouseFileIdentifierFallsBackToCurrentDeviceName() {
    let model = AppModel(startInitialRefresh: false)
    model.devices = []
    model.selectedDeviceIndex = 99
    model.currentDeviceName = "Unmatched Mouse"
    XCTAssertEqual(model.selectedMouseFileIdentifier(), "Unmatched-Mouse")
  }

  func testEditableJSONExportNameEndsWithJSONExtensionAndMouseIdentifier() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let name = model.editableJSONExportName()
    XCTAssertTrue(name.hasSuffix(".json"))
    XCTAssertTrue(name.contains("G502-X"))
    XCTAssertTrue(name.contains("profile-2-export"))
  }

  // MARK: - uniqueBackupStem / uniqueBackupURL / mouseBackupDirectory

  func testUniqueBackupStemAndURLUseModelDirectoryAndMouseIdentifier() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let directory = try makeTempConfigurationDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    model.configurationDirectory = directory

    let stem = model.uniqueBackupStem(prefix: "profile-2-save")
    XCTAssertTrue(stem.hasPrefix("G502-X-profile-2-save-"))

    let url = model.uniqueBackupURL(prefix: "profile-2-save")
    XCTAssertEqual(url.pathExtension, AppConstants.backupExtension)
    XCTAssertEqual(
      url.deletingLastPathComponent().standardizedFileURL,
      model.mouseBackupDirectory().standardizedFileURL)
  }

  func testMouseBackupDirectoryHonorsExplicitIdentifierOverride() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let overridden = model.mouseBackupDirectory(for: "Custom Mouse")
    XCTAssertEqual(
      overridden.standardizedFileURL,
      BackupStorage.modelDirectory(root: model.backupDirectory, mouseIdentifier: "Custom Mouse")
        .standardizedFileURL)
  }

  func testDefaultDocumentsDirectoryMatchesBackupStorage() {
    let model = AppModel(startInitialRefresh: false)
    XCTAssertEqual(model.defaultDocumentsDirectory, BackupStorage.documentsDirectory())
  }

  // MARK: - scheduleInitialBackups / hasBinaryBackup

  func testScheduleInitialBackupsNoOpWhenProfileNumbersEmpty() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let device = model.devices[0]
    model.scheduleInitialBackups(for: device, profileNumbers: [])
    XCTAssertTrue(model.initialBackupKeys.isEmpty)
  }

  func testScheduleInitialBackupsNoOpWhenBinaryBackupAlreadyExists() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let device = model.devices[0]
    model.discoveredBackups = [
      BackupEntry(
        url: URL(fileURLWithPath: "/tmp/existing.logiob"),
        modifiedAt: Date(), size: 1, deviceMatch: .selected, deviceName: "G502 X")
    ]
    model.scheduleInitialBackups(for: device, profileNumbers: [2])
    XCTAssertTrue(model.initialBackupKeys.isEmpty)
  }

  func testScheduleInitialBackupsIgnoresBinaryBackupForADifferentDevice() {
    // hasBinaryBackup's device-key guard should fail when the currently
    // selected device does not match the device passed in, so a binary
    // backup belonging to some other selection must not block scheduling.
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.discoveredBackups = [
      BackupEntry(
        url: URL(fileURLWithPath: "/tmp/existing.logiob"),
        modifiedAt: Date(), size: 1, deviceMatch: .selected, deviceName: "G502 X")
    ]
    let unrelatedDevice = DeviceChoice(
      id: 1, name: "G502 X", connection: "Wired", productID: "0x0000",
      deviceKey: "a-different-key")
    model.scheduleInitialBackups(for: unrelatedDevice, profileNumbers: [2])
    // engine is unavailable in the test environment, so the key is
    // inserted and then left in place (only the async completion, which
    // never runs without a real engine executable, removes it).
    XCTAssertEqual(
      model.initialBackupKeys, ["0x0000|g502 x"])
  }

  func testScheduleInitialBackupsInsertsKeyWhenEngineUnavailable() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let device = model.devices[0]
    XCTAssertNil(model.engine, "test environment must not have a bundled/dev engine binary")
    model.scheduleInitialBackups(for: device, profileNumbers: [2])
    XCTAssertEqual(model.initialBackupKeys, ["0x0000|g502 x"])

    // A second call with the same device is a no-op because the key is
    // already present.
    model.scheduleInitialBackups(for: device, profileNumbers: [2])
    XCTAssertEqual(model.initialBackupKeys, ["0x0000|g502 x"])
  }

  // MARK: - scheduleInitialBackups async dump path (fake `engine` binary)

  /// `engine` resolves to `<cwd>/bin/lope` when no app bundle resource is
  /// present, which is exactly the case under `swift test`. Writing a tiny
  /// executable shell script there and briefly pointing the process's
  /// current directory at it lets `scheduleInitialBackups`'s background
  /// `Task` actually run an "engine" instead of bailing out early, without
  /// touching the real repository binary. `engine` is only read
  /// synchronously inside `scheduleInitialBackups` itself (captured into a
  /// local `let` before the `Task` is created), so the working directory
  /// only needs to be correct for that one call and is restored
  /// immediately afterward.
  ///
  /// The script sleeps briefly so tests have a window to observe
  /// in-flight state, then fails any invocation whose "--profile" argument
  /// is immediately followed by "2".
  private func withFakeEngine(_ body: (URL) async throws -> Void) async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(
      "lope-fake-engine-\(UUID().uuidString)", isDirectory: true)
    let binDirectory = root.appendingPathComponent("bin", isDirectory: true)
    try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
    let scriptURL = binDirectory.appendingPathComponent("lope")
    let script = """
      #!/bin/sh
      sleep 0.05
      prev=""
      for arg in "$@"; do
        if [ "$prev" = "--profile" ] && [ "$arg" = "2" ]; then
          exit 1
        fi
        prev="$arg"
      done
      exit 0
      """
    try script.write(to: scriptURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    defer { try? fileManager.removeItem(at: root) }
    try await body(root)
  }

  /// Points the process's current directory at `root` only for the
  /// duration of `scheduleInitialBackups`'s own synchronous `engine`
  /// lookup, then restores it, so the background `Task` it starts is
  /// unaffected by the change.
  private func callScheduleInitialBackups(
    _ model: AppModel, fakeEngineRoot root: URL, device: DeviceChoice, profileNumbers: [Int]
  ) {
    let fileManager = FileManager.default
    let originalDirectory = fileManager.currentDirectoryPath
    _ = fileManager.changeCurrentDirectoryPath(root.path)
    model.scheduleInitialBackups(for: device, profileNumbers: profileNumbers)
    _ = fileManager.changeCurrentDirectoryPath(originalDirectory)
  }

  func testScheduleInitialBackupsRunsDumpForEachProfileAndReportsSuccess() async throws {
    try await withFakeEngine { root in
      let model = AppModel(startInitialRefresh: false)
      configureFixtureDevice(model)
      let directory = try makeTempConfigurationDirectory()
      model.configurationDirectory = directory
      try FileManager.default.createDirectory(
        at: model.backupDirectory, withIntermediateDirectories: true)
      let device = model.devices[0]

      callScheduleInitialBackups(model, fakeEngineRoot: root, device: device, profileNumbers: [1])
      XCTAssertEqual(model.initialBackupKeys, ["0x0000|g502 x"])

      let deadline = Date().addingTimeInterval(5)
      while model.initialBackupKeys.contains("0x0000|g502 x") && Date() < deadline {
        try await Task.sleep(nanoseconds: 10_000_000)
      }

      XCTAssertTrue(model.initialBackupKeys.isEmpty)
      XCTAssertEqual(model.status, "Created initial backups for 1 onboard profile(s).")
      try? FileManager.default.removeItem(at: directory)
    }
  }

  func testScheduleInitialBackupsReportsPartialFailureCount() async throws {
    try await withFakeEngine { root in
      let model = AppModel(startInitialRefresh: false)
      configureFixtureDevice(model)
      let directory = try makeTempConfigurationDirectory()
      model.configurationDirectory = directory
      try FileManager.default.createDirectory(
        at: model.backupDirectory, withIntermediateDirectories: true)
      let device = model.devices[0]

      // Profile 2 is rigged to fail by the fake engine script; profile 1
      // succeeds.
      callScheduleInitialBackups(
        model, fakeEngineRoot: root, device: device, profileNumbers: [1, 2])

      let key = "0x0000|g502 x"
      let deadline = Date().addingTimeInterval(5)
      while model.initialBackupKeys.contains(key) && Date() < deadline {
        try await Task.sleep(nanoseconds: 10_000_000)
      }

      XCTAssertTrue(model.initialBackupKeys.isEmpty)
      XCTAssertEqual(
        model.status, "Created initial backups for 1 onboard profile(s). (1 could not be saved.)")
      try? FileManager.default.removeItem(at: directory)
    }
  }

  func testScheduleInitialBackupsSkipsStatusUpdateWhenSelectionChangedDuringDump() async throws {
    try await withFakeEngine { root in
      let model = AppModel(startInitialRefresh: false)
      configureFixtureDevice(model)
      let directory = try makeTempConfigurationDirectory()
      model.configurationDirectory = directory
      try FileManager.default.createDirectory(
        at: model.backupDirectory, withIntermediateDirectories: true)
      let device = model.devices[0]
      let statusBeforeCompletion = model.status

      callScheduleInitialBackups(model, fakeEngineRoot: root, device: device, profileNumbers: [1])
      // The fake engine sleeps briefly before exiting, leaving a window to
      // simulate the mouse reconnecting with a new HID++ device key while
      // the dump is still in flight.
      model.devices = [
        DeviceChoice(
          id: 1, name: "G502 X", connection: "Wired", productID: "0x0000",
          deviceKey: "reconnected-with-a-new-key")
      ]

      let key = "0x0000|g502 x"
      let deadline = Date().addingTimeInterval(5)
      while model.initialBackupKeys.contains(key) && Date() < deadline {
        try await Task.sleep(nanoseconds: 10_000_000)
      }

      XCTAssertTrue(model.initialBackupKeys.isEmpty, "the key is still removed on completion")
      XCTAssertEqual(
        model.status, statusBeforeCompletion,
        "status must not describe a backup for a device that is no longer selected")
      try? FileManager.default.removeItem(at: directory)
    }
  }
}
