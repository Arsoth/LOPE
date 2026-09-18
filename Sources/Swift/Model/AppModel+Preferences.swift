// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation

enum AppModelPreferenceKeys {
  static let lightThemeID = "\(AppConstants.defaultsPrefix).lightThemeID"
  static let darkThemeID = "\(AppConstants.defaultsPrefix).darkThemeID"
  static let keyboardKeyGroups = "\(AppConstants.defaultsPrefix).keyboardKeyGroups"
  static let automaticUpdateChecks = "\(AppConstants.defaultsPrefix).automaticUpdateChecks"
}

@MainActor
extension AppModel {
  var lightThemes: [ThemeDefinition] {
    themes.filter { $0.appearance == .light }
  }

  var darkThemes: [ThemeDefinition] {
    themes.filter { $0.appearance == .dark }
  }

  var activeThemeAppearance: ThemeAppearance {
    switch appearancePreference {
    case .light:
      return .light
    case .dark:
      return .dark
    case .system:
      let appearance = NSApp.effectiveAppearance
      return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
  }

  var activeTheme: ThemeDefinition? {
    let appearance = activeThemeAppearance
    let selectedID = appearance == .light ? selectedLightThemeID : selectedDarkThemeID
    let themesForAppearance = themes.filter { $0.appearance == appearance }

    return themesForAppearance.first(where: { $0.id == selectedID }) ?? themesForAppearance.first
  }

  func loadThemePreferences() {
    selectedLightThemeID = validThemeID(
      UserDefaults.standard.string(forKey: AppModelPreferenceKeys.lightThemeID),
      appearance: .light,
      fallback: "light"
    )
    selectedDarkThemeID = validThemeID(
      UserDefaults.standard.string(forKey: AppModelPreferenceKeys.darkThemeID),
      appearance: .dark,
      fallback: "dark"
    )
  }

  func setLightThemeID(_ id: String) {
    reloadThemes()
    guard themes.contains(where: { $0.id == id && $0.appearance == .light }) else { return }
    selectedLightThemeID = id
    UserDefaults.standard.set(id, forKey: AppModelPreferenceKeys.lightThemeID)
  }

  func setDarkThemeID(_ id: String) {
    reloadThemes()
    guard themes.contains(where: { $0.id == id && $0.appearance == .dark }) else { return }
    selectedDarkThemeID = id
    UserDefaults.standard.set(id, forKey: AppModelPreferenceKeys.darkThemeID)
  }

  private func validThemeID(
    _ id: String?, appearance: ThemeAppearance, fallback: String
  ) -> String {
    guard let id, themes.contains(where: { $0.id == id && $0.appearance == appearance }) else {
      return fallback
    }
    return id
  }

  func loadKeyboardKeyPreferences() {
    guard
      let stored = UserDefaults.standard.array(forKey: AppModelPreferenceKeys.keyboardKeyGroups)
        as? [String]
    else {
      enabledKeyboardKeyGroups = [.standard]
      return
    }
    enabledKeyboardKeyGroups = Set(stored.compactMap(KeyboardKeyGroup.init(rawValue:)))
  }

  func isKeyboardKeyGroupEnabled(_ group: KeyboardKeyGroup) -> Bool {
    enabledKeyboardKeyGroups.contains(group)
  }

  func setKeyboardKeyGroup(_ group: KeyboardKeyGroup, enabled: Bool) {
    if enabled {
      enabledKeyboardKeyGroups.insert(group)
    } else {
      enabledKeyboardKeyGroups.remove(group)
    }

    let stored = KeyboardKeyGroup.allCases
      .filter { enabledKeyboardKeyGroups.contains($0) }
      .map(\.rawValue)
    UserDefaults.standard.set(stored, forKey: AppModelPreferenceKeys.keyboardKeyGroups)
  }

  func loadUpdatePreferences() {
    if let stored = UserDefaults.standard.object(
      forKey: AppModelPreferenceKeys.automaticUpdateChecks) as? Bool
    {
      automaticUpdateChecksEnabled = stored
    } else {
      automaticUpdateChecksEnabled = true
    }
  }

  func setAutomaticUpdateChecksEnabled(_ enabled: Bool) {
    automaticUpdateChecksEnabled = enabled
    UserDefaults.standard.set(enabled, forKey: AppModelPreferenceKeys.automaticUpdateChecks)
    if !enabled {
      cancelUpdateCheck()
    }
  }

  var filteredExtendedKeyboardKeyGroups: [KeyboardKeyGroupChoice] {
    filteredExtendedKeyboardKeyGroups(including: nil)
  }

  func filteredExtendedKeyboardKeyGroups(including selectedKey: UInt8?)
    -> [KeyboardKeyGroupChoice]
  {
    extendedKeyboardKeyGroups.compactMap { group in
      let keys = group.keys.filter {
        enabledKeyboardKeyGroups.contains(group.group) || $0.id == selectedKey
      }
      guard !keys.isEmpty else { return nil }
      return KeyboardKeyGroupChoice(group: group.group, keys: keys)
    }
  }

  var filteredExtendedKeyboardKeyLayoutGroups: [KeyboardKeyLayoutGroupChoice] {
    filteredExtendedKeyboardKeyLayoutGroups(including: nil)
  }

  func filteredExtendedKeyboardKeyLayoutGroups(including selectedKey: UInt8?)
    -> [KeyboardKeyLayoutGroupChoice]
  {
    extendedKeyboardKeyLayoutGroups.compactMap { group in
      let keys = group.keys.filter {
        enabledKeyboardKeyGroups.contains(keyboardKeyGroup(for: $0)) || $0.id == selectedKey
      }
      guard !keys.isEmpty else { return nil }
      return KeyboardKeyLayoutGroupChoice(group: group.group, keys: keys)
    }
  }
}
