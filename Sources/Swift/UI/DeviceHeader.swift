// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct DeviceHeader: View {
  @ObservedObject var model: AppModel
  let hidesEditingActions: Bool
  let onSave: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      if !model.devices.isEmpty {
        Text("Device")
          .font(.callout.weight(.medium))
        Picker(
          "",
          selection: Binding(
            get: { model.selectedDeviceIndex },
            set: { model.selectDevice($0) }
          )
        ) {
          ForEach(model.devices) { device in
            Text(device.title).tag(device.id)
          }
        }
        .labelsHidden()
        .frame(width: 180)
        .disabled(model.devices.isEmpty)
        .pointerCursor(enabled: !model.devices.isEmpty)
      }
      Button("Refresh", action: model.refresh)
        .keyboardShortcut("r", modifiers: [.command])
        .disabled(model.busy)
        .pointerCursor(enabled: !model.busy)
      if model.busy {
        ProgressView().controlSize(.small)
      }
      Spacer()
      if !hidesEditingActions {
        Button("Revert edits") { model.reloadSelectedProfile() }
          .pointerCursor()
        Button("Save to mouse", action: onSave)
          .buttonStyle(.borderedProminent)
          .disabled(
            !model.hasPendingChanges || model.busy || !model.currentMouseProfile.profileIO.canSave
              || (model.hasDPIChanges && !model.canApplyDPI)
          )
          .pointerCursor(
            enabled: model.hasPendingChanges && !model.busy
              && model.currentMouseProfile.profileIO.canSave
              && (!model.hasDPIChanges || model.canApplyDPI)
          )
      }
    }
  }
}
