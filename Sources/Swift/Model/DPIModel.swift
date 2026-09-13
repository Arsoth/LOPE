// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

/// The DPI values reported by HID++ 0x2201. Some firmware reports every
/// supported value, while other firmware reports a regular range and step.
struct DPICapabilities: Equatable, Sendable {
  var supportedValues: [Int]
  var minimum: Int?
  var maximum: Int?
  var step: Int?
  var sensorCount: Int?
  var currentValue: Int?
  var errorMessage: String?

  init(
    supportedValues: [Int] = [],
    minimum: Int? = nil,
    maximum: Int? = nil,
    step: Int? = nil,
    sensorCount: Int? = nil,
    currentValue: Int? = nil,
    errorMessage: String? = nil
  ) {
    let sortedValues = Array(Set(supportedValues)).sorted()
    self.supportedValues = sortedValues
    self.minimum = minimum ?? sortedValues.first
    self.maximum = maximum ?? sortedValues.last
    self.step = step ?? Self.inferredStep(for: sortedValues)
    self.sensorCount = sensorCount
    self.currentValue = currentValue
    self.errorMessage = errorMessage
  }

  var hasKnownValues: Bool {
    !supportedValues.isEmpty || (minimum != nil && maximum != nil)
  }

  var displayText: String {
    var lines = [String]()
    if let sensorCount {
      lines.append("DPI sensors: \(sensorCount)")
    }
    if !supportedValues.isEmpty {
      lines.append("Supported DPI: " + supportedValues.map(String.init).joined(separator: ", "))
    } else if let minimum, let maximum {
      if let step {
        lines.append("Supported DPI: \(minimum)..\(maximum) (step \(step))")
      } else {
        lines.append("Supported DPI: \(minimum)..\(maximum)")
      }
    }
    if let currentValue {
      lines.append("Current sensor 1 DPI: \(currentValue)")
    }
    if let errorMessage {
      lines.append("DPI error: \(errorMessage)")
    }
    return lines.joined(separator: "\n")
  }

  func accepts(_ value: Int) -> Bool {
    guard (100...Int(UInt16.max)).contains(value) else { return false }
    if !supportedValues.isEmpty {
      return supportedValues.contains(value)
    }
    guard let minimum, let maximum else {
      // The protocol accepts 100...65535, but the device did not give us
      // a narrower capability list to enforce.
      return true
    }
    guard (minimum...maximum).contains(value) else { return false }
    guard let step, step > 0 else { return true }
    return (value - minimum).isMultiple(of: step)
  }

  /// Returns the closest value the mouse reports, constrained by the values
  /// of the neighboring active stages. A nil result means the neighbors are
  /// adjacent in the device's supported value set.
  func snappedValue(
    for value: Int,
    lowerBound: Int? = nil,
    upperBound: Int? = nil
  ) -> Int? {
    let deviceMinimum = minimum ?? 100
    let deviceMaximum = maximum ?? Int(UInt16.max)
    let lower = max(100, deviceMinimum, lowerBound ?? 100)
    let upper = min(Int(UInt16.max), deviceMaximum, upperBound ?? Int(UInt16.max))
    guard lower <= upper else { return nil }

    if !supportedValues.isEmpty {
      return
        supportedValues
        .filter { $0 >= lower && $0 <= upper }
        .min { lhs, rhs in
          let leftDistance = abs(lhs - value)
          let rightDistance = abs(rhs - value)
          return leftDistance == rightDistance ? lhs < rhs : leftDistance < rightDistance
        }
    }

    let clamped = min(max(value, lower), upper)
    guard let minimum, let step, step > 0 else { return clamped }

    let offset = max(0, clamped - minimum)
    let lowerCandidate = minimum + (offset / step) * step
    let candidates = [lowerCandidate, lowerCandidate + step]
      .filter { $0 >= lower && $0 <= upper && $0 >= minimum && $0 <= (maximum ?? Int(UInt16.max)) }
    return candidates.min { lhs, rhs in
      let leftDistance = abs(lhs - value)
      let rightDistance = abs(rhs - value)
      return leftDistance == rightDistance ? lhs < rhs : leftDistance < rightDistance
    }
  }

