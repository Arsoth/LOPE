// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

extension AppModel {
  func loadingButtonRows() -> [ButtonRow] {
    currentMouseProfile.buttons.map { button in
      let raw = stockRawAssignment(for: button)
      let choice = presets.contains { normalize($0.raw) == raw } ? raw : "keystroke"
      return ButtonRow(
        id: button.number,
        label: button.label,
        currentRaw: raw,
        draftRaw: raw,
        draftChoice: choice,
        layer: .normal
      )
    }
  }

  private func stockRawAssignment(for button: MouseProfileDescriptor.Button) -> String {
    let description = ([button.control] + button.aliases).joined(separator: " ").lowercased()
    if description.contains("g-shift") { return "900B0000" }
    if description.contains("dpi shift") || description.contains("sniper") { return "90070000" }
    if description.contains("dpi up") { return "90030000" }
    if description.contains("dpi down") { return "90040000" }
    if description.contains("dpi button") { return "90050000" }
    if description.contains("profile") || description.contains("mode switch") { return "900A0000" }
    if description.contains("scroll down") { return "90100000" }
    if description.contains("scroll up") { return "90110000" }
    if description.contains("tilt left") || description.contains("scroll left") {
      return "90010000"
    }
    if description.contains("tilt right") || description.contains("scroll right") {
      return "90020000"
    }
    if description.contains("primary") { return "80010001" }
    if description.contains("secondary") { return "80010002" }
    if description.contains("middle") { return "80010004" }
    if description.contains("back") || description.contains("side rear") { return "80010008" }
    if description.contains("forward") || description.contains("side front") { return "80010010" }

    switch button.number {
    case 1: return "80010001"
    case 2: return "80010002"
    case 3: return "80010004"
    case 4: return "80010008"
    case 5: return "80010010"
    default: return "FFFFFFFF"
    }
  }

  var modifierChoices: [ModifierChoice] {
    [
      ModifierChoice(id: 0x01, label: "Ctrl"),
      ModifierChoice(id: 0x02, label: "Shift"),
      ModifierChoice(id: 0x04, label: "Alt"),
      ModifierChoice(id: 0x08, label: "Command"),
    ]
  }

