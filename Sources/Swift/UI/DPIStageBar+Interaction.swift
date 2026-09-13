// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

extension DPIStageBar {
  func interactionTargets(width: CGFloat) -> [DPIStageHitTarget] {
    stages.enumerated().compactMap { index, text in
      guard let value = Int(text) else { return nil }
      let x =
        draggingStage == index
        ? (activeDragX ?? position(for: value, width: width))
        : position(for: value, width: width)
      return DPIStageHitTarget(index: index, x: x)
    }
  }

  func setActiveDragX(_ x: CGFloat, width: CGFloat) {
    let inset = trackInset
    let rightEdge = max(width - inset, inset)
    let clampedX = min(max(x, inset), rightEdge)
    guard activeDragX != clampedX else { return }
    var transaction = Transaction()
    transaction.animation = nil
    withTransaction(transaction) {
      activeDragX = clampedX
    }
  }

  func updateDrag(at x: CGFloat, width: CGFloat) {
    guard let index = draggingStage,
      let candidate = value(at: x, width: width)
    else {
      return
    }
    setActiveDragX(x, width: width)
    let update = DPIStageDragUpdate(index: index, value: candidate)
    guard lastDragUpdate != update else { return }
    let updatedIndex = onDragValue(index, candidate)
    draggingStage = updatedIndex
    lastDragUpdate = DPIStageDragUpdate(index: updatedIndex, value: candidate)
  }

  func finishDrag() {
    onDragEnded()
    withAnimation(.easeOut(duration: 0.08)) {
      draggingStage = nil
      activeDragX = nil
    }
    lastDragUpdate = nil
  }

  @ViewBuilder
  func roleIcon(isDefault: Bool, isShift: Bool, filled: Bool, tint: Color) -> some View {
    Group {
      if isDefault {
        if filled {
          RoundedRectangle(cornerRadius: 3, style: .continuous).fill(tint)
        } else {
          RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(tint, lineWidth: 1.25)
        }
      } else if isShift {
        if filled {
          DPIStagePentagon().fill(tint)
        } else {
          DPIStagePentagon().stroke(tint, lineWidth: 1.25)
        }
      } else {
        if filled {
          Circle().fill(tint)
        } else {
          Circle().stroke(tint, lineWidth: 1.25)
        }
      }
    }
    .frame(width: 14, height: 14)
  }

  var tickValues: [Int] {
    let minimum = capabilities.minimum ?? 100
    let maximum = capabilities.maximum ?? Int(UInt16.max)
    let firstTick = ((minimum + 999) / 1000) * 1000
    guard firstTick <= maximum else { return [] }
    return Array(stride(from: firstTick, through: maximum, by: 1000))
  }

  func presentStageEditor(_ index: Int) {
    if let editingStage, editingStage.index != index {
      onCommitText(editingStage.index)
      fadingStage = presentedStage
      presentedStage = DPIStageSelection(index: index)
      popoverContentOpacity = 0
      withAnimation(.easeOut(duration: stageSwitchDuration)) {
        self.editingStage = DPIStageSelection(index: index)
        popoverContentOpacity = 1
      }
      focusedStageIndex = index
      clearFadingStage(after: stageSwitchDuration, index: index)
      return
    }

    if editingStage == nil {
      presentedStage = DPIStageSelection(index: index)
      fadingStage = nil
      popoverContentOpacity = 1
    }
    withAnimation(.easeOut(duration: 0.04)) {
      editingStage = DPIStageSelection(index: index)
    }
  }

  func dismissStageEditor() {
    if let editingStage {
      onCommitText(editingStage.index)
    }
    withAnimation(.easeOut(duration: 0.04)) {
      editingStage = nil
    }
    presentedStage = nil
    fadingStage = nil
    popoverContentOpacity = 1
  }

  func clearFadingStage(after duration: TimeInterval, index: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
      guard self.editingStage?.index == index else { return }
      fadingStage = nil
    }
  }

  func position(for value: Int, width: CGFloat) -> CGFloat {
    let minimum = capabilities.minimum ?? 100
    let maximum = capabilities.maximum ?? Int(UInt16.max)
    guard maximum > minimum else { return width / 2 }
    let logMinimum = log(Double(minimum))
    let logMaximum = log(Double(maximum))
    let fraction = min(
      max(CGFloat((log(Double(max(value, minimum))) - logMinimum) / (logMaximum - logMinimum)), 0),
      1
    )
    return trackInset + fraction * max(width - trackInset * 2, 1)
  }

  func value(at x: CGFloat, width: CGFloat) -> Int? {
    let minimum = capabilities.minimum ?? 100
    let maximum = capabilities.maximum ?? Int(UInt16.max)
    let fraction = min(max((x - trackInset) / max(width - trackInset * 2, 1), 0), 1)
    let logMinimum = log(Double(minimum))
    let logMaximum = log(Double(maximum))
    let raw = Int(exp(logMinimum + Double(fraction) * (logMaximum - logMinimum)).rounded())
    return capabilities.snappedValue(for: raw)
  }
}
