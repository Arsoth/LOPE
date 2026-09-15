// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

struct ProfileChoice: Identifiable, Hashable {
  let id: Int
  var sector: String
  var enabled: Bool
  // Header-only discovery intentionally does not read the full profile
  // sector, so CRC status can be unknown until that profile is loaded.
  var crcValid: Bool?

  var title: String {
    "Profile \(id)\(enabled ? "" : " (disabled)")"
  }
}

enum ButtonLayer: String, CaseIterable, Hashable, Sendable {
  case normal
  case gShift

  var label: String {
    switch self {
    case .normal: return "Normal"
    case .gShift: return "G-Shift"
    }
  }
}

struct ButtonRow: Identifiable {
  let id: Int
  let label: String
  let currentRaw: String
  var draftRaw: String
  var draftChoice: String
  let layer: ButtonLayer

  init(
    id: Int,
    label: String,
    currentRaw: String,
    draftRaw: String,
    draftChoice: String,
    layer: ButtonLayer
  ) {
    self.id = id
    self.label = label
    self.currentRaw = currentRaw
    self.draftRaw = draftRaw
    self.draftChoice = draftChoice
    self.layer = layer
  }

  var displayLabel: String {
    let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedLabel.isEmpty ? "Button \(id)" : trimmedLabel
  }
}

struct OutputPreset: Identifiable, Hashable {
  let id: String
  let label: String
  let raw: String
}

struct ModifierChoice: Identifiable, Hashable {
  let id: UInt8
  let label: String
}

struct KeyboardKeyChoice: Identifiable, Hashable {
  let id: UInt8
  let label: String
}

struct BackupEntry: Identifiable {
  enum DeviceMatch: Equatable {
    case selected
    case other
    case unknown

    var label: String {
      switch self {
      case .selected: return "Selected mouse"
      case .other: return "Different mouse"
      case .unknown: return "Unknown device"
      }
    }
  }

  let url: URL
  let modifiedAt: Date
  let size: Int64
  let deviceMatch: DeviceMatch
  let deviceName: String?

  var id: String { url.path }
  var name: String { url.lastPathComponent }
  var isJSON: Bool { url.pathExtension.lowercased() == "json" }
  var fileTypeLabel: String { isJSON ? "Editable JSON" : "Exact binary" }

  var deviceStatusLabel: String {
    switch deviceMatch {
    case .selected:
      return deviceName.map { "Selected mouse: \($0)" } ?? deviceMatch.label
    case .other:
      return deviceName.map { "Different mouse: \($0)" } ?? deviceMatch.label
    case .unknown:
      return "Unknown device — review before using"
    }
  }
}

struct DeviceChoice: Identifiable, Hashable, Codable, Sendable {
  let id: Int
  let name: String
  let connection: String
  let productID: String
  let deviceKey: String

  var title: String {
    "\(name) — \(connection)"
  }

  var isWiredDevice: Bool {
    connection.caseInsensitiveCompare("Wired") == .orderedSame
  }

  var isNonWiredDevice: Bool {
    !isWiredDevice
  }

  var isGenericPairedName: Bool {
    Self.isGenericPairedName(name)
  }

  static func isGenericPairedName(_ name: String) -> Bool {
    let components = name.lowercased()
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    guard components.count >= 3,
      components.prefix(3).map(String.init) == ["paired", "logitech", "mouse"]
    else { return false }
    return components.dropFirst(3).allSatisfy { $0 == "lightspeed" }
  }

  func replacingName(_ name: String) -> DeviceChoice {
    DeviceChoice(
      id: id,
      name: name,
      connection: connection,
      productID: productID,
      deviceKey: deviceKey
    )
  }

  static func preferredName(reported: String, fallback: String) -> String {
    let normalizedReported = normalizedReportedName(reported)
    guard !normalizedReported.isEmpty, !isGenericPairedName(normalizedReported) else {
      return normalizedReportedName(fallback)
    }
    return normalizedReported
  }

  static func normalizedReportedName(_ name: String) -> String {
    var normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let genericSuffixes = [" Wireless Gaming Mouse"]
    for suffix in genericSuffixes {
      guard normalized.count > suffix.count,
        normalized.lowercased().hasSuffix(suffix.lowercased())
      else { continue }
      normalized.removeLast(suffix.count)
      normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
      break
    }
    return normalized
  }

  func matchesReconnectIdentity(_ other: DeviceChoice) -> Bool {
    if deviceKey == other.deviceKey { return true }
    guard !productID.isEmpty, productID.caseInsensitiveCompare(other.productID) == .orderedSame
    else { return false }
    if name == other.name { return true }
    return isGenericPairedName || other.isGenericPairedName
  }

}

struct EditableBackup: Codable {
  struct Device: Codable {
    var name: String
    var productID: String
  }

  struct ProfileState: Codable {
    var number: Int
    var enabled: Bool
  }

  struct Button: Codable {
    var number: Int
    var physicalControl: String
    var output: String
    var raw: String
    var layer: String

    init(
      number: Int,
      physicalControl: String,
      output: String,
      raw: String,
      layer: String
    ) {
      self.number = number
      self.physicalControl = physicalControl
      self.output = output
      self.raw = raw
      self.layer = layer
    }

    private enum CodingKeys: String, CodingKey {
      case number, physicalControl, output, raw, layer
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      number = try values.decode(Int.self, forKey: .number)
      physicalControl = try values.decode(String.self, forKey: .physicalControl)
      output = try values.decode(String.self, forKey: .output)
      raw = try values.decode(String.self, forKey: .raw)
      layer = try values.decode(String.self, forKey: .layer)
    }
  }

  struct DPI: Codable {
    var stages: [Int]
    var defaultStage: Int
    var shiftStage: Int
  }

  struct Profile: Codable {
    struct RGB: Codable {
      var zone: Int
      var name: String
      var color: String
    }

    var number: Int
    var sector: String?
    var enabled: Bool
    var buttons: [Button]
    var dpi: DPI?
    var rgb: [RGB]?
  }

  var formatVersion: Int
  var createdAt: String
  var device: Device
  var profiles: [ProfileState]
  var profile: Profile
  var exactBinaryBackup: String?
}
