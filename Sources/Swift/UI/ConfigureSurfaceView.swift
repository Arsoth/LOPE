// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct ConfigureSurfaceView: View {
  @ObservedObject var model: AppModel
  @Binding var confirmRecoveryRestore: Bool
  @Binding var presentedRGBZoneID: Int?
  @Environment(\.lopeTheme) private var theme

  var body: some View {
    ZStack {
      configureContent
        .blur(radius: configureBackgroundBlurRadius)
      if model.loadingProfile && !model.buttons.isEmpty {
        loadingProfileOverlay
      }
      if model.waitingForKnownDevice {
        knownDeviceWakeModal
      }
    }
  }

  @ViewBuilder
  private var configureContent: some View {
    if model.buttons.isEmpty {
      if model.loadingProfile {
        LoadingProfileStateView(model: model)
      } else {
        EmptyStateView(model: model)
      }
    } else {
      ButtonEditorPane(
        model: model,
        confirmRecoveryRestore: $confirmRecoveryRestore,
        presentedRGBZoneID: $presentedRGBZoneID
      )
      .opacity(model.loadingProfile ? 0.72 : 1)
      .allowsHitTesting(!model.loadingProfile && !model.waitingForKnownDevice)
    }
  }

  private var configureBackgroundBlurRadius: CGFloat {
    model.loadingProfile || model.waitingForKnownDevice ? 1.5 : 0
  }

  private var loadingProfileOverlay: some View {
    ZStack {
      Rectangle()
        .fill(.clear)
        .contentShape(Rectangle())
      VStack(spacing: 10) {
        ProgressView()
          .controlSize(.regular)
        Text(L10n.text("Loading profiles from mouse…"))
          .font(.headline)
        Text(
          currentDeviceDisplayName.isEmpty
            ? L10n.text("Finding Logitech mice and reading onboard data")
            : L10n.text("Reading {device}", replacements: ["device": currentDeviceDisplayName])
        )
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 22)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
      .shadow(radius: 12)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
  }

  private var knownDeviceWakeModal: some View {
    ZStack {
      theme.shadow
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .accessibilityHidden(true)

      CenteredAppModal(
        title: L10n.text("Wake {device}", replacements: ["device": currentDeviceDisplayName]),
        message: knownDeviceWakeMessage,
        symbol: "computermouse.fill",
        onDefaultAction: model.knownDeviceWakeExpired ? model.retryKnownDeviceWake : {},
        onCancel: {},
        showsActions: model.knownDeviceWakeExpired
      ) {
        Button(L10n.text("Retry"), action: model.retryKnownDeviceWake)
          .buttonStyle(.borderedProminent)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .transition(.opacity)
    .zIndex(10)
  }

  private var currentDeviceDisplayName: String {
    model.devices.first(where: { $0.id == model.selectedDeviceIndex })?.displayName
      ?? model.currentDeviceName
  }

  private var knownDeviceWakeMessage: String {
    var messages: [String] = []
    if let guidance = model.knownDeviceRefreshGuidance {
      messages.append(guidance.sleepDescription)
      messages.append(guidance.wakeInstructions)
    } else {
      messages.append(L10n.text("Move or click the mouse to wake it while LOPE reads it."))
    }
    messages.append(
      model.knownDeviceWakeExpired
        ? L10n.text(
          "LOPE stopped checking after a minute. Choose Retry to keep waiting for the mouse."
        )
        : L10n.text("LOPE will keep checking in the background."))
    return messages.joined(separator: "\n\n")
  }

}

struct LoadingProfileStateView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(spacing: 10) {
      ProgressView()
        .controlSize(.regular)
      Text(L10n.text("Loading profiles from mouse…"))
        .font(.headline)
      Text(
        currentDeviceDisplayName.isEmpty
          ? L10n.text("Finding Logitech mice and reading onboard data")
          : L10n.text("Reading {device}", replacements: ["device": currentDeviceDisplayName])
      )
      .font(.callout)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var currentDeviceDisplayName: String {
    model.devices.first(where: { $0.id == model.selectedDeviceIndex })?.displayName
      ?? model.currentDeviceName
  }
}

struct EmptyStateView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(spacing: 12) {
      Spacer()
      Image(systemName: emptyStateIcon)
        .font(.system(size: 42))
        .foregroundStyle(.secondary)
      Text(emptyStateTitle)
        .font(.title3.weight(.medium))
      Text(emptyStateMessage)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 560)
      if !engineUnavailable && !model.inputMonitoringAuthorized {
        Button(
          L10n.text("Open Input Monitoring Settings"), action: model.openInputMonitoringSettings)
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var engineUnavailable: Bool {
    model.engine == nil
  }

  private var emptyStateIcon: String {
    engineUnavailable ? "exclamationmark.triangle" : "computermouse"
  }

  private var emptyStateTitle: String {
    if engineUnavailable { return L10n.text("LOPE needs to be reinstalled") }
    if model.devices.isEmpty { return L10n.text("No editable Logitech mouse detected") }
    if inputMonitoringRequiredForWiredMouse {
      return L10n.text(
        "Input Monitoring required for {device}", replacements: ["device": wiredMouseName])
    }
    if model.isMXSeriesMouse && !model.hasSpecificMouseProfile {
      return L10n.text("No MX mouse profile descriptor")
    }
    return L10n.text("No editable onboard profile")
  }

  private var emptyStateMessage: String {
    if engineUnavailable {
      return
        L10n.text(
          "The bundled HID++ engine is missing, so LOPE cannot access your mouse. Please reinstall LOPE to restore it. Your preferences and data are stored separately and will not be lost."
        )
    }
    if model.devices.isEmpty {
      return
        L10n.text(
          "The app lists Logitech mice. macOS may also be blocking access even when the mouse is connected."
        )
    }
    if inputMonitoringRequiredForWiredMouse {
      return
        L10n.text(
          "{device} is connected, but LOPE cannot read its onboard profile until Input Monitoring is enabled. Enable LOPE in System Settings, then choose Refresh.",
          replacements: ["device": wiredMouseName]
        )
    }
    if model.isMXSeriesMouse && !model.hasSpecificMouseProfile {
      return
        L10n.text(
          "{device} is connected, but LOPE does not have a profile JSON for this MX mouse’s button layout yet.",
          replacements: ["device": model.deviceSummary]
        )
    }
    return
      L10n.text(
        "{device} is connected, but it does not expose an onboard profile format this app can edit.",
        replacements: ["device": model.deviceSummary]
      )
  }

  private var inputMonitoringRequiredForWiredMouse: Bool {
    !model.inputMonitoringAuthorized
      && model.devices.first(where: { $0.id == model.selectedDeviceIndex })?.isWiredDevice == true
  }

  private var wiredMouseName: String {
    model.devices.first(where: { $0.id == model.selectedDeviceIndex })?.displayName
      ?? model.currentDeviceName
  }
}
