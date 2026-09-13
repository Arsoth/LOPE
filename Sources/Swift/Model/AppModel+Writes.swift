// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  func applyButtons() {
    guard !busy else { return }
    guard currentMouseProfile.profileIO.canSave else {
      status = "\(currentMouseProfile.name) is cataloged as read-only for onboard profile writes."
      return
    }
    let changes = allButtonRowsForSave().filter {
      normalize($0.currentRaw) != normalize($0.draftRaw)
    }
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

  /// Polling rate is stored in the selected onboard profile. Stage the
  /// change here so it is written with the rest of the profile on Save.
  func applyPollingRate(_ rate: Int) {
    guard !busy else { return }
    guard pollingRateCapabilities.profileSupportedRates.contains(rate) else {
      status = "That polling rate cannot be saved in the selected onboard profile."
      return
    }
    pollingRateDraft = rate
    status = "Polling rate changed to \(rate) Hz; save the profile to write it to the mouse."
  }

  func applyAll() {
    guard !busy else { return }
    guard currentMouseProfile.profileIO.canSave else {
      status = "\(currentMouseProfile.name) is cataloged as read-only for onboard profile writes."
      return
    }
    let buttonChanges = allButtonRowsForSave().filter {
      normalize($0.currentRaw) != normalize($0.draftRaw)
    }
    let dpiChanged = hasDPIChanges
    let pollingRateChanged = hasPollingRateChanges
    let rgbChanges = rgbZones.filter { $0.current != $0.draft }
    let profileChanges =
      profiles
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
    guard
      !buttonChanges.isEmpty || dpiChanged || pollingRateChanged || !rgbChanges.isEmpty
        || !profileChanges.isEmpty
    else {
      status = "No changes to apply."
      return
    }
    guard !dpiChanged || canApplyDPI else {
      status = "Enter one to five numeric DPI stages before saving."
      return
    }
    guard validatePrimaryClickBeforeWrite() else { return }
    executeBatchSave(
      buttonChanges: buttonChanges, dpiChanged: dpiChanged,
      rgbChanges: rgbChanges, profileChanges: profileChanges,
      pollingRate: pollingRateChanged ? pollingRateDraft : nil)
  }

  private func executeBatchSave(
    buttonChanges: [ButtonRow],
    dpiChanged: Bool,
    rgbChanges: [RGBZoneState] = [],
    profileChanges: [ProfileChoice],
    pollingRate: Int? = nil
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
      "apply",
    ]
    arguments += buttonChanges.flatMap {
      let prefix = $0.layer == .gShift ? "gshift:" : "normal:"
      return ["--button-change", "\(prefix)\($0.id):\(normalize($0.draftRaw))"]
    }
    if dpiChanged {
      arguments += [
        "--dpi", dpiStages.prefix(dpiCount).joined(separator: ","),
        "--default", String(defaultStage),
        "--shift", String(shiftStage),
      ]
    }
    if let pollingRate {
      arguments += ["--report-rate", String(pollingRate)]
    }
    arguments += rgbChanges.map { ["--rgb-change", "\($0.id + 1):\($0.draft.bareHex)"] }.flatMap {
      $0
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
      let liveDPI = output.components(separatedBy: "\n")
        .first { $0.hasPrefix("Live default DPI:") }
      let liveSuffix = liveDPI.map { " \($0)" } ?? ""
      let rgbSuffix =
        rgbChanges.isEmpty ? "" : " RGB colors were read back from the profile summary."
      status =
        "Save operation \(operationID) complete: wrote \(verified) sector(s); each was backed up before writing and verified by exact read-back.\(rgbSuffix)\(liveSuffix)"
    } catch {
      let details = error.localizedDescription
      recoveryBackups = batchRecoveryBackups(from: details)
      recoveryDeviceKey =
        recoveryBackups.isEmpty
        ? nil
        : devices.first(where: { $0.id == selectedDeviceIndex })?.deviceKey
      let summary = batchFailureSummary(from: details)
      status =
        recoveryBackups.isEmpty
        ? details
        : "Save operation \(operationID) failed.\n\(summary)\nUse ‘Restore backups from this save’ to recover the pre-save sectors."
    }
  }

  var primaryClickValidationMessage: String? {
    let runtimeMouseName = devices.first(where: { $0.id == selectedDeviceIndex })?.name
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let mouseName =
      runtimeMouseName?.isEmpty == false
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

  private func saveOperationID() -> String {
    uniqueBackupStem(prefix: "profile-\(profileNumber)-save")
  }

  private func batchRecoveryBackups(from message: String) -> [URL] {
    var result: [URL] = []
    for line in message.components(separatedBy: "\n") where line.hasPrefix("Backup saved: ") {
      let value = String(line.dropFirst("Backup saved: ".count))
      let path =
        value.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? ""
      guard !path.isEmpty else { continue }
      let url = URL(fileURLWithPath: path)
      if !result.contains(url) { result.append(url) }
    }
    return result
  }

  private func batchFailureSummary(from message: String) -> String {
    let lines = message.components(separatedBy: "\n").filter { line in
      line.hasPrefix("Save operation") || line.hasPrefix("Preflight") || line.hasPrefix("Planned ")
        || line.hasPrefix("Backup saved: ") || line.hasPrefix("Writing ")
        || line.hasPrefix("Verified sector ") || line.contains("was not verified")
        || line.contains("stopped before any sector write")
    }
    return lines.isEmpty ? message : lines.joined(separator: "\n")
  }

}
