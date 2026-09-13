// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct StatusArea: View {
  let status: String
  let events: [StatusEvent]
  let messageOpacity: Double
  let background: Color
  @Binding var historyPresented: Bool

  private let panelHeight: CGFloat = 270
  private let timestampColumnWidth: CGFloat = 48
  private let eventColumnSpacing: CGFloat = 4
  private let horizontalInset: CGFloat = 20

  var body: some View {
    Group {
      if historyPresented {
        historyDrawer
          .frame(maxWidth: .infinity)
          .frame(height: panelHeight, alignment: .topLeading)
          .transition(.move(edge: .bottom))
      } else {
        statusBar(showsHistoryHeader: false)
      }
    }
  }

  private func statusBar(showsHistoryHeader: Bool) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Divider()
        .frame(maxWidth: .infinity)
        .background(background)
        .shadow(color: .black.opacity(0.22), radius: 6, y: -2)

      HStack(alignment: .top) {
        Button {
          historyPresented.toggle()
        } label: {
          Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsHistoryHeader ? "Close recent events" : "Show recent events")
        .pointerCursor()
        if showsHistoryHeader {
          Text("Recent events")
            .font(.headline)
            .foregroundStyle(.primary)
          Spacer()
          Text("Last \(events.count)")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text(status)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .opacity(messageOpacity)
          Spacer()
        }
      }
      .padding(.horizontal, horizontalInset)
    }
    .padding(.bottom, 20)
    .frame(maxWidth: .infinity)
    .background(background)
    .shadow(color: .black.opacity(0.24), radius: 7, y: -3)
  }

  private var historyDrawer: some View {
    VStack(spacing: 0) {
      statusBar(showsHistoryHeader: true)

      Divider()
        .frame(maxWidth: .infinity)
        .background(background)
        .shadow(color: .black.opacity(0.22), radius: 6, y: 2)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
            VStack(alignment: .leading, spacing: 5) {
              HStack(alignment: .firstTextBaseline, spacing: eventColumnSpacing) {
                Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.primary.opacity(0.58))
                  .frame(width: timestampColumnWidth, alignment: .leading)
                  .textSelection(.enabled)
                Text(event.message)
                  .font(.callout)
                  .fixedSize(horizontal: false, vertical: true)
                  .textSelection(.enabled)
              }
              .padding(.horizontal, horizontalInset)
              if index < events.count - 1 {
                Divider()
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
          }
        }
        .frame(maxWidth: .infinity)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(nsColor: .controlBackgroundColor))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .controlBackgroundColor))
    .overlay {
      EscapeKeyMonitor(onEscape: { historyPresented = false })
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
    .onExitCommand {
      historyPresented = false
    }
  }
}

