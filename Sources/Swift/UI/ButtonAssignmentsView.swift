// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct ButtonAssignmentsView: View {
  @ObservedObject var model: AppModel
  @Environment(\.lopeTheme) private var theme

  var body: some View {
    VStack(spacing: 8) {
      ForEach(model.buttons) { button in
        buttonRow(button.id)
      }
    }
  }

  private func buttonRow(_ buttonID: Int) -> some View {
    Group {
      if let button = model.buttons.first(where: { $0.id == buttonID }) {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 8) {
            Text(button.displayLabel)
              .font(.body.weight(.medium))
              .frame(maxWidth: .infinity, alignment: .leading)
              .lineLimit(1)
              .help(button.displayLabel)
            if button.draftChoice == "keystroke" {
              if model.showNonStandardKeyboardKeys {
                let buttonIndex = model.buttons.firstIndex(where: { $0.id == buttonID }) ?? 0
                if model.keyboardKeyChoice(buttonIndex: buttonIndex) != 0 {
                  keyboardModifierControls(buttonID)
                } else {
                  keyboardRecordingControl(buttonID)
                }
                keyboardChoiceCard(buttonID: buttonID)
              } else {
                keyboardRecordingControl(buttonID)
              }
            }
            Picker(
              "",
              selection: Binding(
                get: {
                  model.buttons.first(where: { $0.id == buttonID })?.draftChoice ?? "keystroke"
                },
                set: { choice in
                  guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else {
                    return
                  }
                  model.selectOutput(buttonIndex: index, choice: choice)
                })
            ) {
              ForEach(model.presets.prefix(1)) { preset in
                Text(preset.label).tag(preset.raw)
              }
              Text("Keystroke").tag("keystroke")
              ForEach(model.presets.dropFirst()) { preset in
                Text(preset.label).tag(preset.raw)
              }
            }
            .labelsHidden()
            .frame(width: 190, alignment: .trailing)
            if model.showAdvancedFields {
              TextField(
                "8 hex digits",
                text: Binding(
                  get: { model.buttons.first(where: { $0.id == buttonID })?.draftRaw ?? "" },
                  set: { raw in
                    guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else {
                      return
                    }
                    model.setRaw(buttonIndex: index, raw: raw)
                  })
              )
              .textFieldStyle(.roundedBorder)
              .frame(width: 122)
            }
          }
          // Keep preset rows the same height as keystroke rows. The
          // keystroke controls are 26 pt tall, while a native
          // Picker can otherwise make preset rows a little shorter.
          .frame(height: 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(theme.card)
        )
        .overlay(alignment: .leading) {
          Capsule(style: .continuous)
            .fill(Color.clear)
            .frame(width: 3)
            .padding(.vertical, 7)
        }
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
              theme.cardBorder,
              lineWidth: 0.5
            )
        }
      }
    }
  }

  private func keyboardRecordingControl(_ buttonID: Int) -> some View {
    HStack(spacing: 4) {
      KeyboardInputMonitor(
        isActive: model.recordingKeyboardButtonID == buttonID,
        onKeyDown: { event in
          guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }),
            let usage = model.keyboardUsage(for: event)
          else { return }
          var modifier: UInt8 = 0
          if event.modifierFlags.contains(.control) { modifier |= 0x01 }
          if event.modifierFlags.contains(.shift) { modifier |= 0x02 }
          if event.modifierFlags.contains(.option) { modifier |= 0x04 }
          if event.modifierFlags.contains(.command) { modifier |= 0x08 }
          model.recordKeyboardEvent(buttonIndex: index, keyCode: usage, modifier: modifier)
        }
      )
      .frame(width: 0, height: 0)
      keyboardRecordingBox(buttonID)
    }
    .help("Click the input box to capture a key and its modifiers. The X cancels recording.")
  }

  private func keyboardModifierControls(_ buttonID: Int) -> some View {
    let buttonIndex = model.buttons.firstIndex(where: { $0.id == buttonID }) ?? 0
    return HStack(spacing: 4) {
      keyboardModifierToggle(buttonIndex: buttonIndex, label: "Ctrl", bit: 0x01)
      keyboardModifierToggle(buttonIndex: buttonIndex, label: "Shift", bit: 0x02)
      keyboardModifierToggle(buttonIndex: buttonIndex, label: "Alt", bit: 0x04)
      keyboardModifierToggle(buttonIndex: buttonIndex, label: "Cmd", bit: 0x08)
    }
    .frame(width: 190, height: 26, alignment: .leading)
    .help("Choose the modifiers to send with the selected extended key.")
  }

  private func keyboardModifierToggle(buttonIndex: Int, label: String, bit: UInt8) -> some View {
    Toggle(
      label,
      isOn: Binding(
        get: { model.isModifierEnabled(buttonIndex: buttonIndex, bit: bit) },
        set: { model.setModifier(buttonIndex: buttonIndex, bit: bit, enabled: $0) }
      )
    )
    .toggleStyle(.checkbox)
    .controlSize(.small)
    .font(.caption)
    .fixedSize()
    .help(label)
  }

  private func keyboardRecordingBox(_ buttonID: Int) -> some View {
    let buttonIndex = model.buttons.firstIndex(where: { $0.id == buttonID }) ?? 0
    let isRecording = model.recordingKeyboardButtonID == buttonID
    let chord = model.keyboardChordText(buttonIndex: buttonIndex)

    return ZStack(alignment: .trailing) {
      Button {
        guard !isRecording else { return }
        model.beginKeyboardRecording(buttonIndex: buttonIndex)
      } label: {
        HStack(spacing: 0) {
          Text(isRecording ? "Recording..." : (chord.isEmpty ? "Click to record" : chord))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 8)
        .padding(.trailing, isRecording ? 28 : 8)
        .frame(width: 190, height: 26, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .contentShape(Rectangle())

      if isRecording {
        Button {
          model.cancelKeyboardRecording()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(theme.secondaryText)
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help("Cancel recording")
      }
    }
    .frame(width: 190, height: 26, alignment: .leading)
    .background(
      isRecording
        ? theme.buttonActive.opacity(0.18)
        : theme.buttonInactive.opacity(0.18),
      in: RoundedRectangle(cornerRadius: 5)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 5)
        .stroke(
          isRecording ? theme.accent : theme.controlBorder,
          lineWidth: isRecording ? 1.5 : 0.75
        )
    }
    .animation(.easeInOut(duration: 0.12), value: isRecording)
  }

  private func keyboardChoiceCard(buttonID: Int) -> some View {
    Picker(
      "Extended key",
      selection: Binding(
        get: {
          guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return 0 }
          return model.keyboardKeyChoice(buttonIndex: index)
        },
        set: { key in
          guard let index = model.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
          model.setKeyboardKeyChoice(buttonIndex: index, key: key)
        })
    ) {
      Text("Use Recorded Key").tag(0)
      ForEach(model.filteredExtendedKeyboardKeyLayoutGroups) { group in
        Section(group.label) {
          ForEach(group.keys) { key in
            Text(key.label).tag(Int(key.id))
          }
        }
      }
      ForEach(model.filteredExtendedKeyboardKeyGroups.filter { $0.group != .standard }) { group in
        Section(group.label) {
          ForEach(group.keys) { key in
            Text(key.label).tag(Int(key.id))
          }
        }
      }
    }
    .controlSize(.small)
    .labelsHidden()
    .frame(width: 150)
    .help("Insert an extended HID keyboard usage directly.")
  }
}
