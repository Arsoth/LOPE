// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  func restoreLastSaveBackups() {
    guard !busy, !recoveryBackups.isEmpty else { return }
    guard recoveryDeviceKey == devices.first(where: { $0.id == selectedDeviceIndex })?.deviceKey
    else {
      recoveryBackups.removeAll()
      recoveryDeviceKey = nil
      status =
        "Recovery backups belong to a different selected mouse. Choose the original mouse before restoring them."
      return
    }
    let candidates = recoveryBackups.filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !candidates.isEmpty else {
      recoveryBackups.removeAll()
      recoveryDeviceKey = nil
      status = "The backups from the failed save are no longer available."
      return
    }
    busy = true
    defer { busy = false }
    var restored = 0
    do {
      for backup in candidates {
        _ = try runEngine(BackupStorage.restoreArguments(for: backup))
        restored += 1
      }
      recoveryBackups.removeAll()
      recoveryDeviceKey = nil
      refreshBackups()
      refresh()
      status = "Restored and verified \(restored) sector backup(s) from the failed save operation."
    } catch {
      let remaining = Array(candidates.dropFirst(restored))
      recoveryBackups = remaining
      status =
        "Restored \(restored) sector backup(s), but recovery stopped: \(error.localizedDescription)"
    }
  }

  func dumpBackup() {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      let backup = backupURL(prefix: "profile-\(profileNumber)-manual")
      try? FileManager.default.createDirectory(
        at: backup.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      _ = try runEngine(["--profile", String(profileNumber), "dump", backup.path])
      refreshBackups()
      status = "Saved a read-only profile backup at \(backup.path)."
    } catch {
      status = error.localizedDescription
    }
  }

  func restore(_ url: URL) {
    guard !busy else { return }
    busy = true
    do {
      _ = try runEngine(BackupStorage.restoreArguments(for: url))
      refreshBackups()
      busy = false
      refresh()
      status = "Restored and verified \(url.lastPathComponent)."
    } catch {
      busy = false
      status = error.localizedDescription
    }
  }
}
