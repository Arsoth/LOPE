// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation

// Finder integration is kept in a shim because NSWorkspace opens a real,
// unmockable Finder window and is excluded from the Swift coverage gate.

@MainActor
extension AppModel {
  func openCustomThemesDirectoryInFinder() {
    reloadThemes()
    loadThemePreferences()
    guard NSWorkspace.shared.open(customThemesDirectory) else {
      status = "Could not open the custom themes directory in Finder."
      return
    }
    status = "Opened the custom themes directory in Finder."
  }
}
