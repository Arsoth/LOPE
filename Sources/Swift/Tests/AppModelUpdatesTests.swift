// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

@MainActor
final class AppModelUpdatesTests: XCTestCase {
  private let successResponse = HTTPURLResponse(
    url: URL(string: "https://api.github.com")!,
    statusCode: 200,
    httpVersion: nil,
    headerFields: nil
  )!

  override func tearDown() {
    UserDefaults.standard.removeObject(
      forKey: "\(AppConstants.defaultsPrefix).automaticUpdateChecks"
    )
    super.tearDown()
  }

  private func client(releaseVersion: String) -> AppUpdateClient {
    let json = """
      {
        "tag_name": "\(releaseVersion)",
        "name": null,
        "html_url": null,
        "assets": [
          {
            "name": "LOPE-\(AppVersion(releaseVersion)?.description ?? releaseVersion)-macos-arm64.zip",
            "browser_download_url": "https://example.com/update.zip"
          }
        ]
      }
      """
    return AppUpdateClient(requestData: { _ in (Data(json.utf8), self.successResponse) })
  }

  private func release(version: String = "0.4.0") -> AppUpdateRelease {
    AppUpdateRelease(
      tagName: "v\(version)",
      name: "LOPE \(version)",
      htmlURL: nil,
      assets: [
        AppUpdateAsset(
          name: "LOPE-\(version)-macos-arm64.zip",
          browserDownloadURL: "https://example.com/update.zip"
        )
      ]
    )
  }

  private func waitFor(_ task: Task<Void, Never>?) async {
    await task?.value
  }

  func testManualCheckPublishesAvailableReleaseAndDismissesIt() async {
    let model = AppModel(
      startInitialRefresh: false, updateClient: client(releaseVersion: "v99.0.0"))
    model.checkForUpdates()
    await waitFor(model.updateCheckTask)

    XCTAssertFalse(model.updateCheckInProgress)
    XCTAssertEqual(model.updateAvailable?.displayVersion, "99.0.0")
    XCTAssertTrue(model.updateAvailableMessage.contains("99.0.0"))
    model.dismissAvailableUpdate()
    XCTAssertNil(model.updateAvailable)
  }

  func testManualCheckReportsUpToDateAndErrors() async {
    let currentModel = AppModel(
      startInitialRefresh: false,
      updateClient: client(releaseVersion: "v0.0.0")
    )
    currentModel.checkForUpdates()
    await waitFor(currentModel.updateCheckTask)
    XCTAssertEqual(currentModel.updateCheckMessage, "LOPE is up to date.")

    let failingClient = AppUpdateClient(requestData: { _ in
      throw AppUpdateError.invalidResponse
    })
    let failingModel = AppModel(startInitialRefresh: false, updateClient: failingClient)
    failingModel.checkForUpdates()
    await waitFor(failingModel.updateCheckTask)
    XCTAssertFalse(failingModel.updateCheckInProgress)
    XCTAssertNotNil(failingModel.updateErrorMessage)
  }

  func testAutomaticCheckCanBeDisabledAndCancelled() async {
    let model = AppModel(startInitialRefresh: false, updateClient: client(releaseVersion: "v0.4.0"))
    model.setAutomaticUpdateChecksEnabled(false)
    model.startAutomaticUpdateCheck()
    XCTAssertFalse(model.updateCheckInProgress)

    model.setAutomaticUpdateChecksEnabled(true)
    model.startAutomaticUpdateCheck()
    let automaticTask = model.updateCheckTask
    model.cancelUpdateCheck()
    await waitFor(automaticTask)

    model.updateCheckInProgress = true
    model.cancelUpdateCheck()
    XCTAssertFalse(model.updateCheckInProgress)
    XCTAssertNil(model.updateCheckTask)
    XCTAssertEqual(model.updateAvailableMessage, "")
  }

  func testInstallFailureIsReportedWhenRunningOutsideAnAppBundle() async {
    let dataResponse = successResponse
    let client = AppUpdateClient(requestData: { _ in (Data([1, 2, 3]), dataResponse) })
    let model = AppModel(startInitialRefresh: false, updateClient: client)
    model.installAvailableUpdate()
    model.updateAvailable = release()
    model.installAvailableUpdate()
    await waitFor(model.updateInstallTask)

    XCTAssertFalse(model.updateCheckInProgress)
    XCTAssertNotNil(model.updateErrorMessage)
    XCTAssertNil(model.updateAvailable)
  }

  func testInstallCancellationLeavesTheTaskWithoutReportingAnError() async {
    let response = successResponse
    let client = AppUpdateClient(requestData: { _ in
      try await Task.sleep(nanoseconds: 1_000_000_000)
      return (Data([1, 2, 3]), response)
    })
    let model = AppModel(startInitialRefresh: false, updateClient: client)
    model.updateAvailable = release()
    model.installAvailableUpdate()
    let installTask = model.updateInstallTask
    installTask?.cancel()
    await waitFor(installTask)

    XCTAssertNil(model.updateErrorMessage)
  }
}
