// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Combine
import Foundation
import IOKit.hidsystem

@MainActor
final class AppModel: ObservableObject {
    @Published var deviceSummary = "No Logitech HID++ device loaded"
    @Published var status = "Connect a Logitech mouse, then choose Refresh."
    @Published var devices: [DeviceChoice] = []
    @Published var selectedDeviceIndex = 0
    @Published var profiles: [ProfileChoice] = []
    // The effective capacity is distinct from the number of readable profile
    // headers. Older engine output falls back to profiles.count and records
    // that the device did not actually report a capacity.
    @Published var onboardProfileCapacity: Int?
    @Published var onboardProfileCapacityWasReported = false
    @Published var profileNumber = 1
    @Published var buttons: [ButtonRow] = []
    @Published var buttonLayer: ButtonLayer = .normal
    @Published var dpiStages = ["", "", "", "", ""]
    @Published var dpiCount = 5
    @Published var defaultStage = 3
    @Published var shiftStage = 1
    @Published var dpiCapabilities = DPICapabilities()
    @Published var dpiDetails = "DPI capabilities have not been read."
    @Published var rgbZones: [RGBZoneState] = []
    @Published var busy = false
    @Published var loadingProfile = false
    @Published var inputMonitoringAuthorized = false
    @Published var wiredAccessInstructionsPresented = false
    @Published var backups: [BackupEntry] = []
    @Published var showAllBackups = false
    @Published var recoveryBackups: [URL] = []
    @Published var configurationDirectoryPath = ""
    @Published var backupDirectoryPath = ""
    @Published var showAdvancedFields = false
    @Published var showNonStandardKeyboardKeys = false
    @Published var waitingForKnownDevice = false
    @Published var knownDevicePollAttempts = 0
    @Published var appearancePreference: AppearancePreference
    @Published var isDarkAppearance = false

    var keyInputDrafts: [Int: String] = [:]
    @Published var recordingKeyboardButtonID: Int?
    var baselineProfileEnabled: [Int: Bool] = [:]
    var baselineDPIStages = [String]()
    var baselineDPICount = 5
    var baselineDefaultStage = 3
    var baselineShiftStage = 1
    var baselineRGBColors: [Int: RGBColor] = [:]
    var rgbEditingAllZones = false
    var currentDeviceName = ""
    var refreshTask: Task<Void, Never>?
    var refreshGeneration = 0
    var recoveryDeviceKey: String?
    var discoveredBackups: [BackupEntry] = []
    var reconnectMonitorTask: Task<Void, Never>?
    var knownDevicePollTask: Task<Void, Never>?
    var liveDPIPollTask: Task<Void, Never>?
    var knownDisconnectedDevice: DeviceChoice?
    var initialBackupKeys = Set<String>()

    var normalButtonRows: [ButtonRow] = []
    var gShiftButtonRows: [ButtonRow] = []

    @Published var profileEditorID = ""
    @Published var profileEditorName = ""
    @Published var profileEditorSources = ""
    @Published var profileEditorButtonNames: [Int: String] = [:]
    // Everything the simple editor fields do not expose (aliases, scroll-wheel
    // labels, hidden-button numbers, refresh guidance, RGB zones, profileIO):
    // carried over untouched from the descriptor already covering this device,
    // an imported file, or a freshly synthesized starting point, so saving or
    // exporting never silently drops data the UI does not surface.
    var profileEditorBase: MouseProfileDescriptor?

    var hasGShiftLayer: Bool {
        !gShiftButtonRows.isEmpty
    }

    /// The physical button numbers currently read from the connected mouse,
    /// independent of the normal/G-Shift output layer. This always tracks
    /// `normalButtonRows`/`gShiftButtonRows` directly rather than being
    /// stored, so the profile editor's row list never goes stale.
    var profileEditorButtonNumbers: [Int] {
        Set(normalButtonRows.map(\.id) + gShiftButtonRows.map(\.id)).sorted()
    }

    // Test and diagnostic callers can replace the process boundary without
    // changing the production HID++ command construction.
    var engineRunnerOverride: (([String]) throws -> String)?

    var currentMouseProfile: MouseProfileDescriptor {
        currentCatalogProfile ?? MouseProfileCatalog.genericProfile
    }

    var currentCatalogProfile: MouseProfileDescriptor? {
        let productID = devices.first(where: { $0.id == selectedDeviceIndex })?.productID ?? ""
        guard !currentDeviceName.isEmpty || !productID.isEmpty else { return nil }
        return MouseProfileCatalog.shared.matchingProfile(deviceName: currentDeviceName, productID: productID)
    }

