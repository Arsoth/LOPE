// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

final class ThemeSupportTests: XCTestCase {
  private var temporaryDirectories: [URL] = []

  override func tearDown() {
    for directory in temporaryDirectories {
      try? FileManager.default.removeItem(at: directory)
    }
    temporaryDirectories.removeAll()
    super.tearDown()
  }

  func testBundledLightAndDarkThemesDecodeWithValidHexColors() {
    let themesDirectory = repositoryThemesDirectory()
    let themes = ThemeCatalog.loadThemes(in: themesDirectory)

    XCTAssertEqual(themes.map(\.id), ["dark", "light"])
    XCTAssertEqual(Set(themes.map(\.appearance)), [.light, .dark])
    for theme in themes {
      XCTAssertNoThrow(try theme.validate())
      XCTAssertTrue(theme.colors.allHexColors.allSatisfy(ThemeColorHex.isValid))
      XCTAssertTrue(theme.dragHandles.allHexColors.allSatisfy(ThemeColorHex.isValid))
      XCTAssertEqual(theme.colors.footer, theme.colors.recentEventsHeader)
    }

    guard let light = themes.first(where: { $0.id == "light" }),
      let dark = themes.first(where: { $0.id == "dark" })
    else {
      return XCTFail("Bundled light and dark themes should both be present")
    }
    XCTAssertEqual(light.dragHandles.defaultStage.color, "#E83D40")
    XCTAssertEqual(light.dragHandles.shiftStage.color, "#3385F0")
    XCTAssertEqual(light.dragHandles.otherStage.color, "#F2B326")
    XCTAssertEqual(dark.dragHandles.defaultStage.color, "#E83D40")
    XCTAssertEqual(dark.dragHandles.shiftStage.color, "#3385F0")
    XCTAssertEqual(dark.dragHandles.otherStage.color, "#F2B326")
    XCTAssertEqual(light.dragHandles.defaultStage.textColor, "#000000")
    XCTAssertEqual(light.dragHandles.shiftStage.textColor, "#000000")
    XCTAssertEqual(light.dragHandles.otherStage.textColor, "#000000")
    XCTAssertEqual(dark.dragHandles.defaultStage.textColor, "#000000")
    XCTAssertEqual(dark.dragHandles.shiftStage.textColor, "#000000")
    XCTAssertEqual(dark.dragHandles.otherStage.textColor, "#000000")
  }

  func testThemeColorHexValidationRejectsMalformedValues() {
    XCTAssertTrue(ThemeColorHex.isValid("#AABBCC"))
    XCTAssertTrue(ThemeColorHex.isValid("#AABBCCDD"))
    XCTAssertFalse(ThemeColorHex.isValid("AABBCC"))
    XCTAssertFalse(ThemeColorHex.isValid("#AABB"))
    XCTAssertFalse(ThemeColorHex.isValid("#AABBCC0"))
    XCTAssertFalse(ThemeColorHex.isValid("#AABBCCG0"))
  }

  func testThemeDecoderRejectsUnsupportedSchemaEmptyMetadataAndInvalidColors() throws {
    let decoder = JSONDecoder()

    let unsupportedSchema = String(
      decoding: try themeJSON(id: "test", name: "Test", appearance: "light"), as: UTF8.self
    )
    .replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2")
    XCTAssertThrowsError(
      try decoder.decode(ThemeDefinition.self, from: Data(unsupportedSchema.utf8)))

    let emptyID = String(
      decoding: try themeJSON(id: "test", name: "Test", appearance: "light"), as: UTF8.self
    )
    .replacingOccurrences(of: "\"id\": \"test\"", with: "\"id\": \"\"")
    XCTAssertThrowsError(try decoder.decode(ThemeDefinition.self, from: Data(emptyID.utf8)))

    let emptyName = String(
      decoding: try themeJSON(id: "test", name: "Test", appearance: "light"), as: UTF8.self
    )
    .replacingOccurrences(of: "\"name\": \"Test\"", with: "\"name\": \"\"")
    XCTAssertThrowsError(try decoder.decode(ThemeDefinition.self, from: Data(emptyName.utf8)))

    let invalidColor = String(
      decoding: try themeJSON(id: "test", name: "Test", appearance: "light"), as: UTF8.self
    )
    .replacingOccurrences(of: "#111111", with: "#GGGGGG")
    XCTAssertThrowsError(try decoder.decode(ThemeDefinition.self, from: Data(invalidColor.utf8)))
  }

