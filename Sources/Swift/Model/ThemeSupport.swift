// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import CryptoKit
import Foundation

enum ThemeColorHex {
  static func isValid(_ value: String) -> Bool {
    guard value.first == "#" else { return false }
    let digits = String(value.dropFirst())
    guard digits.count == 6 || digits.count == 8 else { return false }
    return UInt64(digits, radix: 16) != nil
  }
}

enum ThemeAppearance: String, Codable, CaseIterable, Hashable, Sendable {
  case light
  case dark
}

enum ThemeDragHandleShape: String, Codable, CaseIterable, Hashable, Sendable {
  case circle
  case triangle
  case pentagon
  case roundedRectangle
}

struct ThemeColors: Codable, Equatable, Hashable, Sendable {
  let header: String
  let footer: String
  let recentEventsHeader: String
  let buttonActive: String
  let buttonInactive: String
  let checkboxActive: String
  let checkboxInactive: String
  let mainBackground: String
  let primaryText: String
  let secondaryText: String
  let tertiaryText: String
  let card: String
  let cardBorder: String
  let controlBackground: String
  let controlBorder: String
  let dpiBar: String
  let dpiBackground: String
  let accent: String
  let success: String
  let warning: String
  let error: String
  let separator: String
  let shadow: String
  let hover: String
  let selected: String
  let disabled: String

  var allHexColors: [String] {
    [
      header, footer, recentEventsHeader, buttonActive, buttonInactive,
      checkboxActive, checkboxInactive, mainBackground, primaryText, secondaryText,
      tertiaryText, card, cardBorder, controlBackground, controlBorder, dpiBar,
      dpiBackground, accent, success, warning, error, separator, shadow, hover,
      selected, disabled,
    ]
  }
}

struct ThemeDragHandle: Codable, Equatable, Hashable, Sendable {
  let color: String
  let outline: String
  let textColor: String
  let shape: ThemeDragHandleShape
}

struct ThemeDragHandles: Codable, Equatable, Hashable, Sendable {
  let defaultStage: ThemeDragHandle
  let shiftStage: ThemeDragHandle
  let otherStage: ThemeDragHandle

  var allHexColors: [String] {
    [
      defaultStage.color, defaultStage.outline, defaultStage.textColor,
      shiftStage.color, shiftStage.outline, shiftStage.textColor,
      otherStage.color, otherStage.outline, otherStage.textColor,
    ]
  }
}

