// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import ApplicationServices
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ProfileChoice: Identifiable, Hashable {
    let id: Int
    let sector: String
    var enabled: Bool
    var crcValid: Bool

    var title: String {
        "Profile \(id)\(enabled ? "" : " (disabled)")"
    }
}

struct ButtonRow: Identifiable {
    let id: Int
    let label: String
    let currentRaw: String
    var draftRaw: String
    var draftChoice: String
}

struct OutputPreset: Identifiable, Hashable {
    let id: String
    let label: String
    let raw: String
}

struct ModifierChoice: Identifiable, Hashable {
    let id: UInt8
    let label: String
}

struct KeyboardKeyChoice: Identifiable, Hashable {
    let id: UInt8
    let label: String
}

struct BackupEntry: Identifiable {
    let url: URL
    let modifiedAt: Date
    let size: Int64

    var id: String { url.path }
    var name: String { url.lastPathComponent }
    var isJSON: Bool { url.pathExtension.lowercased() == "json" }
}

struct DeviceChoice: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let connection: String
    let productID: String

    var title: String {
        "\(name) — \(connection)"
    }
}

struct EditableBackup: Codable {
    struct Device: Codable {
        var name: String
        var productID: String
    }

    struct ProfileState: Codable {
        var number: Int
        var enabled: Bool
    }

    struct Button: Codable {
        var number: Int
        var physicalControl: String
        var output: String
        var raw: String
    }

    struct DPI: Codable {
        var stages: [Int]
        var defaultStage: Int
        var shiftStage: Int
    }

    struct Profile: Codable {
        var number: Int
        var sector: String?
        var enabled: Bool
        var buttons: [Button]
        var dpi: DPI?
    }

    var formatVersion: Int
    var createdAt: String
    var device: Device
    var profiles: [ProfileState]
    var profile: Profile
    var exactBinaryBackup: String?
}

private enum EngineError: LocalizedError {
    case unavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The bundled HID++ engine could not be found."
        case .failed(let message):
            return message.isEmpty ? "The HID++ engine failed." : message
        }
    }
}

private enum AppConstants {
    static let engineName = "logitech-onboard"
    static let appSupportDirectory = "LogitechOnboardProfileManager"
    static let defaultsPrefix = "LogitechOnboardProfileManager"
    static let backupExtension = "logiob"
}

private enum EngineRunner {
    static func run(executable: URL, arguments: [String], currentDirectory: URL) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw EngineError.failed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }
}

private struct RefreshSnapshot: Sendable {
    let devices: [DeviceChoice]
    let selectedDeviceIndex: Int?
    let profileText: String?
    let profileError: String?
    let dpiText: String?
    let dpiError: String?
    let selectedProfileNumber: Int?
    let errorMessage: String?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var deviceSummary = "No Logitech HID++ device loaded"
    @Published var status = "Connect a Logitech mouse, then choose Refresh."
    @Published var devices: [DeviceChoice] = []
    @Published var selectedDeviceIndex = 0
    @Published var profiles: [ProfileChoice] = []
    @Published var profileNumber = 1
    @Published var buttons: [ButtonRow] = []
    @Published var dpiStages = ["", "", "", "", ""]
    @Published var dpiCount = 5
    @Published var defaultStage = 3
    @Published var shiftStage = 1
    @Published var dpiDetails = "DPI capabilities have not been read."
    @Published var busy = false
    @Published var backups: [BackupEntry] = []
    @Published var backupDirectoryPath = ""
    @Published var showAdvancedFields = false

    private var keyInputDrafts: [Int: String] = [:]
    private var baselineProfileEnabled: [Int: Bool] = [:]
    private var baselineDPIStages = [String]()
    private var baselineDPICount = 5
    private var baselineDefaultStage = 3
    private var baselineShiftStage = 1
    private var currentDeviceName = ""
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    let modifierChoices: [ModifierChoice] = [
        ModifierChoice(id: 0x01, label: "Ctrl"),
        ModifierChoice(id: 0x02, label: "Shift"),
        ModifierChoice(id: 0x04, label: "Alt"),
        ModifierChoice(id: 0x08, label: "Command")
    ]

    let keyboardKeys: [KeyboardKeyChoice] = {
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
    }()

    var specialKeyboardKeys: [KeyboardKeyChoice] {
        keyboardKeys.filter { key in
            let code = key.id
            return !(0x3A...0x45).contains(code) && !(0x68...0x73).contains(code) &&
                !(0x04...0x1D).contains(code)
        }
    }

    let presets: [OutputPreset] = [
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
        OutputPreset(id: "FFFFFFFF", label: "Disabled", raw: "FFFFFFFF")
    ]

