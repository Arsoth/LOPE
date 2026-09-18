// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

// The installer crosses the process boundary: a running macOS app cannot
// replace its own bundle and relaunch itself synchronously. Keep this small
// process shim outside the coverage target; release selection and downloading
// remain covered in AppUpdate.swift.
enum AppUpdateInstaller {
  static func prepareAndLaunch(archiveData: Data, currentAppURL: URL) throws {
    guard currentAppURL.pathExtension.lowercased() == "app" else {
      throw AppUpdateError.notPackaged
    }

    let fileManager = FileManager.default
    let stagingDirectory = fileManager.temporaryDirectory.appendingPathComponent(
      "LOPE-update-\(UUID().uuidString)", isDirectory: true)
    let archiveURL = stagingDirectory.appendingPathComponent("update.zip")
    let extractionDirectory = stagingDirectory.appendingPathComponent(
      "extracted", isDirectory: true)
    try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
    try archiveData.write(to: archiveURL, options: .atomic)

    try run(
      executable: URL(fileURLWithPath: "/usr/bin/ditto"),
      arguments: ["-x", "-k", archiveURL.path, extractionDirectory.path]
    )

    guard
      let downloadedApp = try fileManager.contentsOfDirectory(
        at: extractionDirectory,
        includingPropertiesForKeys: nil
      ).first(where: { $0.pathExtension.lowercased() == "app" })
    else {
      throw AppUpdateError.archiveExtractionFailed
    }

    let scriptURL = stagingDirectory.appendingPathComponent("install-update.sh")
    try installScript.write(to: scriptURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [
      scriptURL.path,
      currentAppURL.path,
      downloadedApp.path,
      "\(ProcessInfo.processInfo.processIdentifier)",
      stagingDirectory.path,
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      throw AppUpdateError.replacementLaunchFailed
    }
  }

  private static let installScript = """
    #!/bin/sh
    set -eu

    old_app="$1"
    new_app="$2"
    pid="$3"
    staging="$4"

    while kill -0 "$pid" 2>/dev/null; do
      sleep 0.2
    done

    backup="${old_app}.old.$$"
    if [ -e "$old_app" ]; then
      mv "$old_app" "$backup"
    fi

    if ! /usr/bin/ditto "$new_app" "$old_app"; then
      rm -rf "$old_app"
      if [ -e "$backup" ]; then
        mv "$backup" "$old_app"
      fi
      rm -rf "$staging"
      exit 1
    fi

    rm -rf "$backup"
    /usr/bin/open "$old_app"
    rm -rf "$staging"
    """

  private static func run(executable: URL, arguments: [String]) throws {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw AppUpdateError.archiveExtractionFailed
    }
  }
}