struct ThemeDefinition: Codable, Equatable, Hashable, Sendable, Identifiable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let id: String
  let name: String
  let appearance: ThemeAppearance
  let colors: ThemeColors
  let dragHandles: ThemeDragHandles

  init(
    schemaVersion: Int,
    id: String,
    name: String,
    appearance: ThemeAppearance,
    colors: ThemeColors,
    dragHandles: ThemeDragHandles
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.name = name
    self.appearance = appearance
    self.colors = colors
    self.dragHandles = dragHandles
  }

  func replacingID(_ id: String, name: String? = nil) -> ThemeDefinition {
    ThemeDefinition(
      schemaVersion: schemaVersion,
      id: id,
      name: name ?? self.name,
      appearance: appearance,
      colors: colors,
      dragHandles: dragHandles
    )
  }

  func validate() throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw ThemeValidationError.unsupportedSchemaVersion(schemaVersion)
    }
    guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ThemeValidationError.emptyID
    }
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ThemeValidationError.emptyName
    }

    let colorFields = [
      "header": colors.header,
      "footer": colors.footer,
      "recentEventsHeader": colors.recentEventsHeader,
      "buttonActive": colors.buttonActive,
      "buttonInactive": colors.buttonInactive,
      "checkboxActive": colors.checkboxActive,
      "checkboxInactive": colors.checkboxInactive,
      "mainBackground": colors.mainBackground,
      "primaryText": colors.primaryText,
      "secondaryText": colors.secondaryText,
      "tertiaryText": colors.tertiaryText,
      "card": colors.card,
      "cardBorder": colors.cardBorder,
      "controlBackground": colors.controlBackground,
      "controlBorder": colors.controlBorder,
      "dpiBar": colors.dpiBar,
      "dpiBackground": colors.dpiBackground,
      "accent": colors.accent,
      "success": colors.success,
      "warning": colors.warning,
      "error": colors.error,
      "separator": colors.separator,
      "shadow": colors.shadow,
      "hover": colors.hover,
      "selected": colors.selected,
      "disabled": colors.disabled,
      "dragHandles.defaultStage.color": dragHandles.defaultStage.color,
      "dragHandles.defaultStage.outline": dragHandles.defaultStage.outline,
      "dragHandles.defaultStage.textColor": dragHandles.defaultStage.textColor,
      "dragHandles.shiftStage.color": dragHandles.shiftStage.color,
      "dragHandles.shiftStage.outline": dragHandles.shiftStage.outline,
      "dragHandles.shiftStage.textColor": dragHandles.shiftStage.textColor,
      "dragHandles.otherStage.color": dragHandles.otherStage.color,
      "dragHandles.otherStage.outline": dragHandles.otherStage.outline,
      "dragHandles.otherStage.textColor": dragHandles.otherStage.textColor,
    ]
    guard let invalid = colorFields.first(where: { !ThemeColorHex.isValid($0.value) }) else {
      return
    }
    throw ThemeValidationError.invalidColor(field: invalid.key, value: invalid.value)
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    id = try values.decode(String.self, forKey: .id)
    name = try values.decode(String.self, forKey: .name)
    appearance = try values.decode(ThemeAppearance.self, forKey: .appearance)
    colors = try values.decode(ThemeColors.self, forKey: .colors)
    dragHandles = try values.decode(ThemeDragHandles.self, forKey: .dragHandles)
    try validate()
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case id
    case name
    case appearance
    case colors
    case dragHandles
  }
}

enum ThemeValidationError: LocalizedError, Equatable {
  case unsupportedSchemaVersion(Int)
  case emptyID
  case emptyName
  case invalidColor(field: String, value: String)

  var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version):
      return "Unsupported theme schema version \(version)."
    case .emptyID:
      return "Theme ID cannot be empty."
    case .emptyName:
      return "Theme name cannot be empty."
    case .invalidColor(let field, let value):
      return "Theme color \(field) is not a six- or eight-digit hex value: \(value)."
    }
  }
}

enum ThemeStorage {
  static let customThemesDirectoryName = "Custom Themes"
  static let systemThemeIDs: Set<String> = ["light", "dark"]

  static func customThemesDirectory(in configurationDirectory: URL) -> URL {
    configurationDirectory.appendingPathComponent(customThemesDirectoryName, isDirectory: true)
  }

  static func systemThemeURL(id: String, in customThemesDirectory: URL) -> URL {
    customThemesDirectory.appendingPathComponent("\(id).json")
  }

  @discardableResult
  static func ensureCustomThemesDirectory(
    at directory: URL,
    systemThemes: [ThemeDefinition] = [],
    fileManager: FileManager = .default
  ) -> Bool {
    do {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

      for theme in systemThemes where systemThemeIDs.contains(theme.id) {
        let canonicalData = try canonicalThemeData(theme)
        let url = systemThemeURL(id: theme.id, in: directory)

        guard fileManager.fileExists(atPath: url.path) else {
          try canonicalData.write(to: url, options: .atomic)
          continue
        }

        let existingData = try? Data(contentsOf: url)
        if existingData == canonicalData {
          continue
        }

        let preservedURL = preservedSystemThemeURL(
          id: theme.id, originalData: existingData, in: directory, fileManager: fileManager)
        try fileManager.moveItem(at: url, to: preservedURL)
        do {
          try canonicalData.write(to: url, options: .atomic)
        } catch {
          try? fileManager.moveItem(at: preservedURL, to: url)
          throw error
        }
      }
      return true
    } catch {
      return false
    }
  }