  /// Every keyboard-page usage the editor can name. This is intentionally
  /// separate from `keyboardOutputKeys`: the recorder needs to understand
  /// keys that should not clutter the normal override picker.
  private static let keyboardKeyCatalog: [KeyboardKeyChoice] = {
    var choices = [
      // Main typing block: function row, then the typing rows from left to
      // right as they appear on a full-size keyboard.
      KeyboardKeyChoice(id: 0x29, label: "Escape")
    ]
    choices += (0x3A...0x45).map { code in
      KeyboardKeyChoice(id: UInt8(code), label: "F\(code - 0x39)")
    }
    choices += [
      KeyboardKeyChoice(id: 0x35, label: "`")
    ]
    for code in 0x1E...0x27 {
      choices.append(
        KeyboardKeyChoice(id: UInt8(code), label: code == 0x27 ? "0" : "\(code - 0x1D)"))
    }
    choices += [
      KeyboardKeyChoice(id: 0x2D, label: "-"),
      KeyboardKeyChoice(id: 0x2E, label: "="),
      KeyboardKeyChoice(id: 0x2A, label: "Backspace"),
      KeyboardKeyChoice(id: 0x2B, label: "Tab"),
      KeyboardKeyChoice(id: 0x14, label: "Q"),
      KeyboardKeyChoice(id: 0x1A, label: "W"),
      KeyboardKeyChoice(id: 0x08, label: "E"),
      KeyboardKeyChoice(id: 0x15, label: "R"),
      KeyboardKeyChoice(id: 0x17, label: "T"),
      KeyboardKeyChoice(id: 0x1C, label: "Y"),
      KeyboardKeyChoice(id: 0x18, label: "U"),
      KeyboardKeyChoice(id: 0x0C, label: "I"),
      KeyboardKeyChoice(id: 0x12, label: "O"),
      KeyboardKeyChoice(id: 0x13, label: "P"),
      KeyboardKeyChoice(id: 0x2F, label: "["),
      KeyboardKeyChoice(id: 0x30, label: "]"),
      KeyboardKeyChoice(id: 0x31, label: "\\"),
      KeyboardKeyChoice(id: 0x32, label: "Non-US #"),
      KeyboardKeyChoice(id: 0x39, label: "Caps Lock"),
      KeyboardKeyChoice(id: 0x04, label: "A"),
      KeyboardKeyChoice(id: 0x16, label: "S"),
      KeyboardKeyChoice(id: 0x07, label: "D"),
      KeyboardKeyChoice(id: 0x09, label: "F"),
      KeyboardKeyChoice(id: 0x0A, label: "G"),
      KeyboardKeyChoice(id: 0x0B, label: "H"),
      KeyboardKeyChoice(id: 0x0D, label: "J"),
      KeyboardKeyChoice(id: 0x0E, label: "K"),
      KeyboardKeyChoice(id: 0x0F, label: "L"),
      KeyboardKeyChoice(id: 0x33, label: ";"),
      KeyboardKeyChoice(id: 0x34, label: "'"),
      KeyboardKeyChoice(id: 0x28, label: "Enter"),
      KeyboardKeyChoice(id: 0x1D, label: "Z"),
      KeyboardKeyChoice(id: 0x1B, label: "X"),
      KeyboardKeyChoice(id: 0x06, label: "C"),
      KeyboardKeyChoice(id: 0x19, label: "V"),
      KeyboardKeyChoice(id: 0x05, label: "B"),
      KeyboardKeyChoice(id: 0x11, label: "N"),
      KeyboardKeyChoice(id: 0x10, label: "M"),
      KeyboardKeyChoice(id: 0x36, label: ","),
      KeyboardKeyChoice(id: 0x37, label: "."),
      KeyboardKeyChoice(id: 0x38, label: "/"),
      KeyboardKeyChoice(id: 0x2C, label: "Space"),
      KeyboardKeyChoice(id: 0x64, label: "Non-US \\"),
      KeyboardKeyChoice(id: 0x65, label: "Application"),
      KeyboardKeyChoice(id: 0x66, label: "Power"),
      KeyboardKeyChoice(id: 0x82, label: "Locking Caps Lock"),
      // Navigation and arrow cluster: navigation keys followed by the
      // physical arrow arrangement (up, then the three-key bottom row).
      KeyboardKeyChoice(id: 0x46, label: "Print Screen"),
      KeyboardKeyChoice(id: 0x47, label: "Scroll Lock"),
      KeyboardKeyChoice(id: 0x48, label: "Pause"),
      KeyboardKeyChoice(id: 0x49, label: "Insert"),
      KeyboardKeyChoice(id: 0x4A, label: "Home"),
      KeyboardKeyChoice(id: 0x4B, label: "Page Up"),
      KeyboardKeyChoice(id: 0x4C, label: "Delete"),
      KeyboardKeyChoice(id: 0x4D, label: "End"),
      KeyboardKeyChoice(id: 0x4E, label: "Page Down"),
      KeyboardKeyChoice(id: 0x52, label: "Up Arrow"),
      KeyboardKeyChoice(id: 0x50, label: "Left Arrow"),
      KeyboardKeyChoice(id: 0x51, label: "Down Arrow"),
      KeyboardKeyChoice(id: 0x4F, label: "Right Arrow"),
      KeyboardKeyChoice(id: 0x84, label: "Locking Scroll Lock"),
      // Numpad: top row, then the numeric rows. Keypad plus and enter span
      // rows on a physical keyboard, so they follow the row where they begin.
      KeyboardKeyChoice(id: 0x53, label: "Num Lock"),
      KeyboardKeyChoice(id: 0x54, label: "Keypad /"),
      KeyboardKeyChoice(id: 0x55, label: "Keypad *"),
      KeyboardKeyChoice(id: 0x56, label: "Keypad -"),
      KeyboardKeyChoice(id: 0x5F, label: "Keypad 7 / Home"),
      KeyboardKeyChoice(id: 0x60, label: "Keypad 8 / Up Arrow"),
      KeyboardKeyChoice(id: 0x61, label: "Keypad 9 / Page Up"),
      KeyboardKeyChoice(id: 0x57, label: "Keypad +"),
      KeyboardKeyChoice(id: 0x5C, label: "Keypad 4 / Left Arrow"),
      KeyboardKeyChoice(id: 0x5D, label: "Keypad 5"),
      KeyboardKeyChoice(id: 0x5E, label: "Keypad 6 / Right Arrow"),
      KeyboardKeyChoice(id: 0x59, label: "Keypad 1 / End"),
      KeyboardKeyChoice(id: 0x5A, label: "Keypad 2 / Down Arrow"),
      KeyboardKeyChoice(id: 0x5B, label: "Keypad 3 / Page Down"),
      KeyboardKeyChoice(id: 0x58, label: "Keypad Enter"),
      KeyboardKeyChoice(id: 0x62, label: "Keypad 0 / Insert"),
      KeyboardKeyChoice(id: 0x63, label: "Keypad . / Delete"),
      KeyboardKeyChoice(id: 0x67, label: "Keypad ="),
      KeyboardKeyChoice(id: 0x83, label: "Locking Num Lock"),
      KeyboardKeyChoice(id: 0x85, label: "Keypad Comma"),
      KeyboardKeyChoice(id: 0x86, label: "Keypad Equal Sign"),
      KeyboardKeyChoice(id: 0x74, label: "Execute"),
      KeyboardKeyChoice(id: 0x75, label: "Help"),
      KeyboardKeyChoice(id: 0x76, label: "Menu"),
      KeyboardKeyChoice(id: 0x77, label: "Select"),
      KeyboardKeyChoice(id: 0x78, label: "Stop"),
      KeyboardKeyChoice(id: 0x79, label: "Again"),
      KeyboardKeyChoice(id: 0x7A, label: "Undo"),
      KeyboardKeyChoice(id: 0x7B, label: "Cut"),
      KeyboardKeyChoice(id: 0x7C, label: "Copy"),
      KeyboardKeyChoice(id: 0x7D, label: "Paste"),
      KeyboardKeyChoice(id: 0x7E, label: "Find"),
      KeyboardKeyChoice(id: 0x7F, label: "Mute"),
      KeyboardKeyChoice(id: 0x80, label: "Volume Up"),
      KeyboardKeyChoice(id: 0x81, label: "Volume Down"),
      KeyboardKeyChoice(id: 0xB0, label: "Play"),
      KeyboardKeyChoice(id: 0xB1, label: "Pause"),
      KeyboardKeyChoice(id: 0xB2, label: "Record"),
      KeyboardKeyChoice(id: 0xB3, label: "Fast Forward"),
      KeyboardKeyChoice(id: 0xB4, label: "Rewind"),
      KeyboardKeyChoice(id: 0xB5, label: "Scan Next Track"),
      KeyboardKeyChoice(id: 0xB6, label: "Scan Previous Track"),
      KeyboardKeyChoice(id: 0xB7, label: "Stop"),
      KeyboardKeyChoice(id: 0xB8, label: "Eject"),
      KeyboardKeyChoice(id: 0x87, label: "International 1"),
      KeyboardKeyChoice(id: 0x88, label: "International 2"),
      KeyboardKeyChoice(id: 0x89, label: "International 3"),
      KeyboardKeyChoice(id: 0x8A, label: "International 4"),
      KeyboardKeyChoice(id: 0x8B, label: "International 5"),
      KeyboardKeyChoice(id: 0x8C, label: "International 6"),
      KeyboardKeyChoice(id: 0x8D, label: "International 7"),
      KeyboardKeyChoice(id: 0x8E, label: "International 8"),
      KeyboardKeyChoice(id: 0x8F, label: "International 9"),
      KeyboardKeyChoice(id: 0x90, label: "LANG 1"),
      KeyboardKeyChoice(id: 0x91, label: "LANG 2"),
      KeyboardKeyChoice(id: 0x92, label: "LANG 3"),
      KeyboardKeyChoice(id: 0x93, label: "LANG 4"),
      KeyboardKeyChoice(id: 0x94, label: "LANG 5"),
      KeyboardKeyChoice(id: 0x95, label: "LANG 6"),
      KeyboardKeyChoice(id: 0x96, label: "LANG 7"),
      KeyboardKeyChoice(id: 0x97, label: "LANG 8"),
      KeyboardKeyChoice(id: 0x98, label: "LANG 9"),
      KeyboardKeyChoice(id: 0x99, label: "LANG 10"),
      KeyboardKeyChoice(id: 0x9A, label: "Alternate Erase"),
      KeyboardKeyChoice(id: 0x9B, label: "SysReq / Attention"),
      KeyboardKeyChoice(id: 0x9C, label: "Cancel"),
      KeyboardKeyChoice(id: 0x9D, label: "Clear"),
      KeyboardKeyChoice(id: 0x9E, label: "Prior"),
      KeyboardKeyChoice(id: 0x9F, label: "Return"),
      KeyboardKeyChoice(id: 0xA0, label: "Separator"),
      KeyboardKeyChoice(id: 0xA1, label: "Out"),
      KeyboardKeyChoice(id: 0xA2, label: "Oper"),
      KeyboardKeyChoice(id: 0xA3, label: "Clear / Again"),
      KeyboardKeyChoice(id: 0xA4, label: "CrSel / Props"),
      KeyboardKeyChoice(id: 0xA5, label: "ExSel"),
      // HID usage extensions commonly used by programmable keyboards.
      KeyboardKeyChoice(id: 0xF8, label: "Sleep"),
      KeyboardKeyChoice(id: 0xF9, label: "Wake"),
      KeyboardKeyChoice(id: 0xFA, label: "Refresh"),
    ]
    choices += (0x68...0x73).map { code in
      KeyboardKeyChoice(id: UInt8(code), label: "F\(code - 0x5B)")
    }
    return choices
  }()