  func adjustedValue(
    from value: Int,
    direction: AdjustmentDirection,
    lowerBound: Int? = nil,
    upperBound: Int? = nil
  ) -> Int? {
    if !supportedValues.isEmpty {
      let candidates: [Int]
      switch direction {
      case .increase:
        candidates = supportedValues.filter { $0 > value }
      case .decrease:
        candidates = supportedValues.reversed().filter { $0 < value }
      }
      return candidates.first(where: { candidate in
        candidate >= (lowerBound ?? 100) && candidate <= (upperBound ?? Int(UInt16.max))
      })
    }

    let increment = step ?? 100
    let target = direction == .increase ? value + increment : value - increment
    return snappedValue(for: target, lowerBound: lowerBound, upperBound: upperBound)
  }

  enum AdjustmentDirection {
    case increase
    case decrease
  }

  private static func inferredStep(for values: [Int]) -> Int? {
    guard values.count >= 2 else { return nil }
    let differences = zip(values, values.dropFirst()).map { $0.1 - $0.0 }
    guard let first = differences.first, first > 0,
      differences.allSatisfy({ $0 == first })
    else { return nil }
    return first
  }
}

struct DPIOutputParser {
  static func parse(_ text: String) -> DPICapabilities {
    var values: [Int] = []
    var minimum: Int?
    var maximum: Int?
    var step: Int?
    var sensorCount: Int?
    var currentValue: Int?
    var errorMessage: String?

    for rawLine in text.split(whereSeparator: { $0.isNewline }) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.hasPrefix("Supported DPI:") {
        let body = line.dropFirst("Supported DPI:".count).trimmingCharacters(in: .whitespaces)
        let rangeParts = body.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: true)
        let valuesPart = String(rangeParts[0]).trimmingCharacters(in: .whitespaces)
        if let separator = valuesPart.range(of: "..") {
          minimum = Int(valuesPart[..<separator.lowerBound].trimmingCharacters(in: .whitespaces))
          maximum = Int(valuesPart[separator.upperBound...].trimmingCharacters(in: .whitespaces))
          if rangeParts.count == 2 {
            let details = String(rangeParts[1])
            if let stepRange = details.range(of: "step") {
              let stepText = details[stepRange.upperBound...]
                .trimmingCharacters(in: CharacterSet(charactersIn: ") "))
              step = Int(stepText)
            }
          }
        } else {
          values =
            valuesPart
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }
      } else if line.hasPrefix("DPI sensors:") {
        sensorCount = Int(line.dropFirst("DPI sensors:".count).trimmingCharacters(in: .whitespaces))
      } else if line.hasPrefix("Current sensor 1 DPI:") {
        currentValue = Int(
          line.dropFirst("Current sensor 1 DPI:".count).trimmingCharacters(in: .whitespaces))
      } else if line.hasPrefix("DPI error:") {
        errorMessage = String(line.dropFirst("DPI error:".count)).trimmingCharacters(
          in: .whitespaces)
      }
    }

    return DPICapabilities(
      supportedValues: values,
      minimum: minimum,
      maximum: maximum,
      step: step,
      sensorCount: sensorCount,
      currentValue: currentValue,
      errorMessage: errorMessage
    )
  }
}

enum DPIEditorValidation {
  static func message(
    stages: [String],
    count: Int,
    defaultStage: Int,
    shiftStage: Int,
    capabilities: DPICapabilities
  ) -> String? {
    guard (1...5).contains(count), stages.count == 5 else {
      return "Choose between one and five DPI stages."
    }

    let values = stages.prefix(count).enumerated().map { index, text in
      (index: index, value: Int(text))
    }
    guard values.allSatisfy({ $0.value != nil }) else {
      let missing = values.first(where: { $0.value == nil })?.index ?? 0
      return "Enter a numeric value for DPI stage \(missing + 1)."
    }

    let numbers = values.compactMap { $0.value }
    for (index, value) in numbers.enumerated() {
      guard (100...Int(UInt16.max)).contains(value) else {
        return "DPI stage \(index + 1) must be between 100 and 65535."
      }
      guard capabilities.accepts(value) else {
        return "DPI stage \(index + 1) is not supported by this mouse."
      }
      if index > 0, value <= numbers[index - 1] {
        return "DPI stages may not overlap."
      }
    }

    guard (1...count).contains(defaultStage), (1...count).contains(shiftStage) else {
      return "Default and DPI Shift must refer to active stages."
    }
    return nil
  }
}
