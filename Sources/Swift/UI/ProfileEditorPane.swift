// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct ProfileEditorPane<LoadingState: View, EmptyState: View>: View {
  @ObservedObject var model: AppModel
  let loadingState: LoadingState
  let emptyState: EmptyState

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if model.loadingProfile && model.buttons.isEmpty {
        loadingState
      } else if !model.shouldShowButtonEditor {
        emptyState
      } else {
        HStack(spacing: 8) {
          Text(L10n.text("Profile ID"))
            .font(.callout.weight(.medium))
          TextField("", text: $model.profileEditorID)
            .textFieldStyle(.roundedBorder)
            .frame(width: 130)
          Text(L10n.text("Display name"))
            .font(.callout.weight(.medium))
          TextField("", text: $model.profileEditorName)
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
          Spacer()
          Button(L10n.text("Import profile…"), action: model.importProfileEditorDraft)
          Button(L10n.text("Export profile…"), action: model.exportProfileEditorDraft)
        }
        .padding(.horizontal, 20)
        Text(
          L10n.text(
            "Name each control below, then save. The saved profile is matched to {device} by device name and product ID; a file with the same profile ID as a bundled one replaces it. Export produces a complete descriptor, ready to copy into Profiles/ for a pull request once Sources below is filled in.",
            replacements: [
              "device": currentDeviceDisplayName.isEmpty
                ? L10n.text("this mouse") : currentDeviceDisplayName
            ]
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(model.profileEditorButtonNumbers, id: \.self) { number in
              HStack(spacing: 10) {
                Text(L10n.text("Button {number}", replacements: ["number": String(number)]))
                  .frame(width: 90, alignment: .leading)
                  .foregroundStyle(.secondary)
                TextField(
                  L10n.text("Control name"),
                  text: Binding(
                    get: { model.profileEditorButtonNames[number] ?? "" },
                    set: { model.profileEditorButtonNames[number] = $0 }
                  )
                )
                .textFieldStyle(.roundedBorder)
                TextField(
                  L10n.text("Aliases (comma-separated)"),
                  text: Binding(
                    get: { model.profileEditorButtonAliases[number] ?? "" },
                    set: { model.profileEditorButtonAliases[number] = $0 }
                  )
                )
                .textFieldStyle(.roundedBorder)
              }
            }
            Divider()
              .padding(.top, 4)
            Text(L10n.text("Sources (one URL per line)"))
              .font(.callout.weight(.medium))
            TextEditor(text: $model.profileEditorSources)
              .font(.system(.callout, design: .monospaced))
              .frame(height: 70)
              .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(model.selectedDeviceIndex)
        HStack {
          Spacer()
          Button(L10n.text("Save as custom profile")) { model.saveProfileEditorDraft() }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
      }
    }
    .padding(.top, 4)
  }

  private var currentDeviceDisplayName: String {
    model.devices.first(where: { $0.id == model.selectedDeviceIndex })?.displayName
      ?? model.currentDeviceName
  }
}
