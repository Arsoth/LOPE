// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation
import UniformTypeIdentifiers

// See the note in AppModel+JSONEditableBackupsShim.swift: everything under
// Sources/Swift/Model/Shims/ wraps a real, unmockable AppKit modal dialog
// or NSWorkspace call and is excluded from the Swift coverage gate.

@MainActor
extension AppModel {
  func chooseRestoreBackup() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [
      UTType(filenameExtension: AppConstants.backupExtension) ?? .data,
      UTType(filenameExtension: "bin") ?? .data,
    ]
    panel.directoryURL = backupDirectory
    return panel.runModal() == .OK ? panel.url : nil
  }
}