struct DeviceHeader: View {
  @ObservedObject var model: AppModel
  let hidesEditingActions: Bool
  let onSave: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      if !model.devices.isEmpty {
        Text("Device")
          .font(.callout.weight(.medium))
        Picker(
          "",
          selection: Binding(
            get: { model.selectedDeviceIndex },
            set: { model.selectDevice($0) }
          )
        ) {
          ForEach(model.devices) { device in
            Text(device.title).tag(device.id)
          }
        }
        .labelsHidden()
        .frame(width: 180)
        .disabled(model.devices.isEmpty)
        .pointerCursor(enabled: !model.devices.isEmpty)
      }
      Button("Refresh", action: model.refresh)
        .keyboardShortcut("r", modifiers: [.command])
        .disabled(model.busy)
        .pointerCursor(enabled: !model.busy)
      if model.busy {
        ProgressView().controlSize(.small)
      }
      Spacer()
      if !hidesEditingActions {
        Button("Revert edits") { model.reloadSelectedProfile() }
          .pointerCursor()
        Button("Save to mouse", action: onSave)
          .buttonStyle(.borderedProminent)
          .disabled(
            !model.hasPendingChanges || model.busy || !model.currentMouseProfile.profileIO.canSave
              || (model.hasDPIChanges && !model.canApplyDPI)
          )
          .pointerCursor(
            enabled: model.hasPendingChanges && !model.busy
              && model.currentMouseProfile.profileIO.canSave
              && (!model.hasDPIChanges || model.canApplyDPI)
          )
      }
    }
  }
}

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
          .pointerCursor()
        Button("Export JSON…") {
          if let url = model.chooseJSONExport() {
            model.exportCurrentJSON(to: url)
          }
        }
        .pointerCursor()
        Button("Import JSON…") {
          if let url = model.chooseJSONBackup() {
            model.loadEditableBackup(url)
          }
        }
        .pointerCursor()
        Button("Choose another backup…") {
          restoreURL = model.chooseRestoreBackup()
          confirmRestore = restoreURL != nil
        }
        .pointerCursor()
        Button("Refresh list", action: model.refreshBackups)
          .pointerCursor()
        Button("Open in Finder", action: model.openBackupDirectoryInFinder)
          .pointerCursor()
      }
      Toggle(
        "Show backups for all mice",
        isOn: Binding(
          get: { model.showAllBackups },
          set: { model.setShowAllBackups($0) })
      )
      .toggleStyle(.checkbox)
      .pointerCursor()
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
                  .pointerCursor()
                } else {
                  Button("Restore") {
                    restoreURL = backup.url
                    confirmRestore = true
                  }
                  .pointerCursor()
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

struct SettingsPane: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Settings")
        .font(.headline)
      GroupBox("Storage") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Configuration directory")
            .font(.callout.weight(.medium))
          Text(model.configurationDirectoryPath)
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .textSelection(.enabled)
          Text("Backups and custom mouse profiles are stored in separate subfolders here.")
            .font(.caption)
            .foregroundStyle(.secondary)
          HStack {
            Button("Choose directory…") {
              if let directory = model.chooseConfigurationDirectory() {
                model.setConfigurationDirectory(directory)
              }
            }
            .pointerCursor()
            Button("Use default") { model.resetConfigurationDirectory() }
              .disabled(model.configurationDirectoryPath == model.defaultConfigurationDirectoryPath)
              .pointerCursor(
                enabled: model.configurationDirectoryPath != model.defaultConfigurationDirectoryPath
              )
          }
        }
        .padding(4)
      }
      GroupBox("Mouse profiles") {
        VStack(alignment: .leading, spacing: 8) {
          Text(
            model.customMouseProfileCount > 0
              ? "\(model.builtInMouseProfileCount) built-in mice, plus \(model.customMouseProfileCount) custom."
              : "\(model.builtInMouseProfileCount) built-in mice supported."
          )
          .font(.callout)
          Text(
            "Add your own or override a bundled one by dropping a JSON descriptor into the custom profiles folder. It starts with an example file that shows the format."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Button("Open custom profiles folder", action: model.openCustomProfilesDirectoryInFinder)
            .pointerCursor()
        }
        .padding(4)
      }
      GroupBox("Advanced display") {
        VStack(alignment: .leading, spacing: 6) {
          Toggle(
            "Show raw HID++ fields",
            isOn: Binding(
              get: { model.showAdvancedFields },
              set: { model.setShowAdvancedFields($0) })
          )
          .toggleStyle(.checkbox)
          .pointerCursor()
          Text(
            "Shows the 8-digit button records and profile sector numbers. Leave this off for the normal editing view."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .padding(4)
      }
      GroupBox("Keyboard outputs") {
        VStack(alignment: .leading, spacing: 6) {
          Toggle(
            "Show non-standard keyboard keys",
            isOn: Binding(
              get: { model.showNonStandardKeyboardKeys },
              set: { model.setShowNonStandardKeyboardKeys($0) })
          )
          .toggleStyle(.checkbox)
          .pointerCursor()
          Text(
            "Shows the optional extended-key override for usages such as Insert, F13–F24, and Sleep. Recording captures modifiers automatically."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .padding(4)
      }
      GroupBox("Appearance") {
        VStack(alignment: .leading, spacing: 6) {
          Picker(
            "Color mode",
            selection: Binding(
              get: { model.appearancePreference },
              set: { model.setAppearancePreference($0) }
            )
          ) {
            ForEach(AppearancePreference.allCases, id: \.self) { preference in
              Text(preference.label).tag(preference)
            }
          }
          .pickerStyle(.segmented)
          .pointerCursor()
          Text(
            "System follows macOS. Light mode uses a soft off-white background; the DPI colors remain unchanged."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .padding(4)
      }
      Spacer()
    }
    .padding(.top, 4)
    .padding(.horizontal, 20)
  }
}
