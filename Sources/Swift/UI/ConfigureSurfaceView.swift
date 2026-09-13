// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct ConfigureSurfaceView: View {
  @ObservedObject var model: AppModel
  @Binding var confirmRecoveryRestore: Bool
  @Binding var presentedRGBZoneID: Int?

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
        Text("Loading profiles from mouse…")
          .font(.headline)
        Text(
          model.currentDeviceName.isEmpty
            ? "Finding Logitech mice and reading onboard data"
            : "Reading \(model.currentDeviceName)"
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
      Color.black.opacity(0.24)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .accessibilityHidden(true)
        .pointerCursor()

      CenteredAppModal(
        title: "Wake \(model.currentDeviceName)",
        message: knownDeviceWakeMessage,
        symbol: "computermouse.fill",
        onDefaultAction: refreshFromWakeModal,
        onCancel: {}
      ) {
        HStack(spacing: 10) {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Checking for the mouse")
          Button("Refresh", action: refreshFromWakeModal)
            .buttonStyle(.borderedProminent)
            .disabled(model.busy)
            .pointerCursor(enabled: !model.busy)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .transition(.opacity)
    .zIndex(10)
  }

  private var knownDeviceWakeMessage: String {
    var messages: [String] = []
    if let guidance = model.knownDeviceRefreshGuidance {
      messages.append(guidance.sleepDescription)
      messages.append(guidance.wakeInstructions)
    }
    messages.append("LOPE will keep checking in the background.")
    return messages.joined(separator: "\n\n")
  }

  private func refreshFromWakeModal() {
    guard !model.busy else { return }
    model.refresh()
  }
}

struct LoadingProfileStateView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(spacing: 10) {
      ProgressView()
        .controlSize(.regular)
      Text("Loading profiles from mouse…")
        .font(.headline)
      Text(
        model.currentDeviceName.isEmpty
          ? "Finding Logitech mice and reading onboard data" : "Reading \(model.currentDeviceName)"
      )
      .font(.callout)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct EmptyStateView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(spacing: 12) {
      Spacer()
      Image(systemName: "computermouse")
        .font(.system(size: 42))
        .foregroundStyle(.secondary)
      Text(emptyStateTitle)
        .font(.title3.weight(.medium))
      Text(emptyStateMessage)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 560)
      if !model.inputMonitoringAuthorized {
        Button("Open Input Monitoring Settings", action: model.openInputMonitoringSettings)
          .pointerCursor()
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyStateTitle: String {
    if model.devices.isEmpty { return "No editable Logitech mouse detected" }
    if model.isMXSeriesMouse && !model.hasSpecificMouseProfile {
      return "No MX mouse profile descriptor"
    }
    return "No editable onboard profile"
  }

  private var emptyStateMessage: String {
    if model.devices.isEmpty {
      return
        "The app lists Logitech mice. macOS may also be blocking access even when the mouse is connected."
    }
    if model.isMXSeriesMouse && !model.hasSpecificMouseProfile {
      return
        "\(model.deviceSummary) is connected, but LOPE does not have a profile JSON for this MX mouse’s button layout yet."
    }
    return
      "\(model.deviceSummary) is connected, but it does not expose an onboard profile format this app can edit."
  }
}
