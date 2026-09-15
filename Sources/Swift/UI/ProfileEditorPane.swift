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
          Text("Profile ID")
            .font(.callout.weight(.medium))
          TextField("", text: $model.profileEditorID)
            .textFieldStyle(.roundedBorder)
            .frame(width: 130)
          Text("Display name")
            .font(.callout.weight(.medium))
          TextField("", text: $model.profileEditorName)
            .textFieldStyle(.roundedBorder)
            .frame(width: 200)
          Spacer()
          Button("Import profile…", action: model.importProfileEditorDraft)
          Button("Export profile…", action: model.exportProfileEditorDraft)
        }
        .padding(.horizontal, 20)
        Text(
          "Name each control below, then save. The saved profile is matched to \(currentDeviceDisplayName.isEmpty ? "this mouse" : currentDeviceDisplayName) by device name and product ID; a file with the same profile ID as a bundled one replaces it. Export produces a complete descriptor, ready to copy into Profiles/ for a pull request once Sources below is filled in."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(model.profileEditorButtonNumbers, id: \.self) { number in
              HStack(spacing: 10) {
                Text("Button \(number)")
                  .frame(width: 90, alignment: .leading)
                  .foregroundStyle(.secondary)
                TextField(
                  "Control name",
                  text: Binding(
                    get: { model.profileEditorButtonNames[number] ?? "" },
                    set: { model.profileEditorButtonNames[number] = $0 }
                  )
                )
                .textFieldStyle(.roundedBorder)
              }
            }
            Divider()
              .padding(.top, 4)
            Text("Sources (one URL per line)")
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
          Button("Save as custom profile") { model.saveProfileEditorDraft() }
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
