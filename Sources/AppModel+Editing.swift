// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
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
            (0x08, "Cmd")
        ]
        let modifiers = modifierLabels.compactMap { bit, label in
            chord.modifier & bit == 0 ? nil : label
        }
        let key = keyboardKeyText(buttonIndex: buttonIndex)
        return (modifiers + [key]).joined(separator: "+")
    }

    func keyboardKeyChoice(buttonIndex: Int) -> Int {
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
              let selected = keyboardKeys.first(where: { $0.id == usage }) else { return }
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
              recordingKeyboardButtonID == buttons[buttonIndex].id else { return }
        guard let key = keyboardKeys.first(where: { $0.id == keyCode }) else {
            status = "That keyboard input is not supported by the HID++ key table."
            return
        }
        setKeyboardChord(buttonIndex: buttonIndex, modifier: modifier, key: keyCode)
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
            89: 0x5F, 91: 0x60, 92: 0x61, 94: 0x62, 65: 0x63
        ]
        return usages[keyCode]
    }

    /// The Fn modifier turns Return into Insert on common Mac keyboards.
    /// Keep this separate from the key-code table so ordinary Return still
    /// records as Enter.
    func keyboardUsage(for event: NSEvent) -> UInt8? {
        let extendedFunctionUsages: [UInt32: UInt8] = [
            0xF718: 0x70, // F21
            0xF719: 0x71, // F22
            0xF71A: 0x72, // F23
            0xF71B: 0x73  // F24
        ]
        if let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
           let usage = extendedFunctionUsages[scalar.value] {
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

    private func setKeyboardChord(buttonIndex: Int, modifier: UInt8, key: UInt8) {
        setRaw(buttonIndex: buttonIndex, raw: String(format: "8002%02X%02X", modifier, key))
    }

    private func keyboardBytes(_ buttonIndex: Int) -> (modifier: UInt8, key: UInt8)? {
        guard buttons.indices.contains(buttonIndex), let bytes = rawBytes(buttons[buttonIndex].draftRaw),
              bytes[0] == 0x80, bytes[1] == 0x02 else { return nil }
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
        if let known = currentMouseProfile.button(for: number) {
            return known.label
        }
        switch number {
        case 1: return "Primary click"
        case 2: return "Secondary click"
        case 3: return "Middle click"
        default: return "Button \(number)"
        }
    }

    func setDPIStageText(index: Int, text: String) {
        guard dpiStages.indices.contains(index), index < dpiCount else { return }
        dpiStages[index] = text.filter { $0.isNumber }
    }

    func commitDPIStageText(index: Int) {
        guard dpiStages.indices.contains(index), index < dpiCount,
              let value = Int(dpiStages[index]) else { return }
        setDPIStageValue(index: index, value: value)
    }

    func setDPIStageValue(index: Int, value: Int) {
        guard dpiStages.indices.contains(index), index < dpiCount else { return }
        let lowerBound = index > 0 ? Int(dpiStages[index - 1]).map { $0 + 1 } : nil
        let upperBound = index + 1 < dpiCount ? Int(dpiStages[index + 1]).map { $0 - 1 } : nil
        guard let snapped = dpiCapabilities.snappedValue(
            for: value,
            lowerBound: lowerBound,
            upperBound: upperBound
        ) else { return }
        dpiStages[index] = String(snapped)
    }

    /// Moves a stage freely while dragging. When it crosses another stage,
    /// swap their ordered positions so the active stage can continue moving
    /// without leaving the profile in an invalid order.
    @discardableResult
    func moveDPIStageDuringDrag(index: Int, value: Int) -> Int {
        guard dpiStages.indices.contains(index), index < dpiCount,
              let snapped = dpiCapabilities.snappedValue(for: value) else {
            return index
        }
        if Int(dpiStages[index]) == snapped {
            return index
        }

        dpiStages[index] = String(snapped)
        var currentIndex = index

        while currentIndex > 0,
              let currentValue = Int(dpiStages[currentIndex]),
              let previousValue = Int(dpiStages[currentIndex - 1]),
              currentValue < previousValue {
            swapDPIStages(at: currentIndex, and: currentIndex - 1)
            currentIndex -= 1
        }

        while currentIndex + 1 < dpiCount,
              let currentValue = Int(dpiStages[currentIndex]),
              let nextValue = Int(dpiStages[currentIndex + 1]),
              currentValue > nextValue {
            swapDPIStages(at: currentIndex, and: currentIndex + 1)
            currentIndex += 1
        }

        return currentIndex
    }

    /// Resolves the rare case where a drag ends with two handles on the same
    /// supported value, keeping the saved stage list strictly increasing.
    func finishDPIStageDrag() {
        guard dpiCount > 0 else { return }
        var previousValue: Int?
        for index in 0..<dpiCount {
            guard let value = Int(dpiStages[index]),
                  let adjusted = dpiCapabilities.snappedValue(
                      for: value,
                      lowerBound: previousValue.map { $0 + 1 }
                  ) else {
                return
            }
            dpiStages[index] = String(adjusted)
            previousValue = adjusted
        }
    }

    private func swapDPIStages(at firstIndex: Int, and secondIndex: Int) {
        dpiStages.swapAt(firstIndex, secondIndex)
        let firstStage = firstIndex + 1
        let secondStage = secondIndex + 1

        if defaultStage == firstStage {
            defaultStage = secondStage
        } else if defaultStage == secondStage {
            defaultStage = firstStage
        }
        if shiftStage == firstStage {
            shiftStage = secondStage
        } else if shiftStage == secondStage {
            shiftStage = firstStage
        }
    }

    func adjustDPIStage(index: Int, direction: DPICapabilities.AdjustmentDirection) {
        guard dpiStages.indices.contains(index), index < dpiCount,
              let current = Int(dpiStages[index]) else { return }
        let lowerBound = index > 0 ? Int(dpiStages[index - 1]).map { $0 + 1 } : nil
        let upperBound = index + 1 < dpiCount ? Int(dpiStages[index + 1]).map { $0 - 1 } : nil
        guard let adjusted = dpiCapabilities.adjustedValue(
            from: current,
            direction: direction,
            lowerBound: lowerBound,
            upperBound: upperBound
        ) else { return }
        dpiStages[index] = String(adjusted)
    }

    func setDefaultDPIStage(_ stage: Int) {
        guard (1...dpiCount).contains(stage) else { return }
        defaultStage = stage
        guard dpiCount > 1, shiftStage == stage else { return }
        shiftStage = (1...dpiCount).first(where: { $0 != stage }) ?? stage
    }

    func setShiftDPIStage(_ stage: Int) {
        guard (1...dpiCount).contains(stage) else { return }
        shiftStage = stage
        guard dpiCount > 1, defaultStage == stage else { return }
        defaultStage = (1...dpiCount).first(where: { $0 != stage }) ?? stage
    }

    func deleteDPIStage(index: Int) {
        guard dpiCount > 1, (0..<dpiCount).contains(index) else { return }
        let stage = index + 1
        guard stage != defaultStage, stage != shiftStage else { return }

        dpiStages.remove(at: index)
        dpiStages.append("")
        dpiCount -= 1

        if defaultStage > stage {
            defaultStage -= 1
        }
        if shiftStage > stage {
            shiftStage -= 1
        }
    }

    func setDPIStageCount(_ requested: Int) {
        let count = min(max(requested, 1), 5)
        let oldCount = dpiCount
        guard count != oldCount else { return }

        if count > oldCount {
            let activeValues = dpiStages.prefix(oldCount).compactMap(Int.init)
            if activeValues.count == oldCount, let last = activeValues.last {
                let maximum = dpiCapabilities.maximum ?? Int(UInt16.max)
                let insertBeforeLast = maximum - last <= 2_000
                let insertionIndex = insertBeforeLast ? max(activeValues.count - 1, 0) : activeValues.count
                let target = insertBeforeLast ? last - 1_000 : last + 1_000
                let lowerBound = insertionIndex > 0 ? activeValues[insertionIndex - 1] + 1 : nil
                let upperBound = insertionIndex < activeValues.count ? activeValues[insertionIndex] - 1 : nil

                if let suggested = dpiCapabilities.snappedValue(
                    for: target,
                    lowerBound: lowerBound,
                    upperBound: upperBound
                ) {
                    var updatedValues = activeValues
                    updatedValues.insert(suggested, at: insertionIndex)
                    dpiStages = updatedValues.map(String.init) + Array(repeating: "", count: 5 - count)
                    dpiCount = count

                    if defaultStage > insertionIndex {
                        defaultStage += 1
                    }
                    if shiftStage > insertionIndex {
                        shiftStage += 1
                    }
                    if oldCount == 1, defaultStage == shiftStage {
                        shiftStage = defaultStage == 1 ? 2 : 1
                    }
                }
            } else {
                // Keep the active-stage affordance usable while a text field is
                // incomplete; the validation message will request the value.
                dpiCount = count
                let previous = count > 1 ? Int(dpiStages[count - 2]) : nil
                let fallback = previous.map { $0 + 1_000 } ?? 1_000
                dpiStages[count - 1] = String(fallback)
            }
        } else {
            dpiCount = count
        }

        for index in count..<5 {
            dpiStages[index] = ""
        }
        defaultStage = min(max(defaultStage, 1), count)
        shiftStage = min(max(shiftStage, 1), count)
    }
}
