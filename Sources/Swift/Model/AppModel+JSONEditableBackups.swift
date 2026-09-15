// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  func exportCurrentJSON(to url: URL) {
    guard !profiles.isEmpty else {
      status = "Read a Logitech profile before exporting JSON."
      return
    }
    do {
      let backup = makeEditableBackup()
      try writeEditableBackup(backup, to: url)
      refreshBackups()
      status = "Exported profile \(profileNumber) to \(url.path)."
    } catch {
      status = "Could not export JSON: \(error.localizedDescription)"
    }
  }

  func loadEditableBackup(_ url: URL) {
    guard !busy else { return }
    guard !profiles.isEmpty else {
      status = "Read a Logitech profile before loading JSON."
      return
    }
    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      let backup = try decoder.decode(EditableBackup.self, from: data)
      guard backup.formatVersion == 1 else {
        status = "Unsupported JSON profile version \(backup.formatVersion)."
        return
      }
      guard backup.profile.number == profileNumber else {
        status = "Select Profile \(backup.profile.number) before loading this JSON file."
        return
      }

      var proposedStates = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.enabled) })
      for state in backup.profiles where proposedStates[state.number] != nil {
        proposedStates[state.number] = state.enabled
      }
      if proposedStates[backup.profile.number] != nil {
        proposedStates[backup.profile.number] = backup.profile.enabled
      }
      guard proposedStates.values.contains(true) else {
        status = "The JSON would disable every onboard profile. At least one must remain enabled."
        return
      }

      var proposedButtons: [(ButtonLayer, Int, String)] = []
      for button in backup.profile.buttons {
        guard let layer = ButtonLayer(rawValue: button.layer) else {
          status = "JSON button \(button.number) has an unrecognized layer '\(button.layer)'."
          return
        }
        // `buttons` is the active-layer source of truth while the
        // editor is being initialized; use it for the active layer
        // even when the test/import caller has not populated the
        // cached per-layer array separately.
        let targetRows =
          layer == buttonLayer
          ? buttons
          : (layer == .normal ? normalButtonRows : gShiftButtonRows)
        guard let index = targetRows.firstIndex(where: { $0.id == button.number }),
          let raw = jsonRaw(for: button)
        else {
          status =
            "JSON \(layer.label) button \(button.number) has no recognized output or 8-digit raw record."
          return
        }
        proposedButtons.append((layer, index, raw))
      }

      var proposedDPI: EditableBackup.DPI?
      if let dpi = backup.profile.dpi {
        guard (1...5).contains(dpi.stages.count),
          dpi.stages.allSatisfy({ (100...65535).contains($0) }),
          dpi.stages == dpi.stages.sorted(),
          Set(dpi.stages).count == dpi.stages.count,
          (1...dpi.stages.count).contains(dpi.defaultStage),
          (1...dpi.stages.count).contains(dpi.shiftStage)
        else {
          status = "The JSON DPI values or stage indexes are invalid."
          return
        }
        proposedDPI = dpi
      }

      var proposedRGB: [Int: RGBColor] = [:]
      if let rgb = backup.profile.rgb {
        guard let capability = rgbCapabilities(), !capability.zones.isEmpty else {
          status =
            "This JSON contains RGB settings, but the selected device/profile does not advertise writable RGB zones."
          return
        }
        let allowedZones = Set(capability.zones.map(\.index))
        for zone in rgb {
          guard allowedZones.contains(zone.zone),
            proposedRGB[zone.zone] == nil,
            let color = RGBColor(hex: zone.color)
          else {
            status = "The JSON RGB zones or colors are invalid for this device."
            return
          }
          proposedRGB[zone.zone] = color
        }
      }

      for profile in profiles {
        if let enabled = proposedStates[profile.id],
          let index = self.profiles.firstIndex(where: { $0.id == profile.id })
        {
          self.profiles[index].enabled = enabled
        }
      }
      for (layer, index, raw) in proposedButtons {
        setRaw(layer: layer, buttonIndex: index, raw: raw)
      }
      if let dpi = proposedDPI {
        dpiCount = dpi.stages.count
        dpiStages = dpi.stages.map(String.init) + Array(repeating: "", count: 5 - dpi.stages.count)
        defaultStage = dpi.defaultStage
        shiftStage = dpi.shiftStage
      }
      for (zoneID, color) in proposedRGB {
        setRGBColor(zoneID: zoneID, color: color)
      }

      let sourceWarning =
        backup.device.productID.isEmpty
          || devices.first(where: { $0.id == selectedDeviceIndex })?.productID
            == backup.device.productID
        ? ""
        : " The source device differs, so review the outputs before saving."
      status =
        "Loaded \(url.lastPathComponent) into the editor. Review it, then choose Save to mouse.\(sourceWarning)"
    } catch {
      status = "Could not load JSON: \(error.localizedDescription)"
    }
  }

  private func writeEditableBackup(_ backup: EditableBackup, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(backup)
    try data.write(to: url, options: .atomic)
  }

  // Always builds from the current draft state, never the pre-edit
  // baseline: this is only ever called from exportCurrentJSON(), which
  // exports what's currently in the editor. It used to also support a
  // baseline/"current value" mode and an `exactBinaryBackup` source URL
  // for a since-removed caller; both parameters were always passed the
  // same way at the one remaining call site, so they were removed rather
  // than kept as permanently-unreachable branches.
  private func makeEditableBackup() -> EditableBackup {
    let selectedDevice = devices.first(where: { $0.id == selectedDeviceIndex })
    let selectedProfile = profiles.first(where: { $0.id == profileNumber })
    let profileButtons = allButtonRowsForSave().map { button in
      let raw = normalize(button.draftRaw)
      return EditableBackup.Button(
        number: button.id,
        physicalControl: button.displayLabel,
        output: outputLabel(for: raw),
        raw: raw,
        layer: button.layer.rawValue
      )
    }
    let dpiValues = dpiStages.prefix(dpiCount).compactMap(Int.init)
    let dpi: EditableBackup.DPI? =
      dpiValues.count == dpiCount
      ? EditableBackup.DPI(stages: dpiValues, defaultStage: defaultStage, shiftStage: shiftStage)
      : nil
    let rgb: [EditableBackup.Profile.RGB]?
    if let capability = rgbCapabilities(), !rgbZones.isEmpty {
      let colors = rgbZones.compactMap { zone -> EditableBackup.Profile.RGB? in
        guard capability.zones.contains(where: { $0.index == zone.id }) else { return nil }
        return EditableBackup.Profile.RGB(
          zone: zone.id,
          name: zone.name,
          color: zone.draft.hex
        )
      }
      rgb = colors.isEmpty ? nil : colors
    } else {
      rgb = nil
    }
    let states = profiles.map { profile in
      EditableBackup.ProfileState(number: profile.id, enabled: profile.enabled)
    }
    return EditableBackup(
      formatVersion: 1,
      createdAt: ISO8601DateFormatter().string(from: Date()),
      device: EditableBackup.Device(
        name: selectedDevice?.name ?? currentDeviceName,
        productID: selectedDevice?.productID ?? ""
      ),
      profiles: states,
      profile: EditableBackup.Profile(
        number: profileNumber,
        sector: selectedProfile?.sector,
        enabled: selectedProfile?.enabled ?? false,
        buttons: profileButtons,
        dpi: dpi,
        rgb: rgb
      ),
      exactBinaryBackup: nil
    )
  }

  private func outputLabel(for raw: String) -> String {
    let preset = presetLabel(for: raw)
    if preset != "Custom raw output" {
      return preset
    }
    guard let bytes = rawBytes(raw), bytes[0] == 0x80, bytes[1] == 0x02, bytes[3] != 0 else {
      return "Custom"
    }
    var modifiers: [String] = []
    for modifier in modifierChoices where (bytes[2] & modifier.id) != 0 {
      modifiers.append(modifier.label)
    }
    let key =
      keyboardKeys.first(where: { $0.id == bytes[3] })?.label ?? String(format: "0x%02X", bytes[3])
    return modifiers.isEmpty ? key : "\(modifiers.joined(separator: " + ")) + \(key)"
  }

  private func jsonRaw(for button: EditableBackup.Button) -> String? {
    let output = button.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let preset = presets.first(where: { $0.label.lowercased() == output }) {
      return preset.raw
    }
    let compact = output.replacingOccurrences(of: " ", with: "")
    if compact == "alt+tab" || compact == "leftalt+tab" {
      return "8002042B"
    }
    let raw = normalize(button.raw)
    return rawBytes(raw) != nil ? raw : nil
  }
}
