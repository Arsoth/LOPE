// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct BackupsPane: View {
  @ObservedObject var model: AppModel
  @Binding var restoreURL: URL?
  @Binding var confirmRestore: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(L10n.text("Backups"))
        .font(.headline)
      Text(
        L10n.text(
          "Save to mouse creates exact binary backups for the selected mouse before any write. JSON is an explicit import/export format; older JSON sidecars remain available as editable files, but new mouse saves do not create them."
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      HStack {
        Button(L10n.text("Save selected profile backup")) { model.dumpBackup() }
        Button(L10n.text("Export JSON…")) {
          if let url = model.chooseJSONExport() {
            model.exportCurrentJSON(to: url)
          }
        }
        Button(L10n.text("Import JSON…")) {
          if let url = model.chooseJSONBackup() {
            model.loadEditableBackup(url)
          }
        }
        Button(L10n.text("Choose another backup…")) {
          restoreURL = model.chooseRestoreBackup()
          confirmRestore = restoreURL != nil
        }
        Button(L10n.text("Refresh list"), action: model.refreshBackups)
        Button(L10n.text("Open in Finder"), action: model.openBackupDirectoryInFinder)
      }
      Toggle(
        L10n.text("Show backups for all mice"),
        isOn: Binding(
          get: { model.showAllBackups },
          set: { model.setShowAllBackups($0) })
      )
      .toggleStyle(.checkbox)
      Text(
        model.showAllBackups
          ? L10n.text(
            "Showing every backup. Unknown-device files require review before restore or import."
          )
          : L10n.text(
            "Showing backups matched to the selected mouse. Legacy files that cannot be matched safely are hidden."
          )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      GroupBox(L10n.text("Available backups")) {
        if model.backups.isEmpty {
          Text(
            model.showAllBackups
              ? L10n.text(
                "No backups in {path}.", replacements: ["path": model.backupDirectoryPath]
              )
              : L10n.text(
                "No backups for the selected mouse in {path}.",
                replacements: ["path": model.backupDirectoryPath]
              )
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(6)
        } else {
          List {
            ForEach(model.backups) { backup in
              HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(backup.name)
                    .font(.callout)
                    .lineLimit(1)
                  Text(
                    "\(backup.fileTypeLabel) | \(backup.deviceStatusLabel) | \(backup.modifiedAt.formatted(date: .abbreviated, time: .shortened)) | \(ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file))"
                  )
                  .font(.caption)
                  .foregroundStyle(backup.deviceMatch == .unknown ? .orange : .secondary)
                }
                Spacer()
                if backup.isJSON {
                  Button(L10n.text("Load")) {
                    model.loadEditableBackup(backup.url)
                  }
                } else {
                  Button(L10n.text("Restore")) {
                    restoreURL = backup.url
                    confirmRestore = true
                  }
                }
              }
              .padding(.vertical, 2)
            }
          }
          .listStyle(.inset)
          .frame(minHeight: 120, maxHeight: 250)
        }
      }
      Text(
        L10n.text(
          "Quit G HUB and other mouse remappers while saving. Don't bother re-enabling them after ;)"
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.top, 4)
    .padding(.horizontal, 20)
  }
}
