// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

/// A FileManager stub whose `urls(for:in:)` always returns an empty array,
/// so tests can exercise `BackupStorage.documentsDirectory`'s
/// home-directory fallback without needing a machine that lacks a real
/// Documents directory.
private final class EmptyURLsFileManager: FileManager {
  override func urls(
    for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask
  ) -> [URL] {
    []
  }
}

final class BackupStorageTests: XCTestCase {
  func testBackupStorageDirectoryAndFilenameHandling() throws {
    let fileManager = FileManager.default
    let testRoot = fileManager.temporaryDirectory
      .appendingPathComponent("lope-backup-storage-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: testRoot) }

    let g502Directory = BackupStorage.modelDirectory(
      root: testRoot, mouseIdentifier: "G502 X/PLUS")
    let legacyDirectory = testRoot.appendingPathComponent("legacy", isDirectory: true)
    let hiddenDirectory = testRoot.appendingPathComponent(".hidden", isDirectory: true)
    try fileManager.createDirectory(at: g502Directory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true)

    let first = BackupStorage.uniqueBackupURL(
      root: testRoot,
      mouseIdentifier: "G502 X/PLUS",
      prefix: "profile-1-save",
      fileExtension: "logiob",
      timestamp: "20260912-120000"
    )
    XCTAssertEqual(
      first.path,
      testRoot
        .appendingPathComponent("G502-X-PLUS", isDirectory: true)
        .appendingPathComponent("G502-X-PLUS-profile-1-save-20260912-120000.logiob")
        .path
    )
    XCTAssertEqual(
      BackupStorage.mouseIdentifier(fromBackupFilename: first.lastPathComponent), "G502-X-PLUS")

    try Data([0x01]).write(to: first)
    let second = BackupStorage.uniqueBackupURL(
      root: testRoot,
      mouseIdentifier: "G502 X/PLUS",
      prefix: "profile-1-save",
      fileExtension: "logiob",
      timestamp: "20260912-120000"
    )
    XCTAssertEqual(second.lastPathComponent, "G502-X-PLUS-profile-1-save-20260912-120000-2.logiob")

    let legacy = legacyDirectory.appendingPathComponent("legacy.bin")
    let json = g502Directory.appendingPathComponent("G502-X-PLUS-profile-1-export.json")
    let hidden = hiddenDirectory.appendingPathComponent("hidden.logiob")
    try Data([0x02]).write(to: legacy)
    try Data([0x03]).write(to: json)
    try Data([0x04]).write(to: hidden)
    let discovered = Set(BackupStorage.backupURLs(in: testRoot).map { $0.standardizedFileURL })
    let expectedBackups = Set([first, legacy, json].map { $0.standardizedFileURL })
    XCTAssertEqual(discovered, expectedBackups)
    XCTAssertNil(
      BackupStorage.mouseIdentifier(fromBackupFilename: "profile-1-save-20260912-120000.logiob"))
    XCTAssertEqual(BackupStorage.restoreArguments(for: first), ["restore", first.path, "--yes"])

    let expectedDocuments = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
    XCTAssertEqual(BackupStorage.documentsDirectory(fileManager: fileManager), expectedDocuments)
  }

  func testUniqueBackupURLStripsLeadingDotFromFileExtension() {
    let testRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("lope-backup-storage-dot-ext-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: testRoot) }

    let url = BackupStorage.uniqueBackupURL(
      root: testRoot,
      mouseIdentifier: "G502 X",
      prefix: "profile-1-save",
      fileExtension: ".logiob",
      timestamp: "20260912-120000"
    )
    XCTAssertEqual(url.pathExtension, "logiob")
    XCTAssertFalse(url.lastPathComponent.contains("..logiob"))
  }

  func testDocumentsDirectoryFallsBackToHomeDirectoryWhenNoDocumentsURLIsReported() {
    let fileManager = EmptyURLsFileManager()
    XCTAssertEqual(
      BackupStorage.documentsDirectory(fileManager: fileManager),
      fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
    )
  }
}
