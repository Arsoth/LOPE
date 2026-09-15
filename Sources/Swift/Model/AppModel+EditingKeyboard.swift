// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation

@MainActor
extension AppModel {
  func isKeyboardRecord(buttonIndex: Int) -> Bool {
    guard buttons.indices.contains(buttonIndex), let bytes = rawBytes(buttons[buttonIndex].draftRaw)
    else {
      return false
    }
    return bytes[0] == 0x80 && bytes[1] == 0x02
  }

  func isModifierEnabled(buttonIndex: Int, bit: UInt8) -> Bool {
    guard let bytes = keyboardBytes(buttonIndex) else { return false }
    return (bytes.modifier & bit) != 0
  }

  func setModifier(buttonIndex: Int, bit: UInt8, enabled: Bool) {
    guard var chord = keyboardBytes(buttonIndex) else { return }
    if enabled {
      chord.modifier |= bit
    } else {
      chord.modifier &= ~bit
    }
    setKeyboardChord(buttonIndex: buttonIndex, modifier: chord.modifier, key: chord.key)
  }

  func keyboardKey(buttonIndex: Int) -> Int {
    Int(keyboardBytes(buttonIndex)?.key ?? 0)
  }

  func keyboardKeyText(buttonIndex: Int) -> String {
    if let draft = keyInputDrafts[buttonIndex] {
      return draft
    }
    return keyboardKeyLabel(UInt8(keyboardKey(buttonIndex: buttonIndex)))
  }

  func keyboardChordText(buttonIndex: Int) -> String {
    guard let chord = keyboardBytes(buttonIndex), chord.key != 0 else { return "" }
    let modifierLabels: [(UInt8, String)] = [
      (0x01, "Ctrl"),
      (0x02, "Shift"),
      (0x04, "Alt"),
      (0x08, "Cmd"),
    ]
    let modifiers = modifierLabels.compactMap { bit, label in
      chord.modifier & bit == 0 ? nil : label
    }
    let key = keyboardKeyText(buttonIndex: buttonIndex)
    return (modifiers + [key]).joined(separator: "+")
  }

  func keyboardKeyChoice(buttonIndex: Int) -> Int {
    guard !capturedKeyboardButtonIndices.contains(buttonIndex) else { return 0 }
    let key = UInt8(keyboardKey(buttonIndex: buttonIndex))
    return keyboardOutputKeys.contains(where: { $0.id == key }) ? Int(key) : 0
  }

  func setKeyboardKeyChoice(buttonIndex: Int, key: Int) {
    guard buttons.indices.contains(buttonIndex) else { return }
    if key == 0 {
      setKeyboardChord(buttonIndex: buttonIndex, modifier: 0, key: 0)
      return
    }
    guard let usage = UInt8(exactly: key),
      let selected = keyboardKeys.first(where: { $0.id == usage })
    else { return }
    if isNonStandardKeyboardKey(selected) && !showNonStandardKeyboardKeys {
      status = "Enable non-standard keyboard keys in Settings before choosing \(selected.label)."
      return
    }
    let chord = keyboardBytes(buttonIndex) ?? (modifier: 0, key: 0)
    setKeyboardChord(buttonIndex: buttonIndex, modifier: chord.modifier, key: usage)
  }

  func beginKeyboardRecording(buttonIndex: Int) {
    guard buttons.indices.contains(buttonIndex) else { return }
    recordingKeyboardButtonID = buttons[buttonIndex].id
    status = "Press one keyboard key to record it."
  }

  func cancelKeyboardRecording() {
    recordingKeyboardButtonID = nil
    status = "Keyboard recording canceled."
  }

  func recordKeyboardEvent(buttonIndex: Int, keyCode: UInt8, modifier: UInt8) {
    guard buttons.indices.contains(buttonIndex),
      recordingKeyboardButtonID == buttons[buttonIndex].id
    else { return }
    guard let key = keyboardKeys.first(where: { $0.id == keyCode }) else {
      status = "That keyboard input is not supported by the HID++ key table."
      return
    }
    setKeyboardChord(buttonIndex: buttonIndex, modifier: modifier, key: keyCode)
    capturedKeyboardButtonIndices.insert(buttonIndex)
    recordingKeyboardButtonID = nil
    status = "Recorded \(key.label)."
  }

