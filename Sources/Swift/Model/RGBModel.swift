// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

/// A lossless 8-bit RGB value used at the profile-file boundary. Keeping the
/// representation independent of SwiftUI makes JSON import/export and the
/// parser testable without constructing a view.
struct RGBColor: Codable, Hashable, Sendable {
  let red: UInt8
  let green: UInt8
  let blue: UInt8

  init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  init?(hex: String) {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if value.hasPrefix("0X") {
      value.removeFirst(2)
    } else if value.hasPrefix("#") {
      value.removeFirst()
    }
    guard value.count == 6,
      let number = UInt32(value, radix: 16)
    else { return nil }
    self.init(
      red: UInt8((number >> 16) & 0xFF),
      green: UInt8((number >> 8) & 0xFF),
      blue: UInt8(number & 0xFF)
    )
  }

  var hex: String {
    String(format: "0x%02X%02X%02X", red, green, blue)
  }

  var bareHex: String {
    String(format: "%02X%02X%02X", red, green, blue)
  }
}

/// The effect-ID byte at offset 0 of each legacy onboard RGB record. Only the
/// values `profile_codec_rgb_mode_is_known` (Sources/C/Profiles/profile_codec.c)
/// already accepts and names are exposed here; the device also tolerates a
/// handful of unnamed IDs, but those aren't offered as user-facing choices.
enum RGBEffectMode: UInt8, CaseIterable, Codable, Hashable, Sendable {
  case disabled = 0x00
  case solid = 0x01
  case pulse = 0x02
  case cycle = 0x03
  case wave = 0x04
  case breathe = 0x0A
  case ripple = 0x0B

  /// The device also accepts a few unnamed effect IDs (see
  /// `profile_codec_rgb_mode_is_known`) that this closed enum has no case
  /// for. Falling back to `.disabled` keeps the zone displayable rather than
  /// dropping it from the editor entirely.
  static func from(byte: UInt8) -> RGBEffectMode {
    RGBEffectMode(rawValue: byte) ?? .disabled
  }

  init?(named name: String) {
    switch name.lowercased() {
    case "disabled": self = .disabled
    case "static", "solid": self = .solid
    case "pulse": self = .pulse
    case "cycle": self = .cycle
    case "wave": self = .wave
    case "breathe": self = .breathe
    case "ripple": self = .ripple
    default: return nil
    }
  }

  var label: String {
    switch self {
    case .disabled: return L10n.text("Disabled")
    case .solid: return L10n.text("Solid")
    case .pulse: return L10n.text("Pulse")
    case .cycle: return L10n.text("Cycle")
    case .wave: return L10n.text("Wave")
    case .breathe: return L10n.text("Breathe")
    case .ripple: return L10n.text("Ripple")
    }
  }

  var bareHex: String {
    String(format: "%02X", rawValue)
  }
}

struct RGBZoneState: Identifiable, Hashable, Sendable {
  let id: Int
  let name: String
  var current: RGBColor
  var draft: RGBColor
  var currentMode: RGBEffectMode
  var draftMode: RGBEffectMode

  init(
    id: Int,
    name: String,
    current: RGBColor,
    draft: RGBColor,
    currentMode: RGBEffectMode = .solid,
    draftMode: RGBEffectMode = .solid
  ) {
    self.id = id
    self.name = name
    self.current = current
    self.draft = draft
    self.currentMode = currentMode
    self.draftMode = draftMode
  }
}

struct ParsedRGBZone: Hashable, Sendable {
  let index: Int
  let color: RGBColor
  let mode: RGBEffectMode

  init(index: Int, color: RGBColor, mode: RGBEffectMode = .solid) {
    self.index = index
    self.color = color
    self.mode = mode
  }
}

enum RGBEditorLogic {
  static func settingColor(
    in zones: [RGBZoneState],
    zoneID: Int,
    color: RGBColor,
    allZones: Bool
  ) -> [RGBZoneState] {
    guard zones.contains(where: { $0.id == zoneID }) else { return zones }
    return zones.map { zone in
      guard allZones || zone.id == zoneID else { return zone }
      var updated = zone
      updated.draft = color
      return updated
    }
  }

  static func settingMode(
    in zones: [RGBZoneState],
    zoneID: Int,
    mode: RGBEffectMode,
    allZones: Bool
  ) -> [RGBZoneState] {
    guard zones.contains(where: { $0.id == zoneID }) else { return zones }
    return zones.map { zone in
      guard allZones || zone.id == zoneID else { return zone }
      var updated = zone
      updated.draftMode = mode
      return updated
    }
  }
}
