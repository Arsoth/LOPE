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
    @Published var profileNumber = 1
    @Published var buttons: [ButtonRow] = []
    @Published var dpiStages = ["", "", "", "", ""]
    @Published var dpiCount = 5
    @Published var defaultStage = 3
    @Published var shiftStage = 1
    @Published var dpiDetails = "DPI capabilities have not been read."
    @Published var busy = false
    @Published var loadingProfile = false
    @Published var inputMonitoringAuthorized = false
    @Published var backups: [BackupEntry] = []
    @Published var backupDirectoryPath = ""
    @Published var showAdvancedFields = false
    @Published var highlightButtonPresses = false
    @Published var highlightedButtonID: Int?

    var keyInputDrafts: [Int: String] = [:]
    var baselineProfileEnabled: [Int: Bool] = [:]
    var baselineDPIStages = [String]()
    var baselineDPICount = 5
    var baselineDefaultStage = 3
    var baselineShiftStage = 1
    var currentDeviceName = ""
    var refreshTask: Task<Void, Never>?
    var highlightExpiryTask: Task<Void, Never>?
    var refreshGeneration = 0
    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?

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
        let highlightButtonPressesKey = "\(AppConstants.defaultsPrefix).highlightButtonPresses"
        highlightButtonPresses = defaults.bool(forKey: highlightButtonPressesKey)
        inputMonitoringAuthorized = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        try? FileManager.default.createDirectory(at: selectedDirectory, withIntermediateDirectories: true)
        refreshBackups()
        if highlightButtonPresses {
            startButtonPressMonitor()
        }
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
        guard (1...5).contains(dpiCount), dpiStages.count == 5 else { return false }
        return dpiStages.prefix(dpiCount).allSatisfy { UInt16($0) != nil }
    }

    var hasProfileChanges: Bool {
        profiles.contains { $0.enabled != (baselineProfileEnabled[$0.id] ?? $0.enabled) }
    }

    var hasPendingChanges: Bool {
        hasButtonChanges || hasDPIChanges || hasProfileChanges
    }
}
