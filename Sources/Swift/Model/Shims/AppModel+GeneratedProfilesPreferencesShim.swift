// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation

// See the note in AppModel+JSONEditableBackupsShim.swift: everything under
// Sources/Swift/Model/Shims/ wraps a real, unmockable AppKit modal dialog
// or NSWorkspace call and is excluded from the Swift coverage gate.

@MainActor
extension AppModel {
  func chooseConfigurationDirectory() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Choose where LOPE stores backups and custom mouse profiles."
    panel.prompt = "Use this directory"
    panel.directoryURL = configurationDirectory
    return panel.runModal() == .OK ? panel.url : nil
  }

  func openBackupDirectoryInFinder() {
    try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    guard NSWorkspace.shared.open(backupDirectory) else {
      status = "Could not open the backups directory in Finder."
      return
    }
    status = "Opened the backups directory in Finder."
  }

  func openCustomProfilesDirectoryInFinder() {
    let directory = customProfilesDirectory
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    guard NSWorkspace.shared.open(directory) else {
      status = "Could not open the custom profiles directory in Finder."
      return
    }
    status = "Opened the custom profiles directory in Finder."
  }
}
