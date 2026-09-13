// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

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
            Button("Use default") { model.resetConfigurationDirectory() }
              .disabled(model.configurationDirectoryPath == model.defaultConfigurationDirectoryPath)
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