  func testThemeValidationErrorsProvideDescriptions() {
    XCTAssertEqual(
      ThemeValidationError.unsupportedSchemaVersion(2).errorDescription,
      "Unsupported theme schema version 2.")
    XCTAssertEqual(
      ThemeValidationError.emptyID.errorDescription,
      "Theme ID cannot be empty.")
    XCTAssertEqual(
      ThemeValidationError.emptyName.errorDescription,
      "Theme name cannot be empty.")
    XCTAssertEqual(
      ThemeValidationError.invalidColor(field: "header", value: "bad").errorDescription,
      "Theme color header is not a six- or eight-digit hex value: bad.")
  }

  func testThemeCatalogPreservesModifiedSystemThemeAndLoadsCustomThemes() throws {
    let customDirectory = makeTemporaryDirectory().appendingPathComponent(
      "Custom Themes", isDirectory: true)
    let bundledDirectory = makeTemporaryDirectory().appendingPathComponent(
      "Themes", isDirectory: true)
    try FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)

    let bundled = try themeJSON(id: "light", name: "Bundled Light", appearance: "light")
    let customOverride = try themeJSON(id: "light", name: "Custom Light", appearance: "light")
    let customAdditional = try themeJSON(id: "custom-dark", name: "Custom Dark", appearance: "dark")
    try bundled.write(to: bundledDirectory.appendingPathComponent("light.json"))
    try customOverride.write(to: customDirectory.appendingPathComponent("light.json"))
    try customAdditional.write(to: customDirectory.appendingPathComponent("custom-dark.json"))

    let catalog = ThemeCatalog(
      customThemesDirectory: customDirectory, builtInThemesDirectory: bundledDirectory)

