// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation
import UniformTypeIdentifiers

// Everything under Sources/Swift/Model/Shims/ wraps a real AppKit modal
// dialog or NSWorkspace call that blocks on live UI with no test seam, so
// this directory is excluded from the Swift coverage gate (see
// docs/development-standards.md). Keep these wrappers as thin as possible;
// put anything worth unit testing in the corresponding non-Shims
// AppModel+*.swift file instead.

@MainActor
extension AppModel {
  func chooseJSONBackup() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [UTType.json]
    panel.directoryURL = defaultDocumentsDirectory
    return panel.runModal() == .OK ? panel.url : nil
  }

  func chooseJSONExport() -> URL? {
    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [UTType.json]
    panel.directoryURL = defaultDocumentsDirectory
    panel.nameFieldStringValue = editableJSONExportName()
    panel.message = "Export the selected profile as an editable JSON file."
    return panel.runModal() == .OK ? panel.url : nil
  }
}
