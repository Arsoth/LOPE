// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

struct OnboardProfileRefreshGuidance: Codable, Hashable, Sendable {
  let sleepDescription: String
  let wakeInstructions: String
}

enum OnboardProfileRefreshPolicy {
  static let pollIntervalNanoseconds: UInt64 = 1_000_000_000
  static let maximumPollAttempts = 60
}
