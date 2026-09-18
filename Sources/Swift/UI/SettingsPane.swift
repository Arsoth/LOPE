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
        Text(L10n.text("Settings"))
          .font(.headline)
        GroupBox(L10n.text("Storage")) {
          VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Configuration directory"))
              .font(.callout.weight(.medium))
            Text(model.configurationDirectoryPath)
              .font(.system(.callout, design: .monospaced))
              .foregroundStyle(.secondary)
              .lineLimit(3)
              .textSelection(.enabled)
            Text(
              L10n.text("Backups and custom mouse profiles are stored in separate subfolders here.")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
              Button(L10n.text("Choose directory…")) {
                if let directory = model.chooseConfigurationDirectory() {
                  model.setConfigurationDirectory(directory)
                }
              }
              Button(L10n.text("Use default")) { model.resetConfigurationDirectory() }
                .disabled(
                  model.configurationDirectoryPath == model.defaultConfigurationDirectoryPath)
            }
          }
          .padding(4)
          .frame(width: contentWidth, alignment: .leading)
        }
        GroupBox(L10n.text("Input Monitoring")) {
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
                  ? L10n.text("Allowed for this app")
                  : L10n.text("Required to edit wired mice")
              )
              .font(.callout.weight(.medium))
            }
            Text(
              L10n.text(
                "Input Monitoring lets LOPE read wired Logitech mice. On first use, macOS asks to receive keystrokes while it registers LOPE; choose Open System Settings in that dialog, then enable LOPE there. Later clicks open Input Monitoring directly. Wireless and receiver-connected mice do not need this permission."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Button(
              L10n.text("Open Input Monitoring Settings"),
              action: model.openInputMonitoringSettings
            )
          }
          .padding(4)
          .frame(width: contentWidth, alignment: .leading)
        }
        GroupBox(L10n.text("Mouse profiles")) {
          VStack(alignment: .leading, spacing: 8) {
            Text(
              model.customMouseProfileCount > 0
                ? L10n.text(
                  "{builtIn} built-in mice, plus {custom} custom.",
                  replacements: [
                    "builtIn": String(model.builtInMouseProfileCount),
                    "custom": String(model.customMouseProfileCount),
                  ]
                )
                : L10n.text(
                  "{builtIn} built-in mice supported.",
                  replacements: ["builtIn": String(model.builtInMouseProfileCount)]
                )
            )
            .font(.callout)
            Text(
              L10n.text(
                "Add your own or override a bundled one by dropping a JSON descriptor into the custom profiles folder. It starts with an example file that shows the format."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Button(
              L10n.text("Open custom profiles folder"),
              action: model.openCustomProfilesDirectoryInFinder
            )
          }
          .padding(4)
          .frame(width: contentWidth, alignment: .leading)
        }
        GroupBox(L10n.text("Advanced display")) {
          VStack(alignment: .leading, spacing: 6) {
            Toggle(
              L10n.text("Show raw HID++ fields"),
              isOn: Binding(
                get: { model.showAdvancedFields },
                set: { model.setShowAdvancedFields($0) })
            )
            .toggleStyle(.checkbox)
            .tint(theme.checkboxActive)
            Text(
              L10n.text(
                "Shows the 8-digit button records and profile sector numbers. Leave this off for the normal editing view."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          .padding(4)
          .frame(width: contentWidth, alignment: .leading)
        }
        GroupBox(L10n.text("Keyboard outputs")) {
          VStack(alignment: .leading, spacing: 6) {
            Toggle(
              L10n.text("Show non-standard keyboard keys"),
              isOn: Binding(
                get: { model.showNonStandardKeyboardKeys },
                set: { model.setShowNonStandardKeyboardKeys($0) })
            )
            .toggleStyle(.checkbox)
            .tint(theme.checkboxActive)
            Text(
              L10n.text(
                "Shows the optional extended-key override for usages such as Insert, F13–F24, modifier keys, and Sleep. Recording captures modifiers automatically."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
              Text(L10n.text("Key categories"))
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
                    Text(L10n.text(group.rawValue))
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
        GroupBox(L10n.text("Appearance")) {
          VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
              Picker(
                L10n.text("Color mode"),
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
              Button(
                L10n.text("Open custom themes folder"),
                action: model.openCustomThemesDirectoryInFinder
              )
              Button(L10n.text("Refresh themes"), action: model.refreshThemes)
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
                L10n.text("Light theme"),
                selection: Binding(
                  get: { model.selectedLightThemeID },
                  set: { model.setLightThemeID($0) }
                ),
                themes: model.lightThemes
              )
              themePicker(
                L10n.text("Dark theme"),
                selection: Binding(
                  get: { model.selectedDarkThemeID },
                  set: { model.setDarkThemeID($0) }
                ),
                themes: model.darkThemes
              )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(
              L10n.text(
                "System follows macOS and selects the matching theme. Light and dark modes use the theme selected below."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(
              L10n.text(
                "Light and dark themes are loaded from the bundled themes and Custom Themes folders."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
          .padding(4)
          .frame(width: contentWidth, alignment: .leading)
        }
        GroupBox(L10n.text("Updates")) {
          VStack(alignment: .leading, spacing: 6) {
            Toggle(
              L10n.text("Check for updates on launch"),
              isOn: Binding(
                get: { model.automaticUpdateChecksEnabled },
                set: { model.setAutomaticUpdateChecksEnabled($0) }
              )
            )
            .toggleStyle(.checkbox)
            .tint(theme.checkboxActive)
            Text(
              L10n.text(
                "When enabled, LOPE checks GitHub for a newer release each time it launches."
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 8) {
              Button(L10n.text("Check now"), action: model.checkForUpdates)
                .disabled(model.updateCheckInProgress)
              if model.updateCheckInProgress {
                ProgressView()
                  .controlSize(.small)
              }
              if let message = model.updateCheckMessage {
                Text(message)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
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
    .alert(
      Text(L10n.text("Update could not be installed")),
      isPresented: Binding(
        get: { model.updateErrorMessage != nil },
        set: { if !$0 { model.updateErrorMessage = nil } }
      )
    ) {
      Button(L10n.text("OK")) { model.updateErrorMessage = nil }
    } message: {
      Text(model.updateErrorMessage ?? "")
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
