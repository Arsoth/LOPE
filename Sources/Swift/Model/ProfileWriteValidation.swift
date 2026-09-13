// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

enum ProfileWriteValidation {
  /// HID++ mouse-button output record for the primary (left) click.
  static let primaryClickRaw = "80010001"

  static func isPrimaryClick(raw: String) -> Bool {
    raw.filter { !$0.isWhitespace }.uppercased() == primaryClickRaw
  }

  static let gShiftBindingRaw = "900B0000"

  static func isGShiftBinding(raw: String) -> Bool {
    raw.filter { !$0.isWhitespace }.uppercased() == gShiftBindingRaw
  }

  static func inaccessibleGShiftPrimaryClickMessage(
    profileNumber: Int,
    profileName: String,
    normalButtonRaws: [String],
    gShiftButtonRaws: [String]
  ) -> String? {
    guard gShiftButtonRaws.contains(where: isPrimaryClick),
      !normalButtonRaws.contains(where: isGShiftBinding)
    else { return nil }

    let trimmedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
    let profileLabel =
      trimmedName.isEmpty
      ? "Profile " + String(profileNumber)
      : "Profile " + String(profileNumber) + " on " + trimmedName
    return profileLabel
      + " has primary click assigned only on the G-Shift layer, but no Normal-layer button activates G-Shift. Assign G-Shift to a Normal button or add a primary click to the Normal layer, then save again."
  }

  static func missingPrimaryClickMessage(
    profileNumber: Int,
    profileName: String,
    buttonRaws: [String]
  ) -> String? {
    guard !buttonRaws.contains(where: isPrimaryClick) else { return nil }

    let trimmedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
    let profileLabel =
      trimmedName.isEmpty
      ? "Profile " + String(profileNumber)
      : "Profile " + String(profileNumber) + " on " + trimmedName
    return profileLabel
      + " has no primary click assigned. Choose “Left click” for one of its buttons, then save again."
  }
}
