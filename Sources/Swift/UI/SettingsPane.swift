// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct SettingsPane: View {
  @ObservedObject var model: AppModel
  @Environment(\.lopeTheme) private var theme

  var body: some View {
    GeometryReader { geometry in
      let contentWidth = max(geometry.size.width - 40, 0)

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
                .disabled(
                  model.configurationDirectoryPath == model.defaultConfigurationDirectoryPath)
            }
          }
          .padding(4)
          .frame(width: contentWidth, alignment: .leading)
        }
        GroupBox("Input Monitoring") {
          VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
              Image(
                systemName: model.inputMonitoringAuthorized
                  ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
              )
              .foregroundStyle(
                model.inputMonitoringAuthorized ? theme.success : theme.warning
              )
              Text(
                model.inputMonitoringAuthorized
                  ? "Allowed for this app"
                  : "Required to edit wired mice"
              )
              .font(.callout.weight(.medium))
            }
            Text(
              "Input Monitoring lets LOPE read wired Logitech mice. On first use, macOS asks to receive keystrokes while it registers LOPE; choose Open System Settings in that dialog, then enable LOPE there. Later clicks open Input Monitoring directly. Wireless and receiver-connected mice do not need this permission."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Button("Open Input Monitoring Settings", action: model.openInputMonitoringSettings)
          }
          .padding(4)
          .frame(width: contentWidth, alignment: .leading)
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
          .frame(width: contentWidth, alignment: .leading)
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
            .tint(theme.checkboxActive)
            Text(
              "Shows the 8-digit button records and profile sector numbers. Leave this off for the normal editing view."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          .padding(4)
          .frame(width: contentWidth, alignment: .leading)
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
            .tint(theme.checkboxActive)
            Text(
              "Shows the optional extended-key override for usages such as Insert, F13–F24, and Sleep. Recording captures modifiers automatically."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
              Text("Key categories")
                .font(.callout.weight(.medium))
              LazyVGrid(
                columns: [
                  GridItem(.flexible(), alignment: .leading),
                  GridItem(.flexible(), alignment: .leading),
                ],
                alignment: .leading,
                spacing: 4
              ) {
                ForEach(KeyboardKeyGroup.allCases, id: \.self) { group in
                  Toggle(
                    isOn: Binding(
                      get: { model.isKeyboardKeyGroupEnabled(group) },
                      set: { model.setKeyboardKeyGroup(group, enabled: $0) }
                    )
                  ) {
                    Text(group.rawValue)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                  .toggleStyle(.checkbox)
                  .controlSize(.small)
                  .tint(theme.checkboxActive)
                  .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
            }
            .padding(.top, 2)
          }
          .padding(4)
          .frame(width: contentWidth, alignment: .leading)
        }
        GroupBox("Appearance") {
          VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
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
              Button("Open custom themes folder", action: model.openCustomThemesDirectoryInFinder)
              Button("Refresh themes", action: model.refreshThemes)
            }
            LazyVGrid(
              columns: [
                GridItem(.flexible(minimum: 0), alignment: .leading),
                GridItem(.flexible(minimum: 0), alignment: .leading),
              ],
              alignment: .leading,
              spacing: 12
            ) {
              themePicker(
                "Light theme",
                selection: Binding(
                  get: { model.selectedLightThemeID },
                  set: { model.setLightThemeID($0) }
                ),
                themes: model.lightThemes
              )
              themePicker(
                "Dark theme",
                selection: Binding(
                  get: { model.selectedDarkThemeID },
                  set: { model.setDarkThemeID($0) }
                ),
                themes: model.darkThemes
              )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(
              "System follows macOS and selects the matching theme. Light and dark modes use the theme selected below."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(
              "Light and dark themes are loaded from the bundled themes and Custom Themes folders."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          .padding(4)
          .frame(width: contentWidth, alignment: .leading)
        }
        Spacer()
      }
      .padding(.top, 4)
      .padding(.horizontal, 20)
      .frame(width: geometry.size.width, alignment: .leading)
    }
    .onAppear {
      model.updateInputMonitoringAuthorization()
    }
  }

  private func themePicker(
    _ title: String,
    selection: Binding<String>,
    themes: [ThemeDefinition]
  ) -> some View {
    HStack(alignment: .center, spacing: 8) {
      Text(title)
        .font(.callout.weight(.medium))
        .fixedSize()
      Picker("", selection: selection) {
        ForEach(themes) { theme in
          Text(theme.name).tag(theme.id)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
