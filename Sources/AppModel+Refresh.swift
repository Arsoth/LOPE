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

    func initialRefresh() {
        guard let cachedDevice = loadLastSelectedDevice() else {
            refresh()
            return
        }
        startInitialRefresh(cachedDevice: cachedDevice)
    }

    private func startInitialRefresh(cachedDevice: DeviceChoice) {
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let currentDirectory = backupDirectory
        let preferredProfileNumber = profileNumber

        busy = true
        loadingProfile = true
        currentDeviceName = cachedDevice.name
        deviceSummary = cachedDevice.title
        status = "Reading \(cachedDevice.name)…"
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

        // Keep the cached device visible while the targeted read is in flight.
        // The full device list is refreshed after this read succeeds.
        devices = [cachedDevice]
        selectedDeviceIndex = cachedDevice.id
        prepareLoadingEditor(profileNumber: preferredProfileNumber == 0 ? 1 : preferredProfileNumber)
        let profileReadProgress = profileReadProgressHandler(generation: generation)

        refreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.makeProfileSnapshot(
                    executable: engine,
                    currentDirectory: currentDirectory,
                    devices: [cachedDevice],
                    selectedDeviceKey: cachedDevice.deviceKey,
                    selectedDeviceIndex: cachedDevice.id,
                    preferredProfileNumber: preferredProfileNumber,
                    onLine: profileReadProgress
                )
            }.value

            guard !Task.isCancelled, let self,
                  self.refreshGeneration == generation else { return }

            // A stale cached key should not prevent the normal discovery path
            // from finding a newly connected mouse.
            guard snapshot.profileText != nil else {
                self.startRefresh(
                    preferredDeviceIndex: cachedDevice.id,
                    preferredProfileNumber: preferredProfileNumber
                )
                return
            }

            self.applyRefreshSnapshot(snapshot)
            self.startBackgroundDeviceEnumeration(
                executable: engine,
                currentDirectory: currentDirectory,
                cachedDevice: cachedDevice,
                generation: generation
            )
        }
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

        // Keep the identified device's physical button layout visible while
        // the slower profile read is in flight. A zero profile lets the
        // engine choose the first enabled slot, so use a valid placeholder
        // number until the read reports the actual slot.
        prepareLoadingEditor(profileNumber: preferredProfileNumber == 0 ? 1 : preferredProfileNumber)

        refreshTask = Task { [weak self] in
            let enumeration = await Task.detached(priority: .userInitiated) {
                Self.makeDeviceEnumerationSnapshot(
                    executable: engine,
                    currentDirectory: currentDirectory,
                    preferredDeviceIndex: preferredDeviceIndex,
                    preferredDeviceKey: nil
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
            self.rememberSelectedDevice(selected)
            self.prepareLoadingEditor(profileNumber: preferredProfileNumber == 0 ? 1 : preferredProfileNumber)
            self.status = "Found \(selected.name). Reading onboard profile…"
            let profileReadProgress = self.profileReadProgressHandler(generation: generation)

            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.makeProfileSnapshot(
                    executable: engine,
                    currentDirectory: currentDirectory,
                    devices: enumeration.devices,
                    selectedDeviceKey: selected.deviceKey,
                    selectedDeviceIndex: selected.id,
                    preferredProfileNumber: preferredProfileNumber,
                    onLine: profileReadProgress,
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
        recoveryBackups.removeAll()
        recoveryDeviceKey = nil
        selectedDeviceIndex = index
        rememberSelectedDevice(selected)
        // Profile numbers are device-local. Reusing the previous mouse's
        // selection can target a disabled/partially provisioned slot on the
        // newly selected mouse, so let the engine choose its first enabled
        // profile and report that actual slot back to the UI.
        currentDeviceName = selected.name
        deviceSummary = selected.title
        refreshBackups()
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
            onboardProfileCapacity = nil
            profiles = []
            buttons = []
            resetEditorState()
            status = snapshot.accessWarning
                ? "macOS denied access to one or more Logitech HID++ interfaces. Enable Input Monitoring, then Refresh."
                : "No Logitech mouse was found"
            return
        }

        selectedDeviceIndex = selected.id
        currentDeviceName = selected.name
        deviceSummary = selected.title
        rememberSelectedDevice(selected)
        refreshBackups()

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
        let reportedCapacity = Self.onboardProfileCapacity(in: profileText)
        onboardProfileCapacity = reportedCapacity ?? parsed.choices.count
        onboardProfileCapacityWasReported = reportedCapacity != nil
        baselineProfileEnabled = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.enabled) })
        keyInputDrafts.removeAll()
        resetDPIState()
        if profiles.isEmpty {
            buttons = []
            status = "The mouse was found, but no onboard profiles were readable."
            return
        }
        profileNumber = ProfileSelection.resolvedProfileNumber(
            selectedProfileNumber: snapshot.selectedProfileNumber,
            availableProfileIDs: profiles.map(\.id),
            preferredProfileNumber: profileNumber
        ) ?? profiles[0].id
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

    private func profileReadProgressHandler(generation: Int) -> @Sendable (String) -> Void {
        { [weak self] line in
            guard let capacity = Self.onboardProfileCapacity(in: line) else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      self.refreshGeneration == generation,
                      self.loadingProfile else { return }
                self.onboardProfileCapacity = capacity
                self.onboardProfileCapacityWasReported = true
            }
        }
    }

    private func resetEditorState() {
        onboardProfileCapacity = nil
        onboardProfileCapacityWasReported = false
        profiles = []
        buttons = []
        baselineProfileEnabled.removeAll()
        keyInputDrafts.removeAll()
        resetDPIState()
    }

    private func prepareLoadingEditor(profileNumber placeholderProfileNumber: Int) {
        let placeholderNumber = max(placeholderProfileNumber, 1)
        onboardProfileCapacity = nil
        onboardProfileCapacityWasReported = false
        profiles = [ProfileChoice(
            id: placeholderNumber,
            sector: "Loading…",
            enabled: true,
            crcValid: nil
        )]
        profileNumber = placeholderNumber
        baselineProfileEnabled = [placeholderNumber: true]
        keyInputDrafts.removeAll()
        buttons = loadingButtonRows()
        resetDPIState()
        dpiDetails = "Loading DPI capabilities from the mouse…"
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
        preferredDeviceIndex: Int,
        preferredDeviceKey: String?
    ) -> DeviceEnumerationSnapshot {
        do {
            let list = try runDeviceListWithRetry(
                executable: executable,
                currentDirectory: currentDirectory
            )
            let discovered = parseDeviceChoices(list)
            let accessWarning = list.contains("macOS denied HID access")
            let selectedIndex = (preferredDeviceKey.flatMap { key in
                discovered.first(where: { $0.deviceKey == key })
            } ?? discovered.first(where: { $0.id == preferredDeviceIndex }) ?? discovered.first)?.id
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

    private func startBackgroundDeviceEnumeration(
        executable: URL,
        currentDirectory: URL,
        cachedDevice: DeviceChoice,
        generation: Int
    ) {
        refreshTask = Task { [weak self] in
            let enumeration = await Task.detached(priority: .utility) {
                Self.makeDeviceEnumerationSnapshot(
                    executable: executable,
                    currentDirectory: currentDirectory,
                    preferredDeviceIndex: cachedDevice.id,
                    preferredDeviceKey: cachedDevice.deviceKey
                )
            }.value

            guard !Task.isCancelled, let self,
                  self.refreshGeneration == generation else { return }

            self.refreshTask = nil
            if let errorMessage = enumeration.errorMessage {
                self.status = "Loaded \(cachedDevice.name). The device list could not be refreshed: \(errorMessage)"
                return
            }

            guard let selected = enumeration.devices.first(where: { $0.deviceKey == cachedDevice.deviceKey }) else {
                guard let fallback = enumeration.devices.first else {
                    self.devices = []
                    self.selectedDeviceIndex = 0
                    self.currentDeviceName = ""
                    self.deviceSummary = "No editable Logitech mouse found"
                    self.resetEditorState()
                    self.status = enumeration.accessWarning
                        ? "macOS denied access to one or more Logitech HID++ interfaces. Enable Input Monitoring, then choose Refresh."
                        : "No Logitech mouse was found."
                    return
                }

                // The cached mouse disappeared while the list was refreshed.
                // Hand the newly selected device through the normal full read
                // so the editor never shows one mouse's profile for another.
                self.devices = enumeration.devices
                self.selectedDeviceIndex = fallback.id
                self.startRefresh(preferredDeviceIndex: fallback.id, preferredProfileNumber: 0)
                return
            }

            self.devices = enumeration.devices
            self.selectedDeviceIndex = selected.id
            self.currentDeviceName = selected.name
            self.deviceSummary = selected.title
            self.rememberSelectedDevice(selected)
            self.refreshBackups()
        }
    }

    private func loadLastSelectedDevice() -> DeviceChoice? {
        let key = "\(AppConstants.defaultsPrefix).\(AppConstants.lastSelectedDeviceKey)"
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DeviceChoice.self, from: data)
    }

    private func rememberSelectedDevice(_ device: DeviceChoice) {
        let key = "\(AppConstants.defaultsPrefix).\(AppConstants.lastSelectedDeviceKey)"
        guard let data = try? JSONEncoder().encode(device) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private nonisolated static func makeProfileSnapshot(
        executable: URL,
        currentDirectory: URL,
        devices: [DeviceChoice],
        selectedDeviceKey: String,
        selectedDeviceIndex: Int,
        preferredProfileNumber: Int,
        onLine: @escaping @Sendable (String) -> Void = { _ in },
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
                currentDirectory: currentDirectory,
                onLine: onLine
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
        currentDirectory: URL,
        onLine: @escaping @Sendable (String) -> Void
    ) throws -> String {
        var lastError: Error?

        for attempt in 0..<profileReadAttempts {
            do {
                let output = try EngineRunner.runWithLineProgress(
                    executable: executable,
                    arguments: arguments,
                    currentDirectory: currentDirectory,
                    onLine: onLine
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
