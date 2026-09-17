// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

final class LocalizationTests: XCTestCase {
  func testTextUsesJSONValueAndReplacesNamedPlaceholders() {
    let localization = AppLocalization(
      identifier: "fr-fr",
      strings: ["greeting": "Bonjour, {name}!", "missing": "Configured"]
    )

    XCTAssertEqual(
      localization.text("greeting", replacements: ["name": "Ada"]),
      "Bonjour, Ada!"
    )
    XCTAssertEqual(localization.text("missing"), "Configured")
    XCTAssertEqual(localization.text("unknown"), "unknown")
  }

  func testLoadPrefersExactLanguageThenFallsBackToLanguageCode() {
    let frenchData = try! JSONSerialization.data(withJSONObject: [
      "navigation": ["Settings": "Réglages"]
    ])
    let englishData = try! JSONSerialization.data(withJSONObject: ["Settings": "Settings"])

    let exact = AppLocalization.load(preferredLanguages: ["fr-FR", "en-US"]) { identifier in
      ["fr-fr": frenchData, "en-us": englishData][identifier]
    }
    XCTAssertEqual(exact.identifier, "fr-fr")
    XCTAssertEqual(exact.text("Settings"), "Réglages")

    let languageCode = AppLocalization.load(preferredLanguages: ["fr-CA", "en-US"]) { identifier in
      ["fr": frenchData, "en-us": englishData][identifier]
    }
    XCTAssertEqual(languageCode.identifier, "fr")
    XCTAssertEqual(languageCode.text("Settings"), "Réglages")
  }

  func testLoadSkipsInvalidDataAndUsesEnglishFallback() {
    let englishData = try! JSONEncoder().encode(["Settings": "Settings"])

    let fallback = AppLocalization.load(preferredLanguages: ["de-DE"]) { identifier in
      ["de-de": Data("not-json".utf8), "en-us": englishData][identifier]
    }
    XCTAssertEqual(fallback.identifier, "en-us")
    XCTAssertEqual(fallback.text("Settings"), "Settings")

    let empty = AppLocalization.load(preferredLanguages: ["de-DE"]) { _ in nil }
    XCTAssertEqual(empty.identifier, "en-us")
    XCTAssertEqual(empty.text("Settings"), "Settings")
  }
}
