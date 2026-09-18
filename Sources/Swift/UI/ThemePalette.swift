// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct ThemePalette {
  let header: Color
  let footer: Color
  let recentEventsHeader: Color
  let buttonActive: Color
  let buttonInactive: Color
  let checkboxActive: Color
  let checkboxInactive: Color
  let mainBackground: Color
  let primaryText: Color
  let secondaryText: Color
  let tertiaryText: Color
  let card: Color
  let cardBorder: Color
  let controlBackground: Color
  let controlBorder: Color
  let dpiBar: Color
  let dpiBackground: Color
  let accent: Color
  let success: Color
  let warning: Color
  let error: Color
  let separator: Color
  let shadow: Color
  let hover: Color
  let selected: Color
  let disabled: Color
  let defaultStage: Color
  let defaultStageOutline: Color
  let defaultStageText: Color
  let shiftStage: Color
  let shiftStageOutline: Color
  let shiftStageText: Color
  let otherStage: Color
  let otherStageOutline: Color
  let otherStageText: Color
  let defaultStageShape: ThemeDragHandleShape
  let shiftStageShape: ThemeDragHandleShape
  let otherStageShape: ThemeDragHandleShape

  init(theme: ThemeDefinition?, isDarkAppearance: Bool) {
    self.init(
      colors: theme?.colors ?? Self.fallbackColors(isDarkAppearance: isDarkAppearance),
      dragHandles: theme?.dragHandles
        ?? Self.fallbackDragHandles(isDarkAppearance: isDarkAppearance)
    )
  }

  private static func fallbackColors(isDarkAppearance: Bool) -> ThemeColors {
    let background = isDarkAppearance ? "#1E1E1E" : "#F5F6F7"
    let surface = isDarkAppearance ? "#2C2C2E" : "#FFFFFF"
    let secondary = isDarkAppearance ? "#FFFFFF80" : "#59636E"
    let border = isDarkAppearance ? "#FFFFFF26" : "#D5D9DE"
    return ThemeColors(
      header: isDarkAppearance ? background : surface,
      footer: isDarkAppearance ? background : surface,
      recentEventsHeader: isDarkAppearance ? background : surface,
      buttonActive: isDarkAppearance ? "#0A84FF" : "#2F6FEB",
      buttonInactive: isDarkAppearance ? "#FFFFFF" : border,
      checkboxActive: isDarkAppearance ? "#0A84FF" : "#2F6FEB",
      checkboxInactive: secondary,
      mainBackground: background,
      primaryText: isDarkAppearance ? "#FFFFFF" : "#1F2328",
      secondaryText: secondary,
      tertiaryText: isDarkAppearance ? "#FFFFFF66" : "#7D8792",
      card: isDarkAppearance ? "#FFFFFF0B" : surface,
      cardBorder: border,
      controlBackground: surface,
      controlBorder: isDarkAppearance ? "#FFFFFF26" : "#B8C0CA",
      dpiBar: isDarkAppearance ? "#6B7380" : "#6B7280",
      dpiBackground: isDarkAppearance ? "#FFFFFF14" : "#E7EAF0",
      accent: isDarkAppearance ? "#0A84FF" : "#2F6FEB",
      success: isDarkAppearance ? "#30D158" : "#218739",
      warning: isDarkAppearance ? "#FF9F0A" : "#B86E00",
      error: isDarkAppearance ? "#FF453A" : "#C62828",
      separator: border,
      shadow: isDarkAppearance ? "#0000003D" : "#00000026",
      hover: isDarkAppearance ? "#FFFFFF0D" : "#0000000D",
      selected: isDarkAppearance ? "#0A84FF33" : "#2F6FEB24",
      disabled: secondary
    )
  }

  private static func fallbackDragHandles(isDarkAppearance: Bool) -> ThemeDragHandles {
    if isDarkAppearance {
      return ThemeDragHandles(
        defaultStage: ThemeDragHandle(
          color: "#E83D40", outline: "#E83D40", textColor: "#000000", shape: .circle),
        shiftStage: ThemeDragHandle(
          color: "#3385F0", outline: "#3385F0", textColor: "#000000", shape: .pentagon),
        otherStage: ThemeDragHandle(
          color: "#F2B326", outline: "#F2B326", textColor: "#000000", shape: .roundedRectangle)
      )
    }
    return ThemeDragHandles(
      defaultStage: ThemeDragHandle(
        color: "#E83D40", outline: "#E83D40", textColor: "#000000", shape: .circle),
      shiftStage: ThemeDragHandle(
        color: "#3385F0", outline: "#3385F0", textColor: "#000000", shape: .pentagon),
      otherStage: ThemeDragHandle(
        color: "#F2B326", outline: "#F2B326", textColor: "#000000", shape: .roundedRectangle)
    )
  }

  private init(colors: ThemeColors, dragHandles: ThemeDragHandles) {
    header = Self.color(from: colors.header)
    footer = Self.color(from: colors.footer)
    // Keep the two footer surfaces in lockstep even when a custom JSON file
    // has older, distinct values for the two fields.
    recentEventsHeader = footer
    buttonActive = Self.color(from: colors.buttonActive)
    buttonInactive = Self.color(from: colors.buttonInactive)
    checkboxActive = Self.color(from: colors.checkboxActive)
    checkboxInactive = Self.color(from: colors.checkboxInactive)
    mainBackground = Self.color(from: colors.mainBackground)
    primaryText = Self.color(from: colors.primaryText)
    secondaryText = Self.color(from: colors.secondaryText)
    tertiaryText = Self.color(from: colors.tertiaryText)
    card = Self.color(from: colors.card)
    cardBorder = Self.color(from: colors.cardBorder)
    controlBackground = Self.color(from: colors.controlBackground)
    controlBorder = Self.color(from: colors.controlBorder)
    dpiBar = Self.color(from: colors.dpiBar)
    dpiBackground = Self.color(from: colors.dpiBackground)
    accent = Self.color(from: colors.accent)
    success = Self.color(from: colors.success)
    warning = Self.color(from: colors.warning)
    error = Self.color(from: colors.error)
    separator = Self.color(from: colors.separator)
    shadow = Self.color(from: colors.shadow)
    hover = Self.color(from: colors.hover)
    selected = Self.color(from: colors.selected)
    disabled = Self.color(from: colors.disabled)
    defaultStage = Self.color(from: dragHandles.defaultStage.color)
    defaultStageOutline = Self.color(from: dragHandles.defaultStage.outline)
    defaultStageText = Self.color(from: dragHandles.defaultStage.textColor)
    shiftStage = Self.color(from: dragHandles.shiftStage.color)
    shiftStageOutline = Self.color(from: dragHandles.shiftStage.outline)
    shiftStageText = Self.color(from: dragHandles.shiftStage.textColor)
    otherStage = Self.color(from: dragHandles.otherStage.color)
    otherStageOutline = Self.color(from: dragHandles.otherStage.outline)
    otherStageText = Self.color(from: dragHandles.otherStage.textColor)
    defaultStageShape = dragHandles.defaultStage.shape
    shiftStageShape = dragHandles.shiftStage.shape
    otherStageShape = dragHandles.otherStage.shape
  }

  private static func color(from hex: String) -> Color {
    let digits = String(hex.dropFirst())
    guard let value = UInt64(digits, radix: 16) else { return .clear }
    if digits.count == 8 {
      return Color(
        red: Double((value >> 24) & 0xFF) / 255,
        green: Double((value >> 16) & 0xFF) / 255,
        blue: Double((value >> 8) & 0xFF) / 255,
        opacity: Double(value & 0xFF) / 255
      )
    }
    return Color(
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255
    )
  }
}

private struct LOPEThemeEnvironmentKey: EnvironmentKey {
  static let defaultValue = ThemePalette(theme: nil, isDarkAppearance: false)
}

extension EnvironmentValues {
  var lopeTheme: ThemePalette {
    get { self[LOPEThemeEnvironmentKey.self] }
    set { self[LOPEThemeEnvironmentKey.self] = newValue }
  }
}
