// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var confirmRestore = false
    @State private var restoreURL: URL?
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                model.updateInputMonitoringAuthorization()
            }
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
                .disabled(model.busy)
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
            if !model.inputMonitoringAuthorized {
                Button("Open Input Monitoring Settings", action: model.openInputMonitoringSettings)
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
                    .disabled(!model.hasPendingChanges || model.busy || !model.currentMouseProfile.profileIO.canSave)
            }
            Text("Modify profiles, button outputs and DPI together, then save once. The original data is backed up automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Choose a standard output or use Custom for a keyboard chord. Raw HID++ fields are available in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Physical mapping: \(model.currentMouseProfile.name) · \(model.currentMouseProfile.profileIO.capability)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !model.currentMouseProfile.profileIO.canSave {
                Text("This device is cataloged for read-only inspection until its profile-specific save format is validated.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    profilesEditor
                    Divider()
                    VStack(spacing: 8) {
                        ForEach(model.buttons) { button in
                            buttonRow(button.id)
                        }
                    }
                    Divider()
                    dpiEditor
                }
                .padding(.vertical, 4)
            }
            .id(model.selectedDeviceIndex)
        }
        .padding(.top, 4)
    }

    private func buttonRow(_ buttonID: Int) -> some View {
        Group {
            if let button = model.buttons.first(where: { $0.id == buttonID }) {
                VStack(alignment: .leading, spacing: 6) {
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
                            get: { model.buttons.first(where: { $0.id == buttonID })?.draftChoice ?? "custom" },
                            set: { choice in
                                guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                                model.selectOutput(buttonIndex: index, choice: choice)
                            })) {
                            ForEach(model.presets) { preset in
                                Text(preset.label).tag(preset.raw)
                            }
                            Text("Custom").tag("custom")
                        }
                        .labelsHidden()
                        .frame(width: 215)
                        if model.showAdvancedFields {
                            TextField("8 hex digits", text: Binding(
                                get: { model.buttons.first(where: { $0.id == buttonID })?.draftRaw ?? "" },
                                set: { raw in
                                    guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                                    model.setRaw(buttonIndex: index, raw: raw)
                                }))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 122)
                        }
                        Spacer()
                    }
                    if model.buttons.first(where: { $0.id == buttonID })?.draftChoice == "custom" {
                        keyboardChordEditor(buttonID)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
            }
        }
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
        let crcLabel: String
        let crcColor: Color
        let helpText: String
        switch profile.crcValid {
        case true:
            crcLabel = ""
            crcColor = .secondary
            helpText = "Profile \(label) CRC valid"
        case false:
            crcLabel = "Profile invalid"
            crcColor = .red
            helpText = "Profile \(label) CRC invalid"
        case nil:
            crcLabel = ""
            crcColor = .secondary
            helpText = "Profile \(label) CRC not read"
        }
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

    private func keyboardChordEditor(_ buttonID: Int) -> some View {
        HStack(spacing: 8) {
            Text("Custom")
                .font(.caption.weight(.medium))
                .frame(width: 78, alignment: .leading)
            ForEach(model.modifierChoices) { modifier in
                Toggle(modifier.label, isOn: Binding(
                    get: {
                        guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return false }
                        return model.isModifierEnabled(buttonIndex: index, bit: modifier.id)
                    },
                    set: { enabled in
                        guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                        model.setModifier(buttonIndex: index, bit: modifier.id, enabled: enabled)
                    }))
                    .toggleStyle(.checkbox)
                    .disabled({
                        guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return true }
                        return !model.isKeyboardRecord(buttonIndex: index)
                    }())
            }
            TextField("Key name", text: Binding(
                get: {
                    guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return "" }
                    return model.keyboardKeyText(buttonIndex: index)
                },
                set: { text in
                    guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                    model.setKeyboardKeyText(buttonIndex: index, text: text)
                }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
            Text("F key")
                .font(.caption)
            Picker("", selection: Binding(
                get: {
                    guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return 0 }
                    return model.functionKeyChoice(buttonIndex: index)
                },
                set: { number in
                    guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                    model.setFunctionKey(buttonIndex: index, number: number)
                })) {
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
                get: {
                    guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return 0 }
                    return model.specialKeyChoice(buttonIndex: index)
                },
                set: { key in
                    guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                    model.setSpecialKey(buttonIndex: index, key: key)
                })) {
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