    private var engine: URL? {
        if let bundled = Bundle.main.url(forResource: AppConstants.engineName, withExtension: nil) {
            return bundled
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent("bin/\(AppConstants.engineName)"),
            cwd.appendingPathComponent(AppConstants.engineName)
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private var backupDirectory: URL
    private let defaultBackupDirectory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppConstants.appSupportDirectory, isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        defaultBackupDirectory = base
        let defaults = UserDefaults.standard
        let backupDirectoryKey = "\(AppConstants.defaultsPrefix).backupDirectory"
        let selectedPath = defaults.string(forKey: backupDirectoryKey)
        let selectedDirectory = selectedPath.map { URL(fileURLWithPath: $0) } ?? base
        backupDirectory = selectedDirectory
        backupDirectoryPath = selectedDirectory.path
        let advancedFieldsKey = "\(AppConstants.defaultsPrefix).showAdvancedFields"
        showAdvancedFields = defaults.bool(forKey: advancedFieldsKey)
        try? FileManager.default.createDirectory(at: selectedDirectory, withIntermediateDirectories: true)
        refreshBackups()
        Task { @MainActor in
            refresh()
        }
    }

    var defaultBackupDirectoryPath: String { defaultBackupDirectory.path }

    var hasButtonChanges: Bool {
        buttons.contains { normalize($0.currentRaw) != normalize($0.draftRaw) }
    }

    var hasDPIChanges: Bool {
        dpiCount != baselineDPICount || dpiStages != baselineDPIStages ||
            defaultStage != baselineDefaultStage || shiftStage != baselineShiftStage
    }

    var canApplyDPI: Bool {
        guard (1...5).contains(dpiCount), dpiStages.count == 5 else { return false }
        return dpiStages.prefix(dpiCount).allSatisfy { UInt16($0) != nil }
    }

    var hasProfileChanges: Bool {
        profiles.contains { $0.enabled != (baselineProfileEnabled[$0.id] ?? $0.enabled) }
    }

    var hasPendingChanges: Bool {
        hasButtonChanges || hasDPIChanges || hasProfileChanges
    }

    func refresh() {
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let preferredDeviceIndex = selectedDeviceIndex
        let preferredProfileNumber = profileNumber
        let currentDirectory = backupDirectory

        busy = true
        status = "Reading the mouse…"

        guard let engine else {
            busy = false
            status = EngineError.unavailable.localizedDescription
            return
        }

        refreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.makeRefreshSnapshot(
                    executable: engine,
                    currentDirectory: currentDirectory,
                    preferredDeviceIndex: preferredDeviceIndex,
                    preferredProfileNumber: preferredProfileNumber
                )
            }.value

            guard !Task.isCancelled, let self,
                  self.refreshGeneration == generation else { return }
            self.applyRefreshSnapshot(snapshot)
        }
    }

    func selectDevice(_ index: Int) {
        guard let selected = devices.first(where: { $0.id == index }), selectedDeviceIndex != index else { return }
        selectedDeviceIndex = index
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let preferredProfileNumber = profileNumber
        let currentDirectory = backupDirectory

        busy = true
        currentDeviceName = selected.name
        deviceSummary = selected.title
        status = "Reading \(selected.name)…"

        guard let engine else {
            busy = false
            status = EngineError.unavailable.localizedDescription
            return
        }

        let currentDevices = devices
        refreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.makeProfileSnapshot(
                    executable: engine,
                    currentDirectory: currentDirectory,
                    devices: currentDevices,
                    selectedDeviceIndex: selected.id,
                    preferredProfileNumber: preferredProfileNumber
                )
            }.value

            guard !Task.isCancelled, let self,
                  self.refreshGeneration == generation else { return }
            self.applyRefreshSnapshot(snapshot)
        }
    }

    private func applyRefreshSnapshot(_ snapshot: RefreshSnapshot) {
        defer {
            busy = false
            refreshTask = nil
        }

        if let errorMessage = snapshot.errorMessage {
            devices = []
            deviceSummary = "Unable to access the Logitech HID++ interface"
            status = errorMessage
            return
        }

        devices = snapshot.devices
        guard let selectedIndex = snapshot.selectedDeviceIndex,
              let selected = devices.first(where: { $0.id == selectedIndex }) else {
            selectedDeviceIndex = 0
            currentDeviceName = ""
            deviceSummary = "No editable Logitech mouse found"
            profiles = []
            buttons = []
            status = "No Logitech mouse was found. USB receiver entries are hidden."
            return
        }

        selectedDeviceIndex = selected.id
        currentDeviceName = selected.name
        deviceSummary = selected.title

        guard let profileText = snapshot.profileText else {
            profiles = []
            buttons = []
            dpiDetails = "This device does not expose an editable onboard profile through HID++ 0x8100."
            status = "Connected to \(selected.name), but no compatible onboard profile was found."
            return
        }

        let parsed = parseProfiles(profileText)
        profiles = parsed.choices
        baselineProfileEnabled = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.enabled) })
        if profiles.isEmpty {
            buttons = []
            status = "The mouse was found, but no onboard profiles were readable."
            return
        }
        if let loadedProfile = snapshot.selectedProfileNumber,
           profiles.contains(where: { $0.id == loadedProfile }) {
            profileNumber = loadedProfile
        } else if !profiles.contains(where: { $0.id == profileNumber }) {
            profileNumber = profiles[0].id
        }
        buttons = parsed.rowsByProfile[profileNumber] ?? []
        dpiDetails = ""
        if let dpiText = snapshot.dpiText {
            parseDPI(dpiText)
        } else {
            dpiDetails = snapshot.dpiError ?? "DPI capabilities could not be read."
        }
        status = "Read-only inspection complete. Changes are previewed before writing."
    }

    private nonisolated static func makeRefreshSnapshot(
        executable: URL,
        currentDirectory: URL,
        preferredDeviceIndex: Int,
        preferredProfileNumber: Int
    ) -> RefreshSnapshot {
        do {
            let list = try EngineRunner.run(
                executable: executable,
                arguments: ["list"],
                currentDirectory: currentDirectory
            )
            let discovered = parseDeviceChoices(list)
            guard let selected = discovered.first(where: { $0.id == preferredDeviceIndex }) ?? discovered.first else {
                return RefreshSnapshot(
                    devices: [],
                    selectedDeviceIndex: nil,
                    profileText: nil,
                    profileError: nil,
                    dpiText: nil,
                    dpiError: nil,
                    selectedProfileNumber: nil,
                    errorMessage: nil
                )
            }

            return makeProfileSnapshot(
                executable: executable,
                currentDirectory: currentDirectory,
                devices: discovered,
                selectedDeviceIndex: selected.id,
                preferredProfileNumber: preferredProfileNumber
            )
        } catch {
            return RefreshSnapshot(
                devices: [],
                selectedDeviceIndex: nil,
                profileText: nil,
                profileError: nil,
                dpiText: nil,
                dpiError: nil,
                selectedProfileNumber: nil,
                errorMessage: errorMessage(for: error)
            )
        }
    }

    private nonisolated static func makeProfileSnapshot(
        executable: URL,
        currentDirectory: URL,
        devices: [DeviceChoice],
        selectedDeviceIndex: Int,
        preferredProfileNumber: Int
    ) -> RefreshSnapshot {
        do {
            let profileText = try EngineRunner.run(
                executable: executable,
                arguments: ["--device", String(selectedDeviceIndex), "profiles"],
                currentDirectory: currentDirectory
            )

            let availableProfileNumbers = profileNumbers(in: profileText)
            let selectedProfileNumber = availableProfileNumbers.contains(preferredProfileNumber)
                ? preferredProfileNumber
                : availableProfileNumbers.first
            var dpiText: String?
            var dpiError: String?
            if let selectedProfileNumber {
                do {
                    dpiText = try EngineRunner.run(
                        executable: executable,
                        arguments: [
                            "--device", String(selectedDeviceIndex),
                            "--profile", String(selectedProfileNumber),
                            "dpi"
                        ],
                        currentDirectory: currentDirectory
                    )
                } catch {
                    dpiError = errorMessage(for: error)
                }
            }
            return RefreshSnapshot(
                devices: devices,
                selectedDeviceIndex: selectedDeviceIndex,
                profileText: profileText,
                profileError: nil,
                dpiText: dpiText,
                dpiError: dpiError,
                selectedProfileNumber: selectedProfileNumber,
                errorMessage: nil
            )
        } catch {
            return RefreshSnapshot(
                devices: devices,
                selectedDeviceIndex: selectedDeviceIndex,
                profileText: nil,
                profileError: errorMessage(for: error),
                dpiText: nil,
                dpiError: nil,
                selectedProfileNumber: nil,
                errorMessage: nil
            )
        }
    }

    private nonisolated static func errorMessage(for error: Error) -> String {
        error.localizedDescription
    }

    func openInputMonitoringSettings() {
        CGRequestListenEventAccess()
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
        ]
        for value in candidates {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                status = "Enable Input Monitoring for this app, then return and choose Refresh."
                return
            }
        }
        status = "Open System Settings > Privacy & Security > Input Monitoring, enable this app, then choose Refresh."
    }

    func reloadSelectedProfile() {
        guard !busy, !profiles.isEmpty else { return }
        busy = true
        defer { busy = false }
        reloadSelectedProfileContents()
    }

    private func reloadSelectedProfileContents() {
        do {
            let profileText = try runEngine(["profiles"])
            let parsed = parseProfiles(profileText)
            if !parsed.choices.isEmpty {
                profiles = parsed.choices
                baselineProfileEnabled = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.enabled) })
            }
            buttons = parsed.rowsByProfile[profileNumber] ?? parsed.rowsByProfile.values.first ?? []
            loadDPI()
            status = "Reloaded profile \(profileNumber)."
        } catch {
            status = error.localizedDescription
        }
    }

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
        if let bytes = rawBytes(normalized), bytes[0] == 0x80, bytes[1] == 0x02 {
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

    private func rawBytes(_ raw: String) -> [UInt8]? {
        let normalized = normalize(raw)
        guard normalized.count == 8 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(4)
        var index = normalized.startIndex
        for _ in 0..<4 {
            let next = normalized.index(index, offsetBy: 2)
            guard let byte = UInt8(normalized[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
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

    private func physicalButtonLabel(_ number: Int) -> String {
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

    func applyButtons() {
        guard !busy else { return }
        let changes = buttons.filter { normalize($0.currentRaw) != normalize($0.draftRaw) }
        guard !changes.isEmpty else {
            status = "No button changes to apply."
            return
        }
        busy = true
        defer { busy = false }
        do {
            for button in changes {
                let backup = backupURL(prefix: "profile\(profileNumber)-button\(button.id)")
                let jsonBackup = makeEditableBackup(binaryBackup: backup, useDrafts: false)
                _ = try runEngine([
                    "--profile", String(profileNumber),
                    "--button", String(button.id),
                    "--backup", backup.path,
                    "bind", normalize(button.draftRaw), "--yes"
                ])
                try? writeEditableBackup(jsonBackup, to: jsonURL(for: backup))
            }
            reloadSelectedProfileContents()
            refreshBackups()
            status = "Applied \(changes.count) button change(s); each write was backed up and read back."
        } catch {
            status = error.localizedDescription
        }
    }

    func applyDPI() {
        guard !busy else { return }
        guard canApplyDPI else {
            status = "Enter one to five numeric DPI stages."
            return
        }
        let stages = dpiStages.prefix(dpiCount).joined(separator: ",")
        busy = true
        defer { busy = false }
        do {
            let backup = backupURL(prefix: "profile\(profileNumber)-dpi")
            let jsonBackup = makeEditableBackup(binaryBackup: backup, useDrafts: false)
            _ = try runEngine([
                "--profile", String(profileNumber),
                "--default", String(defaultStage),
                "--shift", String(shiftStage),
                "--backup", backup.path,
                "set-dpi", stages, "--yes"
            ])
            try? writeEditableBackup(jsonBackup, to: jsonURL(for: backup))
            reloadSelectedProfileContents()
            refreshBackups()
            status = "Applied the DPI stages; the profile was backed up and read back."
        } catch {
            status = error.localizedDescription
        }
    }

    func applyAll() {
        guard !busy else { return }
        let buttonChanges = buttons.filter { normalize($0.currentRaw) != normalize($0.draftRaw) }
        let dpiChanged = hasDPIChanges
        let profileChanges = profiles
            .filter { $0.enabled != (baselineProfileEnabled[$0.id] ?? $0.enabled) }
            .sorted { $0.enabled && !$1.enabled }
        guard !buttonChanges.isEmpty || dpiChanged || !profileChanges.isEmpty else {
            status = "No changes to apply."
            return
        }
        guard !dpiChanged || canApplyDPI else {
            status = "Enter one to five numeric DPI stages before saving."
            return
        }
        busy = true
        defer { busy = false }
        do {
            for button in buttonChanges {
                let backup = backupURL(prefix: "profile\(profileNumber)-button\(button.id)")
                let jsonBackup = makeEditableBackup(binaryBackup: backup, useDrafts: false)
                _ = try runEngine([
                    "--profile", String(profileNumber),
                    "--button", String(button.id),
                    "--backup", backup.path,
                    "bind", normalize(button.draftRaw), "--yes"
                ])
                try? writeEditableBackup(jsonBackup, to: jsonURL(for: backup))
            }
            if dpiChanged {
                let backup = backupURL(prefix: "profile\(profileNumber)-dpi")
                let jsonBackup = makeEditableBackup(binaryBackup: backup, useDrafts: false)
                let stages = dpiStages.prefix(dpiCount).joined(separator: ",")
                _ = try runEngine([
                    "--profile", String(profileNumber),
                    "--default", String(defaultStage),
                    "--shift", String(shiftStage),
                    "--backup", backup.path,
                    "set-dpi", stages, "--yes"
                ])
                try? writeEditableBackup(jsonBackup, to: jsonURL(for: backup))
            }
            for profile in profileChanges {
                let backup = backupURL(prefix: "profile-state-\(profile.id)")
                let jsonBackup = makeEditableBackup(binaryBackup: backup, useDrafts: false)
                _ = try runEngine([
                    "--backup", backup.path,
                    "set-profile-state", String(profile.id), profile.enabled ? "enable" : "disable", "--yes"
                ])
                try? writeEditableBackup(jsonBackup, to: jsonURL(for: backup))
            }
            reloadSelectedProfileContents()
            refreshBackups()
            var parts = [String]()
            if !buttonChanges.isEmpty { parts.append("\(buttonChanges.count) button change(s)") }
            if dpiChanged { parts.append("DPI changes") }
            if !profileChanges.isEmpty { parts.append("\(profileChanges.count) profile state change(s)") }
            status = "Applied \(parts.joined(separator: " and ")); each write was backed up and read back."
        } catch {
            status = error.localizedDescription
        }
    }

    func dumpBackup() {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let backup = backupURL(prefix: "profile\(profileNumber)-manual")
            _ = try runEngine(["--profile", String(profileNumber), "dump", backup.path])
            let jsonBackup = makeEditableBackup(binaryBackup: backup, useDrafts: false)
            try? writeEditableBackup(jsonBackup, to: jsonURL(for: backup))
            refreshBackups()
            status = "Saved a read-only profile backup at \(backup.path)."
        } catch {
            status = error.localizedDescription
        }
    }

    func chooseRestoreBackup() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: AppConstants.backupExtension) ?? .data,
            UTType(filenameExtension: "bin") ?? .data
        ]
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseBackupDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where Logitech onboard profile backups are saved."
        panel.prompt = "Use this folder"
        return panel.runModal() == .OK ? panel.url : nil
    }

    func setBackupDirectory(_ url: URL) {
        backupDirectory = url
        backupDirectoryPath = url.path
        UserDefaults.standard.set(url.path, forKey: "\(AppConstants.defaultsPrefix).backupDirectory")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        refreshBackups()
        status = "Backups will be saved in \(url.path)."
    }

    func resetBackupDirectory() {
        setBackupDirectory(defaultBackupDirectory)
    }

    func setShowAdvancedFields(_ show: Bool) {
        showAdvancedFields = show
        UserDefaults.standard.set(show, forKey: "\(AppConstants.defaultsPrefix).showAdvancedFields")
    }

    func refreshBackups() {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        backups = urls
            .filter { [AppConstants.backupExtension, "bin", "json"].contains($0.pathExtension.lowercased()) }
            .compactMap { url in
                guard let values = try? url.resourceValues(forKeys: keys),
                      let modifiedAt = values.contentModificationDate,
                      let fileSize = values.fileSize else { return nil }
                return BackupEntry(url: url, modifiedAt: modifiedAt, size: Int64(fileSize))
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func chooseJSONBackup() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.json]
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseJSONExport() -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "profile\(profileNumber).json"
        panel.message = "Export the selected profile as an editable JSON file."
        return panel.runModal() == .OK ? panel.url : nil
    }

    func exportCurrentJSON(to url: URL) {
        guard !profiles.isEmpty else {
            status = "Read a Logitech profile before exporting JSON."
            return
        }
        do {
            let backup = makeEditableBackup(binaryBackup: nil, useDrafts: true)
            try writeEditableBackup(backup, to: url)
            refreshBackups()
            status = "Exported profile \(profileNumber) to \(url.path)."
        } catch {
            status = "Could not export JSON: \(error.localizedDescription)"
        }
    }

    func loadEditableBackup(_ url: URL) {
        guard !busy else { return }
        guard !profiles.isEmpty else {
            status = "Read a Logitech profile before loading JSON."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let backup = try decoder.decode(EditableBackup.self, from: data)
            guard backup.formatVersion == 1 else {
                status = "Unsupported JSON profile version \(backup.formatVersion)."
                return
            }
            guard backup.profile.number == profileNumber else {
                status = "Select Profile \(backup.profile.number) before loading this JSON file."
                return
            }

            var proposedStates = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.enabled) })
            for state in backup.profiles where proposedStates[state.number] != nil {
                proposedStates[state.number] = state.enabled
            }
            if proposedStates[backup.profile.number] != nil {
                proposedStates[backup.profile.number] = backup.profile.enabled
            }
            guard proposedStates.values.contains(true) else {
                status = "The JSON would disable every onboard profile. At least one must remain enabled."
                return
            }

            var proposedButtons: [(Int, String)] = []
            for button in backup.profile.buttons {
                guard let index = buttons.firstIndex(where: { $0.id == button.number }),
                      let raw = jsonRaw(for: button) else {
                    status = "JSON button \(button.number) has no recognized output or 8-digit raw record."
                    return
                }
                proposedButtons.append((index, raw))
            }

            var proposedDPI: EditableBackup.DPI?
            if let dpi = backup.profile.dpi {
                guard (1...5).contains(dpi.stages.count),
                      dpi.stages.allSatisfy({ (100...65535).contains($0) }),
                      dpi.stages == dpi.stages.sorted(),
                      Set(dpi.stages).count == dpi.stages.count,
                      (1...dpi.stages.count).contains(dpi.defaultStage),
                      (1...dpi.stages.count).contains(dpi.shiftStage) else {
                    status = "The JSON DPI values or stage indexes are invalid."
                    return
                }
                proposedDPI = dpi
            }

            for profile in profiles {
                if let enabled = proposedStates[profile.id],
                   let index = self.profiles.firstIndex(where: { $0.id == profile.id }) {
                    self.profiles[index].enabled = enabled
                }
            }
            for (index, raw) in proposedButtons {
                setRaw(buttonIndex: index, raw: raw)
            }
            if let dpi = proposedDPI {
                dpiCount = dpi.stages.count
                dpiStages = dpi.stages.map(String.init) + Array(repeating: "", count: 5 - dpi.stages.count)
                defaultStage = dpi.defaultStage
                shiftStage = dpi.shiftStage
            }

            let sourceWarning = backup.device.productID.isEmpty || devices.first(where: { $0.id == selectedDeviceIndex })?.productID == backup.device.productID
                ? ""
                : " The source device differs, so review the outputs before saving."
            status = "Loaded \(url.lastPathComponent) into the editor. Review it, then choose Save to mouse.\(sourceWarning)"
        } catch {
            status = "Could not load JSON: \(error.localizedDescription)"
        }
    }

    private func jsonURL(for binaryURL: URL) -> URL {
        binaryURL.deletingPathExtension().appendingPathExtension("json")
    }

    private func writeEditableBackup(_ backup: EditableBackup, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        try data.write(to: url, options: .atomic)
    }

    private func makeEditableBackup(binaryBackup: URL?, useDrafts: Bool) -> EditableBackup {
        let selectedDevice = devices.first(where: { $0.id == selectedDeviceIndex })
        let selectedProfile = profiles.first(where: { $0.id == profileNumber })
        let profileButtons = buttons.map { button in
            let raw = normalize(useDrafts ? button.draftRaw : button.currentRaw)
            return EditableBackup.Button(
                number: button.id,
                physicalControl: button.label,
                output: outputLabel(for: raw),
                raw: raw
            )
        }
        let dpi: EditableBackup.DPI?
        if useDrafts {
            let values = dpiStages.prefix(dpiCount).compactMap(Int.init)
            dpi = values.count == dpiCount ? EditableBackup.DPI(stages: values, defaultStage: defaultStage, shiftStage: shiftStage) : nil
        } else {
            let values = baselineDPIStages.prefix(baselineDPICount).compactMap(Int.init)
            dpi = values.count == baselineDPICount ? EditableBackup.DPI(stages: values, defaultStage: baselineDefaultStage, shiftStage: baselineShiftStage) : nil
        }
        let states = profiles.map { profile in
            EditableBackup.ProfileState(
                number: profile.id,
                enabled: useDrafts ? profile.enabled : (baselineProfileEnabled[profile.id] ?? profile.enabled)
            )
        }
        return EditableBackup(
            formatVersion: 1,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            device: EditableBackup.Device(
                name: selectedDevice?.name ?? currentDeviceName,
                productID: selectedDevice?.productID ?? ""
            ),
            profiles: states,
            profile: EditableBackup.Profile(
                number: profileNumber,
                sector: selectedProfile?.sector,
                enabled: useDrafts ? (selectedProfile?.enabled ?? false) : (baselineProfileEnabled[profileNumber] ?? false),
                buttons: profileButtons,
                dpi: dpi
            ),
            exactBinaryBackup: binaryBackup?.lastPathComponent
        )
    }

    private func outputLabel(for raw: String) -> String {
        let preset = presetLabel(for: raw)
        if preset != "Custom raw output" {
            return preset
        }
        guard let bytes = rawBytes(raw), bytes[0] == 0x80, bytes[1] == 0x02, bytes[3] != 0 else {
            return "Custom"
        }
        var modifiers: [String] = []
        for modifier in modifierChoices where (bytes[2] & modifier.id) != 0 {
            modifiers.append(modifier.label)
        }
        let key = keyboardKeyLabel(bytes[3])
        return modifiers.isEmpty ? key : "\(modifiers.joined(separator: " + ")) + \(key)"
    }

    private func jsonRaw(for button: EditableBackup.Button) -> String? {
        let output = button.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let preset = presets.first(where: { $0.label.lowercased() == output }) {
            return preset.raw
        }
        let compact = output.replacingOccurrences(of: " ", with: "")
        if compact == "alt+tab" || compact == "leftalt+tab" {
            return "8002042B"
        }
        let raw = normalize(button.raw)
        return rawBytes(raw) != nil ? raw : nil
    }

    func restore(_ url: URL) {
        guard !busy else { return }
        busy = true
        do {
            _ = try runEngine(["restore", url.path, "--yes"])
            refreshBackups()
            busy = false
            refresh()
            status = "Restored and verified \(url.lastPathComponent)."
        } catch {
            busy = false
            status = error.localizedDescription
        }
    }

    func presetLabel(for raw: String) -> String {
        presets.first(where: { normalize($0.raw) == normalize(raw) })?.label ?? "Custom raw output"
    }

    private func loadDPI() {
        dpiDetails = ""
        do {
            let dpiText = try runEngine(["--profile", String(profileNumber), "dpi"])
            parseDPI(dpiText)
        } catch {
            dpiDetails = error.localizedDescription
        }
    }

    private func runEngine(_ arguments: [String]) throws -> String {
        try runEngine(arguments, selectingDevice: true)
    }

    private func runEngine(_ arguments: [String], selectingDevice: Bool) throws -> String {
        guard let engine else { throw EngineError.unavailable }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = engine
        process.arguments = selectingDevice && !devices.isEmpty
            ? ["--device", String(selectedDeviceIndex)] + arguments
            : arguments
        process.currentDirectoryURL = backupDirectory
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw EngineError.failed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private func backupURL(prefix: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return backupDirectory.appendingPathComponent("\(prefix)-\(formatter.string(from: Date())).\(AppConstants.backupExtension)")
    }

    private func normalize(_ raw: String) -> String {
        raw.filter { !$0.isWhitespace }.uppercased()
    }

    private nonisolated static func parseDeviceChoices(_ text: String) -> [DeviceChoice] {
        let pattern = try! NSRegularExpression(pattern: #"^\[(\d+)\]\s+(.+?)\s+\(HID\+\+\s+[0-9.]+,\s+product\s+(0x[0-9A-Fa-f]+)\)$"#)
        var result: [DeviceChoice] = []
        for line in text.split(separator: "\n").map(String.init) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = pattern.firstMatch(in: line, range: range),
                  let id = Int(capture(match, in: line, index: 1)) else { continue }
            let descriptor = capture(match, in: line, index: 2)
            let pieces = descriptor.components(separatedBy: "  ").filter { !$0.isEmpty }
            let connection = pieces.first ?? "Logitech HID++"
            let name = pieces.dropFirst().joined(separator: " ").isEmpty
                ? descriptor
                : pieces.dropFirst().joined(separator: " ")
            result.append(DeviceChoice(
                id: id,
                name: name,
                connection: connection,
                productID: capture(match, in: line, index: 3)
            ))
        }
        return result.sorted { $0.id < $1.id }
    }

    private nonisolated static func profileNumbers(in text: String) -> [Int] {
        let pattern = try! NSRegularExpression(pattern: #"^Profile\s+(\d+)\s+\("#)
        var result: [Int] = []
        for line in text.split(separator: "\n").map(String.init) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = pattern.firstMatch(in: line, range: range),
                  let number = Int(capture(match, in: line, index: 1)) else { continue }
            result.append(number)
        }
        return result
    }

    private func parseProfiles(_ text: String) -> (choices: [ProfileChoice], rowsByProfile: [Int: [ButtonRow]]) {
        let profilePattern = try! NSRegularExpression(pattern: #"^Profile\s+(\d+)\s+\(sector\s+(0x[0-9A-Fa-f]+),\s+enabled=(yes|no)\)"#)
        let buttonPattern = try! NSRegularExpression(pattern: #"^\s*button\s+(\d+):\s*(.*?)\s*\[([0-9A-Fa-f ]+)\]"#)
        var choices: [ProfileChoice] = []
        var rows: [Int: [ButtonRow]] = [:]
        var currentProfile: Int?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let full = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = profilePattern.firstMatch(in: line, range: full),
               let id = Int(capture(match, in: line, index: 1)) {
                let sector = capture(match, in: line, index: 2)
                let enabledText = capture(match, in: line, index: 3)
                currentProfile = id
                choices.append(ProfileChoice(
                    id: id,
                    sector: sector,
                    enabled: enabledText == "yes",
                    crcValid: false
                ))
                rows[id] = []
                continue
            }
            if let profile = currentProfile,
               line.trimmingCharacters(in: .whitespaces) == "CRC: OK",
               let index = choices.firstIndex(where: { $0.id == profile }) {
                choices[index].crcValid = true
                continue
            }
            guard let profile = currentProfile,
                  let match = buttonPattern.firstMatch(in: line, range: full),
                  let number = Int(capture(match, in: line, index: 1)) else { continue }
            let rawBytes = capture(match, in: line, index: 3)
            let raw = normalize(rawBytes)
            rows[profile, default: []].append(ButtonRow(
                id: number,
                label: physicalButtonLabel(number),
                currentRaw: raw,
                draftRaw: raw,
                draftChoice: presets.contains(where: { normalize($0.raw) == raw }) ? raw : "custom"
            ))
        }
        return (choices, rows)
    }

    private func parseDPI(_ text: String) {
        let pattern = try! NSRegularExpression(pattern: #"(?:Onboard profile \d+ )?DPI stages:\s*([0-9, ]+)\s*\(default\s+(\d+),\s*shift\s+(\d+)\)"#)
        for line in text.split(separator: "\n").map(String.init) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = pattern.firstMatch(in: line, range: range) {
                let stageText = capture(match, in: line, index: 1)
                let defaultText = capture(match, in: line, index: 2)
                let shiftText = capture(match, in: line, index: 3)
                let values = stageText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if (1...5).contains(values.count) {
                    dpiCount = values.count
                    dpiStages = values + Array(repeating: "", count: 5 - values.count)
                    defaultStage = Int(defaultText) ?? defaultStage
                    shiftStage = Int(shiftText) ?? shiftStage
                    baselineDPICount = dpiCount
                    baselineDPIStages = dpiStages
                    baselineDefaultStage = defaultStage
                    baselineShiftStage = shiftStage
                }
            }
            if line.hasPrefix("Supported DPI:") || line.hasPrefix("Current sensor") {
                dpiDetails = [dpiDetails, line].filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }
    }

    private nonisolated static func capture(_ match: NSTextCheckingResult, in text: String, index: Int) -> String {
        let range = match.range(at: index)
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange])
    }

    private func capture(_ match: NSTextCheckingResult, in text: String, index: Int) -> String {
        Self.capture(match, in: text, index: index)
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var confirmRestore = false
    @State private var restoreURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            TabView {
                Group {
                    if model.profiles.isEmpty {
                        emptyState
                    } else {
                        buttonsPane
                    }
                }
                .tabItem { Label("Buttons", systemImage: "cursorarrow.click") }
                backupsPane
                    .tabItem { Label("Backups", systemImage: "archivebox") }
                settingsPane
                .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            Divider()
            HStack(alignment: .top) {
                Image(systemName: "info.circle")
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 960, minHeight: 520)
        .onChange(of: model.profileNumber) { _ in
            model.reloadSelectedProfile()
        }
        .alert("Restore this backup?", isPresented: $confirmRestore) {
            Button("Cancel", role: .cancel) { restoreURL = nil }
            Button("Restore and verify", role: .destructive) {
                if let restoreURL { model.restore(restoreURL) }
                restoreURL = nil
            }
        } message: {
            Text(restoreURL?.lastPathComponent ?? "Selected backup")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Logitech Onboard Profiles")
                    .font(.title2.weight(.semibold))
                Text(model.deviceSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !model.devices.isEmpty {
                Picker("Device", selection: Binding(
                    get: { model.selectedDeviceIndex },
                    set: { model.selectDevice($0) })) {
                    ForEach(model.devices) { device in
                        Text(device.title).tag(device.id)
                    }
                }
                .frame(width: 310)
            }
            if !model.profiles.isEmpty {
                Picker("Profile", selection: $model.profileNumber) {
                    ForEach(model.profiles) { profile in
                        Text(profile.title).tag(profile.id)
                    }
                }
                .frame(width: 180)
            }
            Button("Refresh", action: model.refresh)
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.busy)
            if model.busy { ProgressView().controlSize(.small) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "computermouse")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(model.devices.isEmpty ? "No editable Logitech mouse detected" : "No editable onboard profile")
                .font(.title3.weight(.medium))
            Text(model.devices.isEmpty
                 ? "The app lists Logitech mice and hides USB receiver entries. macOS may also be blocking access even when the mouse is connected."
                 : "\(model.deviceSummary) is connected, but it does not expose an onboard profile format this app can edit.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560)
            HStack {
                Button("Open Input Monitoring Settings", action: model.openInputMonitoringSettings)
                Button("Refresh", action: model.refresh)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var buttonsPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Profiles, buttons and DPI")
                    .font(.headline)
                Spacer()
                Button("Revert edits") { model.reloadSelectedProfile() }
                Button("Save to mouse", action: model.applyAll)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.hasPendingChanges || model.busy)
            }
            Text("Modify profiles, button outputs and DPI together, then save once. The original data is backed up automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Choose a standard output or use Custom for a keyboard chord. Raw HID++ fields are available in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    profilesEditor
                    Divider()
                    VStack(spacing: 8) {
                        ForEach(model.buttons.indices, id: \.self) { index in
                            buttonRow(index)
                        }
                    }
                    Divider()
                    dpiEditor
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.top, 4)
    }

    private func buttonRow(_ index: Int) -> some View {
        let button = model.buttons[index]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Button \(button.id)")
                    .font(.body.weight(.medium))
                    .frame(width: 78, alignment: .leading)
                Text(button.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 210, alignment: .leading)
                    .lineLimit(1)
                Picker("", selection: Binding(
                    get: { model.buttons[index].draftChoice },
                    set: { model.selectOutput(buttonIndex: index, choice: $0) })) {
                    ForEach(model.presets) { preset in
                        Text(preset.label).tag(preset.raw)
                    }
                    Text("Custom").tag("custom")
                }
                .labelsHidden()
                .frame(width: 215)
                if model.showAdvancedFields {
                    TextField("8 hex digits", text: Binding(
                        get: { model.buttons[index].draftRaw },
                        set: { model.setRaw(buttonIndex: index, raw: $0) }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 122)
                }
                Spacer()
            }
            if model.buttons[index].draftChoice == "custom" {
                keyboardChordEditor(index)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
    }

    private var profilesEditor: some View {
        GroupBox("Onboard profiles") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Disable a profile to keep it out of the mouse’s profile cycle. At least one profile must remain enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text("Enable Profile(s):")
                        .font(.callout.weight(.medium))
                    ForEach(model.profiles) { profile in
                        profileEnableControl(profile)
                    }
                    Spacer()
                }
                if model.showAdvancedFields {
                    HStack(spacing: 12) {
                        Text("Sectors:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(model.profiles) { profile in
                            Text("Profile \(profile.id): \(profile.sector)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    private func profileEnableControl(_ profile: ProfileChoice) -> some View {
        let profileID = profile.id
        let label = String(profileID)
        let crcLabel = profile.crcValid ? "" : "Profile invalid"
        let crcColor: Color = profile.crcValid ? .secondary : .red
        let helpText = "Profile \(label) is \(profile.crcValid ? "CRC valid" : "CRC invalid")"
        let enabled = Binding<Bool>(
            get: { model.profileEnabled(profileID) },
            set: { model.setProfileEnabled(profileID: profileID, enabled: $0) }
        )
        return HStack(spacing: 4) {
            Text(label)
            Toggle("", isOn: enabled)
                .labelsHidden()
                .toggleStyle(.checkbox)
            Text(crcLabel)
                .font(.caption)
                .foregroundStyle(crcColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            profileID == model.profileNumber
                ? Color.accentColor.opacity(0.12)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .help(helpText)
    }

    private func keyboardChordEditor(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Text("Custom")
                .font(.caption.weight(.medium))
                .frame(width: 78, alignment: .leading)
            ForEach(model.modifierChoices) { modifier in
                Toggle(modifier.label, isOn: Binding(
                    get: { model.isModifierEnabled(buttonIndex: index, bit: modifier.id) },
                    set: { model.setModifier(buttonIndex: index, bit: modifier.id, enabled: $0) }))
                    .toggleStyle(.checkbox)
                    .disabled(!model.isKeyboardRecord(buttonIndex: index))
            }
            TextField("Key name", text: Binding(
                get: { model.keyboardKeyText(buttonIndex: index) },
                set: { model.setKeyboardKeyText(buttonIndex: index, text: $0) }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
            Text("F key")
                .font(.caption)
            Picker("", selection: Binding(
                get: { model.functionKeyChoice(buttonIndex: index) },
                set: { model.setFunctionKey(buttonIndex: index, number: $0) })) {
                Text("None").tag(0)
                ForEach(1...24, id: \.self) { number in
                    Text("F\(number)").tag(number)
                }
            }
            .labelsHidden()
            .frame(width: 92)
            Text("Special")
                .font(.caption)
            Picker("", selection: Binding(
                get: { model.specialKeyChoice(buttonIndex: index) },
                set: { model.setSpecialKey(buttonIndex: index, key: $0) })) {
                Text("None").tag(0)
                ForEach(model.specialKeyboardKeys) { key in
                    Text(key.label).tag(Int(key.id))
                }
            }
            .labelsHidden()
            .frame(width: 142)
        }
        .padding(.leading, 0)
        .help("Type a key name such as A or F13, choose an F key or special key, and add modifiers with the checkboxes.")
    }

    private var dpiEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Onboard DPI stages")
                    .font(.headline)
            }
            Text("Choose one to five active stages for the selected profile. Unused slots are cleared.")
                .font(.caption)
                .foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Picker("Active stages", selection: Binding(
                            get: { model.dpiCount },
                            set: { model.setDPIStageCount($0) })) {
                            ForEach(1...5, id: \.self) { count in
                                Text("\(count) of 5").tag(count)
                            }
                        }
                        Text("of 5 stages active")
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        ForEach(0..<model.dpiCount, id: \.self) { index in
                            VStack(spacing: 4) {
                                Text("Stage \(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("DPI", text: Binding(
                                    get: { model.dpiStages[index] },
                                    set: { model.dpiStages[index] = $0.filter { $0.isNumber } }))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 92)
                            }
                        }
                    }
                    HStack(spacing: 14) {
                        Picker("Default stage", selection: $model.defaultStage) {
                            ForEach(1...model.dpiCount, id: \.self) { Text("Stage \($0)").tag($0) }
                        }
                        Picker("DPI-shift stage", selection: $model.shiftStage) {
                            ForEach(1...model.dpiCount, id: \.self) { Text("Stage \($0)").tag($0) }
                        }
                    }
                }
                .padding(4)
            }
            Text(model.dpiDetails)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var backupsPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Backups")
                .font(.headline)
            Text("The app saves an exact binary copy before every mouse write. It also creates an editable JSON profile beside it. JSON loads into the editor; Save to mouse is the step that writes to the device.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Save selected profile backup") { model.dumpBackup() }
                Button("Export JSON…") {
                    if let url = model.chooseJSONExport() {
                        model.exportCurrentJSON(to: url)
                    }
                }
                Button("Import JSON…") {
                    if let url = model.chooseJSONBackup() {
                        model.loadEditableBackup(url)
                    }
                }
                Button("Choose another backup…") {
                    restoreURL = model.chooseRestoreBackup()
                    confirmRestore = restoreURL != nil
                }
                Button("Refresh list", action: model.refreshBackups)
            }
            GroupBox("Available backups") {
                if model.backups.isEmpty {
                    Text("No backups in \(model.backupDirectoryPath).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                } else {
                    List {
                        ForEach(model.backups) { backup in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(backup.name)
                                        .font(.callout)
                                        .lineLimit(1)
                                    Text("\(backup.isJSON ? "Editable JSON" : "Exact binary") | \(backup.modifiedAt.formatted(date: .abbreviated, time: .shortened)) | \(ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if backup.isJSON {
                                    Button("Load") {
                                        model.loadEditableBackup(backup.url)
                                    }
                                } else {
                                    Button("Restore") {
                                        restoreURL = backup.url
                                        confirmRestore = true
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 120, maxHeight: 250)
                }
            }
            Text("Quit G HUB and other mouse remappers while saving. Re-enable them after verifying the onboard behavior.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var settingsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
            GroupBox("Backups") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backup folder")
                        .font(.callout.weight(.medium))
                    Text(model.backupDirectoryPath)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    HStack {
                        Button("Choose folder…") {
                            if let folder = model.chooseBackupDirectory() {
                                model.setBackupDirectory(folder)
                            }
                        }
                        Button("Use default") { model.resetBackupDirectory() }
                            .disabled(model.backupDirectoryPath == model.defaultBackupDirectoryPath)
                    }
                }
                .padding(4)
            }
            GroupBox("Advanced display") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Show raw HID++ fields", isOn: Binding(
                        get: { model.showAdvancedFields },
                        set: { model.setShowAdvancedFields($0) }))
                        .toggleStyle(.checkbox)
                    Text("Shows the 8-digit button records and profile sector numbers. Leave this off for the normal editing view.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }
            Spacer()
        }
        .padding(.top, 4)
    }
}

@main
struct LogitechOnboardProfileManagerApp: App {
    var body: some Scene {
        WindowGroup("Logitech Onboard Profile Manager") {
            ContentView()
        }
    }
}
