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
  private var theme: ThemePalette {
    ThemePalette(theme: model.activeTheme, isDarkAppearance: model.isDarkAppearance)
  }

  private var preferredColorScheme: ColorScheme {
    model.isDarkAppearance ? .dark : .light
  }

  private var appBackground: Color {
    theme.mainBackground
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
            deviceHeaderSurface
              .zIndex(1)
          }
          TabView(selection: $selectedTab) {
            ZStack {
              ConfigureSurfaceView(
                model: model,
                confirmRecoveryRestore: $confirmRecoveryRestore,
                presentedRGBZoneID: $presentedRGBZoneID
              )
            }
            .tabItem { Label("Configure", systemImage: "cursorarrow.click") }
            .tag(AppTab.configure)
            BackupsPane(
              model: model,
              restoreURL: $restoreURL,
              confirmRestore: $confirmRestore
            )
            .tabItem { Label("Backups", systemImage: "archivebox") }
            .tag(AppTab.backups)
            ProfileEditorPane(
              model: model,
              loadingState: LoadingProfileStateView(model: model),
              emptyState: EmptyStateView(model: model)
            )
            .tabItem { Label("Profile Editor", systemImage: "square.and.pencil") }
            .tag(AppTab.profileEditor)
            SettingsPane(model: model)
              .tabItem { Label("Settings", systemImage: "gearshape") }
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
          status: model.statusFooterText,
          events: statusHistory.events,
          messageOpacity: statusMessageOpacity,
          background: theme.footer,
          historyPresented: $statusHistoryPresented
        )

      }
      if model.wiredAccessInstructionsPresented {
        wiredAccessInstructionsModal
      }
    }
    .padding(.top, selectedTab == .settings ? 20 : 0)
    .frame(minWidth: 960, minHeight: 520)
    .background(appBackground)
    .environment(\.lopeTheme, theme)
    .preferredColorScheme(preferredColorScheme)
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
    .alert("Restore this backup?", isPresented: $confirmRestore) {
      Button("Cancel", role: .cancel) { restoreURL = nil }
      Button("Restore and verify", role: .destructive) {
        if let restoreURL { model.restore(restoreURL) }
        restoreURL = nil
      }
    } message: {
      Text(restoreURL?.lastPathComponent ?? "Selected backup")
    }
    .alert("Restore backups from this save?", isPresented: $confirmRecoveryRestore) {
      Button("Cancel", role: .cancel) {}
      Button("Restore and verify", role: .destructive) {
        model.restoreLastSaveBackups()
      }
    } message: {
      Text(
        "LOPE will restore the exact pre-save sectors captured by the failed operation. Any sector that was already unchanged will be skipped safely."
      )
    }
    .alert("Primary click required", isPresented: $primaryClickModalPresented) {
      Button("Return to editor", role: .cancel) {}
    } message: {
      Text(
        model.primaryClickValidationMessage
          ?? "Choose “Left click” for the primary-click button, then save again."
      )
    }
  }

  private var deviceHeaderSurface: some View {
    VStack(alignment: .leading, spacing: 14) {
      DeviceHeader(
        model: model,
        hidesEditingActions: selectedTab == .profileEditor,
        onSave: saveToMouse
      )
      .padding(.horizontal, 20)
      Divider()
        .frame(maxWidth: .infinity)
    }
    .padding(.top, 20)
    .frame(maxWidth: .infinity)
    .background(theme.header)
    .shadow(color: theme.shadow, radius: 8, y: 3)
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

  private var wiredAccessInstructionsModal: some View {
    ZStack {
      theme.shadow
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .accessibilityHidden(true)

      CenteredAppModal(
        title: model.wiredAccessDeviceName.map { "Allow \($0)" } ?? "Allow wired mice",
        message: wiredAccessInstructionsMessage,
        symbol: "lock.shield",
        onDefaultAction: openWiredAccessSettings,
        onCancel: dismissWiredAccessInstructions
      ) {
        Button("Cancel", role: .cancel, action: dismissWiredAccessInstructions)
        Button("Open System Settings", action: openWiredAccessSettings)
          .buttonStyle(.borderedProminent)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .transition(.opacity)
    .zIndex(20)
  }

  private var wiredAccessInstructionsMessage: String {
    "LOPE can use wireless and receiver-connected mice without this permission. To read and edit a wired mouse, enable LOPE in System Settings > Privacy & Security > Input Monitoring, then return and choose Refresh."
  }

  private func dismissWiredAccessInstructions() {
    model.wiredAccessInstructionsPresented = false
    model.wiredAccessDeviceName = nil
  }

  private func openWiredAccessSettings() {
    model.openInputMonitoringSettings()
    dismissWiredAccessInstructions()
  }

}
