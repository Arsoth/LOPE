// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  /// The standard modern HID++ 0x8100 writer fields shared by every
  /// verified current-generation descriptor (see g502-hero.json and
  /// Profiles/README.md). Used as the starting point for a brand-new
  /// descriptor, since a live connected device that reached this editor
  /// has already confirmed the feature works exactly this way.
  private static let standardModernProfileIO = MouseProfileDescriptor.ProfileIO(
    supported: true,
    capability: "HID++ 2.0 ONBOARD_PROFILES",
    feature: "0x8100",
    load: [
      "command": "profiles",
      "engineArguments": "--summary-only --with-dpi --profile <number>",
      "getInfo": "0x00",
      "readSector": "0x50",
      "controlSector": "0; fallback 1 when empty",
      "explicitProfile": "required when multiple slots",
    ],
    save: [
      "strategy": "standard-hidpp20-sector-write",
      "startWrite": "0x60",
      "writeData": "0x70",
      "endWrite": "0x80",
      "chunkBytes": "16",
      "backup": "exact binary sector before write",
      "verify": "CRC and full-sector readback",
    ],
    layout: [
      "buttonRecord": "4 bytes per control",
      "buttonOffsetByFormat": "format 4/5 -> 32; format 6/7 -> 48",
      "crc": "CRC-16/CCITT-FALSE",
    ],
    notes: []
  )

  /// Re-primes the profile editor from whatever descriptor currently
  /// applies to the connected device (built-in, custom, or generated), or
  /// synthesizes a fresh full descriptor -- using the standard modern
  /// profileIO fields and a best-effort scroll-wheel guess from each
  /// button's current live output -- when none matches. Called whenever
  /// `setButtonRows` runs, so the editor tracks the same live button list
  /// as the Configure tab and, like the rest of the app's edit state,
  /// resets on every refresh rather than surviving across a device change.
  func resetProfileEditorDraft() {
    let selected = devices.first(where: { $0.id == selectedDeviceIndex })
    let deviceName = currentDeviceName.isEmpty ? (selected?.name ?? "") : currentDeviceName
    let productID = selected?.productID ?? ""

    let base: MouseProfileDescriptor
    if hasSpecificMouseProfile {
      base = currentMouseProfile
    } else {
      let rawByNumber = Dictionary(
        uniqueKeysWithValues: normalButtonRows.map { ($0.id, $0.currentRaw) })
      var scrollLabels: [String: String] = [:]
      for number in profileEditorButtonNumbers {
        if let raw = rawByNumber[number],
          let label = ProfileOutputParser.scrollWheelOutputLabel(raw)
        {
          scrollLabels[String(number)] = label
        }
      }
      base = MouseProfileDescriptor(
        schemaVersion: 1,
        id: "",
        name: "",
        match: .init(nameContains: [], productIDs: []),
        buttons: profileEditorButtonNumbers.map {
          .init(number: $0, control: "Button \($0)", aliases: [], notes: nil)
        },
        scrollWheelButtonLabels: scrollLabels.isEmpty ? nil : scrollLabels,
        hiddenProfileButtonNumbers: nil,
        dpiRange: nil,
        refreshGuidance: nil,
        profileIO: Self.standardModernProfileIO,
        rgbProfile: nil,
        sources: []
      )
    }
    profileEditorBase = base

    let fallbackIdentifier = BackupStorage.sanitizedMouseIdentifier(
      deviceName.isEmpty ? productID : deviceName,
      fallback: "mouse"
    )
    profileEditorID = hasSpecificMouseProfile ? base.id : fallbackIdentifier
    profileEditorName =
      hasSpecificMouseProfile
      ? base.name
      : (deviceName.isEmpty ? "Unnamed mouse" : deviceName)
    profileEditorSources = base.sources.joined(separator: "\n")

    var names: [Int: String] = [:]
    for number in profileEditorButtonNumbers {
      names[number] =
        base.button(for: number)?.control
        ?? base.scrollWheelButtonLabel(for: number)
        ?? "Button \(number)"
    }
    profileEditorButtonNames = names
  }

  /// Merges the editable overlay (id, name, match target, sources, dpi
  /// range, and each button's control name) onto
  /// `profileEditorBase`, so every other field -- aliases, scroll-wheel
  /// labels, hidden-button numbers, refresh guidance, RGB zones, and
  /// profileIO -- survives unchanged. The result is meant to be a complete
  /// descriptor a contributor could drop into `Profiles/` and open a PR
  /// with unmodified.
  func buildProfileEditorDescriptor() -> MouseProfileDescriptor? {
    let trimmedID = profileEditorID.trimmingCharacters(in: .whitespaces)
    guard !trimmedID.isEmpty, !profileEditorButtonNumbers.isEmpty, let base = profileEditorBase
    else {
      return nil
    }
    let id = BackupStorage.sanitizedMouseIdentifier(trimmedID, fallback: "mouse")
    let trimmedName = profileEditorName.trimmingCharacters(in: .whitespaces)

    let selected = devices.first(where: { $0.id == selectedDeviceIndex })
    let deviceName = currentDeviceName.isEmpty ? (selected?.name ?? "") : currentDeviceName
    let productID = selected?.productID ?? ""

    let buttons = profileEditorButtonNumbers.map { number -> MouseProfileDescriptor.Button in
      let trimmedControl = (profileEditorButtonNames[number] ?? "").trimmingCharacters(
        in: .whitespaces)
      let existing = base.button(for: number)
      return MouseProfileDescriptor.Button(
        number: number,
        control: trimmedControl.isEmpty
          ? (existing?.control ?? "Button \(number)") : trimmedControl,
        aliases: existing?.aliases ?? [],
        notes: existing?.notes
      )
    }
    let sources =
      profileEditorSources
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    let dpiRange: MouseProfileDescriptor.DPIRange? = {
      guard let minimum = dpiCapabilities.minimum, let maximum = dpiCapabilities.maximum else {
        return base.dpiRange
      }
      return MouseProfileDescriptor.DPIRange(minimum: minimum, maximum: maximum)
    }()

    return MouseProfileDescriptor(
      schemaVersion: 1,
      id: id,
      name: trimmedName.isEmpty ? id : trimmedName,
      match: .init(
        nameContains: deviceName.isEmpty ? [] : [deviceName],
        productIDs: productID.isEmpty ? [] : [productID]
      ),
      buttons: buttons,
      scrollWheelButtonLabels: base.scrollWheelButtonLabels,
      hiddenProfileButtonNumbers: base.hiddenProfileButtonNumbers,
      dpiRange: dpiRange,
      refreshGuidance: base.refreshGuidance,
      profileIO: base.profileIO,
      rgbProfile: base.rgbProfile,
      sources: sources,
      generated: nil
    )
  }

  /// Writes the current draft to the custom profiles folder as a normal
  /// (non-`generated`) descriptor, so it ranks the same as any other
  /// hand-authored profile, then reloads the catalog so it applies
  /// immediately. Refused outright for an MX-classified device, matching
  /// `createGeneratedProfile()`: a device merely answering the onboard
  /// profile feature query is not evidence that naming or writing to it is
  /// meaningful. See Profiles/README.md.
  @discardableResult
  func saveProfileEditorDraft() -> URL? {
    guard !isMXSeriesMouse else {
      status =
        "LOPE does not save profiles for MX-series mice; their controls are managed by Logi Options+, not onboard memory."
      return nil
    }
    guard let descriptor = buildProfileEditorDescriptor() else {
      status = "Enter a profile ID before saving."
      return nil
    }

    let directory = customProfilesDirectory
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("\(descriptor.id).json")
    guard let data = try? Self.profileEditorEncoder.encode(descriptor),
      (try? data.write(to: url, options: .atomic)) != nil
    else {
      status = "Could not write the profile to \(directory.path)."
      return nil
    }

    MouseProfileCatalog.reload(customProfilesDirectory: customProfilesDirectory)
    status = "Saved \(url.lastPathComponent) to the custom profiles folder."
    refresh()
    return url
  }

  /// Writes `descriptor` to `url` as the exported profile JSON. Called by
  /// `exportProfileEditorDraft()` (Shims/) once the save panel returns a
  /// URL; kept here, taking a plain URL, so it stays unit-testable.
  @discardableResult
  func writeProfileEditorExport(_ descriptor: MouseProfileDescriptor, to url: URL) -> Bool {
    guard let data = try? Self.profileEditorEncoder.encode(descriptor),
      (try? data.write(to: url, options: .atomic)) != nil
    else {
      status = "Could not export the profile to \(url.path)."
      return false
    }
    status = "Exported \(url.lastPathComponent)."
    return true
  }

  /// Applies `descriptor` (loaded from `url`) as the new profile editor
  /// base -- id, name, sources, aliases, scroll-wheel labels,
  /// hidden-button numbers, refresh guidance, RGB zones, and profileIO all
  /// included -- so it can serve as a full template for the connected
  /// mouse, not just a source of button names. `match.nameContains`/
  /// `productIDs` are still re-derived from the connected device on save
  /// or export, since the draft always targets whatever mouse is plugged
  /// in now, regardless of which file it was templated from. Called by
  /// `importProfileEditorDraft()` (Shims/) once the open panel returns a
  /// URL and the file decodes; kept here, taking a plain descriptor/URL,
  /// so it stays unit-testable.
  func applyImportedProfileEditorDraft(_ descriptor: MouseProfileDescriptor, from url: URL) {
    profileEditorBase = descriptor
    profileEditorID = descriptor.id
    profileEditorName = descriptor.name
    profileEditorSources = descriptor.sources.joined(separator: "\n")
    for number in profileEditorButtonNumbers {
      profileEditorButtonNames[number] =
        descriptor.button(for: number)?.control
        ?? descriptor.scrollWheelButtonLabel(for: number)
        ?? profileEditorButtonNames[number]
        ?? "Button \(number)"
    }
    status = "Loaded \(url.lastPathComponent) as a template."
  }

  private static let profileEditorEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()
}
