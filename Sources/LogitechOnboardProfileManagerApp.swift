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
    @Published var dpiStages = ["", "", "", "", ""]
    @Published var dpiCount = 5
    @Published var defaultStage = 3
    @Published var shiftStage = 1
    @Published var dpiCapabilities = DPICapabilities()
    @Published var dpiDetails = "DPI capabilities have not been read."
    @Published var busy = false
    @Published var loadingProfile = false
    @Published var inputMonitoringAuthorized = false
    @Published var backups: [BackupEntry] = []
    @Published var showAllBackups = false
    @Published var recoveryBackups: [URL] = []
    @Published var backupDirectoryPath = ""
    @Published var showAdvancedFields = false

    var keyInputDrafts: [Int: String] = [:]
    var baselineProfileEnabled: [Int: Bool] = [:]
    var baselineDPIStages = [String]()
    var baselineDPICount = 5
    var baselineDefaultStage = 3
    var baselineShiftStage = 1
    var currentDeviceName = ""
    var refreshTask: Task<Void, Never>?
    var refreshGeneration = 0
    var recoveryDeviceKey: String?
    var discoveredBackups: [BackupEntry] = []

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

    var isMXSeriesMouse: Bool {
        let tokens = currentDeviceName.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return tokens.contains("mx")
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

    var backupDirectory: URL
    let defaultBackupDirectory: URL

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
        inputMonitoringAuthorized = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        try? FileManager.default.createDirectory(at: selectedDirectory, withIntermediateDirectories: true)
        refreshBackups()
        Task { @MainActor in
            initialRefresh()
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
        dpiValidationMessage == nil
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
        hasButtonChanges || hasDPIChanges || hasProfileChanges
    }
}
