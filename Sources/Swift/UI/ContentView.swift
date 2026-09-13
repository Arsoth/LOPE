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
              ConfigureSurfaceView(
                model: model,
                confirmRecoveryRestore: $confirmRecoveryRestore,
                presentedRGBZoneID: $presentedRGBZoneID
              )
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
              loadingState: LoadingProfileStateView(model: model),
              emptyState: EmptyStateView(model: model)
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

}
