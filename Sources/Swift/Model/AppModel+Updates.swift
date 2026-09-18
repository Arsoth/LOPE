// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import Foundation

@MainActor
extension AppModel {
  var updateAvailableMessage: String {
    guard let updateAvailable else { return "" }
    return L10n.text(
      "LOPE version {version} is available. Download and install it now?",
      replacements: ["version": updateAvailable.displayVersion]
    )
  }

  func startAutomaticUpdateCheck() {
    guard automaticUpdateChecksEnabled else { return }
    scheduleUpdateCheck(delayNanoseconds: 1_000_000_000, isManual: false)
  }

  func checkForUpdates() {
    scheduleUpdateCheck(delayNanoseconds: 0, isManual: true)
  }

  func dismissAvailableUpdate() {
    updateAvailable = nil
  }

  func installAvailableUpdate() {
    guard let updateAvailable else { return }
    self.updateAvailable = nil
    updateCheckInProgress = true
    updateCheckMessage = L10n.text("Downloading update…")
    updateErrorMessage = nil

    let client = updateClient
    updateInstallTask?.cancel()
    updateInstallTask = Task { @MainActor [weak self] in
      do {
        let archive = try await client.download(
          updateAvailable,
          architecture: AppUpdateClient.currentArchitecture
        )
        try AppUpdateInstaller.prepareAndLaunch(
          archiveData: archive,
          currentAppURL: Bundle.main.bundleURL
        )
        NSApp.terminate(nil)
      } catch is CancellationError {
        return
      } catch {
        guard let self else { return }
        self.updateCheckInProgress = false
        self.updateCheckMessage = nil
        self.updateErrorMessage = error.localizedDescription
      }
    }
  }

  func cancelUpdateCheck() {
    updateCheckTask?.cancel()
    updateCheckTask = nil
    updateCheckInProgress = false
  }

  private func scheduleUpdateCheck(delayNanoseconds: UInt64, isManual: Bool) {
    updateCheckTask?.cancel()
    updateCheckInProgress = true
    updateCheckMessage = nil
    updateErrorMessage = nil

    let client = updateClient
    updateCheckTask = Task { @MainActor [weak self] in
      do {
        if delayNanoseconds > 0 {
          try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard let self, !Task.isCancelled else { return }
        let release = try await client.latestRelease(
          currentVersion: AppUpdateClient.installedVersion,
          architecture: AppUpdateClient.currentArchitecture
        )
        guard !Task.isCancelled else { return }
        self.updateCheckInProgress = false
        self.updateCheckTask = nil
        if let release {
          self.updateAvailable = release
          self.updateCheckMessage = L10n.text(
            "Version {version} is available.",
            replacements: ["version": release.displayVersion]
          )
        } else if isManual {
          self.updateCheckMessage = L10n.text("LOPE is up to date.")
        }
      } catch is CancellationError {
        return
      } catch {
        guard let self, !Task.isCancelled else { return }
        self.updateCheckInProgress = false
        self.updateCheckTask = nil
        if isManual {
          self.updateErrorMessage = error.localizedDescription
        }
      }
    }
  }
}