  var keyboardKeys: [KeyboardKeyChoice] {
    Self.keyboardKeyCatalog
  }

  var keyboardKeyLayoutGroups: [KeyboardKeyLayoutGroupChoice] {
    KeyboardKeyLayoutGroup.allCases.compactMap { group in
      let keys = keyboardKeys.filter { keyboardKeyLayoutGroup(for: $0) == group }
      guard !keys.isEmpty else { return nil }
      return KeyboardKeyLayoutGroupChoice(group: group, keys: keys)
    }
  }

  /// Keys that are useful as explicit HID++ overrides but should stay out
  /// of the normal recorder UI. Character keys, F1–F12, Tab, Enter, and
  /// similar everyday keys are captured by recording instead.
  var extendedKeyboardKeys: [KeyboardKeyChoice] {
    extendedKeyboardKeyGroups.flatMap(\.keys)
  }

  var extendedKeyboardKeyGroups: [KeyboardKeyGroupChoice] {
    KeyboardKeyGroup.allCases.compactMap { group in
      let filteredKeys = keyboardKeys.filter {
        isExtendedKeyboardKey($0) && keyboardKeyGroup(for: $0) == group
      }
      let keys =
        group == .standard
        ? filteredKeys
        : filteredKeys.sorted { lhs, rhs in
          let leftLabel = lhs.label.lowercased()
          let rightLabel = rhs.label.lowercased()
          if leftLabel != rightLabel {
            return leftLabel < rightLabel
          }
          return lhs.id < rhs.id
        }
      guard !keys.isEmpty else { return nil }
      return KeyboardKeyGroupChoice(group: group, keys: keys)
    }
  }

