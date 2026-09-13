// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import ApplicationServices
import CoreGraphics
import CoreVideo
import SwiftUI

struct ContentView: View {
  private enum AppTab: Hashable {
    case configure
    case backups
    case profileEditor
    case settings
  }

  @StateObject private var model = AppModel()
  @State private var selectedTab: AppTab = .configure
  @State private var confirmRestore = false
  @State private var restoreURL: URL?
  @State private var confirmRecoveryRestore = false
  @State private var presentedRGBZoneID: Int?
  @State private var primaryClickModalPresented = false
  @State private var statusHistoryPresented = false
  @State private var statusMessageOpacity = 1.0
  @State private var statusHistory = StatusHistory()
  @Environment(\.scenePhase) private var scenePhase

  private let statusFadeDelayNanoseconds: UInt64 = 30_000_000_000
  private var preferredColorScheme: ColorScheme {
    model.isDarkAppearance ? .dark : .light
  }

  private static let darkAppBackground = Color(nsColor: .windowBackgroundColor)

  private var appBackground: Color {
    model.isDarkAppearance
      ? Self.darkAppBackground
      : Color(red: 0.965, green: 0.965, blue: 0.95)
  }

  var body: some View {
    ZStack {
      // Keep Settings on the standard macOS ⌘, shortcut even though the
      // tab itself is represented by a TabView item.
      Button("Settings") {
        selectedTab = .settings
      }
      .keyboardShortcut(",", modifiers: [.command])
      .opacity(0)
      .frame(width: 0, height: 0)

      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          if selectedTab != .settings {
            VStack(alignment: .leading, spacing: 14) {
              DeviceHeader(
                model: model,
                hidesEditingActions: selectedTab == .profileEditor,
                onSave: saveToMouse
              )
              .padding(.horizontal, 20)
              Divider()
                .frame(maxWidth: .infinity)
                .background(appBackground)
                .shadow(color: .black.opacity(0.22), radius: 6, y: 2)
            }
          }
          TabView(selection: $selectedTab) {
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
            .tabItem { Label("Configure", systemImage: "cursorarrow.click").pointerCursor() }
            .tag(AppTab.configure)
            BackupsPane(
              model: model,
              restoreURL: $restoreURL,
              confirmRestore: $confirmRestore
            )
            .tabItem { Label("Backups", systemImage: "archivebox").pointerCursor() }
            .tag(AppTab.backups)
            ProfileEditorPane(
              model: model,
              loadingState: loadingProfileState,
              emptyState: emptyState
            )
            .tabItem { Label("Profile Editor", systemImage: "square.and.pencil").pointerCursor() }
            .tag(AppTab.profileEditor)
            SettingsPane(model: model)
              .tabItem { Label("Settings", systemImage: "gearshape").pointerCursor() }
              .tag(AppTab.settings)
          }
        }
        .simultaneousGesture(
          TapGesture().onEnded {
            if statusHistoryPresented {
              statusHistoryPresented = false
            }
          }
        )
        StatusArea(
          status: model.status,
          events: statusHistory.events,
          messageOpacity: statusMessageOpacity,
          background: appBackground,
          historyPresented: $statusHistoryPresented
        )

        // Future expansion: restore the button-press highlighting control
        // here, below the footer/status line, after a reliable Logitech
        // button-event path is available. AppKit only exposed buttons 1–3
        // in testing, and the HID monitor did not provide dependable
        // mappings for the remaining controls.
        // HStack(spacing: 8) {
        //     Spacer()
        //     Button("Highlight presses") {
        //         // Future button-event monitor action.
        //     }
        // }
      }
    }
    .padding(.top, 20)
    .frame(minWidth: 960, minHeight: 520)
    .background(appBackground)
    .preferredColorScheme(preferredColorScheme)
    .overlay {
      ZStack {
        if primaryClickModalPresented {
          ZStack {
            Color.black.opacity(0.24)
              .ignoresSafeArea()
              .onTapGesture { primaryClickModalPresented = false }
              .pointerCursor()
            CenteredAppModal(
              title: "Primary click required",
              message: model.primaryClickValidationMessage
                ?? "Choose “Left click” for the primary-click button, then save again.",
              symbol: "exclamationmark.triangle",
              onDefaultAction: { primaryClickModalPresented = false },
              onCancel: { primaryClickModalPresented = false }
            ) {
              Button("Return to editor", role: .cancel) {
                primaryClickModalPresented = false
              }
              .keyboardShortcut(.defaultAction)
              .buttonStyle(.borderedProminent)
              .pointerCursor()
            }
          }
          .transition(.opacity)
          .zIndex(10)
        }
      }
    }
    .animation(.easeInOut(duration: 0.16), value: primaryClickModalPresented)
    .animation(.easeInOut(duration: 0.2), value: statusHistoryPresented)
    .task(id: model.status) {
      statusMessageOpacity = 1
      do {
        try await Task.sleep(nanoseconds: statusFadeDelayNanoseconds)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.6)) {
          statusMessageOpacity = 0
        }
      } catch {
        // A new status message cancels the previous fade timer.
      }
    }
    .onChange(of: model.status) { newStatus in
      statusHistory.record(newStatus)
    }
    .onChange(of: model.profileNumber) { _ in
      model.reloadSelectedProfile()
    }
    .onChange(of: model.selectedDeviceIndex) { _ in
      model.refreshBackups()
    }
    .onChange(of: scenePhase) { phase in
      if phase == .active {
        model.updateInputMonitoringAuthorization()
      }
    }
    .alert("Allow wired mice", isPresented: $model.wiredAccessInstructionsPresented) {
      Button("Open Input Monitoring Settings", action: model.openInputMonitoringSettings)
        .pointerCursor()
      Button("Cancel", role: .cancel) {}
        .pointerCursor()
    } message: {
      Text(
        "LOPE can use wireless and receiver-connected mice without this permission. To read and edit a wired mouse, enable LOPE in System Settings > Privacy & Security > Input Monitoring, then return and choose Refresh."
      )
    }
    .alert("Restore this backup?", isPresented: $confirmRestore) {
      Button("Cancel", role: .cancel) { restoreURL = nil }
        .pointerCursor()
      Button("Restore and verify", role: .destructive) {
        if let restoreURL { model.restore(restoreURL) }
        restoreURL = nil
      }
      .pointerCursor()
    } message: {
      Text(restoreURL?.lastPathComponent ?? "Selected backup")
    }
    .alert("Restore backups from this save?", isPresented: $confirmRecoveryRestore) {
      Button("Cancel", role: .cancel) {}
        .pointerCursor()
      Button("Restore and verify", role: .destructive) {
        model.restoreLastSaveBackups()
      }
      .pointerCursor()
    } message: {
      Text(
        "LOPE will restore the exact pre-save sectors captured by the failed operation. Any sector that was already unchanged will be skipped safely."
      )
    }
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

  @ViewBuilder
  private var configureContent: some View {
    if model.buttons.isEmpty {
      if model.loadingProfile {
        loadingProfileState
      } else {
        emptyState
      }
    } else {
      buttonsPane
        .opacity(model.loadingProfile ? 0.72 : 1)
        .allowsHitTesting(!model.loadingProfile && !model.waitingForKnownDevice)
    }
  }

  private var configureBackgroundBlurRadius: CGFloat {
    model.loadingProfile || model.waitingForKnownDevice ? 1.5 : 0
  }

  private var loadingProfileState: some View {
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

  private var emptyState: some View {
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

  private var buttonsPane: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !model.isProvisionalMouseData && !model.recoveryBackups.isEmpty {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
          Text(
            "The last save was only partially completed. Exact pre-save backups are available for recovery."
          )
          .font(.callout)
          Spacer()
          Button("Restore backups from this save") {
            confirmRecoveryRestore = true
          }
          .buttonStyle(.bordered)
          .pointerCursor()
        }
        .padding(8)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
      }
      if !model.isProvisionalMouseData && !model.currentMouseProfile.profileIO.canSave {
        Text(
          "This device is cataloged for read-only inspection until its profile-specific save format is validated."
        )
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(.horizontal, 20)
      }
      if !model.isProvisionalMouseData && !model.hasSpecificMouseProfile {
        HStack(spacing: 8) {
          Image(systemName: "questionmark.circle.fill")
            .foregroundStyle(.secondary)
          Text("LOPE doesn't recognize this mouse, so buttons below are shown by number only.")
            .font(.callout)
          Spacer()
          Button("Create profile") { model.createGeneratedProfile() }
            .buttonStyle(.bordered)
            .pointerCursor()
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 20)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          profilesEditor
          if model.hasGShiftLayer {
            HStack(spacing: 10) {
              Text("Button assignments")
                .font(.callout.weight(.medium))
              Text("G-Shift assignments apply while holding the mouse’s G-Shift button.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
          }
          Divider()
          VStack(spacing: 8) {
            ForEach(model.buttons) { button in
              buttonRow(button.id)
            }
          }
          Divider()
          if model.canEditOnboardDPI {
            dpiEditor
          } else {
            Text("Onboard DPI editing is unavailable for this legacy profile path.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
          }
          if model.shouldShowRGBEditor {
            Divider()
            rgbEditor
          }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
        .background(ScrollViewScrollerInset(rightInset: 3))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .id(model.selectedDeviceIndex)

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
            .pointerCursor()
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
            .fill(Color.white.opacity(0.045))
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
              Color.white.opacity(0.055),
              lineWidth: 0.5
            )
        }
      }
    }
  }

  private func saveToMouse() {
    let canAttemptSave =
      model.hasPendingChanges && !model.busy && model.currentMouseProfile.profileIO.canSave
      && (!model.hasDPIChanges || model.canApplyDPI)
    guard canAttemptSave else {
      model.applyAll()
      return
    }

    if model.primaryClickValidationMessage != nil {
      primaryClickModalPresented = true
    } else {
      model.applyAll()
    }
  }

  private var profilesEditor: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 12) {
        Text(model.onboardProfileSummary)
          .font(.callout.weight(.medium))
        Spacer(minLength: 12)
        if model.hasGShiftLayer {
          Picker(
            "Button layer",
            selection: Binding(
              get: { model.buttonLayer },
              set: { model.selectButtonLayer($0) }
            )
          ) {
            ForEach(ButtonLayer.allCases, id: \.self) { layer in
              Text(layer.label).tag(layer)
            }
          }
          .labelsHidden()
          .pickerStyle(.segmented)
          .frame(width: 150)
          .pointerCursor()
        }
        if model.profiles.count > 1 {
          Text("Profile:")
            .font(.callout.weight(.medium))
          Picker("Profile", selection: $model.profileNumber) {
            ForEach(model.profiles) { profile in
              Text(profile.title).tag(profile.id)
            }
          }
          .labelsHidden()
          .frame(width: 150)
          .disabled(model.busy)
          .pointerCursor(enabled: !model.busy)
          // Spacer(minLength: 0)
          //     .frame(width: 6)

          Text("Enable:")
            .font(.callout.weight(.medium))
          ForEach(model.profiles) { profile in
            profileEnableControl(profile)
          }
        }
      }
      if model.showAdvancedFields {
        HStack(spacing: 12) {
          Text("Sectors:")
            .font(.caption)
            .foregroundStyle(.secondary)
          ForEach(model.profiles) { profile in
            Text("Profile \(profile.id): \(profile.sector)")
              .font(.caption.monospaced())
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    // Keep the loading placeholder as tall as the populated profile bar.
    // The picker and enable controls are intentionally hidden until the
    // profile read completes, which would otherwise make this bar jump.
    .frame(minHeight: 36)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.white.opacity(0.045))
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.white.opacity(0.055), lineWidth: 0.5)
    }
  }

  private func profileEnableControl(_ profile: ProfileChoice) -> some View {
    let profileID = profile.id
    let label = String(profileID)
    let crcLabel: String
    let crcColor: Color
    let helpText: String
    switch profile.crcValid {
    case true:
      crcLabel = ""
      crcColor = .secondary
      helpText = "Profile \(label) CRC valid"
    case false:
      crcLabel = "Profile invalid"
      crcColor = .red
      helpText = "Profile \(label) CRC invalid"
    case nil:
      crcLabel = ""
      crcColor = .secondary
      helpText = "Profile \(label) CRC not read"
    }
    let enabled = Binding<Bool>(
      get: { model.profileEnabled(profileID) },
      set: { model.setProfileEnabled(profileID: profileID, enabled: $0) }
    )
    return HStack(spacing: 3) {
      Text(label)
        .font(.caption)
      Toggle("", isOn: enabled)
        .labelsHidden()
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .disabled(model.busy || !model.canEditProfileState)
        .pointerCursor(enabled: !model.busy && model.canEditProfileState)
      Text(crcLabel)
        .font(.caption)
        .foregroundStyle(crcColor)
    }
    .padding(.horizontal, 2)
    .padding(.vertical, 2)
    // .background(
    //   profileID == model.profileNumber
    //     ? Color.accentColor.opacity(0.12)
    //     : Color.clear,
    //   in: RoundedRectangle(cornerRadius: 6)
    // )
    .help(helpText)
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
    .pointerCursor()
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
      .pointerCursor(enabled: !isRecording)

      if isRecording {
        Button {
          model.cancelKeyboardRecording()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help("Cancel recording")
        .pointerCursor()
      }
    }
    .frame(width: 190, height: 26, alignment: .leading)
    .background(
      isRecording
        ? Color.accentColor.opacity(0.18)
        : Color.primary.opacity(0.08),
      in: RoundedRectangle(cornerRadius: 5)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 5)
        .stroke(
          isRecording ? Color.accentColor : Color.primary.opacity(0.14),
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
      ForEach(model.keyboardOutputKeys) { key in
        Text(key.label).tag(Int(key.id))
      }
    }
    .controlSize(.small)
    .labelsHidden()
    .frame(width: 150)
    .help("Insert an extended HID keyboard usage directly.")
    .pointerCursor()
  }

  private var dpiEditor: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Onboard DPI")
            .font(.headline)
          Text("Set the active sensitivity stages for this profile.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        HStack(spacing: 4) {
          if !model.pollingRateCapabilities.profileSupportedRates.isEmpty {
            Text("Polling rate")
              .font(.caption)
              .foregroundStyle(.secondary)
            Picker(
              "Polling rate",
              selection: Binding(
                get: {
                  model.pollingRateDraft ?? model.pollingRateCapabilities.currentRate
                    ?? model.pollingRateCapabilities.profileSupportedRates.first ?? 0
                },
                set: { model.applyPollingRate($0) }
              )
            ) {
              ForEach(model.pollingRateCapabilities.profileSupportedRates, id: \.self) { rate in
                Text("\(rate) Hz").tag(rate)
              }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 105)
            .disabled(model.busy || model.loadingProfile)
            .pointerCursor(enabled: !model.busy && !model.loadingProfile)
            .help("Choose a polling rate, then Save to write it to the selected onboard profile.")
          }
          Text("Active stages")
            .font(.caption)
            .foregroundStyle(.secondary)
          Button {
            model.setDPIStageCount(model.dpiCount - 1)
          } label: {
            Image(systemName: "minus")
              .font(.body.weight(.semibold))
              .frame(width: 28, height: 24)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(model.dpiCount <= 1)
          .pointerCursor(enabled: model.dpiCount > 1)
          .accessibilityLabel("Remove DPI stage")
          Text("\(model.dpiCount) of 5")
            .font(.callout.monospacedDigit())
            .frame(minWidth: 40)
          Button {
            model.setDPIStageCount(model.dpiCount + 1)
          } label: {
            Image(systemName: "plus")
              .font(.body.weight(.semibold))
              .frame(width: 28, height: 24)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(model.dpiCount >= 5)
          .pointerCursor(enabled: model.dpiCount < 5)
          .accessibilityLabel("Add DPI stage")
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        if !model.isProvisionalMouseData, let currentDPI = model.dpiCapabilities.currentValue {
          HStack(spacing: 6) {
            Text("Live DPI")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(formattedDPIValue(currentDPI))
              .font(.caption.monospacedDigit().weight(.semibold))
          }
        }

        DPIStageBar(
          stages: Array(model.dpiStages.prefix(model.dpiCount)),
          defaultStage: model.defaultStage,
          shiftStage: model.shiftStage,
          capabilities: model.dpiCapabilities,
          isLoading: model.loadingProfile,
          validationMessage: model.dpiValidationMessage,
          onDragValue: { index, value in
            model.moveDPIStageDuringDrag(index: index, value: value)
          },
          onDragEnded: {
            model.finishDPIStageDrag()
          },
          onAdjust: { index, direction in
            model.adjustDPIStage(index: index, direction: direction)
          },
          onTextChange: { index, text in
            model.setDPIStageText(index: index, text: text)
          },
          onCommitText: { index in
            model.commitDPIStageText(index: index)
          },
          onSetDefault: { index in
            model.setDefaultDPIStage(index + 1)
          },
          onSetShift: { index in
            model.setShiftDPIStage(index + 1)
          },
          onDelete: { index in
            model.deleteDPIStage(index: index)
          }
        )
        .frame(height: 105)
        .zIndex(10)
      }
      .padding(8)
      .background(
        .quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
    .padding(.top, 4)
  }

  private var rgbEditor: some View {
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
      presentedRGBZoneID = zone.id
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
        get: { presentedRGBZoneID == zone.id },
        set: { isPresented in
          if !isPresented {
            presentedRGBZoneID = nil
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
