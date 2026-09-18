// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

extension DPIStageBar {
  func beginDrag(at index: Int) {
    draggingStage = index
    activeDragValue = nil
    dragOriginIndex = index
    dragStages = stages
    dragDefaultStage = defaultStage
    dragShiftStage = shiftStage
  }

  func interactionTargets(width: CGFloat) -> [DPIStageHitTarget] {
    visibleStages.enumerated().compactMap { index, text in
      guard let value = Int(text) else { return nil }
      let x =
        draggingStage == index
        ? (activeDragX ?? position(for: value, width: width))
        : position(for: value, width: width)
      let role: DPILegendRole =
        visibleDefaultStage == index + 1
        ? .defaultStage
        : (visibleShiftStage == index + 1 ? .shift : .other)
      return DPIStageHitTarget(index: index, x: x, role: role)
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
      var localStages = dragStages,
      let candidate = value(at: x, width: width)
    else { return }
    setActiveDragX(x, width: width)
    guard Int(localStages[index]) != candidate else {
      activeDragValue = candidate
      return
    }

    localStages[index] = String(candidate)
    var currentIndex = index
    while currentIndex > 0,
      let currentValue = Int(localStages[currentIndex]),
      let previousValue = Int(localStages[currentIndex - 1]),
      currentValue < previousValue
    {
      localStages.swapAt(currentIndex, currentIndex - 1)
      swapDragRoles(at: currentIndex, and: currentIndex - 1)
      currentIndex -= 1
    }
    while currentIndex + 1 < localStages.count,
      let currentValue = Int(localStages[currentIndex]),
      let nextValue = Int(localStages[currentIndex + 1]),
      currentValue > nextValue
    {
      localStages.swapAt(currentIndex, currentIndex + 1)
      swapDragRoles(at: currentIndex, and: currentIndex + 1)
      currentIndex += 1
    }

    dragStages = localStages
    draggingStage = currentIndex
    activeDragValue = candidate
  }

  func finishDrag() {
    finishLocalDrag()
    if let dragOriginIndex,
      let draggingStage,
      let localStages = dragStages,
      localStages.indices.contains(draggingStage),
      let finalValue = Int(localStages[draggingStage])
    {
      _ = onDragValue(dragOriginIndex, finalValue)
    }
    onDragEnded()
    withAnimation(.easeOut(duration: 0.08)) {
      draggingStage = nil
      activeDragX = nil
      activeDragValue = nil
      dragOriginIndex = nil
      dragStages = nil
      dragDefaultStage = nil
      dragShiftStage = nil
    }
  }

  private func swapDragRoles(at firstIndex: Int, and secondIndex: Int) {
    let firstStage = firstIndex + 1
    let secondStage = secondIndex + 1
    if dragDefaultStage == firstStage {
      dragDefaultStage = secondStage
    } else if dragDefaultStage == secondStage {
      dragDefaultStage = firstStage
    }
    if dragShiftStage == firstStage {
      dragShiftStage = secondStage
    } else if dragShiftStage == secondStage {
      dragShiftStage = firstStage
    }
  }

  private func finishLocalDrag() {
    guard var localStages = dragStages else { return }
    var previousValue: Int?
    for index in localStages.indices {
      guard let value = Int(localStages[index]),
        let adjusted = capabilities.snappedValue(
          for: value,
          lowerBound: previousValue.map { $0 + 1 }
        )
      else { return }
      localStages[index] = String(adjusted)
      previousValue = adjusted
    }
    dragStages = localStages
    if let draggingStage, localStages.indices.contains(draggingStage) {
      activeDragValue = Int(localStages[draggingStage])
    }
  }

  @ViewBuilder
  func roleIcon(isDefault: Bool, isShift: Bool, filled: Bool, tint: Color) -> some View {
    let shape =
      isDefault
      ? theme.defaultStageShape
      : (isShift ? theme.shiftStageShape : theme.otherStageShape)
    let outline =
      isDefault
      ? theme.defaultStageOutline
      : (isShift ? theme.shiftStageOutline : theme.otherStageOutline)
    themedRoleShape(shape: shape, fill: tint, outline: outline, filled: filled)
      .frame(width: 14, height: 14)
  }

  @ViewBuilder
  func themedRoleShape(
    shape: ThemeDragHandleShape,
    fill: Color,
    outline: Color,
    filled: Bool,
    hovered: Bool = false
  ) -> some View {
    switch shape {
    case .circle:
      if filled {
        Circle().fill(fill).overlay {
          if hovered { Circle().stroke(outline, lineWidth: 2) }
        }
      } else {
        Circle().stroke(outline, lineWidth: 1.25)
      }
    case .triangle:
      if filled {
        DPIStageTriangle().fill(fill).overlay {
          if hovered { DPIStageTriangle().stroke(outline, lineWidth: 2) }
        }
      } else {
        DPIStageTriangle().stroke(outline, lineWidth: 1.25)
      }
    case .pentagon:
      if filled {
        DPIStagePentagon().fill(fill).overlay {
          if hovered { DPIStagePentagon().stroke(outline, lineWidth: 2) }
        }
      } else {
        DPIStagePentagon().stroke(outline, lineWidth: 1.25)
      }
    case .roundedRectangle:
      if filled {
        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(fill).overlay {
          if hovered {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .stroke(outline, lineWidth: 2)
          }
        }
      } else {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .stroke(outline, lineWidth: 1.25)
      }
    }
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
