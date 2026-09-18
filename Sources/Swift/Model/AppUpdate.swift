// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
  let major: Int
  let minor: Int
  let patch: Int

  init?(_ rawValue: String) {
    var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.first == "v" || value.first == "V" {
      value.removeFirst()
    }

    guard let core = value.split(separator: "-", maxSplits: 1).first else { return nil }
    let components = core.split(separator: ".", omittingEmptySubsequences: false)
    guard !components.isEmpty, components.count <= 3 else { return nil }
    guard components.allSatisfy({ Int($0) != nil }) else { return nil }

    major = Int(components[0])!
    minor = components.count > 1 ? Int(components[1])! : 0
    patch = components.count > 2 ? Int(components[2])! : 0
  }

  var description: String {
    "\(major).\(minor).\(patch)"
  }

  static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
    (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
  }
}

struct AppUpdateAsset: Decodable, Equatable, Sendable {
  let name: String
  let browserDownloadURL: String

  enum CodingKeys: String, CodingKey {
    case name
    case browserDownloadURL = "browser_download_url"
  }
}

struct AppUpdateRelease: Decodable, Equatable, Identifiable, Sendable {
  let tagName: String
  let name: String?
  let htmlURL: URL?
  let assets: [AppUpdateAsset]

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case name
    case htmlURL = "html_url"
    case assets
  }

  var id: String { tagName }

  var version: AppVersion? {
    AppVersion(tagName)
  }

  var displayVersion: String {
    if let version {
      return version.description
    }
    return tagName
  }

  func asset(for architecture: String) -> AppUpdateAsset? {
    let normalizedArchitecture = architecture.lowercased()
    let exactName = "lope-\(displayVersion)-macos-\(normalizedArchitecture).zip"
    if let exact = assets.first(where: { $0.name.lowercased() == exactName }) {
      return exact
    }

    return assets.first { asset in
      let name = asset.name.lowercased()
      return name.hasSuffix(".zip")
        && name.contains("macos")
        && name.contains(normalizedArchitecture)
    }
  }
}

enum AppUpdateError: LocalizedError, Equatable, Sendable {
  case invalidResponse
  case httpStatus(Int)
  case invalidVersion
  case missingAsset(String)
  case invalidDownloadURL
  case notPackaged
  case archiveExtractionFailed
  case replacementLaunchFailed

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return L10n.text("GitHub returned an invalid update response.")
    case .httpStatus(let status):
      return L10n.text(
        "GitHub returned HTTP status {status}.",
        replacements: ["status": "\(status)"]
      )
    case .invalidVersion:
      return L10n.text("The installed or released LOPE version is invalid.")
    case .missingAsset(let architecture):
      return L10n.text(
        "No macOS {architecture} update was published for this release.",
        replacements: ["architecture": architecture]
      )
    case .invalidDownloadURL:
      return L10n.text("The GitHub update download URL is invalid.")
    case .notPackaged:
      return L10n.text("Updates can only be installed from a packaged LOPE app.")
    case .archiveExtractionFailed:
      return L10n.text("The downloaded LOPE update could not be opened.")
    case .replacementLaunchFailed:
      return L10n.text("LOPE could not start the update installer.")
    }
  }
}

struct AppUpdateClient: Sendable {
  typealias RequestData = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  private let requestData: RequestData

  static let live = AppUpdateClient(requestData: AppUpdateNetworking.requestData)

  init(requestData: @escaping RequestData) {
    self.requestData = requestData
  }

  func latestRelease(currentVersion: String, architecture: String) async throws
    -> AppUpdateRelease?
  {
    let release = try await fetchLatestRelease()
    guard let latestVersion = release.version,
      let installedVersion = AppVersion(currentVersion)
    else {
      throw AppUpdateError.invalidVersion
    }
    guard latestVersion > installedVersion else { return nil }
    guard release.asset(for: architecture) != nil else {
      throw AppUpdateError.missingAsset(architecture)
    }
    return release
  }

  func fetchLatestRelease() async throws -> AppUpdateRelease {
    let url = URL(
      string: "https://api.github.com/repos/\(AppConstants.updateRepository)/releases/latest"
    )!
    let (data, response) = try await requestData(
      makeRequest(url: url, accepts: "application/vnd.github+json")
    )
    try validate(response)
    do {
      return try JSONDecoder().decode(AppUpdateRelease.self, from: data)
    } catch {
      throw AppUpdateError.invalidResponse
    }
  }

  func download(_ release: AppUpdateRelease, architecture: String) async throws -> Data {
    guard let asset = release.asset(for: architecture),
      let url = URL(string: asset.browserDownloadURL),
      url.scheme?.lowercased() == "https"
    else {
      throw AppUpdateError.invalidDownloadURL
    }

    let (data, response) = try await requestData(
      makeRequest(url: url, accepts: "application/octet-stream")
    )
    try validate(response)
    return data
  }

  static var installedVersion: String {
    versionOrDefault(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    )
  }

  static func versionOrDefault(_ version: String?) -> String {
    version ?? "0.0.0"
  }

  static var currentArchitecture: String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x86_64"
    #else
      return "unknown"
    #endif
  }

  private func makeRequest(url: URL, accepts: String) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue(accepts, forHTTPHeaderField: "Accept")
    request.setValue("LOPE/\(Self.installedVersion)", forHTTPHeaderField: "User-Agent")
    return request
  }

  private func validate(_ response: URLResponse) throws {
    guard let response = response as? HTTPURLResponse else {
      throw AppUpdateError.invalidResponse
    }
    guard (200..<300).contains(response.statusCode) else {
      throw AppUpdateError.httpStatus(response.statusCode)
    }
  }
}
