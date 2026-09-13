// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  func setDPIStageText(index: Int, text: String) {
    guard dpiStages.indices.contains(index), index < dpiCount else { return }
    dpiStages[index] = text.filter { $0.isNumber }
  }

  func commitDPIStageText(index: Int) {
    guard dpiStages.indices.contains(index), index < dpiCount,
      let value = Int(dpiStages[index])
    else { return }
    setDPIStageValue(index: index, value: value)
  }

  func setDPIStageValue(index: Int, value: Int) {
    guard dpiStages.indices.contains(index), index < dpiCount else { return }
    let lowerBound = index > 0 ? Int(dpiStages[index - 1]).map { $0 + 1 } : nil
    let upperBound = index + 1 < dpiCount ? Int(dpiStages[index + 1]).map { $0 - 1 } : nil
    guard
      let snapped = dpiCapabilities.snappedValue(
        for: value,
        lowerBound: lowerBound,
        upperBound: upperBound
      )
    else { return }
    dpiStages[index] = String(snapped)
  }

  /// Moves a stage freely while dragging. When it crosses another stage,
  /// swap their ordered positions so the active stage can continue moving
  /// without leaving the profile in an invalid order.
  @discardableResult
  func moveDPIStageDuringDrag(index: Int, value: Int) -> Int {
    guard dpiStages.indices.contains(index), index < dpiCount,
      let snapped = dpiCapabilities.snappedValue(for: value)
    else {
      return index
    }
    if Int(dpiStages[index]) == snapped {
      return index
    }

    dpiStages[index] = String(snapped)
    var currentIndex = index

    while currentIndex > 0,
      let currentValue = Int(dpiStages[currentIndex]),
      let previousValue = Int(dpiStages[currentIndex - 1]),
      currentValue < previousValue
    {
      swapDPIStages(at: currentIndex, and: currentIndex - 1)
      currentIndex -= 1
    }

    while currentIndex + 1 < dpiCount,
      let currentValue = Int(dpiStages[currentIndex]),
      let nextValue = Int(dpiStages[currentIndex + 1]),
      currentValue > nextValue
    {
      swapDPIStages(at: currentIndex, and: currentIndex + 1)
      currentIndex += 1
    }

    return currentIndex
  }

  /// Resolves the rare case where a drag ends with two handles on the same
  /// supported value, keeping the saved stage list strictly increasing.
  func finishDPIStageDrag() {
    guard dpiCount > 0 else { return }
    var previousValue: Int?
    for index in 0..<dpiCount {
      guard let value = Int(dpiStages[index]),
        let adjusted = dpiCapabilities.snappedValue(
          for: value,
          lowerBound: previousValue.map { $0 + 1 }
        )
      else {
        return
      }
      dpiStages[index] = String(adjusted)
      previousValue = adjusted
    }
  }

  private func swapDPIStages(at firstIndex: Int, and secondIndex: Int) {
    dpiStages.swapAt(firstIndex, secondIndex)
    let firstStage = firstIndex + 1
    let secondStage = secondIndex + 1

    if defaultStage == firstStage {
      defaultStage = secondStage
    } else if defaultStage == secondStage {
      defaultStage = firstStage
    }
    if shiftStage == firstStage {
      shiftStage = secondStage
    } else if shiftStage == secondStage {
      shiftStage = firstStage
    }
  }

  func adjustDPIStage(index: Int, direction: DPICapabilities.AdjustmentDirection) {
    guard dpiStages.indices.contains(index), index < dpiCount,
      let current = Int(dpiStages[index])
    else { return }
    let lowerBound = index > 0 ? Int(dpiStages[index - 1]).map { $0 + 1 } : nil
    let upperBound = index + 1 < dpiCount ? Int(dpiStages[index + 1]).map { $0 - 1 } : nil
    guard
      let adjusted = dpiCapabilities.adjustedValue(
        from: current,
        direction: direction,
        lowerBound: lowerBound,
        upperBound: upperBound
      )
    else { return }
    dpiStages[index] = String(adjusted)
  }

  func setDefaultDPIStage(_ stage: Int) {
    guard (1...dpiCount).contains(stage) else { return }
    defaultStage = stage
    guard dpiCount > 1, shiftStage == stage else { return }
    shiftStage = (1...dpiCount).first(where: { $0 != stage }) ?? stage
  }

  func setShiftDPIStage(_ stage: Int) {
    guard (1...dpiCount).contains(stage) else { return }
    shiftStage = stage
    guard dpiCount > 1, defaultStage == stage else { return }
    defaultStage = (1...dpiCount).first(where: { $0 != stage }) ?? stage
  }

  func deleteDPIStage(index: Int) {
    guard dpiCount > 1, (0..<dpiCount).contains(index) else { return }
    let stage = index + 1
    guard stage != defaultStage, stage != shiftStage else { return }

    dpiStages.remove(at: index)
    dpiStages.append("")
    dpiCount -= 1

    if defaultStage > stage {
      defaultStage -= 1
    }
    if shiftStage > stage {
      shiftStage -= 1
    }
  }

  func setDPIStageCount(_ requested: Int) {
    let count = min(max(requested, 1), 5)
    let oldCount = dpiCount
    guard count != oldCount else { return }

    if count > oldCount {
      let activeValues = dpiStages.prefix(oldCount).compactMap(Int.init)
      if activeValues.count == oldCount, let last = activeValues.last {
        let maximum = dpiCapabilities.maximum ?? Int(UInt16.max)
        let insertBeforeLast = maximum - last <= 2_000
        let insertionIndex = insertBeforeLast ? max(activeValues.count - 1, 0) : activeValues.count
        let target = insertBeforeLast ? last - 1_000 : last + 1_000
        let lowerBound = insertionIndex > 0 ? activeValues[insertionIndex - 1] + 1 : nil
        let upperBound =
          insertionIndex < activeValues.count ? activeValues[insertionIndex] - 1 : nil

        if let suggested = dpiCapabilities.snappedValue(
          for: target,
          lowerBound: lowerBound,
          upperBound: upperBound
        ) {
          var updatedValues = activeValues
          updatedValues.insert(suggested, at: insertionIndex)
          dpiStages = updatedValues.map(String.init) + Array(repeating: "", count: 5 - count)
          dpiCount = count

          if defaultStage > insertionIndex {
            defaultStage += 1
          }
          if shiftStage > insertionIndex {
            shiftStage += 1
          }
          if oldCount == 1, defaultStage == shiftStage {
            shiftStage = defaultStage == 1 ? 2 : 1
          }
        }
      } else {
        // Keep the active-stage affordance usable while a text field is
        // incomplete; the validation message will request the value.
        dpiCount = count
        let previous = count > 1 ? Int(dpiStages[count - 2]) : nil
        let fallback = previous.map { $0 + 1_000 } ?? 1_000
        dpiStages[count - 1] = String(fallback)
      }
    } else {
      dpiCount = count
    }

    for index in count..<5 {
      dpiStages[index] = ""
    }
    defaultStage = min(max(defaultStage, 1), count)
    shiftStage = min(max(shiftStage, 1), count)
  }
}
