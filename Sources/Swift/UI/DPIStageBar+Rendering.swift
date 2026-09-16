// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

extension DPIStageBar {
  func stageHandle(index: Int, text: String, width: CGFloat) -> some View {
    let parsedValue = Int(text)
    let liveValue = draggingStage == index ? activeDragValue ?? parsedValue : parsedValue
    let displayValue = liveValue.map(formattedDPIValue) ?? "Enter DPI"
    let positionValue = parsedValue ?? capabilities.minimum ?? 800
    let isDefault = visibleDefaultStage == index + 1
    let isShift = visibleShiftStage == index + 1
    let isHovered = hoveredStageIndex == index && draggingStage == nil && editingStage == nil
    let handleTextColor =
      isDefault
      ? theme.defaultStageText
      : (isShift ? theme.shiftStageText : theme.otherStageText)
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
          stageShape(isDefault: isDefault, isShift: isShift, isHovered: isHovered)
            .frame(width: 30, height: 30)
          Text("\(index + 1)")
            .font(.callout.weight(.bold))
            .foregroundStyle(handleTextColor)
        }
        .frame(width: 30, height: 30)
        .position(x: 42, y: 16)
        Text(displayValue)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(parsedValue == nil ? theme.warning : theme.primaryText)
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
    .accessibilityValue(liveValue.map { "\(formattedDPIValue($0)) DPI" } ?? "Invalid value")
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
  func stageShape(isDefault: Bool, isShift: Bool, isHovered: Bool = false) -> some View {
    if isDefault {
      themedRoleShape(
        shape: theme.defaultStageShape,
        fill: theme.defaultStage,
        outline: theme.defaultStageOutline,
        filled: true,
        hovered: isHovered
      )
    } else if isShift {
      themedRoleShape(
        shape: theme.shiftStageShape,
        fill: theme.shiftStage,
        outline: theme.shiftStageOutline,
        filled: true,
        hovered: isHovered
      )
    } else {
      themedRoleShape(
        shape: theme.otherStageShape,
        fill: theme.otherStage,
        outline: theme.otherStageOutline,
        filled: true,
        hovered: isHovered
      )
    }
  }
}