    var hasSpecificMouseProfile: Bool {
        currentCatalogProfile != nil
    }

    var builtInMouseProfileCount: Int {
        MouseProfileCatalog.shared.builtInProfileCount
    }

    var customMouseProfileCount: Int {
        MouseProfileCatalog.shared.customProfileCount
    }

    var knownDeviceRefreshGuidance: OnboardProfileRefreshGuidance? {
        guard let device = knownDisconnectedDevice else { return nil }
        return MouseProfileCatalog.shared.matchingProfile(
            deviceName: device.name,
            productID: device.productID
        )?.refreshGuidance
    }

    var isMXSeriesMouse: Bool {
        let selected = devices.first(where: { $0.id == selectedDeviceIndex })
        return DeviceClassification.isMXSeriesMouse(
            name: currentDeviceName.isEmpty ? (selected?.name ?? "") : currentDeviceName,
            productID: selected?.productID ?? ""
        )
    }

    var shouldShowButtonEditor: Bool {
        guard !loadingProfile, !profiles.isEmpty else { return false }
        // MX mice do not share the G-series physical-button layout. Do not
        // present runtime-numbered fallback controls until a dedicated JSON
        // descriptor has been added to the catalog.
        return !isMXSeriesMouse || hasSpecificMouseProfile
    }

    var onboardProfileSummary: String {
        guard !loadingProfile else { return "Onboard profiles" }
        let readableCount = profiles.count
        guard readableCount > 0 else { return "Onboard profiles" }

        guard let capacity = onboardProfileCapacity else {
            return readableCount == 1
                ? "Profile 1 (capacity not reported)"
                : "Onboard profiles (\(readableCount) readable; capacity not reported)"
        }

        guard capacity >= readableCount else {
            return "Onboard profiles (\(readableCount) readable; reported capacity inconsistent)"
        }

        if !onboardProfileCapacityWasReported {
            return readableCount == 1
                ? "Profile 1 (1 readable; capacity not reported)"
                : "Onboard profiles (\(readableCount) readable; capacity not reported)"
        }

        if readableCount == 1 && capacity == 1 {
            return "Profile 1 of 1"
        }
        return "Onboard profiles (\(readableCount) of \(capacity) supported)"
    }

