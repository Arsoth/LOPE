// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import ApplicationServices
import CoreGraphics
import CoreVideo
import SwiftUI

struct ContentView: View {
  private enum AppTab: CaseIterable, Hashable {
    case configure
    case backups
    case profileEditor
    case settings

    var title: String {
      switch self {
      case .configure: return "Configure"
      case .backups: return "Backups"
      case .profileEditor: return "Profile Editor"
      case .settings: return "Settings"
      }
    }

    var systemImage: String {
      switch self {
      case .configure: return "cursorarrow.click"
      case .backups: return "archivebox"
      case .profileEditor: return "square.and.pencil"
      case .settings: return "gearshape"
      }
    }
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

  private let tabBarHeight: CGFloat = 36
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
      // tab itself is represented by a custom tab-bar button.
      Button(L10n.text("Settings")) {
        selectedTab = .settings
      }
      .keyboardShortcut(",", modifiers: [.command])
      .opacity(0)
      .frame(width: 0, height: 0)

      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          tabBar
          if selectedTab != .settings {
            deviceHeaderSurface
              .zIndex(1)
          }
          tabContent
            .padding(.top, selectedTab == .settings || selectedTab == .configure ? 0 : 20)
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
    .alert(Text(L10n.text("Restore this backup?")), isPresented: $confirmRestore) {
      Button(L10n.text("Cancel"), role: .cancel) { restoreURL = nil }
      Button(L10n.text("Restore and verify"), role: .destructive) {
        if let restoreURL { model.restore(restoreURL) }
        restoreURL = nil
      }
    } message: {
      Text(restoreURL?.lastPathComponent ?? L10n.text("Selected backup"))
    }
    .alert(Text(L10n.text("Restore backups from this save?")), isPresented: $confirmRecoveryRestore)
    {
      Button(L10n.text("Cancel"), role: .cancel) {}
      Button(L10n.text("Restore and verify"), role: .destructive) {
        model.restoreLastSaveBackups()
      }
    } message: {
      Text(
        L10n.text(
          "LOPE will restore the exact pre-save sectors captured by the failed operation. Any sector that was already unchanged will be skipped safely."
        )
      )
    }
    .alert(Text(L10n.text("Primary click required")), isPresented: $primaryClickModalPresented) {
      Button(L10n.text("Return to editor"), role: .cancel) {}
    } message: {
      Text(
        model.primaryClickValidationMessage
          ?? L10n.text("Choose “Left click” for the primary-click button, then save again.")
      )
    }
  }

  private var tabBar: some View {
    HStack(spacing: 0) {
      ForEach(AppTab.allCases, id: \.self) { tab in
        Button {
          selectedTab = tab
        } label: {
          ZStack {
            Color.clear
            Label(L10n.text(tab.title), systemImage: tab.systemImage)
              .font(.callout.weight(.medium))
              .foregroundStyle(theme.primaryText)
          }
          .frame(maxWidth: .infinity, minHeight: tabBarHeight)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: tabBarHeight)
        .contentShape(Rectangle())
        .background(selectedTab == tab ? theme.controlBackground : theme.mainBackground)
        .overlay(alignment: .trailing) {
          if tab != .settings {
            Rectangle()
              .fill(theme.separator)
              .frame(width: 1)
          }
        }
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
      }
    }
    .frame(maxWidth: .infinity)
    .background(theme.header)
    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(theme.separator)
        .frame(height: 1)
    }
  }

  private var tabContent: some View {
    ZStack {
      tabPane(.configure) {
        ZStack {
          ConfigureSurfaceView(
            model: model,
            confirmRecoveryRestore: $confirmRecoveryRestore,
            presentedRGBZoneID: $presentedRGBZoneID
          )
        }
      }
      tabPane(.backups) {
        BackupsPane(
          model: model,
          restoreURL: $restoreURL,
          confirmRestore: $confirmRestore
        )
      }
      tabPane(.profileEditor) {
        ProfileEditorPane(
          model: model,
          loadingState: LoadingProfileStateView(model: model),
          emptyState: EmptyStateView(model: model)
        )
      }
      tabPane(.settings) {
        SettingsPane(model: model)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func tabPane<Content: View>(
    _ tab: AppTab,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .opacity(selectedTab == tab ? 1 : 0)
      .allowsHitTesting(selectedTab == tab)
      .accessibilityHidden(selectedTab != tab)
      .zIndex(selectedTab == tab ? 1 : 0)
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
        title: model.wiredAccessDeviceName.map {
          L10n.text("Input Monitoring required for {device}", replacements: ["device": $0])
        } ?? L10n.text("Input Monitoring required"),
        message: wiredAccessInstructionsMessage,
        symbol: "lock.shield",
        onDefaultAction: openWiredAccessSettings,
        onCancel: dismissWiredAccessInstructions
      ) {
        Button(L10n.text("Cancel"), role: .cancel, action: dismissWiredAccessInstructions)
        Button(L10n.text("Open System Settings"), action: openWiredAccessSettings)
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
    L10n.text(
      "LOPE can use wireless and receiver-connected mice without this permission. To read and edit a wired mouse, use the button below. On first use, macOS asks to receive keystrokes while it registers LOPE; choose Open System Settings, enable LOPE there, then return and choose Refresh."
    )
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
