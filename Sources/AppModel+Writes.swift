// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
extension AppModel {
    func applyButtons() {
        guard !busy else { return }
        guard currentMouseProfile.profileIO.canSave else {
            status = "\(currentMouseProfile.name) is cataloged as read-only for onboard profile writes."
            return
        }
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
        guard currentMouseProfile.profileIO.canSave else {
            status = "\(currentMouseProfile.name) is cataloged as read-only for onboard profile writes."
            return
        }
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
        guard currentMouseProfile.profileIO.canSave else {
            status = "\(currentMouseProfile.name) is cataloged as read-only for onboard profile writes."
            return
        }
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
        let key = keyboardKeys.first(where: { $0.id == bytes[3] })?.label ?? String(format: "0x%02X", bytes[3])
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
}
