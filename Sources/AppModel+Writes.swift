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
        let changes = allButtonRowsForSave().filter { normalize($0.currentRaw) != normalize($0.draftRaw) }
        guard !changes.isEmpty else {
            status = "No button changes to apply."
            return
        }
        guard validatePrimaryClickBeforeWrite() else { return }
        executeBatchSave(buttonChanges: changes, dpiChanged: false, profileChanges: [])
    }

    func applyDPI() {
        guard !busy else { return }
        guard canEditOnboardDPI else {
            status = "Onboard DPI editing is unavailable for this legacy profile path."
            return
        }
        guard currentMouseProfile.profileIO.canSave else {
            status = "\(currentMouseProfile.name) is cataloged as read-only for onboard profile writes."
            return
        }
        guard canApplyDPI else {
            status = "Enter one to five numeric DPI stages."
            return
        }
        guard validatePrimaryClickBeforeWrite() else { return }
        executeBatchSave(buttonChanges: [], dpiChanged: true, profileChanges: [])
    }

    func applyAll() {
        guard !busy else { return }
        guard currentMouseProfile.profileIO.canSave else {
            status = "\(currentMouseProfile.name) is cataloged as read-only for onboard profile writes."
            return
        }
        let buttonChanges = allButtonRowsForSave().filter { normalize($0.currentRaw) != normalize($0.draftRaw) }
        let dpiChanged = hasDPIChanges
        let rgbChanges = rgbZones.filter { $0.current != $0.draft }
        let profileChanges = profiles
            .filter { $0.enabled != (baselineProfileEnabled[$0.id] ?? $0.enabled) }
            .sorted { $0.enabled && !$1.enabled }
        if !canEditOnboardDPI && dpiChanged {
            status = "Onboard DPI editing is unavailable for this legacy profile path."
            return
        }
        if !canEditProfileState && !profileChanges.isEmpty {
            status = "Profile enable-state editing is unavailable for this legacy profile path."
            return
        }
        guard !buttonChanges.isEmpty || dpiChanged || !rgbChanges.isEmpty || !profileChanges.isEmpty else {
            status = "No changes to apply."
            return
        }
        guard !dpiChanged || canApplyDPI else {
            status = "Enter one to five numeric DPI stages before saving."
            return
        }
        guard validatePrimaryClickBeforeWrite() else { return }
        executeBatchSave(buttonChanges: buttonChanges, dpiChanged: dpiChanged,
                         rgbChanges: rgbChanges, profileChanges: profileChanges)
    }

    private func executeBatchSave(
        buttonChanges: [ButtonRow],
        dpiChanged: Bool,
        rgbChanges: [RGBZoneState] = [],
        profileChanges: [ProfileChoice]
    ) {
        guard !busy else { return }
        guard validatePrimaryClickBeforeWrite() else { return }
        busy = true
        defer { busy = false }
        let operationID = saveOperationID()
        let operationBackupDirectory = mouseBackupDirectory()
        try? FileManager.default.createDirectory(
            at: operationBackupDirectory,
            withIntermediateDirectories: true
        )
        var arguments = [
            "--profile", String(profileNumber),
            "--backup-directory", operationBackupDirectory.path,
            "--operation-id", operationID,
            "apply"
        ]
        arguments += buttonChanges.flatMap {
            let prefix = $0.layer == .gShift ? "gshift:" : "normal:"
            return ["--button-change", "\(prefix)\($0.id):\(normalize($0.draftRaw))"]
        }
        if dpiChanged {
            arguments += [
                "--dpi", dpiStages.prefix(dpiCount).joined(separator: ","),
                "--default", String(defaultStage),
                "--shift", String(shiftStage)
            ]
        }
        arguments += rgbChanges.map { ["--rgb-change", "\($0.id + 1):\($0.draft.bareHex)"] }.flatMap { $0 }
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
            let liveDPI = output.components(separatedBy: "\n")
                .first { $0.hasPrefix("Live default DPI:") }
            let liveSuffix = liveDPI.map { " \($0)" } ?? ""
            let rgbSuffix = rgbChanges.isEmpty ? "" : " RGB colors were read back from the profile summary."
            status = "Save operation \(operationID) complete: wrote \(verified) sector(s); each was backed up before writing and verified by exact read-back.\(rgbSuffix)\(liveSuffix)"
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

    var primaryClickValidationMessage: String? {
        let runtimeMouseName = devices.first(where: { $0.id == selectedDeviceIndex })?.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mouseName = runtimeMouseName?.isEmpty == false
            ? runtimeMouseName!
            : currentDeviceName
        let normalButtonRaws = allButtonRowsForSave()
            .filter { $0.layer == .normal }
            .map(\.draftRaw)
        let gShiftButtonRaws = allButtonRowsForSave()
            .filter { $0.layer == .gShift }
            .map(\.draftRaw)
        if let message = ProfileWriteValidation.inaccessibleGShiftPrimaryClickMessage(
            profileNumber: profileNumber,
            profileName: mouseName,
            normalButtonRaws: normalButtonRaws,
            gShiftButtonRaws: gShiftButtonRaws
        ) {
            return message
        }
        return ProfileWriteValidation.missingPrimaryClickMessage(
            profileNumber: profileNumber,
            profileName: mouseName,
            buttonRaws: normalButtonRaws
        )
    }

    private func validatePrimaryClickBeforeWrite() -> Bool {
        guard let message = primaryClickValidationMessage else { return true }
        status = message
        return false
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
                _ = try runEngine(BackupStorage.restoreArguments(for: backup))
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
        uniqueBackupStem(prefix: "profile-\(profileNumber)-save")
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
            let backup = backupURL(prefix: "profile-\(profileNumber)-manual")
            try? FileManager.default.createDirectory(
                at: backup.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
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
        panel.directoryURL = backupDirectory
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

    func openBackupDirectoryInFinder() {
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        guard NSWorkspace.shared.open(backupDirectory) else {
            status = "Could not open the backups directory in Finder."
            return
        }
        status = "Opened the backups directory in Finder."
    }

    func setShowAdvancedFields(_ show: Bool) {
        showAdvancedFields = show
        UserDefaults.standard.set(show, forKey: "\(AppConstants.defaultsPrefix).showAdvancedFields")
    }

    func setShowNonStandardKeyboardKeys(_ show: Bool) {
        showNonStandardKeyboardKeys = show
        UserDefaults.standard.set(show, forKey: "\(AppConstants.defaultsPrefix).showNonStandardKeyboardKeys")
    }

    func chooseJSONBackup() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.json]
        panel.directoryURL = defaultDocumentsDirectory
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseJSONExport() -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType.json]
        panel.directoryURL = defaultDocumentsDirectory
        panel.nameFieldStringValue = editableJSONExportName()
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

            var proposedButtons: [(ButtonLayer, Int, String)] = []
            for button in backup.profile.buttons {
                guard let layer = ButtonLayer(rawValue: button.layer) else {
                    status = "JSON button \(button.number) has an unrecognized layer '\(button.layer)'."
                    return
                }
                // `buttons` is the active-layer source of truth while the
                // editor is being initialized; use it for the active layer
                // even when the test/import caller has not populated the
                // cached per-layer array separately.
                let targetRows = layer == buttonLayer
                    ? buttons
                    : (layer == .normal ? normalButtonRows : gShiftButtonRows)
                guard let index = targetRows.firstIndex(where: { $0.id == button.number }),
                      let raw = jsonRaw(for: button) else {
                    status = "JSON \(layer.label) button \(button.number) has no recognized output or 8-digit raw record."
                    return
                }
                proposedButtons.append((layer, index, raw))
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

            var proposedRGB: [Int: RGBColor] = [:]
            if let rgb = backup.profile.rgb {
                guard let capability = rgbCapabilities(), !capability.zones.isEmpty else {
                    status = "This JSON contains RGB settings, but the selected device/profile does not advertise writable RGB zones."
                    return
                }
                let allowedZones = Set(capability.zones.map(\.index))
                for zone in rgb {
                    guard allowedZones.contains(zone.zone),
                          proposedRGB[zone.zone] == nil,
                          let color = RGBColor(hex: zone.color) else {
                        status = "The JSON RGB zones or colors are invalid for this device."
                        return
                    }
                    proposedRGB[zone.zone] = color
                }
            }

            for profile in profiles {
                if let enabled = proposedStates[profile.id],
                   let index = self.profiles.firstIndex(where: { $0.id == profile.id }) {
                    self.profiles[index].enabled = enabled
                }
            }
            for (layer, index, raw) in proposedButtons {
                setRaw(layer: layer, buttonIndex: index, raw: raw)
            }
            if let dpi = proposedDPI {
                dpiCount = dpi.stages.count
                dpiStages = dpi.stages.map(String.init) + Array(repeating: "", count: 5 - dpi.stages.count)
                defaultStage = dpi.defaultStage
                shiftStage = dpi.shiftStage
            }
            for (zoneID, color) in proposedRGB {
                setRGBColor(zoneID: zoneID, color: color)
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
        let profileButtons = allButtonRowsForSave().map { button in
            let raw = normalize(useDrafts ? button.draftRaw : button.currentRaw)
            return EditableBackup.Button(
                number: button.id,
                physicalControl: button.displayLabel,
                output: outputLabel(for: raw),
                raw: raw,
                layer: button.layer.rawValue
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
        let rgb: [EditableBackup.Profile.RGB]?
        if let capability = rgbCapabilities(), !rgbZones.isEmpty {
            let colors = rgbZones.compactMap { zone -> EditableBackup.Profile.RGB? in
                let color = useDrafts ? zone.draft : zone.current
                guard capability.zones.contains(where: { $0.index == zone.id }) else { return nil }
                return EditableBackup.Profile.RGB(
                    zone: zone.id,
                    name: zone.name,
                    color: color.hex
                )
            }
            rgb = colors.isEmpty ? nil : colors
        } else {
            rgb = nil
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
                dpi: dpi,
                rgb: rgb
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
            _ = try runEngine(BackupStorage.restoreArguments(for: url))
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
