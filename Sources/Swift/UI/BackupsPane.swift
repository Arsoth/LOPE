// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct BackupsPane: View {
  @ObservedObject var model: AppModel
  @Binding var restoreURL: URL?
  @Binding var confirmRestore: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Backups")
        .font(.headline)
      Text(
        "Save to mouse creates exact binary backups for the selected mouse before any write. JSON is an explicit import/export format; older JSON sidecars remain available as editable files, but new mouse saves do not create them."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      HStack {
        Button("Save selected profile backup") { model.dumpBackup() }
        Button("Export JSON…") {
          if let url = model.chooseJSONExport() {
            model.exportCurrentJSON(to: url)
          }
        }
        Button("Import JSON…") {
          if let url = model.chooseJSONBackup() {
            model.loadEditableBackup(url)
          }
        }
        Button("Choose another backup…") {
          restoreURL = model.chooseRestoreBackup()
          confirmRestore = restoreURL != nil
        }
        Button("Refresh list", action: model.refreshBackups)
        Button("Open in Finder", action: model.openBackupDirectoryInFinder)
      }
      Toggle(
        "Show backups for all mice",
        isOn: Binding(
          get: { model.showAllBackups },
          set: { model.setShowAllBackups($0) })
      )
      .toggleStyle(.checkbox)
      Text(
        model.showAllBackups
          ? "Showing every backup. Unknown-device files require review before restore or import."
          : "Showing backups matched to the selected mouse. Legacy files that cannot be matched safely are hidden."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      GroupBox("Available backups") {
        if model.backups.isEmpty {
          Text(
            model.showAllBackups
              ? "No backups in \(model.backupDirectoryPath)."
              : "No backups for the selected mouse in \(model.backupDirectoryPath)."
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
                  Button("Load") {
                    model.loadEditableBackup(backup.url)
                  }
                } else {
                  Button("Restore") {
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
        "Quit G HUB and other mouse remappers while saving. Don't bother re-enabling them after ;)"
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.top, 4)
    .padding(.horizontal, 20)
  }
}