    XCTAssertEqual(catalog.builtInThemeCount, 1)
    XCTAssertEqual(catalog.customThemeCount, 3)
    XCTAssertTrue(catalog.themes.contains(where: { $0.id == "custom-dark" }))
    XCTAssertTrue(catalog.themes.contains(where: { $0.id == "light" }))
    XCTAssertEqual(catalog.themes.first(where: { $0.id == "light" })?.name, "Bundled Light")
    let preserved = try FileManager.default.contentsOfDirectory(
      at: customDirectory, includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("Custom Light (Modified)-") }
    XCTAssertEqual(preserved.count, 1)
    XCTAssertTrue(preserved.allSatisfy { !$0.lastPathComponent.hasPrefix("_") })
    XCTAssertEqual(try Data(contentsOf: preserved[0]), customOverride)
    let modifiedTheme = catalog.themes.first(
      where: { $0.id.hasPrefix("custom-light-modified-") })
    XCTAssertNotNil(modifiedTheme)
    XCTAssertEqual(modifiedTheme?.name, "Custom Custom Light (Modified)")
  }

  func testInvalidCustomThemesAreIgnoredAndUnderscoreFilesAreNotLoaded() throws {
    let customDirectory = makeTemporaryDirectory()
    try FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: customDirectory.appendingPathComponent("broken.json"))
    try FileManager.default.createDirectory(
      at: customDirectory.appendingPathComponent("directory.json"),
      withIntermediateDirectories: false)
    try themeJSON(id: "ignored", name: "Ignored", appearance: "light").write(
      to: customDirectory.appendingPathComponent("_ignored.json"))

    let bundledDirectory = makeTemporaryDirectory()
    try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
    let catalog = ThemeCatalog(
      customThemesDirectory: customDirectory, builtInThemesDirectory: bundledDirectory)

    XCTAssertEqual(catalog.customThemeCount, 0)
    XCTAssertTrue(catalog.themes.isEmpty)
  }

  func testCustomThemesDirectoryIsSeededWithSystemThemes() throws {
    let configurationDirectory = makeTemporaryDirectory()
    let customDirectory = ThemeStorage.customThemesDirectory(in: configurationDirectory)

    let bundledDirectory = makeTemporaryDirectory()
    try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
    try themeJSON(id: "light", name: "Light", appearance: "light").write(
      to: bundledDirectory.appendingPathComponent("light.json"))
    try themeJSON(id: "dark", name: "Dark", appearance: "dark").write(
      to: bundledDirectory.appendingPathComponent("dark.json"))
    let catalog = ThemeCatalog(
      customThemesDirectory: customDirectory, builtInThemesDirectory: bundledDirectory)

    XCTAssertTrue(FileManager.default.fileExists(atPath: customDirectory.path))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: ThemeStorage.systemThemeURL(id: "light", in: customDirectory).path))
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: ThemeStorage.systemThemeURL(id: "dark", in: customDirectory).path))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: customDirectory.appendingPathComponent("_empty.json").path))
    XCTAssertEqual(catalog.customThemeCount, 2)
    XCTAssertEqual(catalog.themes.map(\.id), ["dark", "light"])
  }

  func testMissingOrModifiedSystemThemeIsRecreatedAndPreservedOnNextLoad() throws {
    let configurationDirectory = makeTemporaryDirectory()
    let customDirectory = ThemeStorage.customThemesDirectory(in: configurationDirectory)
    let bundledDirectory = makeTemporaryDirectory()
    try FileManager.default.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
    let bundledLight = try themeJSON(id: "light", name: "Light", appearance: "light")
    try bundledLight.write(to: bundledDirectory.appendingPathComponent("light.json"))
    try themeJSON(id: "dark", name: "Dark", appearance: "dark").write(
      to: bundledDirectory.appendingPathComponent("dark.json"))
    _ = ThemeCatalog(
      customThemesDirectory: customDirectory, builtInThemesDirectory: bundledDirectory)
    let lightURL = ThemeStorage.systemThemeURL(id: "light", in: customDirectory)

    try FileManager.default.removeItem(at: lightURL)
    XCTAssertFalse(FileManager.default.fileExists(atPath: lightURL.path))
    _ = ThemeCatalog(
      customThemesDirectory: customDirectory, builtInThemesDirectory: bundledDirectory)
    XCTAssertTrue(FileManager.default.fileExists(atPath: lightURL.path))

    var modified = try themeJSON(id: "light", name: "Modified Light", appearance: "light")
    modified = Data(
      String(decoding: modified, as: UTF8.self)
        .replacingOccurrences(of: "#111111", with: "#010203")
        .utf8)
    try modified.write(to: lightURL)
    let catalog = ThemeCatalog(
      customThemesDirectory: customDirectory, builtInThemesDirectory: bundledDirectory)
    XCTAssertEqual(catalog.themes.first(where: { $0.id == "light" })?.name, "Light")
    let modifiedTheme = catalog.themes.first(
      where: { $0.id.hasPrefix("custom-light-modified-") })
    XCTAssertNotNil(modifiedTheme)
    XCTAssertEqual(modifiedTheme?.name, "Custom Modified Light (Modified)")
    XCTAssertEqual(modifiedTheme?.colors.header, "#010203")
    XCTAssertEqual(modifiedTheme?.colors.mainBackground, "#888888")
    XCTAssertEqual(
      try Data(contentsOf: lightURL),
      try ThemeStorage.canonicalThemeData(
        JSONDecoder().decode(ThemeDefinition.self, from: bundledLight)))
    let preserved = try FileManager.default.contentsOfDirectory(
      at: customDirectory, includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("Custom Light (Modified)-") }
    XCTAssertEqual(preserved.count, 1)
    XCTAssertTrue(preserved.allSatisfy { !$0.lastPathComponent.hasPrefix("_") })
    XCTAssertEqual(try Data(contentsOf: preserved[0]), modified)

    try Data("not json".utf8).write(to: lightURL)
    _ = ThemeCatalog(
      customThemesDirectory: customDirectory, builtInThemesDirectory: bundledDirectory)
    let preservedAfterInvalidEdit = try FileManager.default.contentsOfDirectory(
      at: customDirectory, includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("Custom Light (Modified)-") }
    XCTAssertEqual(preservedAfterInvalidEdit.count, 2)
    XCTAssertTrue(
      preservedAfterInvalidEdit.contains { (try? Data(contentsOf: $0)) == Data("not json".utf8) })
  }

  func testThemeStorageReportsFailureWhenDirectoryPathIsAFile() throws {
    let parent = makeTemporaryDirectory()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let blockedURL = parent.appendingPathComponent("blocked")
    try Data("blocked".utf8).write(to: blockedURL)

    XCTAssertFalse(ThemeStorage.ensureCustomThemesDirectory(at: blockedURL))
  }

  @MainActor
  func testAppModelLoadsThemesAndReprimesThemWhenConfigurationMoves() throws {
    let previousValue = UserDefaults.standard.string(
      forKey: "\(AppConstants.defaultsPrefix).configurationDirectory")
    let model = AppModel(startInitialRefresh: false)
    let configurationDirectory = makeTemporaryDirectory()
    defer {
      if let previousValue {
        UserDefaults.standard.set(
          previousValue, forKey: "\(AppConstants.defaultsPrefix).configurationDirectory")
      } else {
        UserDefaults.standard.removeObject(
          forKey: "\(AppConstants.defaultsPrefix).configurationDirectory")
      }
      ThemeCatalog.reload(customThemesDirectory: nil)
    }

    XCTAssertTrue(model.themes.contains(where: { $0.id == "light" }))
    XCTAssertTrue(model.themes.contains(where: { $0.id == "dark" }))

    model.setConfigurationDirectory(configurationDirectory)

    XCTAssertEqual(
      model.customThemesDirectory, ThemeStorage.customThemesDirectory(in: configurationDirectory))
    XCTAssertEqual(model.customThemesDirectoryPath, model.customThemesDirectory.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: model.customThemesDirectory.path))
    XCTAssertTrue(model.themes.contains(where: { $0.id == "light" }))
  }

  private func makeTemporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lope-theme-test-\(UUID().uuidString)", isDirectory: true)
    temporaryDirectories.append(directory)
    return directory
  }

  private func repositoryThemesDirectory() -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("Themes", isDirectory: true)
  }

  private func themeJSON(id: String, name: String, appearance: String) throws -> Data {
    let source = """
      {
        "schemaVersion": 1,
        "id": "\(id)",
        "name": "\(name)",
        "appearance": "\(appearance)",
        "colors": {
          "header": "#111111",
          "footer": "#222222",
          "recentEventsHeader": "#333333",
          "buttonActive": "#444444",
          "buttonInactive": "#555555",
          "checkboxActive": "#666666",
          "checkboxInactive": "#777777",
          "mainBackground": "#888888",
          "primaryText": "#999999",
          "secondaryText": "#AAAAAA",
          "tertiaryText": "#BBBBBB",
          "card": "#CCCCCC",
          "cardBorder": "#DDDDDD",
          "controlBackground": "#EEEEEE",
          "controlBorder": "#F0F0F0",
          "dpiBar": "#123450",
          "dpiBackground": "#123451",
          "accent": "#123456",
          "success": "#234567",
          "warning": "#345678",
          "error": "#456789",
          "separator": "#56789A",
          "shadow": "#89ABCD",
          "hover": "#9ABCDE",
          "selected": "#ABCDEF",
          "disabled": "#BCDEF0"
        },
        "dragHandles": {
          "defaultStage": { "color": "#9ABCDE", "outline": "#ABCDEF", "textColor": "#000000", "shape": "circle" },
          "shiftStage": { "color": "#ABCDEF", "outline": "#BCDEF0", "textColor": "#000000", "shape": "pentagon" },
          "otherStage": { "color": "#CDEF01", "outline": "#DEF012", "textColor": "#000000", "shape": "roundedRectangle" }
        }
      }
      """
    return Data(source.utf8)
  }
}
