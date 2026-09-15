// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

/// A data-driven description of a Logitech G mouse's physical controls and
/// onboard-profile transport. The JSON files are deliberately more verbose
/// than the Swift model: fields in `profileIO` are intended to be useful when
/// adding a device whose firmware does not follow the common path.
struct MouseProfileDescriptor: Codable, Hashable, Sendable {
  struct DPIRange: Codable, Hashable, Sendable {
    var minimum: Int
    var maximum: Int

    var capabilities: DPICapabilities {
      DPICapabilities(minimum: minimum, maximum: maximum)
    }
  }

  struct Match: Codable, Hashable, Sendable {
    var nameContains: [String]
    var productIDs: [String]
  }

  struct Button: Codable, Hashable, Sendable {
    var number: Int
    var control: String
    var aliases: [String]
    var notes: String?

    var label: String {
      aliases.isEmpty ? control : "\(control) (\(aliases.joined(separator: ", ")))"
    }
  }

  struct ProfileIO: Codable, Hashable, Sendable {
    var supported: Bool
    var capability: String
    var feature: String
    var load: [String: String]
    var save: [String: String]
    var layout: [String: String]
    var notes: [String]

    var canSave: Bool { supported && save["strategy"] != "read-only" }

    init(
      supported: Bool,
      capability: String,
      feature: String,
      load: [String: String],
      save: [String: String],
      layout: [String: String],
      notes: [String]
    ) {
      self.supported = supported
      self.capability = capability
      self.feature = feature
      self.load = load
      self.save = save
      self.layout = layout
      self.notes = notes
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      supported = try values.decodeIfPresent(Bool.self, forKey: .supported) ?? true
      capability = try values.decodeIfPresent(String.self, forKey: .capability) ?? "unknown"
      feature = try values.decodeIfPresent(String.self, forKey: .feature) ?? ""
      load = try values.decodeIfPresent([String: String].self, forKey: .load) ?? [:]
      save = try values.decodeIfPresent([String: String].self, forKey: .save) ?? [:]
      layout = try values.decodeIfPresent([String: String].self, forKey: .layout) ?? [:]
      notes = try values.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
  }

  /// The small, fixed RGB records used by the validated format-4/5 profile
  /// layout. `index` is the zero-based record index in the profile sector;
  /// the user-facing name is supplied by the device descriptor.
  struct RGBProfile: Codable, Hashable, Sendable {
    struct Zone: Codable, Hashable, Sendable {
      var index: Int
      var name: String
    }

    var supported: Bool
    var profileFormats: [Int]
    var baseOffset: Int
    var recordBytes: Int
    var colorOffset: Int
    var zones: [Zone]
    var deviceNameContains: [String]?
    var productIDs: [String]?
    var notes: [String]

    func matches(deviceName: String, productID: String) -> Bool {
      let name = deviceName.lowercased()
      let product = productID.lowercased()
      let nameHit = deviceNameContains?.contains { name.contains($0.lowercased()) } ?? false
      let productHit = productIDs?.contains { product == $0.lowercased() } ?? false
      let hasRestriction = !(deviceNameContains ?? []).isEmpty || !(productIDs ?? []).isEmpty
      return !hasRestriction || nameHit || productHit
    }

    func supports(profileFormat: Int?) -> Bool {
      guard supported else { return false }
      guard let profileFormat else { return true }
      return profileFormats.contains(profileFormat)
    }

    var canEdit: Bool {
      supported && !zones.isEmpty && baseOffset >= 0 && recordBytes >= 4
        && (0..<recordBytes).contains(colorOffset) && colorOffset + 3 <= recordBytes
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      supported = try values.decodeIfPresent(Bool.self, forKey: .supported) ?? false
      profileFormats = try values.decodeIfPresent([Int].self, forKey: .profileFormats) ?? []
      baseOffset = try values.decodeIfPresent(Int.self, forKey: .baseOffset) ?? 208
      recordBytes = try values.decodeIfPresent(Int.self, forKey: .recordBytes) ?? 11
      colorOffset = try values.decodeIfPresent(Int.self, forKey: .colorOffset) ?? 1
      zones = try values.decodeIfPresent([Zone].self, forKey: .zones) ?? []
      deviceNameContains = try values.decodeIfPresent([String].self, forKey: .deviceNameContains)
      productIDs = try values.decodeIfPresent([String].self, forKey: .productIDs)
      notes = try values.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
  }

