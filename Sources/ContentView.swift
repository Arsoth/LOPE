// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var confirmRestore = false
    @State private var restoreURL: URL?
    @State private var confirmRecoveryRestore = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            TabView {
                ZStack {
                    if model.loadingProfile && model.buttons.isEmpty {
                        loadingProfileState
                    } else if !model.loadingProfile && !model.shouldShowButtonEditor {
                        emptyState
                    } else {
                        buttonsPane
                            .opacity(model.loadingProfile ? 0.72 : 1)
                            .allowsHitTesting(!model.loadingProfile)
                    }
                    if model.loadingProfile && !model.buttons.isEmpty {
                        loadingProfileOverlay
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

            // Future expansion: restore the button-press highlighting control
            // here, below the footer/status line, after a reliable Logitech
            // button-event path is available. AppKit only exposed buttons 1–3
            // in testing, and the HID monitor did not provide dependable
            // mappings for the remaining controls.
            // HStack(spacing: 8) {
            //     Spacer()
            //     Button("Highlight presses") {
            //         // Future button-event monitor action.
            //     }
            // }
        }
        .padding(20)
        .frame(minWidth: 960, minHeight: 520)
        .onChange(of: model.profileNumber) { _ in
            model.reloadSelectedProfile()
        }
        .onChange(of: model.selectedDeviceIndex) { _ in
            model.refreshBackups()
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
        .alert("Restore backups from this save?", isPresented: $confirmRecoveryRestore) {
            Button("Cancel", role: .cancel) {}
            Button("Restore and verify", role: .destructive) {
                model.restoreLastSaveBackups()
            }
        } message: {
            Text("LOPE will restore the exact pre-save sectors captured by the failed operation. Any sector that was already unchanged will be skipped safely.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppConstants.displayName)
                    .font(.title2.weight(.semibold))
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
                .disabled(model.devices.isEmpty)
            }
            if model.profiles.count > 1 {
                Picker("Profile", selection: $model.profileNumber) {
                    ForEach(model.profiles) { profile in
                        Text(profile.title).tag(profile.id)
                    }
                }
                .frame(width: 180)
                .disabled(model.busy)
            }
            Button("Refresh", action: model.refresh)
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.busy)
            if model.busy { ProgressView().controlSize(.small) }
        }
    }

    private var loadingProfileOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading profiles from mouse…")
                    .font(.headline)
                Text(model.currentDeviceName.isEmpty ? "Finding Logitech mice and reading onboard data" : "Reading \(model.currentDeviceName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var loadingProfileState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading profiles from mouse…")
                .font(.headline)
            Text(model.currentDeviceName.isEmpty ? "Finding Logitech mice and reading onboard data" : "Reading \(model.currentDeviceName)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "computermouse")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(emptyStateTitle)
                .font(.title3.weight(.medium))
            Text(emptyStateMessage)
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

    private var emptyStateTitle: String {
        if model.devices.isEmpty { return "No editable Logitech mouse detected" }
        if model.isMXSeriesMouse && !model.hasSpecificMouseProfile {
            return "No MX mouse profile descriptor"
        }
        return "No editable onboard profile"
    }

    private var emptyStateMessage: String {
        if model.devices.isEmpty {
            return "The app lists Logitech mice. macOS may also be blocking access even when the mouse is connected."
        }
        if model.isMXSeriesMouse && !model.hasSpecificMouseProfile {
            return "\(model.deviceSummary) is connected, but LOPE does not have a profile JSON for this MX mouse’s button layout yet."
        }
        return "\(model.deviceSummary) is connected, but it does not expose an onboard profile format this app can edit."
    }

    private var buttonsPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Button assignments")
                    .font(.headline)
                Spacer()
                Button("Revert edits") { model.reloadSelectedProfile() }
                Button("Save to mouse", action: model.applyAll)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.hasPendingChanges || model.busy || !model.currentMouseProfile.profileIO.canSave)
            }
            Text("Change button outputs and DPI together, then save once. The original data is backed up automatically.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !model.recoveryBackups.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("The last save was only partially completed. Exact pre-save backups are available for recovery.")
                        .font(.callout)
                    Spacer()
                    Button("Restore backups from this save") {
                        confirmRecoveryRestore = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(8)
                .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
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
                            .frame(width: 76, alignment: .leading)
                        Text(button.label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        .frame(width: 190)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                )
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.clear)
                        .frame(width: 3)
                        .padding(.vertical, 7)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            Color.white.opacity(0.055),
                            lineWidth: 0.5
                        )
                }
            }
        }
    }

    private var profilesEditor: some View {
        GroupBox(model.onboardProfileSummary) {
            VStack(alignment: .leading, spacing: 4) {
                if model.profiles.count > 1 {
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
                } else {
                    Text("This mouse has one readable onboard profile; profile cycling and disabling are unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Custom keyboard output", systemImage: "keyboard")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("Modifiers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        .controlSize(.small)
                        .disabled({
                            guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return true }
                            return !model.isKeyboardRecord(buttonIndex: index)
                        }())
                }
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Typed key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("A, Tab, or 0x04", text: Binding(
                        get: {
                            guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return "" }
                            return model.keyboardKeyText(buttonIndex: index)
                        },
                        set: { text in
                            guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                            model.setKeyboardKeyText(buttonIndex: index, text: text)
                        }))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 150)
                }

                keyboardChoiceCard(buttonID: buttonID, title: "Function key", systemImage: "f.square")
                keyboardChoiceCard(buttonID: buttonID, title: "Special key", systemImage: "command.square")
                Spacer()
            }
        }
        .padding(.leading, 76)
        .padding(.top, 2)
        .help("Type a key name such as A or F13, choose a function or special key, and add modifiers with the checkboxes.")
    }

    private func keyboardChoiceCard(buttonID: Int, title: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            if title == "Function key" {
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
                .controlSize(.small)
                .frame(width: 112)
            } else {
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
                .controlSize(.small)
                .frame(width: 156)
            }
        }
    }

    private var dpiEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Onboard DPI")
                        .font(.headline)
                    Text("Set the active sensitivity stages for this profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Active stages", selection: Binding(
                    get: { model.dpiCount },
                    set: { model.setDPIStageCount($0) })) {
                    ForEach(1...5, id: \.self) { count in
                        Text("\(count) stages").tag(count)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(0..<model.dpiCount, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Stage \(index + 1)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                TextField("DPI", text: Binding(
                                    get: { model.dpiStages[index] },
                                    set: { model.dpiStages[index] = $0.filter { $0.isNumber } }))
                                    .textFieldStyle(.roundedBorder)
                                    .controlSize(.small)
                                Text("DPI")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                HStack(spacing: 8) {
                    dpiStagePicker(title: "Default", selection: $model.defaultStage)
                    dpiStagePicker(title: "DPI shift", selection: $model.shiftStage)
                    Spacer()
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            Text(model.dpiDetails)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func dpiStagePicker(title: String, selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(1...model.dpiCount, id: \.self) { stage in
                    Text("Stage \(stage)").tag(stage)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 126)
        }
    }

    private var backupsPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Backups")
                .font(.headline)
            Text("Save to mouse creates exact binary backups for the selected mouse before any write. JSON is an explicit import/export format; older JSON sidecars remain available as editable files, but new mouse saves do not create them.")
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
            Toggle("Show backups for all mice", isOn: Binding(
                get: { model.showAllBackups },
                set: { model.setShowAllBackups($0) }))
            .toggleStyle(.checkbox)
            Text(model.showAllBackups
                 ? "Showing every backup. Unknown-device files require review before restore or import."
                 : "Showing backups matched to the selected mouse. Legacy files that cannot be matched safely are hidden.")
                .font(.caption)
                .foregroundStyle(.secondary)
            GroupBox("Available backups") {
                if model.backups.isEmpty {
                    Text(model.showAllBackups
                         ? "No backups in \(model.backupDirectoryPath)."
                         : "No backups for the selected mouse in \(model.backupDirectoryPath).")
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
                                    Text("\(backup.fileTypeLabel) | \(backup.deviceStatusLabel) | \(backup.modifiedAt.formatted(date: .abbreviated, time: .shortened)) | \(ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file))")
                                        .font(.caption)
                                        .foregroundStyle(backup.deviceMatch == .unknown ? .orange : .secondary)
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
