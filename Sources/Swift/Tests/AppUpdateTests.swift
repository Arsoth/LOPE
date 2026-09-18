// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import XCTest

@testable import LOPECore

final class AppUpdateTests: XCTestCase {
  private let releaseJSON = """
    {
      "tag_name": "v0.4.0",
      "name": "LOPE 0.4.0",
      "html_url": "https://github.com/Arsoth/LOPE/releases/tag/v0.4.0",
      "assets": [
        {
          "name": "LOPE-0.4.0-macos-arm64.zip",
          "browser_download_url": "https://github.com/Arsoth/LOPE/releases/download/v0.4.0/LOPE-0.4.0-macos-arm64.zip"
        },
        {
          "name": "LOPE-0.4.0-macos-x86_64.zip",
          "browser_download_url": "https://github.com/Arsoth/LOPE/releases/download/v0.4.0/LOPE-0.4.0-macos-x86_64.zip"
        }
      ]
    }
    """

  func testAppVersionParsesTagsAndComparesSemantically() {
    XCTAssertEqual(AppVersion("v1.2.3-beta")?.description, "1.2.3")
    XCTAssertTrue(AppVersion("1.10.0")! > AppVersion("1.9.99")!)
    XCTAssertEqual(AppVersion("2")?.description, "2.0.0")
  }

  func testAppVersionRejectsMalformedValues() {
    XCTAssertNil(AppVersion(""))
    XCTAssertNil(AppVersion("v1..2"))
    XCTAssertNil(AppVersion("1.2.3.4"))
  }

  func testReleaseDecodesAndSelectsArchitectureAsset() throws {
    let release = try JSONDecoder().decode(
      AppUpdateRelease.self,
      from: Data(releaseJSON.utf8)
    )

    XCTAssertEqual(release.displayVersion, "0.4.0")
    XCTAssertEqual(release.id, "v0.4.0")
    XCTAssertEqual(release.asset(for: "arm64")?.name, "LOPE-0.4.0-macos-arm64.zip")
    XCTAssertEqual(release.asset(for: "x86_64")?.name, "LOPE-0.4.0-macos-x86_64.zip")
    XCTAssertNil(release.asset(for: "unknown"))

    let fallback = AppUpdateRelease(
      tagName: "release-name",
      name: nil,
      htmlURL: nil,
      assets: [
        AppUpdateAsset(
          name: "release-macos-arm64.zip",
          browserDownloadURL: "https://example.com/update.zip"
        )
      ]
    )
    XCTAssertEqual(fallback.asset(for: "arm64")?.name, "release-macos-arm64.zip")
    XCTAssertEqual(fallback.displayVersion, "release-name")
  }

