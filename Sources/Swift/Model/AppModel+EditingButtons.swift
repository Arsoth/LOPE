// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  func setPreset(buttonIndex: Int, raw: String) {
    setRaw(buttonIndex: buttonIndex, raw: raw)
  }

  func selectOutput(buttonIndex: Int, choice: String) {
    guard buttons.indices.contains(buttonIndex) else { return }
    if choice == "keystroke" {
      buttons[buttonIndex].draftChoice = "keystroke"
      if !isKeyboardRecord(buttonIndex: buttonIndex) {
        setKeyboardChord(buttonIndex: buttonIndex, modifier: 0, key: 0)
      }
    } else {
      setPreset(buttonIndex: buttonIndex, raw: choice)
    }
  }

  func profileEnabled(_ profileID: Int) -> Bool {
    profiles.first(where: { $0.id == profileID })?.enabled ?? false
  }

  func setProfileEnabled(profileID: Int, enabled: Bool) {
    guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
    if !enabled && profiles.filter({ $0.enabled }).count <= 1 {
      status = "At least one onboard profile must remain enabled."
      return
    }
    profiles[index].enabled = enabled
    status =
      "Profile \(profileID) will be \(enabled ? "enabled" : "disabled") when you save to the mouse."
  }

  func setRaw(buttonIndex: Int, raw: String) {
    guard buttons.indices.contains(buttonIndex) else { return }
    let normalized = normalize(raw)
    buttons[buttonIndex].draftRaw = normalized
    buttons[buttonIndex].draftChoice =
      presets.contains(where: { normalize($0.raw) == normalized }) ? normalized : "keystroke"
    if let bytes = rawBytes(normalized), bytes[0] == 0x80, bytes[1] == 0x02, bytes[3] != 0 {
      keyInputDrafts[buttonIndex] = keyboardKeyLabel(bytes[3])
    } else {
      keyInputDrafts.removeValue(forKey: buttonIndex)
    }
  }

  func setRaw(layer: ButtonLayer, buttonIndex: Int, raw: String) {
    if layer == buttonLayer {
      setRaw(buttonIndex: buttonIndex, raw: raw)
      return
    }

    let normalized = normalize(raw)
    switch layer {
    case .normal:
      guard normalButtonRows.indices.contains(buttonIndex) else { return }
      normalButtonRows[buttonIndex].draftRaw = normalized
      normalButtonRows[buttonIndex].draftChoice =
        presets.contains {
          normalize($0.raw) == normalized
        } ? normalized : "keystroke"
    case .gShift:
      guard gShiftButtonRows.indices.contains(buttonIndex) else { return }
      gShiftButtonRows[buttonIndex].draftRaw = normalized
      gShiftButtonRows[buttonIndex].draftChoice =
        presets.contains {
          normalize($0.raw) == normalized
        } ? normalized : "keystroke"
    }
  }
}
