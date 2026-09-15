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
    setRaw(layer: buttonLayer, buttonIndex: buttonIndex, raw: raw)
  }

  /// Every button-binding write in the app funnels through this single
  /// choke point, so it is also the one place that keeps the physical
  /// button bound to G-Shift identical on both layers: that button always
  /// activates the G-Shift layer, so it cannot carry a different,
  /// layer-specific binding. Setting it mirrors the G-Shift binding onto
  /// the same `buttonIndex` on the other layer; changing it away from the
  /// G-Shift binding mirrors the new value the same way, so the two layers
  /// never end up with only one side pointing at G-Shift.
  func setRaw(layer: ButtonLayer, buttonIndex: Int, raw: String) {
    let normalized = normalize(raw)
    guard let previousRaw = currentRaw(layer: layer, buttonIndex: buttonIndex) else { return }
    applyRaw(layer: layer, buttonIndex: buttonIndex, normalized: normalized)
    guard previousRaw != normalized else { return }
    mirrorGShiftBinding(
      sourceLayer: layer, buttonIndex: buttonIndex, previousRaw: previousRaw, newRaw: normalized)
  }

  private func currentRaw(layer: ButtonLayer, buttonIndex: Int) -> String? {
    if layer == buttonLayer {
      return buttons.indices.contains(buttonIndex) ? buttons[buttonIndex].draftRaw : nil
    }
    switch layer {
    case .normal:
      return normalButtonRows.indices.contains(buttonIndex)
        ? normalButtonRows[buttonIndex].draftRaw : nil
    case .gShift:
      return gShiftButtonRows.indices.contains(buttonIndex)
        ? gShiftButtonRows[buttonIndex].draftRaw : nil
    }
  }

  private func applyRaw(layer: ButtonLayer, buttonIndex: Int, normalized: String) {
    let draftChoice =
      presets.contains { normalize($0.raw) == normalized } ? normalized : "keystroke"
    if layer == buttonLayer {
      capturedKeyboardButtonIndices.remove(buttonIndex)
      buttons[buttonIndex].draftRaw = normalized
      buttons[buttonIndex].draftChoice = draftChoice
      if let bytes = rawBytes(normalized), bytes[0] == 0x80, bytes[1] == 0x02, bytes[3] != 0 {
        keyInputDrafts[buttonIndex] = keyboardKeyLabel(bytes[3])
      } else {
        keyInputDrafts.removeValue(forKey: buttonIndex)
      }
      return
    }
    switch layer {
    case .normal:
      normalButtonRows[buttonIndex].draftRaw = normalized
      normalButtonRows[buttonIndex].draftChoice = draftChoice
    case .gShift:
      gShiftButtonRows[buttonIndex].draftRaw = normalized
      gShiftButtonRows[buttonIndex].draftChoice = draftChoice
    }
  }

  /// Mirrors a change at `(sourceLayer, buttonIndex)` onto the other layer's
  /// same index when the change either creates or breaks a G-Shift-binding
  /// pairing between the two layers. A plain edit that never involved the
  /// G-Shift binding on either side is left alone.
  private func mirrorGShiftBinding(
    sourceLayer: ButtonLayer, buttonIndex: Int, previousRaw: String, newRaw: String
  ) {
    let otherLayer: ButtonLayer = sourceLayer == .normal ? .gShift : .normal
    guard let otherRaw = currentRaw(layer: otherLayer, buttonIndex: buttonIndex) else { return }
    guard otherRaw != newRaw else { return }
    let becameGShift = ProfileWriteValidation.isGShiftBinding(raw: newRaw)
    let otherWasPaired = ProfileWriteValidation.isGShiftBinding(raw: otherRaw)
    guard becameGShift || otherWasPaired else { return }
    applyRaw(layer: otherLayer, buttonIndex: buttonIndex, normalized: newRaw)
  }
}