    var engine: URL? {
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

    var configurationDirectory: URL
    let defaultConfigurationDirectory: URL

    var backupDirectory: URL {
        configurationDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    var customProfilesDirectory: URL {
        configurationDirectory.appendingPathComponent("Custom Profiles", isDirectory: true)
    }

    init(startInitialRefresh: Bool = true) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppConstants.appSupportDirectory, isDirectory: true)
        defaultConfigurationDirectory = base
        let defaults = UserDefaults.standard
        let configurationDirectoryKey = "\(AppConstants.defaultsPrefix).configurationDirectory"
        let selectedPath = defaults.string(forKey: configurationDirectoryKey)
        let selectedDirectory = selectedPath.map { URL(fileURLWithPath: $0) } ?? base
        configurationDirectory = selectedDirectory
        configurationDirectoryPath = selectedDirectory.path
        backupDirectoryPath = selectedDirectory
            .appendingPathComponent("Backups", isDirectory: true)
            .path
        let advancedFieldsKey = "\(AppConstants.defaultsPrefix).showAdvancedFields"
        showAdvancedFields = defaults.bool(forKey: advancedFieldsKey)
        let nonStandardKeysKey = "\(AppConstants.defaultsPrefix).showNonStandardKeyboardKeys"
        showNonStandardKeyboardKeys = defaults.bool(forKey: nonStandardKeysKey)
        let appearanceKey = "\(AppConstants.defaultsPrefix).\(AppConstants.appearancePreferenceKey)"
        appearancePreference = AppearancePreference(rawValue: defaults.string(forKey: appearanceKey) ?? "") ?? .system
        inputMonitoringAuthorized = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        try? FileManager.default.createDirectory(at: selectedDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        MouseProfileCatalog.reload(customProfilesDirectory: customProfilesDirectory)
        refreshBackups()
        if startInitialRefresh {
            applyWindowAppearance(appearancePreference)
            isDarkAppearance = effectiveAppearanceIsDark(for: appearancePreference)
            Task { @MainActor in
                initialRefresh()
                startReconnectMonitor()
            }
        }
    }

    var defaultConfigurationDirectoryPath: String { defaultConfigurationDirectory.path }

    func setAppearancePreference(_ preference: AppearancePreference) {
        appearancePreference = preference
        applyWindowAppearance(preference)
        isDarkAppearance = effectiveAppearanceIsDark(for: preference)
        UserDefaults.standard.set(preference.rawValue, forKey: "\(AppConstants.defaultsPrefix).\(AppConstants.appearancePreferenceKey)")
    }

    private func effectiveAppearanceIsDark(for preference: AppearancePreference) -> Bool {
        switch preference {
        case .light:
            return false
        case .dark:
            return true
        case .system:
            let appearance = NSApp.windows.first?.effectiveAppearance ?? NSApp.effectiveAppearance
            return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    private func applyWindowAppearance(_ preference: AppearancePreference) {
        let appearance: NSAppearance?
        switch preference {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }

        // preferredColorScheme updates SwiftUI's controls, but clearing that
        // preference does not always make an existing WindowGroup re-adopt
        // the system appearance until the app loses focus. Apply the same
        // choice directly to the window so the effective appearance changes
        // while the app is still active.
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
            window.contentView?.appearance = appearance
            window.contentView?.needsDisplay = true
        }
    }

    var hasButtonChanges: Bool {
        let alternateRows = buttonLayer == .normal ? gShiftButtonRows : normalButtonRows
        return (buttons + alternateRows).contains {
            normalize($0.currentRaw) != normalize($0.draftRaw)
        }
    }

    var hasDPIChanges: Bool {
        dpiCount != baselineDPICount || dpiStages != baselineDPIStages ||
            defaultStage != baselineDefaultStage || shiftStage != baselineShiftStage
    }

    func rgbCapabilities(profileFormat: Int? = nil) -> MouseProfileDescriptor.RGBProfile? {
        let selected = devices.first(where: { $0.id == selectedDeviceIndex })
        guard currentMouseProfile.profileIO.canSave else { return nil }
        return currentMouseProfile.rgbCapabilities(
            deviceName: currentDeviceName.isEmpty ? (selected?.name ?? "") : currentDeviceName,
            productID: selected?.productID ?? "",
            profileFormat: profileFormat
        )
    }

    var shouldShowRGBEditor: Bool {
        !loadingProfile && !rgbZones.isEmpty && rgbCapabilities() != nil
    }

    var hasRGBChanges: Bool {
        rgbZones.contains { $0.current != $0.draft }
    }

    var canApplyDPI: Bool {
        dpiCapabilities.errorMessage == nil && dpiValidationMessage == nil
    }

    var canEditOnboardDPI: Bool {
        currentMouseProfile.profileIO.save["dpi"] != "unsupported"
    }

    var canEditProfileState: Bool {
        currentMouseProfile.profileIO.save["profileState"] != "unsupported"
    }

    var dpiValidationMessage: String? {
        DPIEditorValidation.message(
            stages: dpiStages,
            count: dpiCount,
            defaultStage: defaultStage,
            shiftStage: shiftStage,
            capabilities: dpiCapabilities
        )
    }

    var hasProfileChanges: Bool {
        profiles.contains { $0.enabled != (baselineProfileEnabled[$0.id] ?? $0.enabled) }
    }

    var hasPendingChanges: Bool {
        hasButtonChanges || hasDPIChanges || hasProfileChanges || hasRGBChanges
    }

    func setButtonRows(normal: [ButtonRow], gShift: [ButtonRow]) {
        normalButtonRows = normal
        gShiftButtonRows = gShift
        buttonLayer = .normal
        buttons = normal
        keyInputDrafts.removeAll()
        recordingKeyboardButtonID = nil
        resetProfileEditorDraft()
    }

    func selectButtonLayer(_ layer: ButtonLayer) {
        guard layer != buttonLayer else { return }
        guard layer == .normal || hasGShiftLayer else { return }

        if buttonLayer == .normal {
            normalButtonRows = buttons
        } else {
            gShiftButtonRows = buttons
        }
        buttonLayer = layer
        buttons = layer == .normal ? normalButtonRows : gShiftButtonRows
        keyInputDrafts.removeAll()
        recordingKeyboardButtonID = nil
    }

    func allButtonRowsForSave() -> [ButtonRow] {
        let alternateRows = buttonLayer == .normal ? gShiftButtonRows : normalButtonRows
        return buttons + alternateRows
    }
}
