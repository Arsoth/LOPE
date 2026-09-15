// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

/// Pure resolution logic for `AppModel.restoreReferenceDefaults()`, split out
/// so the validation rules (DPI stage bounds, effect-name lookup, report-rate
/// support) are unit-testable without a live device, matching the
/// RGBEditorLogic/DPIEditorValidation split used elsewhere in this codebase.
enum ReferenceDefaultsLogic {
  static func buttonRawByNumber(
    _ reference: MouseProfileDescriptor.ReferenceProfile
  ) -> [Int: String] {
    Dictionary(uniqueKeysWithValues: reference.buttons.map { ($0.number, $0.raw) })
  }

  /// `nil` when onboard DPI editing isn't available for this profile path, or
  /// the recorded stage table/indexes are out of bounds.
  static func resolvedDPI(
    _ reference: MouseProfileDescriptor.ReferenceProfile,
    canEditOnboardDPI: Bool
  ) -> MouseProfileDescriptor.ReferenceProfile.DPI? {
    guard canEditOnboardDPI, let dpi = reference.dpi,
      (1...5).contains(dpi.stages.count),
      (1...dpi.stages.count).contains(dpi.defaultStage),
      (1...dpi.stages.count).contains(dpi.shiftStage)
    else { return nil }
    return dpi
  }

  /// `nil` when there's no recorded report rate, or the device's profile
  /// doesn't support saving that rate.
  static func resolvedReportRateHz(
    _ reference: MouseProfileDescriptor.ReferenceProfile,
    profileSupportedRates: [Int]
  ) -> Int? {
    guard let rate = reference.reportRateHz, profileSupportedRates.contains(rate) else {
      return nil
    }
    return rate
  }

  struct RGBZoneUpdate {
    let index: Int
    let mode: RGBEffectMode?
    let color: RGBColor?
  }

  static func rgbZoneUpdates(
    _ reference: MouseProfileDescriptor.ReferenceProfile
  ) -> [RGBZoneUpdate] {
    (reference.rgbZones ?? []).map { zone in
      RGBZoneUpdate(
        index: zone.index,
        mode: RGBEffectMode(named: zone.mode),
        color: zone.color.flatMap(RGBColor.init(hex:))
      )
    }
  }
}

@MainActor
extension AppModel {
  /// Loads the descriptor's `referenceProfile` values into the editor drafts.
  /// This only stages the change; the user still reviews and chooses Save to
  /// mouse, exactly like loading a JSON backup. Only offered when
  /// `canRestoreReferenceProfile` is true, i.e. the reference data came from
  /// an actual verified factory reset rather than a guess.
  func restoreReferenceDefaults() {
    guard !busy else { return }
    guard currentMouseProfile.canRestoreReferenceProfile,
      let reference = currentMouseProfile.referenceProfile
    else {
      status = "\(currentMouseProfile.name) has no verified reference profile yet."
      return
    }

    for (number, raw) in ReferenceDefaultsLogic.buttonRawByNumber(reference) {
      guard let index = buttons.firstIndex(where: { $0.id == number }) else { continue }
      setRaw(layer: .normal, buttonIndex: index, raw: raw)
    }

    if let dpi = ReferenceDefaultsLogic.resolvedDPI(reference, canEditOnboardDPI: canEditOnboardDPI)
    {
      dpiCount = dpi.stages.count
      dpiStages = dpi.stages.map(String.init) + Array(repeating: "", count: 5 - dpi.stages.count)
      defaultStage = dpi.defaultStage
      shiftStage = dpi.shiftStage
    }

    if let reportRateHz = ReferenceDefaultsLogic.resolvedReportRateHz(
      reference, profileSupportedRates: pollingRateCapabilities.profileSupportedRates)
    {
      pollingRateDraft = reportRateHz
    }

    for update in ReferenceDefaultsLogic.rgbZoneUpdates(reference) {
      if let mode = update.mode {
        setRGBMode(zoneID: update.index, mode: mode)
      }
      if let color = update.color {
        setRGBColor(zoneID: update.index, color: color)
      }
    }

    status =
      "Loaded \(currentMouseProfile.name)'s verified reference profile into the editor. Review it, then choose Save to mouse."
  }
}
