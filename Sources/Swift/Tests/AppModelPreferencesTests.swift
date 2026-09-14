// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelPreferencesTests: XCTestCase {
  private let lightThemeKey = "\(AppConstants.defaultsPrefix).lightThemeID"
  private let darkThemeKey = "\(AppConstants.defaultsPrefix).darkThemeID"
  private let keyboardGroupsKey = "\(AppConstants.defaultsPrefix).keyboardKeyGroups"

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: lightThemeKey)
    UserDefaults.standard.removeObject(forKey: darkThemeKey)
    UserDefaults.standard.removeObject(forKey: keyboardGroupsKey)
    ThemeCatalog.reload(customThemesDirectory: nil)
    super.tearDown()
  }

  func testThemePreferencesDefaultToBundledLightAndDarkThemes() {
    let model = AppModel(startInitialRefresh: false)

    XCTAssertEqual(model.selectedLightThemeID, "light")
    XCTAssertEqual(model.selectedDarkThemeID, "dark")
    XCTAssertEqual(model.lightThemes.first(where: { $0.id == "light" })?.appearance, .light)
    XCTAssertEqual(model.darkThemes.first(where: { $0.id == "dark" })?.appearance, .dark)
  }

  func testThemePreferencesPersistAndDriveActiveThemeForEachMode() {
    _ = NSApplication.shared
    let model = AppModel(startInitialRefresh: false)

    model.setLightThemeID("light")
    model.setDarkThemeID("dark")
    model.setAppearancePreference(.light)
    XCTAssertEqual(model.activeTheme?.id, "light")
    XCTAssertEqual(UserDefaults.standard.string(forKey: lightThemeKey), "light")
    XCTAssertEqual(UserDefaults.standard.string(forKey: darkThemeKey), "dark")

    model.setAppearancePreference(.dark)
    XCTAssertEqual(model.activeTheme?.id, "dark")

    model.setAppearancePreference(.system)
    XCTAssertEqual(model.activeTheme?.appearance, model.activeThemeAppearance)
  }

  func testThemePreferenceRejectsThemeWithTheWrongAppearance() {
    let model = AppModel(startInitialRefresh: false)
    let originalLightID = model.selectedLightThemeID
    let originalDarkID = model.selectedDarkThemeID

    model.setLightThemeID("dark")
    model.setDarkThemeID("light")

    XCTAssertEqual(model.selectedLightThemeID, originalLightID)
    XCTAssertEqual(model.selectedDarkThemeID, originalDarkID)
    XCTAssertNil(UserDefaults.standard.string(forKey: lightThemeKey))
    XCTAssertNil(UserDefaults.standard.string(forKey: darkThemeKey))
  }

  func testThemeRefreshAndSelectionReadCurrentJSON() throws {
    let configurationKey = "\(AppConstants.defaultsPrefix).configurationDirectory"
    let previousConfiguration = UserDefaults.standard.string(forKey: configurationKey)
    let model = AppModel(startInitialRefresh: false)
    let configurationDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lope-live-theme-test-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: configurationDirectory)
      if let previousConfiguration {
        UserDefaults.standard.set(previousConfiguration, forKey: configurationKey)
      } else {
        UserDefaults.standard.removeObject(forKey: configurationKey)
      }
      ThemeCatalog.reload(customThemesDirectory: nil)
    }

    model.setConfigurationDirectory(configurationDirectory)
    let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("Themes/light.json")
    var source = try String(contentsOf: sourceURL, encoding: .utf8)
    source = source.replacingOccurrences(of: "\"id\": \"light\"", with: "\"id\": \"live-light\"")
    source = source.replacingOccurrences(
      of: "\"name\": \"Light\"", with: "\"name\": \"Live Light\"")
    let themeURL = model.customThemesDirectory.appendingPathComponent("live-light.json")
    try Data(source.utf8).write(to: themeURL)

    model.refreshThemes()
    XCTAssertEqual(model.themes.first(where: { $0.id == "live-light" })?.name, "Live Light")

    source = source.replacingOccurrences(
      of: "\"name\": \"Live Light\"", with: "\"name\": \"Updated Live Light\"")
    try Data(source.utf8).write(to: themeURL)
    model.refreshThemes()
    XCTAssertEqual(
      model.themes.first(where: { $0.id == "live-light" })?.name, "Updated Live Light")

    source = source.replacingOccurrences(
      of: "\"name\": \"Updated Live Light\"", with: "\"name\": \"Selected Live Light\"")
    try Data(source.utf8).write(to: themeURL)
    model.setAppearancePreference(.light)
    model.setLightThemeID("live-light")
    XCTAssertEqual(model.activeTheme?.name, "Selected Live Light")
  }

  func testPreferencesLoadFromUserDefaults() {
    UserDefaults.standard.set("light", forKey: lightThemeKey)
    UserDefaults.standard.set("dark", forKey: darkThemeKey)
    UserDefaults.standard.set(
      [KeyboardKeyGroup.media.rawValue, KeyboardKeyGroup.other.rawValue],
      forKey: keyboardGroupsKey
    )

    let model = AppModel(startInitialRefresh: false)

    XCTAssertEqual(model.selectedLightThemeID, "light")
    XCTAssertEqual(model.selectedDarkThemeID, "dark")
    XCTAssertEqual(model.enabledKeyboardKeyGroups, [.media, .other])
  }

  func testKeyboardKeyGroupsDefaultToStandardAndPersistIndependently() {
    let model = AppModel(startInitialRefresh: false)

    XCTAssertEqual(model.enabledKeyboardKeyGroups, [.standard])

    model.setKeyboardKeyGroup(.function, enabled: true)
    model.setKeyboardKeyGroup(.standard, enabled: false)

    XCTAssertEqual(model.enabledKeyboardKeyGroups, [.function])
    XCTAssertEqual(
      UserDefaults.standard.array(forKey: keyboardGroupsKey) as? [String],
      [KeyboardKeyGroup.function.rawValue]
    )
  }

  func testFilteredKeyboardGroupsOnlyIncludeEnabledCategories() {
    let model = AppModel(startInitialRefresh: false)
    model.setKeyboardKeyGroup(.standard, enabled: false)
    model.setKeyboardKeyGroup(.function, enabled: true)
    model.setKeyboardKeyGroup(.media, enabled: false)
    model.setKeyboardKeyGroup(.other, enabled: false)

    XCTAssertEqual(model.filteredExtendedKeyboardKeyGroups.map(\.group), [.function])
    XCTAssertEqual(
      model.filteredExtendedKeyboardKeyLayoutGroups.flatMap(\.keys),
      model.extendedKeyboardKeyLayoutGroups.flatMap { group in
        group.keys.filter { model.keyboardKeyGroup(for: $0) == .function }
      }
    )
  }

  func testFilteredKeyboardGroupsKeepSelectedKeyFromDisabledCategory() {
    let model = AppModel(startInitialRefresh: false)
    model.setKeyboardKeyGroup(.standard, enabled: false)
    model.setKeyboardKeyGroup(.function, enabled: false)
    model.setKeyboardKeyGroup(.media, enabled: false)
    model.setKeyboardKeyGroup(.other, enabled: false)

    let groups = model.filteredExtendedKeyboardKeyGroups(including: 0x68)

    XCTAssertEqual(groups.map(\.group), [.function])
    XCTAssertEqual(groups[0].keys.map(\.label), ["F13"])
  }

  func testFilteredKeyboardLayoutGroupsKeepSelectedKeyFromDisabledCategory() {
    let model = AppModel(startInitialRefresh: false)
    model.setKeyboardKeyGroup(.standard, enabled: false)
    model.setKeyboardKeyGroup(.function, enabled: false)
    model.setKeyboardKeyGroup(.media, enabled: false)
    model.setKeyboardKeyGroup(.other, enabled: false)

    let groups = model.filteredExtendedKeyboardKeyLayoutGroups(including: 0x49)

    XCTAssertEqual(groups.map(\.group), [.navigation])
    XCTAssertEqual(groups[0].keys.map(\.label), ["Insert"])
  }

  func testDirectExtendedKeySelectionIgnoresCategoryFilters() {
    let model = AppModel(startInitialRefresh: false)
    configureFixtureDevice(model)
    model.showNonStandardKeyboardKeys = true
    model.setKeyboardKeyGroup(.standard, enabled: false)
    model.setKeyboardKeyGroup(.function, enabled: false)
    model.setKeyboardKeyGroup(.media, enabled: false)
    model.setKeyboardKeyGroup(.other, enabled: false)

    model.setKeyboardKeyChoice(buttonIndex: 0, key: 0x49)

    XCTAssertEqual(model.keyboardKey(buttonIndex: 0), 0x49)
    XCTAssertEqual(model.keyboardKeyChoice(buttonIndex: 0), 0x49)
    XCTAssertTrue(model.filteredExtendedKeyboardKeyGroups.isEmpty)
    XCTAssertTrue(model.filteredExtendedKeyboardKeyLayoutGroups.isEmpty)
  }
}
