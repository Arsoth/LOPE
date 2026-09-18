// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

struct AppLocalization: Sendable {
  static let englishIdentifier = "en-us"

  let identifier: String
  private let strings: [String: String]

  init(identifier: String, strings: [String: String]) {
    self.identifier = identifier
    self.strings = strings
  }

  func text(_ key: String, replacements: [String: String] = [:]) -> String {
    var value = strings[key] ?? key
    for (placeholder, replacement) in replacements {
      value = value.replacingOccurrences(of: "{\(placeholder)}", with: replacement)
    }
    return value
  }

  static let shared = load()

  static func load(
    bundle: Bundle = .main,
    preferredLanguages: [String] = Locale.preferredLanguages
  ) -> AppLocalization {
    load(preferredLanguages: preferredLanguages) { identifier in
      guard
        let url = bundle.url(
          forResource: identifier,
          withExtension: "json",
          subdirectory: "Localization"
        ) ?? bundle.url(forResource: identifier, withExtension: "json")
      else {
        return nil
      }
      return try? Data(contentsOf: url)
    }
  }

  static func load(
    preferredLanguages: [String],
    dataForIdentifier: (String) -> Data?
  ) -> AppLocalization {
    var candidates: [String] = []
    for language in preferredLanguages {
      let normalized = language.replacingOccurrences(of: "_", with: "-").lowercased()
      guard !normalized.isEmpty else { continue }
      candidates.append(normalized)
      if let languageCode = normalized.split(separator: "-").first.map(String.init),
        languageCode != normalized
      {
        candidates.append(languageCode)
      }
    }
    candidates.append(englishIdentifier)

    var attempted = Set<String>()
    for identifier in candidates where attempted.insert(identifier).inserted {
      guard let data = dataForIdentifier(identifier),
        let strings = decodeStrings(data)
      else { continue }
      return AppLocalization(identifier: identifier, strings: strings)
    }
    return AppLocalization(identifier: englishIdentifier, strings: [:])
  }

  private static func decodeStrings(_ data: Data) -> [String: String]? {
    guard
      let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else { return nil }

    var strings: [String: String] = [:]
    func collect(_ dictionary: [String: Any]) {
      for (key, value) in dictionary {
        if let string = value as? String {
          strings[key] = string
        } else if let nested = value as? [String: Any] {
          collect(nested)
        }
      }
    }
    collect(dictionary)
    return strings.isEmpty ? nil : strings
  }
}

enum L10n {
  static func text(_ key: String, replacements: [String: String] = [:]) -> String {
    AppLocalization.shared.text(key, replacements: replacements)
  }
}