  func keyboardUsage(forMacKeyCode keyCode: UInt16) -> UInt8? {
    let usages: [UInt16: UInt8] = [
      0: 0x04, 1: 0x16, 2: 0x07, 3: 0x09, 4: 0x0B, 5: 0x0A,
      6: 0x1D, 7: 0x1B, 8: 0x06, 9: 0x19, 11: 0x05, 12: 0x14,
      13: 0x1A, 14: 0x08, 15: 0x15, 16: 0x1C, 17: 0x17,
      18: 0x1E, 19: 0x1F, 20: 0x20, 21: 0x21, 22: 0x23, 23: 0x22,
      24: 0x2E, 25: 0x26, 26: 0x24, 27: 0x2D, 28: 0x25, 29: 0x27,
      30: 0x30, 31: 0x12, 32: 0x18, 33: 0x2F, 34: 0x0C, 35: 0x13,
      37: 0x0F, 38: 0x0D, 39: 0x34, 40: 0x0E, 41: 0x33, 42: 0x31,
      43: 0x36, 44: 0x38, 45: 0x11, 46: 0x10, 47: 0x37, 49: 0x2C,
      50: 0x35, 36: 0x28, 48: 0x2B, 51: 0x2A, 53: 0x29,
      122: 0x3A, 120: 0x3B, 99: 0x3C, 118: 0x3D, 96: 0x3E, 97: 0x3F,
      98: 0x40, 100: 0x41, 101: 0x42, 109: 0x43, 103: 0x44, 111: 0x45,
      105: 0x68, 107: 0x69, 113: 0x6A, 106: 0x6B, 64: 0x6C, 79: 0x6D,
      80: 0x6E, 90: 0x6F, 123: 0x50, 124: 0x4F, 125: 0x51, 126: 0x52,
      // macOS reports the Help/Insert key as key code 114 on many
      // extended keyboards. HID++ needs the keyboard Insert usage.
      114: 0x49,
      115: 0x4A, 116: 0x4B, 117: 0x4C, 119: 0x4D, 121: 0x4E,
      71: 0x53, 73: 0x54, 75: 0x55, 67: 0x56, 69: 0x57, 76: 0x58,
      82: 0x59, 83: 0x5A, 84: 0x5B, 86: 0x5C, 87: 0x5D, 88: 0x5E,
      89: 0x5F, 91: 0x60, 92: 0x61, 94: 0x62, 65: 0x63,
    ]
    return usages[keyCode]
  }

  /// The Fn modifier turns Return into Insert on common Mac keyboards.
  /// Keep this separate from the key-code table so ordinary Return still
  /// records as Enter.
  func keyboardUsage(for event: NSEvent) -> UInt8? {
    let extendedFunctionUsages: [UInt32: UInt8] = [
      0xF718: 0x70,  // F21
      0xF719: 0x71,  // F22
      0xF71A: 0x72,  // F23
      0xF71B: 0x73,  // F24
    ]
    if let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
      let usage = extendedFunctionUsages[scalar.value]
    {
      return usage
    }
    if event.keyCode == 36 && event.modifierFlags.contains(.function) {
      return 0x49
    }
    return keyboardUsage(forMacKeyCode: event.keyCode)
  }

  func functionKeyChoice(buttonIndex: Int) -> Int {
    let key = UInt8(keyboardKey(buttonIndex: buttonIndex))
    if (0x3A...0x45).contains(key) {
      return Int(key - 0x39)
    }
    if (0x68...0x73).contains(key) {
      return Int(key - 0x5B)
    }
    return 0
  }

  func setFunctionKey(buttonIndex: Int, number: Int) {
    guard (1...24).contains(number) else { return }
    let key: UInt8 = number <= 12 ? UInt8(0x39 + number) : UInt8(0x5B + number)
    let chord = keyboardBytes(buttonIndex) ?? (modifier: 0, key: 0)
    setKeyboardChord(buttonIndex: buttonIndex, modifier: chord.modifier, key: key)
  }

  func specialKeyChoice(buttonIndex: Int) -> Int {
    guard !capturedKeyboardButtonIndices.contains(buttonIndex) else { return 0 }
    let key = UInt8(keyboardKey(buttonIndex: buttonIndex))
    return keyboardOutputKeys.contains(where: { $0.id == key }) ? Int(key) : 0
  }

  func setSpecialKey(buttonIndex: Int, key: Int) {
    guard key > 0 else { return }
    let chord = keyboardBytes(buttonIndex) ?? (modifier: 0, key: 0)
    setKeyboardChord(buttonIndex: buttonIndex, modifier: chord.modifier, key: UInt8(clamping: key))
  }

  func setKeyboardKey(buttonIndex: Int, key: Int) {
    let chord = keyboardBytes(buttonIndex) ?? (modifier: 0, key: 0)
    setKeyboardChord(buttonIndex: buttonIndex, modifier: chord.modifier, key: UInt8(clamping: key))
  }

  func setKeyboardChord(buttonIndex: Int, modifier: UInt8, key: UInt8) {
    setRaw(buttonIndex: buttonIndex, raw: String(format: "8002%02X%02X", modifier, key))
  }

  private func keyboardBytes(_ buttonIndex: Int) -> (modifier: UInt8, key: UInt8)? {
    guard buttons.indices.contains(buttonIndex),
      let bytes = rawBytes(buttons[buttonIndex].draftRaw),
      bytes[0] == 0x80, bytes[1] == 0x02
    else { return nil }
    return (bytes[2], bytes[3])
  }

  func keyboardKeyLabel(_ code: UInt8) -> String {
    if code == 0 { return "" }
    return keyboardKeys.first(where: { $0.id == code })?.label ?? String(format: "0x%02X", code)
  }
}
