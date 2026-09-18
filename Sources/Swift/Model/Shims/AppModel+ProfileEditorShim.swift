// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation
import UniformTypeIdentifiers

// See the note in AppModel+JSONEditableBackupsShim.swift: everything under
// Sources/Swift/Model/Shims/ wraps a real, unmockable AppKit modal dialog
// or NSWorkspace call and is excluded from the Swift coverage gate. The
// logic that runs once a URL is in hand (writeProfileEditorExport,
// applyImportedProfileEditorDraft) lives in AppModel+ProfileEditor.swift
// instead, where it's covered directly with a plain URL argument.

@MainActor
extension AppModel {
  /// Exports the current draft to a user-chosen location as a complete
  /// descriptor -- suitable, once `sources` is reviewed, for copying
  /// straight into `Profiles/` in a pull request. Does not touch the
  /// catalog.
  func exportProfileEditorDraft() {
    guard let descriptor = buildProfileEditorDescriptor() else {
      status = "Enter a profile ID before exporting."
      return
    }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "\(descriptor.id).json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    writeProfileEditorExport(descriptor, to: url)
  }

  /// Loads an entire descriptor file as the new base -- id, name, sources,
  /// aliases, scroll-wheel labels, hidden-button numbers, refresh
  /// guidance, RGB zones, and profileIO all included -- so it can serve
  /// as a full template for the connected mouse, not just
  /// a source of button names. `match.nameContains`/`productIDs` are still
  /// re-derived from the connected device on save or export, since the
  /// draft always targets whatever mouse is plugged in now, regardless of
  /// which file it was templated from.
  func importProfileEditorDraft() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url,
      let data = try? Data(contentsOf: url),
      let descriptor = try? JSONDecoder().decode(MouseProfileDescriptor.self, from: data)
    else {
      return
    }
    applyImportedProfileEditorDraft(descriptor, from: url)
  }
}
