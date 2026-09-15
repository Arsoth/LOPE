// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct ButtonEditorPane: View {
  @ObservedObject var model: AppModel
  @Binding var confirmRecoveryRestore: Bool
  @Binding var presentedRGBZoneID: Int?
  @Environment(\.lopeTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          recoveryNotice
          readOnlyNotice
          generatedProfileNotice
          ProfileControlsView(model: model)
          if model.hasGShiftLayer {
            HStack(spacing: 10) {
              Text("Button assignments")
                .font(.callout.weight(.medium))
              Text("G-Shift assignments apply while holding the mouse’s G-Shift button.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
          }
          Divider()
          ButtonAssignmentsView(model: model)
          Divider()
          if model.canEditOnboardDPI {
            DPIEditorView(model: model)
          } else {
            Text("Onboard DPI editing is unavailable for this legacy profile path.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
          }
          if model.shouldShowRGBEditor {
            Divider()
            RGBEditorView(model: model, presentedZoneID: $presentedRGBZoneID)
          }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .background(ScrollViewScrollerInset(rightInset: 3))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .id(model.selectedDeviceIndex)
    }
  }

  @ViewBuilder
  private var recoveryNotice: some View {
    if !model.isProvisionalMouseData && !model.recoveryBackups.isEmpty {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(theme.warning)
        Text(
          "The last save was only partially completed. Exact pre-save backups are available for recovery."
        )
        .font(.callout)
        Spacer()
        Button("Restore backups from this save") {
          confirmRecoveryRestore = true
        }
        .buttonStyle(.bordered)
      }
      .padding(8)
      .background(theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }
  }

  @ViewBuilder
  private var readOnlyNotice: some View {
    if !model.isProvisionalMouseData && !model.currentMouseProfile.profileIO.canSave {
      Text(
        "This device is cataloged for read-only inspection until its profile-specific save format is validated."
      )
      .font(.caption)
      .foregroundStyle(theme.warning)
    }
  }

  @ViewBuilder
  private var generatedProfileNotice: some View {
    if !model.isProvisionalMouseData && !model.hasSpecificMouseProfile {
      HStack(spacing: 8) {
        Image(systemName: "questionmark.circle.fill")
          .foregroundStyle(.secondary)
        Text("LOPE doesn't recognize this mouse, so buttons below are shown by number only.")
          .font(.callout)
        Spacer()
        Button("Create profile") { model.createGeneratedProfile() }
          .buttonStyle(.bordered)
      }
      .padding(8)
      .background(theme.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
    }
  }
}

struct ProfileControlsView: View {
  @ObservedObject var model: AppModel
  @Environment(\.lopeTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 12) {
        Text(model.onboardProfileSummary)
          .font(.callout.weight(.medium))
        Spacer(minLength: 12)
        if model.hasGShiftLayer {
          Picker(
            "Button layer",
            selection: Binding(
              get: { model.buttonLayer },
              set: { model.selectButtonLayer($0) }
            )
          ) {
            ForEach(ButtonLayer.allCases, id: \.self) { layer in
              Text(layer.label).tag(layer)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 150)
        }
        if model.profiles.count > 1 {
          Text("Profile:")
            .font(.callout.weight(.medium))
          Picker("Profile", selection: $model.profileNumber) {
            ForEach(model.profiles) { profile in
              Text(profile.title).tag(profile.id)
            }
          }
          .labelsHidden()
          .frame(width: 150)
          .disabled(model.busy)

          Text("Enable:")
            .font(.callout.weight(.medium))
          ForEach(model.profiles) { profile in
            profileEnableControl(profile)
          }
        }
      }
      if model.showAdvancedFields {
        HStack(spacing: 12) {
          Text("Sectors:")
            .font(.caption)
            .foregroundStyle(.secondary)
          ForEach(model.profiles) { profile in
            Text("Profile \(profile.id): \(profile.sector)")
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(minHeight: 36)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(theme.card)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(theme.cardBorder, lineWidth: 0.5)
    }
    .padding(.top, 20)
  }

  private func profileEnableControl(_ profile: ProfileChoice) -> some View {
    let profileID = profile.id
    let label = String(profileID)
    let crcLabel: String
    let crcColor: Color
    let helpText: String
    switch profile.crcValid {
    case true:
      crcLabel = ""
      crcColor = .secondary
      helpText = "Profile \(label) CRC valid"
    case false:
      crcLabel = "Profile invalid"
      crcColor = .red
      helpText = "Profile \(label) CRC invalid"
    case nil:
      crcLabel = ""
      crcColor = .secondary
      helpText = "Profile \(label) CRC not read"
    }
    let enabled = Binding<Bool>(
      get: { model.profileEnabled(profileID) },
      set: { model.setProfileEnabled(profileID: profileID, enabled: $0) }
    )
    return HStack(spacing: 3) {
      Text(label)
        .font(.caption)
      Toggle("", isOn: enabled)
        .labelsHidden()
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .disabled(model.busy || !model.canEditProfileState)
      Text(crcLabel)
        .font(.caption)
        .foregroundStyle(crcColor)
    }
    .padding(.horizontal, 2)
    .padding(.vertical, 2)
    .help(helpText)
  }
}
