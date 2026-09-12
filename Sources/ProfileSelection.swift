// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

enum ProfileSelection {
  static func resolvedProfileNumber(
    selectedProfileNumber: Int?,
    availableProfileIDs: [Int],
    preferredProfileNumber: Int
  ) -> Int? {
    guard !availableProfileIDs.isEmpty else { return nil }
    if let selectedProfileNumber,
      availableProfileIDs.contains(selectedProfileNumber)
    {
      return selectedProfileNumber
    }
    if availableProfileIDs.contains(preferredProfileNumber) {
      return preferredProfileNumber
    }
    return availableProfileIDs[0]
  }
}