  static func canonicalThemeData(_ theme: ThemeDefinition) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(theme)
  }

  static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func preservedSystemThemeURL(
    id: String,
    originalData: Data?,
    in directory: URL,
    fileManager: FileManager
  ) -> URL {
    let digest = originalData.map { String(sha256Hex($0).prefix(12)) } ?? "unreadable"
    let baseName = "Custom \(id.capitalized) (Modified)-\(digest)"
    var candidate = directory.appendingPathComponent("\(baseName).json")
    var suffix = 2
    while fileManager.fileExists(atPath: candidate.path) {
      candidate = directory.appendingPathComponent("\(baseName)-\(suffix).json")
      suffix += 1
    }
    return candidate
  }
}

struct ThemeCatalog: Sendable {
  static var shared = ThemeCatalog()

  static func reload(customThemesDirectory: URL? = nil) {
    shared = ThemeCatalog(customThemesDirectory: customThemesDirectory)
  }

  let themes: [ThemeDefinition]
  let bundledThemes: [ThemeDefinition]
  let customThemes: [ThemeDefinition]
  let customThemesDirectory: URL
  let builtInThemeCount: Int
  let customThemeCount: Int

  init(
    customThemesDirectory: URL? = nil,
    builtInThemesDirectory: URL? = nil,
    fileManager: FileManager = .default
  ) {
    let customDirectory =
      customThemesDirectory
      ?? ThemeStorage.customThemesDirectory(
        in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          .appendingPathComponent(AppConstants.appSupportDirectory, isDirectory: true))
    self.customThemesDirectory = customDirectory

    let bundledDirectory = builtInThemesDirectory ?? Self.defaultBundledThemesDirectory
    let bundled = Self.loadThemes(in: bundledDirectory, fileManager: fileManager)
    let custom = Self.loadCustomThemes(
      in: customDirectory, systemThemes: bundled, fileManager: fileManager)
    bundledThemes = bundled
    customThemes = custom
    builtInThemeCount = bundled.count
    customThemeCount = custom.count

    var merged: [String: ThemeDefinition] = [:]
    for theme in bundled { merged[theme.id] = theme }
    for theme in custom { merged[theme.id] = theme }
    themes = merged.values.sorted { $0.id < $1.id }
  }

  static func loadThemes(in directory: URL, fileManager: FileManager = .default)
    -> [ThemeDefinition]
  {
    loadThemeFiles(in: directory, fileManager: fileManager).map(\.theme)
  }

  private struct ThemeFile {
    let url: URL
    let theme: ThemeDefinition
    let data: Data
  }

  private static func loadThemeFiles(in directory: URL, fileManager: FileManager)
    -> [ThemeFile]
  {
    guard
      let urls = try? fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    else { return [] }

    return
      urls
      .filter {
        $0.pathExtension.caseInsensitiveCompare("json") == .orderedSame
          && !$0.lastPathComponent.hasPrefix("_")
      }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .compactMap { url in
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let theme = try? JSONDecoder().decode(ThemeDefinition.self, from: data) else {
          return nil
        }
        return ThemeFile(url: url, theme: theme, data: data)
      }
  }

  private static func loadCustomThemes(
    in directory: URL,
    systemThemes: [ThemeDefinition],
    fileManager: FileManager
  )
    -> [ThemeDefinition]
  {
    ThemeStorage.ensureCustomThemesDirectory(
      at: directory, systemThemes: systemThemes, fileManager: fileManager)
    return loadThemeFiles(in: directory, fileManager: fileManager).map { file in
      guard
        file.url.deletingPathExtension().lastPathComponent
          .hasPrefix("Custom \(file.theme.id.capitalized) (Modified)-")
      else {
        return file.theme
      }

      let digest = String(ThemeStorage.sha256Hex(file.data).prefix(12))
      return file.theme.replacingID(
        "custom-\(file.theme.id)-modified-\(digest)",
        name: "Custom \(file.theme.name) (Modified)"
      )
    }
  }

  private static var defaultBundledThemesDirectory: URL {
    if let bundled = Bundle.main.url(forResource: "Themes", withExtension: nil) {
      return bundled
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("Themes", isDirectory: true)
  }
}
