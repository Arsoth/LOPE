// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct DPIEditorView: View {
  @ObservedObject var model: AppModel
  @Environment(\.lopeTheme) private var theme

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.text("Onboard DPI"))
            .font(.headline)
          Text(L10n.text("Set the active sensitivity stages for this profile."))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        HStack(spacing: 4) {
          if !model.pollingRateCapabilities.profileSupportedRates.isEmpty {
            Text(L10n.text("Polling rate"))
              .font(.caption)
              .foregroundStyle(.secondary)
            Picker(
              L10n.text("Polling rate"),
              selection: Binding(
                get: {
                  model.pollingRateDraft ?? model.pollingRateCapabilities.currentRate
                    ?? model.pollingRateCapabilities.profileSupportedRates.first ?? 0
                },
                set: { model.applyPollingRate($0) }
              )
            ) {
              ForEach(model.pollingRateCapabilities.profileSupportedRates, id: \.self) { rate in
                Text(L10n.text("{rate} Hz", replacements: ["rate": formattedWholeNumber(rate)]))
                  .tag(rate)
              }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 105)
            .disabled(model.busy || model.loadingProfile)
            .help(
              L10n.text(
                "Choose a polling rate, then Save to write it to the selected onboard profile."
              )
            )
          }
          Text(L10n.text("Active stages"))
            .font(.caption)
            .foregroundStyle(.secondary)
          Button {
            model.setDPIStageCount(model.dpiCount - 1)
          } label: {
            Image(systemName: "minus")
              .font(.body.weight(.semibold))
              .frame(width: 28, height: 24)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(model.dpiCount <= 1)
          .accessibilityLabel(L10n.text("Remove DPI stage"))
          Text(L10n.text("{count} of 5", replacements: ["count": String(model.dpiCount)]))
            .font(.callout.monospacedDigit())
            .frame(minWidth: 40)
          Button {
            model.setDPIStageCount(model.dpiCount + 1)
          } label: {
            Image(systemName: "plus")
              .font(.body.weight(.semibold))
              .frame(width: 28, height: 24)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(model.dpiCount >= 5)
          .accessibilityLabel(L10n.text("Add DPI stage"))
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        if !model.isProvisionalMouseData, let currentDPI = model.dpiCapabilities.currentValue {
          HStack(spacing: 6) {
            Text(L10n.text("Live DPI"))
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(formattedWholeNumber(currentDPI))
              .font(.caption.monospacedDigit().weight(.semibold))
          }
        }

        DPIStageBar(
          stages: Array(model.dpiStages.prefix(model.dpiCount)),
          defaultStage: model.defaultStage,
          shiftStage: model.shiftStage,
          capabilities: model.dpiCapabilities,
          isLoading: model.loadingProfile,
          validationMessage: model.dpiValidationMessage,
          onDragValue: { index, value in
            model.moveDPIStageDuringDrag(index: index, value: value)
          },
          onDragEnded: {
            model.finishDPIStageDrag()
          },
          onAdjust: { index, direction in
            model.adjustDPIStage(index: index, direction: direction)
          },
          onTextChange: { index, text in
            model.setDPIStageText(index: index, text: text)
          },
          onCommitText: { index in
            model.commitDPIStageText(index: index)
          },
          onSetDefault: { index in
            model.setDefaultDPIStage(index + 1)
          },
          onSetShift: { index in
            model.setShiftDPIStage(index + 1)
          },
          onDelete: { index in
            model.deleteDPIStage(index: index)
          }
        )
        .frame(height: 105)
        .zIndex(10)
      }
      .padding(8)
      .background(
        theme.dpiBackground.opacity(0.28),
        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
      )
    }
    .padding(.top, 4)
  }
}
