// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  var customThemesDirectory: URL {
    ThemeStorage.customThemesDirectory(in: configurationDirectory)
  }

  var customThemesDirectoryPath: String {
    customThemesDirectory.path
  }

  func reloadThemes() {
    ThemeCatalog.reload(customThemesDirectory: customThemesDirectory)
    themes = ThemeCatalog.shared.themes
  }

  /// Re-reads the bundled and custom theme JSON files and republishes the
  /// catalog so the settings UI can refresh without rebuilding the app.
  func refreshThemes() {
    reloadThemes()
    loadThemePreferences()
    status = "Themes refreshed from \(customThemesDirectory.path)."
  }
}
