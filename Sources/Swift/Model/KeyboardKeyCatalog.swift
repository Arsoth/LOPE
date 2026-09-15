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

enum KeyboardKeyLayoutGroup: String, CaseIterable, Hashable, Sendable {
  case mainTyping = "Main typing block"
  case navigation = "Navigation and arrow cluster"
  case numpad = "Numpad"
}

struct KeyboardKeyLayoutGroupChoice: Identifiable, Hashable {
  let group: KeyboardKeyLayoutGroup
  let keys: [KeyboardKeyChoice]

  var id: KeyboardKeyLayoutGroup { group }
  var label: String { group.rawValue }
}
