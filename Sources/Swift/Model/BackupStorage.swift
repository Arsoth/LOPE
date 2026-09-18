// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

enum BackupStorage {
  static let supportedFileExtensions: Set<String> = ["logiob", "bin", "json"]

  static func sanitizedMouseIdentifier(_ value: String, fallback: String = "mouse") -> String {
    let folded = value.folding(
      options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
    var result = ""
    var needsSeparator = false
    for scalar in folded.unicodeScalars {
      let asciiAlphaNumeric =
        (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 65 && scalar.value <= 90)
        || (scalar.value >= 97 && scalar.value <= 122)
      if asciiAlphaNumeric {
        if needsSeparator && !result.isEmpty { result.append("-") }
        result.append(Character(String(scalar)))
        needsSeparator = false
      } else {
        needsSeparator = true
      }
    }
    let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
    let bounded = String(trimmed.prefix(32))
    return bounded.isEmpty ? fallback : bounded
  }

  static func modelDirectory(root: URL, mouseIdentifier: String) -> URL {
    root.appendingPathComponent(
      sanitizedMouseIdentifier(mouseIdentifier),
      isDirectory: true
    )
  }

  static func uniqueFilename(
    in directory: URL,
    mouseIdentifier: String,
    prefix: String,
    fileExtension: String,
    timestamp: String,
    fileManager: FileManager = .default
  ) -> String {
    let identifier = sanitizedMouseIdentifier(mouseIdentifier)
    let extensionWithoutDot =
      fileExtension.hasPrefix(".")
      ? String(fileExtension.dropFirst())
      : fileExtension
    let base = "\(identifier)-\(prefix)-\(timestamp)"
    var candidate = base
    var suffix = 2
    while fileManager.fileExists(
      atPath: directory.appendingPathComponent("\(candidate).\(extensionWithoutDot)").path
    ) {
      candidate = "\(base)-\(suffix)"
      suffix += 1
    }
    return candidate
  }

  static func uniqueBackupURL(
    root: URL,
    mouseIdentifier: String,
    prefix: String,
    fileExtension: String,
    timestamp: String,
    fileManager: FileManager = .default
  ) -> URL {
    let directory = modelDirectory(root: root, mouseIdentifier: mouseIdentifier)
    let extensionWithoutDot =
      fileExtension.hasPrefix(".")
      ? String(fileExtension.dropFirst())
      : fileExtension
    let filename = uniqueFilename(
      in: directory,
      mouseIdentifier: mouseIdentifier,
      prefix: prefix,
      fileExtension: fileExtension,
      timestamp: timestamp,
      fileManager: fileManager
    )
    return directory.appendingPathComponent("\(filename).\(extensionWithoutDot)")
  }

  static func documentsDirectory(fileManager: FileManager = .default) -> URL {
    fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Documents", isDirectory: true)
  }

  static func backupURLs(in root: URL, fileManager: FileManager = .default) -> [URL] {
    guard
      let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    return enumerator.compactMap { item in
      guard let url = item as? URL,
        supportedFileExtensions.contains(url.pathExtension.lowercased()),
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
        values.isDirectory == false
      else {
        return nil
      }
      return url
    }
  }

  static func restoreArguments(for url: URL) -> [String] {
    ["restore", url.path, "--yes"]
  }

  // Binary package metadata identifies the product; the model prefix in the
  // filename remains a human-readable sanity check and a useful fallback
  // for older packages whose names carry the only model hint.
  static func mouseIdentifier(fromBackupFilename filename: String) -> String? {
    let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
    guard let marker = stem.range(of: "-profile-", options: [.caseInsensitive]),
      marker.lowerBound != stem.startIndex
    else {
      return nil
    }
    let identifier = String(stem[..<marker.lowerBound])
    return identifier.isEmpty ? nil : identifier
  }
}
