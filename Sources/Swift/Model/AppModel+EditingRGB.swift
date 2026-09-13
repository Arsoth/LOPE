// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation

@MainActor
extension AppModel {
  func applyRGBZones(_ parsedZones: [ParsedRGBZone], profileFormat: Int?) {
    rgbEditingAllZones = false
    rgbZones.removeAll()
    baselineRGBColors.removeAll()
    guard let capability = rgbCapabilities(profileFormat: profileFormat) else { return }

    let parsedByIndex = Dictionary(uniqueKeysWithValues: parsedZones.map { ($0.index, $0.color) })
    for descriptor in capability.zones {
      guard let color = parsedByIndex[descriptor.index] else { continue }
      rgbZones.append(
        RGBZoneState(
          id: descriptor.index,
          name: descriptor.name,
          current: color,
          draft: color
        ))
    }
    baselineRGBColors = Dictionary(uniqueKeysWithValues: rgbZones.map { ($0.id, $0.current) })
  }

  func beginRGBEdit(zoneID: Int, allZones: Bool) {
    guard rgbZones.contains(where: { $0.id == zoneID }) else { return }
    rgbEditingAllZones = allZones
    if allZones {
      status = "Editing all RGB zones. Choose a color for every advertised zone."
    }
  }

  func setRGBColor(zoneID: Int, color: RGBColor) {
    rgbZones = RGBEditorLogic.settingColor(
      in: rgbZones,
      zoneID: zoneID,
      color: color,
      allZones: rgbEditingAllZones
    )
  }
}