  var extendedKeyboardKeyLayoutGroups: [KeyboardKeyLayoutGroupChoice] {
    KeyboardKeyLayoutGroup.allCases.compactMap { group in
      let keys = keyboardKeys.filter {
        isExtendedKeyboardKey($0) && keyboardKeyLayoutGroup(for: $0) == group
      }
      guard !keys.isEmpty else { return nil }
      return KeyboardKeyLayoutGroupChoice(group: group, keys: keys)
    }
  }

  var keyboardOutputKeys: [KeyboardKeyChoice] {
    showNonStandardKeyboardKeys ? extendedKeyboardKeys : []
  }

  func isNonStandardKeyboardKey(_ key: KeyboardKeyChoice) -> Bool {
    isExtendedKeyboardKey(key)
  }

  func isExtendedKeyboardKey(_ key: KeyboardKeyChoice) -> Bool {
    switch key.id {
    case 0x46...0x67,  // Print Screen through keypad equal sign
      0x68...0x73,  // F13–F24
      0x74...0xA5,  // extended keyboard/page usages
      0xB0...0xB8,  // media usages
      0xF8...0xFA:  // Sleep, Wake, Refresh extensions
      return true
    default:
      return false
    }
  }

  func keyboardKeyGroup(for key: KeyboardKeyChoice) -> KeyboardKeyGroup {
    switch key.id {
    case 0x04...0x67, 0x82...0x86:
      return .standard
    case 0x68...0x73:
      return .function
    case 0x7F...0x81, 0xB0...0xB8:
      return .media
    default:
      return .other
    }
  }

