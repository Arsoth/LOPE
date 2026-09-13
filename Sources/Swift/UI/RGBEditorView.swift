// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import SwiftUI

struct RGBEditorView: View {
  @ObservedObject var model: AppModel
  @Binding var presentedZoneID: Int?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Onboard RGB")
            .font(.headline)
          Text("Choose a color for each advertised lighting zone.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      VStack(spacing: 6) {
        ForEach(model.rgbZones) { zone in
          rgbZoneRow(zone)
        }
      }
      Text("Shift-click a zone to edit every advertised zone together.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(8)
    .background(
      .quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
  }

  private func rgbZoneRow(_ zone: RGBZoneState) -> some View {
    Button {
      let allZones = NSEvent.modifierFlags.contains(.shift)
      model.beginRGBEdit(zoneID: zone.id, allZones: allZones)
      presentedZoneID = zone.id
    } label: {
      HStack(spacing: 9) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(swiftUIColor(zone.draft))
          .frame(width: 28, height: 24)
          .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .stroke(Color.primary.opacity(0.28), lineWidth: 0.75)
          }
        Text(zone.name)
          .font(.callout.weight(.medium))
        Spacer()
        Text(zone.draft.hex)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 7)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.white.opacity(0.055), lineWidth: 0.5)
    }
    .help("Click to choose a color. Shift-click to apply the chosen color to all RGB zones.")
    .pointerCursor()
    .popover(
      isPresented: Binding(
        get: { presentedZoneID == zone.id },
        set: { isPresented in
          if !isPresented {
            presentedZoneID = nil
            model.rgbEditingAllZones = false
          }
        }
      ),
      arrowEdge: .trailing
    ) {
      VStack(alignment: .leading, spacing: 10) {
        Text(model.rgbEditingAllZones ? "All RGB zones" : zone.name)
          .font(.headline)
        ColorPicker("Color", selection: rgbColorBinding(zoneID: zone.id), supportsOpacity: false)
          .pointerCursor()
        if let current = model.rgbZones.first(where: { $0.id == zone.id })?.draft {
          Text(current.hex)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }
      .padding(14)
      .frame(width: 220)
    }
  }

  private func swiftUIColor(_ color: RGBColor) -> Color {
    Color(
      red: Double(color.red) / 255.0,
      green: Double(color.green) / 255.0,
      blue: Double(color.blue) / 255.0
    )
  }

  private func rgbColorBinding(zoneID: Int) -> Binding<Color> {
    Binding(
      get: {
        let color =
          model.rgbZones.first(where: { $0.id == zoneID })?.draft
          ?? RGBColor(red: 255, green: 255, blue: 255)
        return swiftUIColor(color)
      },
      set: { color in
        let converted = NSColor(color).usingColorSpace(.deviceRGB)
        guard let converted else { return }
        model.setRGBColor(
          zoneID: zoneID,
          color: RGBColor(
            red: UInt8((converted.redComponent * 255.0).rounded()),
            green: UInt8((converted.greenComponent * 255.0).rounded()),
            blue: UInt8((converted.blueComponent * 255.0).rounded())
          )
        )
      }
    )
  }
}
