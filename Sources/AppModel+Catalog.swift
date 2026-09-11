// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

extension AppModel {
    func loadingButtonRows() -> [ButtonRow] {
        currentMouseProfile.buttons.map { button in
            let raw = stockRawAssignment(for: button)
            let choice = presets.contains { normalize($0.raw) == raw } ? raw : "custom"
            return ButtonRow(
                id: button.number,
                label: button.label,
                currentRaw: raw,
                draftRaw: raw,
                draftChoice: choice
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
        if description.contains("tilt left") || description.contains("scroll left") { return "90010000" }
        if description.contains("tilt right") || description.contains("scroll right") { return "90020000" }
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
            ModifierChoice(id: 0x08, label: "Command")
        ]
    }

    var keyboardKeys: [KeyboardKeyChoice] {
        var choices = [
            KeyboardKeyChoice(id: 0x2A, label: "Backspace"),
            KeyboardKeyChoice(id: 0x2B, label: "Tab"),
            KeyboardKeyChoice(id: 0x28, label: "Enter"),
            KeyboardKeyChoice(id: 0x29, label: "Escape"),
            KeyboardKeyChoice(id: 0x2C, label: "Space"),
            KeyboardKeyChoice(id: 0x49, label: "Insert"),
            KeyboardKeyChoice(id: 0x4A, label: "Home"),
            KeyboardKeyChoice(id: 0x4B, label: "Page Up"),
            KeyboardKeyChoice(id: 0x4C, label: "Delete"),
            KeyboardKeyChoice(id: 0x4D, label: "End"),
            KeyboardKeyChoice(id: 0x4E, label: "Page Down"),
            KeyboardKeyChoice(id: 0x4F, label: "Right Arrow"),
            KeyboardKeyChoice(id: 0x50, label: "Left Arrow"),
            KeyboardKeyChoice(id: 0x51, label: "Down Arrow"),
            KeyboardKeyChoice(id: 0x52, label: "Up Arrow")
        ]
        for code in 0x3A...0x45 {
            choices.append(KeyboardKeyChoice(id: UInt8(code), label: "F\(code - 0x39)"))
        }
        for code in 0x68...0x73 {
            choices.append(KeyboardKeyChoice(id: UInt8(code), label: "F\(code - 0x5B)"))
        }
        for (offset, letter) in Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").enumerated() {
            choices.append(KeyboardKeyChoice(id: UInt8(0x04 + offset), label: String(letter)))
        }
        return choices
    }

    var specialKeyboardKeys: [KeyboardKeyChoice] {
        keyboardKeys.filter { key in
            let code = key.id
            return !(0x3A...0x45).contains(code) && !(0x68...0x73).contains(code) &&
                !(0x04...0x1D).contains(code)
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
