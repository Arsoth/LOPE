// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

enum ProfileOutputParser {
    static func onboardProfileCapacity(in text: String) -> Int? {
        let pattern = try! NSRegularExpression(pattern: #"^Profile capacity:\s+(\d+)\s*$"#)
        let normalizedText = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        for rawLine in normalizedText.split(separator: "\n").map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = pattern.firstMatch(in: line, range: range),
                  let range = Range(match.range(at: 1), in: line),
                  let capacity = Int(line[range]),
                  capacity > 0 else { continue }
            return capacity
        }
        return nil
    }
}
