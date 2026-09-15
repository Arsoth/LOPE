// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

extension DPIStageBar {
  var stagePopoverBackground: Color {
    theme.controlBackground
  }

  var stagePopoverBorder: Color {
    theme.controlBorder
  }

  func stagePopover(index: Int, isInteractive: Bool) -> some View {
    let isDefault = defaultStage == index + 1
    let isShift = shiftStage == index + 1
    let canDelete = !isDefault && !isShift
    return VStack(alignment: .leading, spacing: 10) {
      Text("DPI stage \(index + 1)")
        .font(.headline)
      stageValueField(index: index, isInteractive: isInteractive)

      Divider()

      Button {
        onSetDefault(index)
        dismissStageEditor()
      } label: {
        HStack(spacing: 7) {
          roleIcon(
            isDefault: true, isShift: false, filled: isDefault, tint: theme.defaultStage)
          Text(isDefault ? "Default" : "Make Default")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())

      Divider()

      Button {
        onSetShift(index)
        dismissStageEditor()
      } label: {
        HStack(spacing: 7) {
          roleIcon(isDefault: false, isShift: true, filled: isShift, tint: theme.shiftStage)
          Text(isShift ? "DPI Shift" : "Make DPI Shift")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())

      Divider()

      Button(role: .destructive) {
        onDelete(index)
        dismissStageEditor()
      } label: {
        Label("Delete stage", systemImage: "trash")
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .disabled(!canDelete)

      Text("Dragging snaps to the mouse’s supported DPI values.")
        .font(.caption)
        .foregroundStyle(theme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(width: 230)
    .background(
      stagePopoverBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(stagePopoverBorder, lineWidth: 0.75)
    }
    .shadow(color: theme.shadow, radius: 8, y: 3)
  }

  @ViewBuilder
  func stageValueField(index: Int, isInteractive: Bool) -> some View {
    let binding = Binding(
      get: { stages.indices.contains(index) ? stages[index] : "" },
      set: { onTextChange(index, $0) }
    )
    if isInteractive {
      TextField("DPI", text: binding)
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .focused($focusedStageIndex, equals: index)
        .onSubmit { onCommitText(index) }
    } else {
      TextField("DPI", text: binding)
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .allowsHitTesting(false)
    }
  }

  var dpiLegend: some View {
    HStack(spacing: 7) {
      ForEach(legendOrder, id: \.self) { role in
        legendItem(role)
      }
    }
  }

  func legendItem(_ role: DPILegendRole) -> some View {
    let label: String
    let isDefault: Bool
    let isShift: Bool
    let tint: Color

    switch role {
    case .defaultStage:
      label = "Default"
      isDefault = true
      isShift = false
      tint = theme.defaultStage
    case .shift:
      label = "DPI Shift"
      isDefault = false
      isShift = true
      tint = theme.shiftStage
    case .other:
      label = "Other"
      isDefault = false
      isShift = false
      tint = theme.otherStage
    }

    return HStack(spacing: 3) {
      roleIcon(isDefault: isDefault, isShift: isShift, filled: true, tint: tint)
      Text(label)
    }
  }

  var legendOrder: [DPILegendRole] {
    let lowerRole: DPILegendRole = defaultStage <= shiftStage ? .defaultStage : .shift
    let upperRole: DPILegendRole = defaultStage <= shiftStage ? .shift : .defaultStage
    let lowerStage = min(defaultStage, shiftStage)
    let upperStage = max(defaultStage, shiftStage)
    var beforeCount = 0
    var betweenCount = 0
    var afterCount = 0

    for (index, text) in stages.enumerated() where Int(text) != nil {
      let stage = index + 1
      guard stage != defaultStage, stage != shiftStage else { continue }
      if stage < lowerStage {
        beforeCount += 1
      } else if stage > upperStage {
        afterCount += 1
      } else {
        betweenCount += 1
      }
    }

    if betweenCount > beforeCount, betweenCount > afterCount {
      return [lowerRole, .other, upperRole]
    }
    if beforeCount > betweenCount, beforeCount > afterCount {
      return [.other, lowerRole, upperRole]
    }
    // After is the fallback for ties, including one Other stage on each
    // outside of the two role stages.
    return [lowerRole, upperRole, .other]
  }
}
