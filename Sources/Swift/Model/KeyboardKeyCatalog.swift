// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

enum KeyboardKeyGroup: String, CaseIterable, Hashable, Sendable {
  case standard = "Standard full-size keyboard keys"
  case function = "F13 and later keys"
  case media = "Media keys"
  case other = "Other unusual keys"
}

struct KeyboardKeyGroupChoice: Identifiable, Hashable {
  let group: KeyboardKeyGroup
  let keys: [KeyboardKeyChoice]

  var id: KeyboardKeyGroup { group }
  var label: String { group.rawValue }
}