  /// A known-good set of button/DPI/report-rate/RGB values for this device,
  /// sourced from somewhere more concrete than a guess. `source` records
  /// exactly how confident that provenance is: only `verifiedFactoryReset`
  /// comes from actually triggering the manufacturer's own onboard-memory
  /// reset and reading the result back from the device, so only that case is
  /// offered as a one-click "restore" write in the app. The others exist so
  /// the reference data can still be recorded (and improved later) without
  /// being presented as something to write to hardware it was never
  /// confirmed against.
  struct ReferenceProfile: Codable, Hashable, Sendable {
    enum Source: String, Codable, Hashable, Sendable {
      case verifiedFactoryReset
      case userConfiguration
      case manufacturerSpec
      case communityReverseEngineering
      case unknown
    }

    struct Button: Codable, Hashable, Sendable {
      var number: Int
      var raw: String
    }

    struct DPI: Codable, Hashable, Sendable {
      var stages: [Int]
      var defaultStage: Int
      var shiftStage: Int
    }

    struct RGBZone: Codable, Hashable, Sendable {
      var index: Int
      var mode: String
      var color: String?
    }

    var source: Source
    var buttons: [Button]
    var dpi: DPI?
    var reportRateHz: Int?
    var rgbZones: [RGBZone]?
    var notes: [String]

    init(
      source: Source,
      buttons: [Button],
      dpi: DPI?,
      reportRateHz: Int?,
      rgbZones: [RGBZone]?,
      notes: [String]
    ) {
      self.source = source
      self.buttons = buttons
      self.dpi = dpi
      self.reportRateHz = reportRateHz
      self.rgbZones = rgbZones
      self.notes = notes
    }

    init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      source = try values.decodeIfPresent(Source.self, forKey: .source) ?? .unknown
      buttons = try values.decodeIfPresent([Button].self, forKey: .buttons) ?? []
      dpi = try values.decodeIfPresent(DPI.self, forKey: .dpi)
      reportRateHz = try values.decodeIfPresent(Int.self, forKey: .reportRateHz)
      rgbZones = try values.decodeIfPresent([RGBZone].self, forKey: .rgbZones)
      notes = try values.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
  }

  var schemaVersion: Int
  var id: String
  var name: String
  var match: Match
  var buttons: [Button]
  var scrollWheelButtonLabels: [String: String]?
  var hiddenProfileButtonNumbers: [Int]?
  var dpiRange: DPIRange?
  var refreshGuidance: OnboardProfileRefreshGuidance?
  var profileIO: ProfileIO
  var rgbProfile: RGBProfile?
  var referenceProfile: ReferenceProfile?
  var sources: [String]
  var generated: Bool?

  /// Only a verified factory reset is trustworthy enough to offer as a
  /// one-click device write; other sources are recorded but not writable.
  var canRestoreReferenceProfile: Bool {
    referenceProfile?.source == .verifiedFactoryReset && profileIO.canSave
  }

  var isGenerated: Bool { generated ?? false }

  var initialDPICapabilities: DPICapabilities {
    dpiRange?.capabilities ?? DPICapabilities()
  }

  func button(for number: Int) -> Button? {
    buttons.first { $0.number == number }
  }

  func scrollWheelButtonLabel(for number: Int) -> String? {
    scrollWheelButtonLabels?[String(number)]
  }

  func rgbCapabilities(deviceName: String, productID: String, profileFormat: Int? = nil)
    -> RGBProfile?
  {
    guard let rgbProfile,
      rgbProfile.canEdit,
      rgbProfile.matches(deviceName: deviceName, productID: productID),
      rgbProfile.supports(profileFormat: profileFormat)
    else { return nil }
    return rgbProfile
  }
}