  func keyboardKeyLayoutGroup(for key: KeyboardKeyChoice) -> KeyboardKeyLayoutGroup? {
    switch key.id {
    case 0x04...0x45, 0x64...0x66, 0x82:
      return .mainTyping
    case 0x46...0x52, 0x84:
      return .navigation
    case 0x53...0x63, 0x67, 0x83, 0x85...0x86:
      return .numpad
    default:
      return nil
    }
  }

  var presets: [OutputPreset] {
    [
      OutputPreset(id: "FFFFFFFF", label: "Disabled", raw: "FFFFFFFF"),
      OutputPreset(id: "80010001", label: "Left click", raw: "80010001"),
      OutputPreset(id: "80010002", label: "Right click", raw: "80010002"),
      OutputPreset(id: "80010004", label: "Middle click", raw: "80010004"),
      OutputPreset(id: "80010008", label: "Back", raw: "80010008"),
      OutputPreset(id: "80010010", label: "Forward", raw: "80010010"),
      OutputPreset(id: "80010020", label: "Mouse button 6", raw: "80010020"),
      OutputPreset(id: "80010040", label: "Mouse button 7", raw: "80010040"),
      OutputPreset(id: "80010080", label: "Mouse button 8", raw: "80010080"),
      OutputPreset(id: "90010000", label: "Tilt left", raw: "90010000"),
      OutputPreset(id: "90020000", label: "Tilt right", raw: "90020000"),
      OutputPreset(id: "90100000", label: "Scroll down", raw: "90100000"),
      OutputPreset(id: "90110000", label: "Scroll up", raw: "90110000"),
      OutputPreset(id: "90030000", label: "DPI up", raw: "90030000"),
      OutputPreset(id: "90040000", label: "DPI down", raw: "90040000"),
      OutputPreset(id: "90050000", label: "Cycle DPI", raw: "90050000"),
      OutputPreset(id: "90060000", label: "Default DPI", raw: "90060000"),
      OutputPreset(id: "90070000", label: "DPI shift", raw: "90070000"),
      OutputPreset(id: "900A0000", label: "Cycle profile", raw: "900A0000"),
      OutputPreset(id: "900B0000", label: "G-Shift", raw: "900B0000"),
    ]
  }
}
