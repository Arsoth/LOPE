// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import ApplicationServices
import Foundation
import IOKit.hidsystem

@MainActor
extension AppModel {
    func refresh() {
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let preferredDeviceIndex = selectedDeviceIndex
        let preferredProfileNumber = profileNumber
        let currentDirectory = backupDirectory

        busy = true
        status = "Reading the mouse…"
        // Receiver and Bluetooth HID++ interfaces are protected by macOS
        // Input Monitoring. Request access on the normal refresh path too,
        // since a wired G502 can otherwise make the app look healthy while
        // the other mice are silently denied.
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

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
                    selectedDeviceKey: selected.deviceKey,
                    selectedDeviceIndex: selected.id,
                    preferredProfileNumber: preferredProfileNumber
                )
            }.value

            guard !Task.isCancelled, let self,
                  self.refreshGeneration == generation else { return }
            self.applyRefreshSnapshot(snapshot)
        }
    }

    func applyRefreshSnapshot(_ snapshot: RefreshSnapshot) {
        defer {
            busy = false
            refreshTask = nil
        }

        if let errorMessage = snapshot.errorMessage {
            devices = []
            resetEditorState()
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
            resetEditorState()
            status = snapshot.accessWarning
                ? "macOS denied access to one or more Logitech HID++ interfaces. Enable Input Monitoring, then Refresh."
                : "No Logitech mouse was found. USB receiver entries are hidden."
            return
        }

        selectedDeviceIndex = selected.id
        currentDeviceName = selected.name
        deviceSummary = selected.title

        guard let profileText = snapshot.profileText else {
            resetEditorState()
            dpiDetails = "This device does not expose an editable onboard profile through HID++ 0x8100."
            status = "Connected to \(selected.name), but no compatible onboard profile was found."
            return
        }

        let parsed = parseProfiles(profileText)
        profiles = parsed.choices
        baselineProfileEnabled = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.enabled) })
        keyInputDrafts.removeAll()
        resetDPIState()
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
        parseDPI(profileText)
        if dpiDetails.isEmpty {
            dpiDetails = snapshot.dpiError ?? "DPI capabilities could not be read."
        }
        status = snapshot.accessWarning
            ? "Some Logitech interfaces were denied by macOS. Enable Input Monitoring, then Refresh."
            : "Read-only inspection complete. Changes are previewed before writing."
    }

    private func resetEditorState() {
        profiles = []
        buttons = []
        baselineProfileEnabled.removeAll()
        keyInputDrafts.removeAll()
        resetDPIState()
    }

    private func resetDPIState() {
        dpiStages = ["", "", "", "", ""]
        dpiCount = 5
        defaultStage = 1
        shiftStage = 1
        baselineDPIStages = ["", "", "", "", ""]
        baselineDPICount = 5
        baselineDefaultStage = 1
        baselineShiftStage = 1
        dpiDetails = "DPI capabilities have not been read."
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
            let accessWarning = list.contains("macOS denied HID access")
            guard let selected = discovered.first(where: { $0.id == preferredDeviceIndex }) ?? discovered.first else {
                return RefreshSnapshot(
                    devices: [], selectedDeviceIndex: nil, profileText: nil, profileError: nil,
                    dpiText: nil, dpiError: nil, selectedProfileNumber: nil, errorMessage: nil,
                    accessWarning: accessWarning
                )
            }

            return makeProfileSnapshot(
                executable: executable,
                currentDirectory: currentDirectory,
                devices: discovered,
                selectedDeviceKey: selected.deviceKey,
                selectedDeviceIndex: selected.id,
                preferredProfileNumber: preferredProfileNumber,
                accessWarning: accessWarning
            )
        } catch {
            return RefreshSnapshot(
                devices: [], selectedDeviceIndex: nil, profileText: nil, profileError: nil,
                dpiText: nil, dpiError: nil, selectedProfileNumber: nil,
                errorMessage: errorMessage(for: error), accessWarning: false
            )
        }
    }

    private nonisolated static func makeProfileSnapshot(
        executable: URL,
        currentDirectory: URL,
        devices: [DeviceChoice],
        selectedDeviceKey: String,
        selectedDeviceIndex: Int,
        preferredProfileNumber: Int,
        accessWarning: Bool = false
    ) -> RefreshSnapshot {
        do {
            // The engine keeps one HID context for this combined read. The
            // previous implementation launched separate processes for headers,
            // profile data, and DPI, repeating feature discovery each time.
            let profileText = try EngineRunner.run(
                executable: executable,
                arguments: [
                    "--device-key", selectedDeviceKey,
                    "--summary-only",
                    "--with-dpi",
                    "--profile", String(preferredProfileNumber),
                    "profiles"
                ],
                currentDirectory: currentDirectory
            )
            let selectedProfileNumber = Self.selectedProfileNumber(in: profileText)
            return RefreshSnapshot(
                devices: devices, selectedDeviceIndex: selectedDeviceIndex,
                profileText: profileText, profileError: nil, dpiText: nil,
                dpiError: nil, selectedProfileNumber: selectedProfileNumber,
                errorMessage: nil, accessWarning: accessWarning
            )
        } catch {
            return RefreshSnapshot(
                devices: devices, selectedDeviceIndex: selectedDeviceIndex,
                profileText: nil, profileError: errorMessage(for: error), dpiText: nil,
                dpiError: nil, selectedProfileNumber: nil, errorMessage: nil,
                accessWarning: accessWarning
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

    func reloadSelectedProfileContents() {
        do {
            let profileText = try runEngine([
                "--summary-only",
                "--profile", String(profileNumber),
                "profiles"
            ])
            let parsed = parseProfiles(profileText)
            buttons = parsed.rowsByProfile[profileNumber] ?? parsed.rowsByProfile.values.first ?? []
            loadDPI(profileText: profileText)
            status = "Reloaded profile \(profileNumber)."
        } catch {
            status = error.localizedDescription
        }
    }
}
