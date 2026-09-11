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
        if choice == "custom" {
            buttons[buttonIndex].draftChoice = "custom"
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
        status = "Profile \(profileID) will be \(enabled ? "enabled" : "disabled") when you save to the mouse."
    }

    func setRaw(buttonIndex: Int, raw: String) {
        guard buttons.indices.contains(buttonIndex) else { return }
        let normalized = normalize(raw)
        buttons[buttonIndex].draftRaw = normalized
        buttons[buttonIndex].draftChoice = presets.contains(where: { normalize($0.raw) == normalized }) ? normalized : "custom"
        if let bytes = rawBytes(normalized), bytes[0] == 0x80, bytes[1] == 0x02, bytes[3] != 0 {
            keyInputDrafts[buttonIndex] = keyboardKeyLabel(bytes[3])
        } else {
            keyInputDrafts.removeValue(forKey: buttonIndex)
        }
    }

    func isKeyboardRecord(buttonIndex: Int) -> Bool {
        guard buttons.indices.contains(buttonIndex), let bytes = rawBytes(buttons[buttonIndex].draftRaw) else {
            return false
        }
        return bytes[0] == 0x80 && bytes[1] == 0x02 && bytes[3] != 0
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

    func setKeyboardKeyText(buttonIndex: Int, text: String) {
        keyInputDrafts[buttonIndex] = text
        if let key = keyboardKeyCode(for: text) {
            let chord = keyboardBytes(buttonIndex) ?? (modifier: 0, key: 0)
            setKeyboardChord(buttonIndex: buttonIndex, modifier: chord.modifier, key: key)
        }
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
        let key = UInt8(keyboardKey(buttonIndex: buttonIndex))
        return specialKeyboardKeys.contains(where: { $0.id == key }) ? Int(key) : 0
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

    private func setKeyboardChord(buttonIndex: Int, modifier: UInt8, key: UInt8) {
        setRaw(buttonIndex: buttonIndex, raw: String(format: "8002%02X%02X", modifier, key))
    }

    private func keyboardBytes(_ buttonIndex: Int) -> (modifier: UInt8, key: UInt8)? {
        guard buttons.indices.contains(buttonIndex), let bytes = rawBytes(buttons[buttonIndex].draftRaw),
              bytes[0] == 0x80, bytes[1] == 0x02, bytes[3] != 0 else { return nil }
        return (bytes[2], bytes[3])
    }

    private func keyboardKeyLabel(_ code: UInt8) -> String {
        if code == 0 { return "" }
        return keyboardKeys.first(where: { $0.id == code })?.label ?? String(format: "0x%02X", code)
    }

    private func keyboardKeyCode(for text: String) -> UInt8? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let key = keyboardKeys.first(where: { $0.label.uppercased() == normalized }) {
            return key.id
        }
        let hexText = normalized.hasPrefix("0X") ? String(normalized.dropFirst(2)) : normalized
        guard hexText.count == 2 else { return nil }
        return UInt8(hexText, radix: 16)
    }

    func physicalButtonLabel(_ number: Int) -> String {
        if !currentDeviceName.lowercased().contains("g502") {
            switch number {
            case 1: return "Primary click"
            case 2: return "Secondary click"
            case 3: return "Middle click"
            case 4: return "Back / thumb"
            default: return "Button \(number)"
            }
        }
        switch number {
        case 1: return "G1 (Left)"
        case 2: return "G2 (Right)"
        case 3: return "G3 (Middle)"
        case 4: return "G4 (Back)"
        case 5: return "G6 (DPI Shift)"
        case 6: return "G5 (Forward)"
        case 7: return "Wheel tilt left"
        case 8: return "Wheel tilt right"
        case 9: return "G9 (Profile)"
        case 10: return "G8 (DPI Up)"
        case 11: return "G7 (DPI Down)"
        default: return "Button \(number)"
        }
    }

    func setDPIStageCount(_ requested: Int) {
        let count = min(max(requested, 1), 5)
        dpiCount = count
        for index in count..<5 {
            dpiStages[index] = ""
        }
        defaultStage = min(max(defaultStage, 1), count)
        shiftStage = min(max(shiftStage, 1), count)
    }
}
