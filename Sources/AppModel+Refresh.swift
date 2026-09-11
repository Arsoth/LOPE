// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import ApplicationServices
import Foundation
import IOKit.hidsystem

private let deviceReadAttempts = 3
private let deviceReadRetryDelay: TimeInterval = 0.2
private let profileReadAttempts = 5
private let profileReadRetryDelay: TimeInterval = 0.25

@MainActor
extension AppModel {
    func refresh() {
        startRefresh(
            preferredDeviceIndex: selectedDeviceIndex,
            preferredProfileNumber: profileNumber
        )
    }

    private func startRefresh(
        preferredDeviceIndex: Int,
        preferredProfileNumber: Int
    ) {
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let currentDirectory = backupDirectory

        busy = true
        loadingProfile = true
        status = "Reading the mouse…"
        // Receiver and Bluetooth HID++ interfaces are protected by macOS
        // Input Monitoring. Avoid asking an already-authorized app for access
        // on every refresh; the access request can otherwise delay the first
        // device enumeration even though no prompt is needed.
        if !inputMonitoringAuthorized {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            updateInputMonitoringAuthorization()
        }

        guard let engine else {
            busy = false
            loadingProfile = false
            status = EngineError.unavailable.localizedDescription
            return
        }

        refreshTask = Task { [weak self] in
            let enumeration = await Task.detached(priority: .userInitiated) {
                Self.makeDeviceEnumerationSnapshot(
                    executable: engine,
                    currentDirectory: currentDirectory,
                    preferredDeviceIndex: preferredDeviceIndex
                )
            }.value

            guard !Task.isCancelled, let self,
                  self.refreshGeneration == generation else { return }

            guard enumeration.errorMessage == nil,
                  let selectedIndex = enumeration.selectedDeviceIndex,
                  let selected = enumeration.devices.first(where: { $0.id == selectedIndex }) else {
                self.applyRefreshSnapshot(RefreshSnapshot(
                    devices: enumeration.devices,
                    selectedDeviceIndex: nil,
                    profileText: nil,
                    profileError: nil,
                    dpiText: nil,
                    dpiError: nil,
                    selectedProfileNumber: nil,
                    errorMessage: enumeration.errorMessage,
                    accessWarning: enumeration.accessWarning
                ))
                return
            }

            // Publish the device list as soon as enumeration completes. The
            // profile read is slower, but the picker can now populate while
            // the button editor remains in its explicit loading state.
            self.devices = enumeration.devices
            self.selectedDeviceIndex = selected.id
            self.currentDeviceName = selected.name
            self.deviceSummary = selected.title
            self.resetEditorState()
            self.status = "Found \(selected.name). Reading onboard profile…"

            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.makeProfileSnapshot(
                    executable: engine,
                    currentDirectory: currentDirectory,
                    devices: enumeration.devices,
                    selectedDeviceKey: selected.deviceKey,
                    selectedDeviceIndex: selected.id,
                    preferredProfileNumber: preferredProfileNumber,
                    accessWarning: enumeration.accessWarning
                )
            }.value

            guard !Task.isCancelled,
                  self.refreshGeneration == generation else { return }
            self.applyRefreshSnapshot(snapshot)
        }
    }

    func selectDevice(_ index: Int) {
        guard let selected = devices.first(where: { $0.id == index }), selectedDeviceIndex != index else { return }
        selectedDeviceIndex = index
        // Profile numbers are device-local. Reusing the previous mouse's
        // selection can target a disabled/partially provisioned slot on the
        // newly selected mouse, so let the engine choose its first enabled
        // profile and report that actual slot back to the UI.
        currentDeviceName = selected.name
        deviceSummary = selected.title
        startRefresh(preferredDeviceIndex: index, preferredProfileNumber: 0)
    }

    func applyRefreshSnapshot(_ snapshot: RefreshSnapshot) {
        defer {
            busy = false
            loadingProfile = false
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
            if snapshot.profileError != nil {
                status = profileReadStatus(for: selected.name, accessWarning: snapshot.accessWarning)
            } else {
                status = "Connected to \(selected.name), but no compatible onboard profile was found."
            }
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

    private func profileReadStatus(for deviceName: String, accessWarning: Bool) -> String {
        if accessWarning {
            return "macOS is blocking access to \(deviceName). Enable Input Monitoring, then choose Refresh."
        }
        return "Couldn’t read \(deviceName)’s onboard profile. Is the mouse turned on and awake? Wake it, then choose Refresh."
    }

    private nonisolated static func makeDeviceEnumerationSnapshot(
        executable: URL,
        currentDirectory: URL,
        preferredDeviceIndex: Int
    ) -> DeviceEnumerationSnapshot {
        do {
            let list = try runDeviceListWithRetry(
                executable: executable,
                currentDirectory: currentDirectory
            )
            let discovered = parseDeviceChoices(list)
            let accessWarning = list.contains("macOS denied HID access")
            let selectedIndex = (discovered.first(where: { $0.id == preferredDeviceIndex }) ?? discovered.first)?.id
            return DeviceEnumerationSnapshot(
                devices: discovered,
                selectedDeviceIndex: selectedIndex,
                accessWarning: accessWarning,
                errorMessage: nil
            )
        } catch {
            return DeviceEnumerationSnapshot(
                devices: [],
                selectedDeviceIndex: nil,
                accessWarning: false,
                errorMessage: errorMessage(for: error)
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
            // A missing --profile lets the engine choose the first enabled
            // slot. Passing --profile 0 is invalid because explicit profile
            // numbers are one-based.
            var arguments = [
                "--device-key", selectedDeviceKey,
                "--summary-only",
                "--with-dpi"
            ]
            if preferredProfileNumber > 0 {
                arguments += ["--profile", String(preferredProfileNumber)]
            }
            arguments.append("profiles")
            let profileText = try runProfileReadWithRetry(
                executable: executable,
                arguments: arguments,
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

    private nonisolated static func runDeviceListWithRetry(
        executable: URL,
        currentDirectory: URL
    ) throws -> String {
        var lastError: Error?

        for attempt in 0..<deviceReadAttempts {
            do {
                let output = try EngineRunner.run(
                    executable: executable,
                    arguments: ["list"],
                    currentDirectory: currentDirectory
                )
                if !parseDeviceChoices(output).isEmpty || attempt == deviceReadAttempts - 1 {
                    return output
                }
                lastError = EngineError.failed("The Logitech device list was empty.")
            } catch {
                lastError = error
            }

            if attempt < deviceReadAttempts - 1 {
                Thread.sleep(forTimeInterval: deviceReadRetryDelay)
            }
        }

        throw lastError ?? EngineError.failed("The Logitech device list could not be read.")
    }

    private nonisolated static func runProfileReadWithRetry(
        executable: URL,
        arguments: [String],
        currentDirectory: URL
    ) throws -> String {
        var lastError: Error?

        for attempt in 0..<profileReadAttempts {
            do {
                let output = try EngineRunner.run(
                    executable: executable,
                    arguments: arguments,
                    currentDirectory: currentDirectory
                )
                // run_profiles historically returned success after emitting
                // headers when the selected sector read timed out. Require
                // this marker so a transient G603 wake-up failure is retried
                // instead of being presented as a mouse with no profile.
                if selectedProfileNumber(in: output) != nil {
                    return output
                }
                lastError = EngineError.failed("The selected onboard profile was not returned.")
            } catch {
                lastError = error
            }

            if attempt < profileReadAttempts - 1 {
                // Each attempt launches a fresh HID context, but only for the
                // selected device key. This gives macOS time to finish the
                // interface handoff without re-enumerating every mouse.
                Thread.sleep(forTimeInterval: profileReadRetryDelay)
            }
        }

        throw lastError ?? EngineError.failed("The selected onboard profile could not be read.")
    }

    private nonisolated static func errorMessage(for error: Error) -> String {
        error.localizedDescription
    }

    func openInputMonitoringSettings() {
        CGRequestListenEventAccess()
        updateInputMonitoringAuthorization()
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

    func updateInputMonitoringAuthorization() {
        inputMonitoringAuthorized = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    func reloadSelectedProfile() {
        guard !busy, !profiles.isEmpty else { return }
        // Profile changes use the same enumerating, retrying path as the
        // Refresh button. The old one-shot read could return only the profile
        // header after a transient HID++ timeout and leave the editor empty.
        refresh()
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
