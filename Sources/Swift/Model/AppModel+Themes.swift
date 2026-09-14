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

  var themes: [ThemeDefinition] {
    ThemeCatalog.shared.themes
  }

  func reloadThemes() {
    ThemeCatalog.reload(customThemesDirectory: customThemesDirectory)
  }
}
