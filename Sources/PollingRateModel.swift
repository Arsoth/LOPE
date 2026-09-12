// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

/// Polling rates are normalized to integer Hz for the UI. The native engine
/// keeps the feature-specific wire value, so legacy 0x8060 millisecond
/// intervals remain exact when a rounded Hz label such as 333 is selected.
struct PollingRateCapabilities: Equatable, Sendable {
  var supportedRates: [Int]
  var currentRate: Int?
  var errorMessage: String?

  init(
    supportedRates: [Int] = [],
    currentRate: Int? = nil,
    errorMessage: String? = nil
  ) {
    self.supportedRates = Array(Set(supportedRates.filter { $0 > 0 })).sorted()
    self.currentRate = currentRate
    self.errorMessage = errorMessage
  }

  var hasKnownRates: Bool {
    !supportedRates.isEmpty
  }

  func accepts(_ rate: Int) -> Bool {
    supportedRates.contains(rate)
  }

  var displayText: String {
    var lines = [String]()
    if !supportedRates.isEmpty {
      lines.append(
        "Supported polling rates: " + supportedRates.map(String.init).joined(separator: ", "))
    }
    if let currentRate {
      lines.append("Current polling rate: \(currentRate) Hz")
    }
    if let errorMessage {
      lines.append("Polling-rate error: \(errorMessage)")
    }
    return lines.joined(separator: "\n")
  }
}

struct PollingRateOutputParser {
  static func parse(_ text: String) -> PollingRateCapabilities {
    var supportedRates = [Int]()
    var currentRate: Int?
    var errorMessage: String?

    for rawLine in text.split(whereSeparator: { $0.isNewline }) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.hasPrefix("Supported polling rates:") {
        let body = line.dropFirst("Supported polling rates:".count)
        supportedRates =
          body
          .split(separator: ",")
          .compactMap {
            Int($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " Hz", with: ""))
          }
      } else if line.hasPrefix("Current polling rate:") || line.hasPrefix("Verified polling rate:")
      {
        let body =
          line
          .drop(while: { $0 != ":" })
          .dropFirst()
          .trimmingCharacters(in: .whitespaces)
        currentRate = Int(body.split(separator: " ").first ?? "")
      } else if line.hasPrefix("Report rate error:") {
        errorMessage = String(line.dropFirst("Report rate error:".count))
          .trimmingCharacters(in: .whitespaces)
      }
    }

    return PollingRateCapabilities(
      supportedRates: supportedRates,
      currentRate: currentRate,
      errorMessage: errorMessage
    )
  }
}
