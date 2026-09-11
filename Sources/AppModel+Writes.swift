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
        executeBatchSave(buttonChanges: changes, dpiChanged: false, profileChanges: [])
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
        executeBatchSave(buttonChanges: [], dpiChanged: true, profileChanges: [])
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
        executeBatchSave(buttonChanges: buttonChanges, dpiChanged: dpiChanged, profileChanges: profileChanges)
    }

    private func executeBatchSave(
        buttonChanges: [ButtonRow],
        dpiChanged: Bool,
        profileChanges: [ProfileChoice]
    ) {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let operationID = saveOperationID()
        var arguments = [
            "--profile", String(profileNumber),
            "--backup-directory", backupDirectory.path,
            "--operation-id", operationID,
            "apply"
        ]
        arguments += buttonChanges.flatMap { ["--button-change", "\($0.id):\(normalize($0.draftRaw))"] }
        if dpiChanged {
            arguments += [
                "--dpi", dpiStages.prefix(dpiCount).joined(separator: ","),
                "--default", String(defaultStage),
                "--shift", String(shiftStage)
            ]
        }
        arguments += profileChanges.flatMap {
            ["--profile-state-change", "\($0.id):\($0.enabled ? "enable" : "disable")"]
        }
        do {
            let output = try runEngine(arguments + ["--yes"])
            recoveryBackups.removeAll()
            recoveryDeviceKey = nil
            reloadSelectedProfileContents()
            refreshBackups()
            let verified = output.components(separatedBy: "\n")
                .filter { $0.hasPrefix("Verified sector ") }
                .count
            status = "Save operation \(operationID) complete: wrote \(verified) sector(s); each was backed up before writing and verified by exact read-back."
        } catch {
            let details = error.localizedDescription
            recoveryBackups = batchRecoveryBackups(from: details)
            recoveryDeviceKey = recoveryBackups.isEmpty
                ? nil
                : devices.first(where: { $0.id == selectedDeviceIndex })?.deviceKey
            let summary = batchFailureSummary(from: details)
            status = recoveryBackups.isEmpty
                ? details
                : "Save operation \(operationID) failed.\n\(summary)\nUse ‘Restore backups from this save’ to recover the pre-save sectors."
        }
    }

    func restoreLastSaveBackups() {
        guard !busy, !recoveryBackups.isEmpty else { return }
        guard recoveryDeviceKey == devices.first(where: { $0.id == selectedDeviceIndex })?.deviceKey else {
            recoveryBackups.removeAll()
            recoveryDeviceKey = nil
            status = "Recovery backups belong to a different selected mouse. Choose the original mouse before restoring them."
            return
        }
        let candidates = recoveryBackups.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !candidates.isEmpty else {
            recoveryBackups.removeAll()
            recoveryDeviceKey = nil
            status = "The backups from the failed save are no longer available."
            return
        }
        busy = true
        defer { busy = false }
        var restored = 0
        do {
            for backup in candidates {
                _ = try runEngine(["restore", backup.path, "--yes"])
                restored += 1
            }
            recoveryBackups.removeAll()
            recoveryDeviceKey = nil
            refreshBackups()
            refresh()
            status = "Restored and verified \(restored) sector backup(s) from the failed save operation."
        } catch {
            let remaining = Array(candidates.dropFirst(restored))
            recoveryBackups = remaining
            status = "Restored \(restored) sector backup(s), but recovery stopped: \(error.localizedDescription)"
        }
    }

    private func saveOperationID() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
        return "save-\(formatter.string(from: Date()))-\(suffix)"
    }

    private func batchRecoveryBackups(from message: String) -> [URL] {
        var result: [URL] = []
        for line in message.components(separatedBy: "\n") where line.hasPrefix("Backup saved: ") {
            let value = String(line.dropFirst("Backup saved: ".count))
            let path = value.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !path.isEmpty else { continue }
            let url = URL(fileURLWithPath: path)
            if !result.contains(url) { result.append(url) }
        }
        return result
    }

    private func batchFailureSummary(from message: String) -> String {
        let lines = message.components(separatedBy: "\n").filter { line in
            line.hasPrefix("Save operation") || line.hasPrefix("Preflight") ||
            line.hasPrefix("Planned ") || line.hasPrefix("Backup saved: ") ||
            line.hasPrefix("Writing ") || line.hasPrefix("Verified sector ") ||
            line.contains("was not verified") || line.contains("stopped before any sector write")
        }
        return lines.isEmpty ? message : lines.joined(separator: "\n")
    }

    func dumpBackup() {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let backup = backupURL(prefix: "profile\(profileNumber)-manual")
            _ = try runEngine(["--profile", String(profileNumber), "dump", backup.path])
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
