// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import SwiftUI

struct RGBEditorView: View {
  @ObservedObject var model: AppModel
  @Binding var presentedZoneID: Int?
  @State private var hoveredZoneID: Int?
  @Environment(\.lopeTheme) private var theme

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
      theme.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
  }

  /// A profile with a single advertised zone lights the whole mouse as one
  /// unit (e.g. `Profiles/g-pro.json`'s "Logo and side lighting"), while a
  /// profile with more than one zone names distinct regions (e.g.
  /// `Profiles/g502-hero.json`'s "Primary"/"Logo"). The zone list carries no
  /// explicit scope flag, but that count already distinguishes the two
  /// cases, so the mode-button layout is derived from it rather than adding
  /// a new descriptor field.
  private var isPerRegionScope: Bool {
    model.rgbZones.count > 1
  }

  private func rgbZoneRow(_ zone: RGBZoneState) -> some View {
    let hoverVisible = hoveredZoneID == zone.id && presentedZoneID == nil
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 9) {
        colorSwatchButton(zone)
        if isPerRegionScope {
          modeButtonsRow(zone)
        }
        Text(zone.name)
          .font(.callout.weight(.medium))
        Spacer()
      }
      if !isPerRegionScope {
        modeButtonsRow(zone)
          .padding(.leading, 37)
      }
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 7)
    .background(
      hoverVisible ? theme.hover : theme.controlBackground,
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(theme.cardBorder, lineWidth: 0.5)
    }
    .onHover { isHovering in
      if isHovering {
        hoveredZoneID = zone.id
      } else if hoveredZoneID == zone.id {
        hoveredZoneID = nil
      }
    }
    .animation(.easeInOut(duration: 0.12), value: hoverVisible)
  }

  private func colorSwatchButton(_ zone: RGBZoneState) -> some View {
    Button {
      let allZones = NSEvent.modifierFlags.contains(.shift)
      model.beginRGBEdit(zoneID: zone.id, allZones: allZones)
      presentedZoneID = zone.id
    } label: {
      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(swiftUIColor(zone.draft))
        .frame(width: 28, height: 24)
        .overlay {
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .stroke(theme.controlBorder, lineWidth: 0.75)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .pointingHandCursor()
    .help("Click to choose a color. Shift-click to apply the chosen color to all RGB zones.")
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
      RGBColorPopoverView(
        title: model.rgbEditingAllZones ? "All RGB zones" : zone.name,
        initialColor: zone.draft,
        onCommit: { color in
          model.setRGBColor(zoneID: zone.id, color: color)
        }
      )
    }
  }

  /// Only modes the current device's catalog entry marks as confirmed are
  /// offered (see `RGBProfile.confirmedEffectModes`), plus whichever mode
  /// the zone is already set to, so a mode read back from the device never
  /// disappears from the row just for being unconfirmed.
  private func availableModes(for zone: RGBZoneState) -> [RGBEffectMode] {
    let confirmed =
      model.rgbCapabilities()?.confirmedEffectModes
      ?? MouseProfileDescriptor.RGBProfile.defaultConfirmedModes
    return RGBEffectMode.allCases.filter {
      confirmed.contains($0) || $0 == zone.currentMode || $0 == zone.draftMode
    }
  }

  private func modeButtonsRow(_ zone: RGBZoneState) -> some View {
    HStack(spacing: 4) {
      ForEach(availableModes(for: zone), id: \.self) { mode in
        modeButton(zone, mode: mode)
      }
    }
  }

  private func modeButton(_ zone: RGBZoneState, mode: RGBEffectMode) -> some View {
    let isSelected = zone.draftMode == mode
    return Button {
      let allZones = NSEvent.modifierFlags.contains(.shift)
      model.beginRGBEdit(zoneID: zone.id, allZones: allZones)
      model.setRGBMode(zoneID: zone.id, mode: mode)
    } label: {
      Text(mode.label)
        .font(.caption2.weight(isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? theme.accent : theme.secondaryText)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      isSelected ? theme.selected : theme.controlBackground,
      in: RoundedRectangle(cornerRadius: 5, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .stroke(theme.cardBorder, lineWidth: 0.5)
    }
    .pointingHandCursor()
    .help("Set \(zone.name) lighting mode to \(mode.label). Shift-click to apply to all zones.")
  }

}

private func swiftUIColor(_ color: RGBColor) -> Color {
  Color(
    red: Double(color.red) / 255.0,
    green: Double(color.green) / 255.0,
    blue: Double(color.blue) / 255.0
  )
}

/// HSB triple shared by the color wheel and the brightness slider below. Kept
/// as a plain tuple rather than a model type since it only exists to drive
/// these two in-app controls; the persisted representation stays the plain
/// `RGBColor` in `RGBModel.swift`.
private typealias HSBComponents = (hue: CGFloat, saturation: CGFloat, brightness: CGFloat)

/// Converts a SwiftUI `Color` to hue/saturation/brightness via AppKit's
/// device RGB colorspace, matching the conversion `RGBEditorView` already
/// performs when writing a picked color back to the model.
private func hsbComponents(of color: Color) -> HSBComponents {
  guard let converted = NSColor(color).usingColorSpace(.deviceRGB) else {
    return (0, 0, 1)
  }
  var hue: CGFloat = 0
  var saturation: CGFloat = 0
  var brightness: CGFloat = 0
  var alpha: CGFloat = 0
  converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
  return (hue, saturation, brightness)
}

/// An in-app hue/saturation wheel: dragging anywhere in the circle picks a
/// hue (angle, clockwise from the top) and a saturation (distance from
/// center). `AngularGradient`'s own 0° reference point renders at 3 o'clock
/// (east), not at the top, so `thumb`/`update` apply a quarter-turn (`.pi /
/// 2`) offset to keep the top-based hue math here aligned with where the
/// gradient actually paints each hue. Brightness is left untouched here and
/// is controlled separately by `RGBBrightnessSlider` alongside it, mirroring
/// the wheel/slider split in macOS's own color panel.
private struct RGBColorPopoverView: View {
  let title: String
  let onCommit: (RGBColor) -> Void
  @State private var pickerColor: Color
  @State private var hexInput: String
  @State private var hexError: String?

  init(title: String, initialColor: RGBColor, onCommit: @escaping (RGBColor) -> Void) {
    self.title = title
    self.onCommit = onCommit
    _pickerColor = State(initialValue: swiftUIColor(initialColor))
    _hexInput = State(initialValue: "#\(initialColor.bareHex)")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.headline)
      HStack(alignment: .center, spacing: 14) {
        RGBColorWheel(color: $pickerColor, onCommit: commitPickerColor)
          .frame(width: 140, height: 140)
        RGBBrightnessSlider(color: $pickerColor, onCommit: commitPickerColor)
          .frame(width: 22, height: 140)
      }
      HStack(spacing: 6) {
        TextField("#RRGGBB", text: $hexInput)
          .textFieldStyle(.roundedBorder)
          .font(.caption.monospaced())
          .onSubmit(applyHexInput)
        Button("Apply", action: applyHexInput)
          .buttonStyle(.bordered)
      }
      if let hexError {
        Text(hexError)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
    .padding(14)
    .frame(width: 232)
  }

  private func commitPickerColor(_ color: Color) {
    guard let converted = rgbColor(from: color) else { return }
    pickerColor = color
    hexInput = "#\(converted.bareHex)"
    hexError = nil
    onCommit(converted)
  }

  private func applyHexInput() {
    guard let color = RGBColor(hex: hexInput) else {
      hexError = "Enter a 6-digit hex color, such as #33AAFF."
      return
    }
    pickerColor = swiftUIColor(color)
    hexInput = "#\(color.bareHex)"
    hexError = nil
    onCommit(color)
  }
}

private func rgbColor(from color: Color) -> RGBColor? {
  guard let converted = NSColor(color).usingColorSpace(.deviceRGB) else { return nil }
  return RGBColor(
    red: UInt8((converted.redComponent * 255.0).rounded()),
    green: UInt8((converted.greenComponent * 255.0).rounded()),
    blue: UInt8((converted.blueComponent * 255.0).rounded())
  )
}

private struct RGBColorWheel: View {
  @Binding var color: Color
  let onCommit: (Color) -> Void
  // Keep high-frequency drag samples local. Writing through the model-backed
  // binding for every sample invalidates the whole editor, the same shared
  // cause that DPIStageBar avoids with its local drag position.
  @State private var dragHSB: HSBComponents?

  private static let hueStops: [Color] = (0...12).map { step in
    Color(hue: Double(step) / 12.0, saturation: 1, brightness: 1)
  }

  var body: some View {
    GeometryReader { proxy in
      let size = min(proxy.size.width, proxy.size.height)
      let radius = size / 2
      let hsb = dragHSB ?? hsbComponents(of: color)
      ZStack {
        Circle()
          .fill(AngularGradient(gradient: Gradient(colors: Self.hueStops), center: .center))
          .overlay(
            Circle()
              .fill(
                RadialGradient(
                  gradient: Gradient(colors: [.white, .white.opacity(0)]),
                  center: .center,
                  startRadius: 0,
                  endRadius: radius
                )
              )
          )
          .clipShape(Circle())
          .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
        thumb(hsb: hsb, radius: radius)
      }
      .frame(width: size, height: size)
      .contentShape(Circle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            update(at: value.location, radius: radius, brightness: hsb.brightness)
          }
          .onEnded { _ in
            commitDrag()
          }
      )
    }
  }

  private func thumb(hsb: HSBComponents, radius: CGFloat) -> some View {
    let angle = hsb.hue * 2 * .pi + .pi / 2
    let distance = hsb.saturation * radius
    let x = radius + sin(angle) * distance
    let y = radius - cos(angle) * distance
    return Circle()
      .fill(Color(hue: hsb.hue, saturation: hsb.saturation, brightness: 1))
      .frame(width: 14, height: 14)
      .overlay(Circle().stroke(Color.white, lineWidth: 2))
      .shadow(radius: 1)
      .contentShape(Circle())
      .pointingHandCursor()
      .position(x: x, y: y)
  }

  /// `dx`/`dy` follow the same clockwise-from-top convention as `thumb`:
  /// `dy` grows downward (screen space) and angle 0 points up. The `.pi / 2`
  /// subtraction is the inverse of the offset `thumb` adds, undoing the
  /// quarter turn needed to match `AngularGradient`'s 3-o'clock-origin hue 0.
  private func update(at point: CGPoint, radius: CGFloat, brightness: CGFloat) {
    guard radius > 0 else { return }
    let dx = point.x - radius
    let dy = point.y - radius
    let distance = min(sqrt(dx * dx + dy * dy), radius)
    let saturation = distance / radius
    var angle = atan2(dx, -dy) - .pi / 2
    if angle < 0 { angle += 2 * .pi }
    let hue = angle / (2 * .pi)
    let nextColor = Color(hue: hue, saturation: saturation, brightness: brightness)
    dragHSB = (hue, saturation, brightness)
    color = nextColor
  }

  private func commitDrag() {
    guard let dragHSB else { return }
    let committedColor = Color(
      hue: dragHSB.hue,
      saturation: dragHSB.saturation,
      brightness: dragHSB.brightness
    )
    var transaction = Transaction()
    transaction.animation = nil
    withTransaction(transaction) {
      color = committedColor
      self.dragHSB = nil
    }
    onCommit(committedColor)
  }
}

/// A vertical brightness bar for the hue/saturation picked in
/// `RGBColorWheel`: top is full brightness at the current hue/saturation,
/// bottom is black. Implemented as a plain drag-tracked gradient rather than
/// a rotated `Slider`, since a `Slider` rotated with `.rotationEffect` does
/// not reliably hit-test in AppKit-backed SwiftUI.
private struct RGBBrightnessSlider: View {
  @Binding var color: Color
  let onCommit: (Color) -> Void

  var body: some View {
    GeometryReader { proxy in
      let hsb = hsbComponents(of: color)
      let width = proxy.size.width
      let height = proxy.size.height
      ZStack(alignment: .top) {
        RoundedRectangle(cornerRadius: width / 2, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color(hue: hsb.hue, saturation: hsb.saturation, brightness: 1),
                Color.black,
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .overlay(
            RoundedRectangle(cornerRadius: width / 2, style: .continuous)
              .stroke(Color.black.opacity(0.15), lineWidth: 1)
          )
        thumb(hsb: hsb, width: width, height: height)
      }
      .frame(width: width, height: height)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            update(at: value.location, height: height, hue: hsb.hue, saturation: hsb.saturation)
          }
          .onEnded { _ in
            onCommit(color)
          }
      )
    }
  }

  private func thumb(hsb: HSBComponents, width: CGFloat, height: CGFloat) -> some View {
    let y = (1 - hsb.brightness) * height
    return RoundedRectangle(cornerRadius: 2, style: .continuous)
      .stroke(Color.white, lineWidth: 2)
      .frame(width: width + 4, height: 4)
      .shadow(radius: 1)
      .position(x: width / 2, y: min(max(y, 2), height - 2))
  }

  private func update(at point: CGPoint, height: CGFloat, hue: CGFloat, saturation: CGFloat) {
    guard height > 0 else { return }
    let clamped = min(max(point.y, 0), height)
    let brightness = 1 - (clamped / height)
    color = Color(hue: hue, saturation: saturation, brightness: brightness)
  }
}
