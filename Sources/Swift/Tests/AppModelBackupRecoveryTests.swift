// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelBackupRecoveryTests: XCTestCase {
  private func makeTempConfigurationDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lope-backup-recovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func makeExistingBackupFile(in directory: URL, named name: String) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try Data([0x01, 0x02]).write(to: url)
    return url
  }

  // MARK: - restoreLastSaveBackups

  func testRestoreLastSaveBackupsNoOpWhenBusy() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.busy = true
    model.recoveryBackups = [URL(fileURLWithPath: "/tmp/does-not-matter.logiob")]
    model.restoreLastSaveBackups()
    XCTAssertEqual(model.recoveryBackups.count, 1, "busy guard should prevent any mutation")
  }

  func testRestoreLastSaveBackupsNoOpWhenEmpty() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.recoveryBackups = []
    let originalStatus = model.status
    model.restoreLastSaveBackups()
    XCTAssertEqual(model.status, originalStatus)
  }

  func testRestoreLastSaveBackupsClearsWhenDeviceMismatch() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.recoveryDeviceKey = "a-different-device"
    model.recoveryBackups = [URL(fileURLWithPath: "/tmp/whatever.logiob")]
    model.restoreLastSaveBackups()
    XCTAssertTrue(model.recoveryBackups.isEmpty)
    XCTAssertNil(model.recoveryDeviceKey)
    XCTAssertTrue(model.status.contains("different selected mouse"))
  }

  func testRestoreLastSaveBackupsClearsWhenFilesMissing() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.recoveryDeviceKey = "test-device"
    model.recoveryBackups = [
      FileManager.default.temporaryDirectory.appendingPathComponent(
        "lope-missing-\(UUID().uuidString).logiob")
    ]
    model.restoreLastSaveBackups()
    XCTAssertTrue(model.recoveryBackups.isEmpty)
    XCTAssertNil(model.recoveryDeviceKey)
    XCTAssertTrue(model.status.contains("no longer available"))
  }

  func testRestoreLastSaveBackupsSuccessRestoresAllAndClearsQueue() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let directory = try makeTempConfigurationDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    model.configurationDirectory = directory

    let first = try makeExistingBackupFile(in: directory, named: "first.logiob")
    let second = try makeExistingBackupFile(in: directory, named: "second.logiob")
    model.recoveryDeviceKey = "test-device"
    model.recoveryBackups = [first, second]

    var recordedCalls = [[String]]()
    model.engineRunnerOverride = { arguments in
      recordedCalls.append(arguments)
      return ""
    }

    model.restoreLastSaveBackups()

    XCTAssertTrue(model.recoveryBackups.isEmpty)
    XCTAssertNil(model.recoveryDeviceKey)
    XCTAssertTrue(model.status.contains("Restored and verified 2 sector backup(s)"))
    XCTAssertEqual(recordedCalls.count, 2)
    XCTAssertEqual(recordedCalls[0], BackupStorage.restoreArguments(for: first))
    XCTAssertEqual(recordedCalls[1], BackupStorage.restoreArguments(for: second))
    XCTAssertFalse(model.busy)
  }

  func testRestoreLastSaveBackupsPartialFailureKeepsRemaining() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let directory = try makeTempConfigurationDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    model.configurationDirectory = directory

    let first = try makeExistingBackupFile(in: directory, named: "first.logiob")
    let second = try makeExistingBackupFile(in: directory, named: "second.logiob")
    model.recoveryDeviceKey = "test-device"
    model.recoveryBackups = [first, second]

    var callCount = 0
    model.engineRunnerOverride = { _ in
      callCount += 1
      if callCount == 2 {
        throw EngineError.failed("simulated restore failure")
      }
      return ""
    }

    model.restoreLastSaveBackups()

    XCTAssertEqual(model.recoveryBackups, [second])
    XCTAssertTrue(model.status.contains("Restored 1 sector backup(s), but recovery stopped"))
    XCTAssertTrue(model.status.contains("simulated restore failure"))
  }

  // MARK: - dumpBackup

  func testDumpBackupNoOpWhenBusy() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.busy = true
    let originalStatus = model.status
    model.dumpBackup()
    XCTAssertEqual(model.status, originalStatus)
  }

  func testDumpBackupSuccessCreatesDirectoryAndReportsPath() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let directory = try makeTempConfigurationDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    model.configurationDirectory = directory

    var recordedCalls = [[String]]()
    model.engineRunnerOverride = { arguments in
      recordedCalls.append(arguments)
      return ""
    }

    model.dumpBackup()

    XCTAssertFalse(model.busy)
    XCTAssertTrue(model.status.contains("Saved a read-only profile backup at"))
    XCTAssertTrue(model.status.contains("profile-2-manual"))
    XCTAssertEqual(recordedCalls.count, 1)
    XCTAssertEqual(Array(recordedCalls[0].prefix(3)), ["--profile", "2", "dump"])
    XCTAssertTrue(recordedCalls[0].last?.contains("profile-2-manual") == true)
  }

  func testDumpBackupFailureReportsEngineError() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let directory = try makeTempConfigurationDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    model.configurationDirectory = directory

    model.engineRunnerOverride = { _ in
      throw EngineError.failed("dump failed")
    }

    model.dumpBackup()

    XCTAssertFalse(model.busy)
    XCTAssertEqual(model.status, "dump failed")
  }

  // MARK: - restore(_:)

  func testRestoreNoOpWhenBusy() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.busy = true
    let originalStatus = model.status
    model.restore(URL(fileURLWithPath: "/tmp/whatever.logiob"))
    XCTAssertEqual(model.status, originalStatus)
  }

  func testRestoreSuccessReportsFilenameAndRefreshesBackups() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let directory = try makeTempConfigurationDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    model.configurationDirectory = directory
    let backupFile = try makeExistingBackupFile(in: directory, named: "restore-me.logiob")

    var recordedCalls = [[String]]()
    model.engineRunnerOverride = { arguments in
      recordedCalls.append(arguments)
      return ""
    }

    model.restore(backupFile)

    XCTAssertFalse(model.busy)
    XCTAssertEqual(model.status, "Restored and verified \(backupFile.lastPathComponent).")
    XCTAssertEqual(recordedCalls, [BackupStorage.restoreArguments(for: backupFile)])
  }

  func testRestoreFailureReportsEngineError() throws {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    let directory = try makeTempConfigurationDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    model.configurationDirectory = directory
    let backupFile = try makeExistingBackupFile(in: directory, named: "restore-me.logiob")

    model.engineRunnerOverride = { _ in
      throw EngineError.failed("restore failed")
    }

    model.restore(backupFile)

    XCTAssertFalse(model.busy)
    XCTAssertEqual(model.status, "restore failed")
  }
}