  func testLatestReleaseReturnsOnlyAReleaseNewerThanInstalledVersion() async throws {
    let data = Data(releaseJSON.utf8)
    let response = HTTPURLResponse(
      url: URL(string: "https://api.github.com")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    let client = AppUpdateClient(requestData: { _ in (data, response) })

    let update = try await client.latestRelease(currentVersion: "0.3.0", architecture: "arm64")
    XCTAssertEqual(update?.displayVersion, "0.4.0")

    let noUpdate = try await client.latestRelease(currentVersion: "0.4.0", architecture: "arm64")
    XCTAssertNil(noUpdate)
  }

  func testLatestReleaseReportsHTTPFailuresAndMissingAssets() async {
    let response = HTTPURLResponse(
      url: URL(string: "https://api.github.com")!,
      statusCode: 503,
      httpVersion: nil,
      headerFields: nil
    )!
    let failingClient = AppUpdateClient(requestData: { _ in (Data(), response) })

    do {
      _ = try await failingClient.latestRelease(currentVersion: "0.3.0", architecture: "arm64")
      XCTFail("Expected the HTTP failure to be reported")
    } catch let error as AppUpdateError {
      XCTAssertEqual(error, .httpStatus(503))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let data = Data(releaseJSON.utf8)
    let okResponse = HTTPURLResponse(
      url: URL(string: "https://api.github.com")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    let client = AppUpdateClient(requestData: { _ in (data, okResponse) })
    do {
      _ = try await client.latestRelease(currentVersion: "0.3.0", architecture: "unknown")
      XCTFail("Expected the missing asset to be reported")
    } catch let error as AppUpdateError {
      XCTAssertEqual(error, .missingAsset("unknown"))
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testLatestReleaseReportsInvalidVersionsAndJSON() async {
    let response = HTTPURLResponse(
      url: URL(string: "https://api.github.com")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    let invalidJSONClient = AppUpdateClient(requestData: { _ in (Data("{}".utf8), response) })

    do {
      _ = try await invalidJSONClient.latestRelease(currentVersion: "0.3.0", architecture: "arm64")
      XCTFail("Expected malformed release JSON to be reported")
    } catch let error as AppUpdateError {
      XCTAssertEqual(error, .invalidResponse)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }

    let data = Data(releaseJSON.utf8)
    let client = AppUpdateClient(requestData: { _ in (data, response) })
    do {
      _ = try await client.latestRelease(currentVersion: "not-a-version", architecture: "arm64")
      XCTFail("Expected an invalid installed version to be reported")
    } catch let error as AppUpdateError {
      XCTAssertEqual(error, .invalidVersion)
    } catch {
      XCTFail("Unexpected error: \(error)")
    }
  }

  func testDownloadReturnsDataAndValidatesResponses() async throws {
    let release = try JSONDecoder().decode(
      AppUpdateRelease.self,
      from: Data(releaseJSON.utf8)
    )
    let successResponse = HTTPURLResponse(
      url: URL(string: "https://github.com")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    let client = AppUpdateClient(requestData: { _ in (Data([1, 2, 3]), successResponse) })
    let downloadedData = try await client.download(release, architecture: "arm64")
    XCTAssertEqual(
      downloadedData,
      Data([1, 2, 3])
    )

    let failureResponse = HTTPURLResponse(
      url: URL(string: "https://github.com")!,
      statusCode: 404,
      httpVersion: nil,
      headerFields: nil
    )!
    let failingClient = AppUpdateClient(requestData: { _ in (Data(), failureResponse) })
    do {
      _ = try await failingClient.download(release, architecture: "arm64")
      XCTFail("Expected the download HTTP failure to be reported")
    } catch let error as AppUpdateError {
      XCTAssertEqual(error, .httpStatus(404))
    }
  }

  func testUpdateErrorsHaveUserFacingDescriptions() {
    let errors: [AppUpdateError] = [
      .invalidResponse,
      .httpStatus(500),
      .invalidVersion,
      .missingAsset("arm64"),
      .invalidDownloadURL,
      .notPackaged,
      .archiveExtractionFailed,
      .replacementLaunchFailed,
    ]
    for error in errors {
      XCTAssertFalse(error.localizedDescription.isEmpty)
    }

    XCTAssertFalse(AppUpdateClient.installedVersion.isEmpty)
    XCTAssertEqual(AppUpdateClient.versionOrDefault(nil), "0.0.0")
    XCTAssertEqual(AppUpdateClient.versionOrDefault("1.2.3"), "1.2.3")
    XCTAssertEqual(AppUpdateClient.currentArchitecture, "arm64")
  }

  func testDownloadRejectsNonHTTPSAssetURLs() async throws {
    let response = HTTPURLResponse(
      url: URL(string: "https://api.github.com")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    let client = AppUpdateClient(requestData: { _ in (Data(), response) })
    let release = AppUpdateRelease(
      tagName: "v0.4.0",
      name: "LOPE 0.4.0",
      htmlURL: nil,
      assets: [
        AppUpdateAsset(
          name: "LOPE-0.4.0-macos-arm64.zip",
          browserDownloadURL: "http://example.com/update.zip"
        )
      ]
    )

    do {
      _ = try await client.download(release, architecture: "arm64")
      XCTFail("Expected the insecure URL to be rejected")
    } catch let error as AppUpdateError {
      XCTAssertEqual(error, .invalidDownloadURL)
    }
  }
}
