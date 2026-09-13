// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

extension DPIStageBar {
  func stageHandle(index: Int, text: String, width: CGFloat) -> some View {
    let parsedValue = Int(text)
    let displayValue = parsedValue.map(formattedDPIValue) ?? "Enter DPI"
    let positionValue = parsedValue ?? capabilities.minimum ?? 800
    let isDefault = defaultStage == index + 1
    let isShift = shiftStage == index + 1
    let x =
      draggingStage == index
      ? (activeDragX ?? position(for: positionValue, width: width))
      : position(for: positionValue, width: width)

    return Button {
      guard draggingStage == nil else { return }
      presentStageEditor(index)
    } label: {
      ZStack(alignment: .topLeading) {
        ZStack {
          stageShape(isDefault: isDefault, isShift: isShift)
            .frame(width: 30, height: 30)
          Text("\(index + 1)")
            .font(.callout.weight(.bold))
            .foregroundStyle(.black)
        }
        .frame(width: 34, height: 34)
        .position(x: 42, y: 16)
        Text(displayValue)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(parsedValue == nil ? .orange : .primary)
          .lineLimit(1)
          .frame(width: 84)
          .position(x: 42, y: 45)
          .contentTransition(.opacity)
          .animation(.easeInOut(duration: 0.04), value: displayValue)
          .allowsHitTesting(false)
      }
    }
    .frame(width: 84, height: 62)
    .buttonStyle(.plain)
    .contentShape(Rectangle())
    .accessibilityLabel("DPI stage \(index + 1)")
    .accessibilityValue(parsedValue.map { "\(formattedDPIValue($0)) DPI" } ?? "Invalid value")
    .accessibilityHint("Click to edit, drag to change, or use the keyboard adjustment action.")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        onAdjust(index, .increase)
      case .decrement:
        onAdjust(index, .decrease)
      @unknown default:
        break
      }
    }
    .position(x: x, y: 58)
    .zIndex(draggingStage == index ? 20 : 2)
  }

  @ViewBuilder
  func stageShape(isDefault: Bool, isShift: Bool) -> some View {
    if isDefault {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(DPIStagePalette.defaultStage)
    } else if isShift {
      DPIStagePentagon()
        .fill(DPIStagePalette.shift)
    } else {
      Circle()
        .fill(DPIStagePalette.other)
    }
  }
}
