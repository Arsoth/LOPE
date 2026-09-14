// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

// Status and top-level section views are kept in dedicated files.

import SwiftUI

struct StatusArea: View {
  let status: String
  let events: [StatusEvent]
  let messageOpacity: Double
  let background: Color
  @Binding var historyPresented: Bool

  private let panelHeight: CGFloat = 270
  private let historyHeaderHeight: CGFloat = 48
  private let eventRowHeight: CGFloat = 40
  private let timestampColumnWidth: CGFloat = 48
  private let eventColumnSpacing: CGFloat = 4
  private let horizontalInset: CGFloat = 20

  var body: some View {
    Group {
      if historyPresented {
        historyDrawer
          .frame(maxWidth: .infinity)
          .frame(height: panelHeight, alignment: .topLeading)
          .transition(.move(edge: .bottom))
      } else {
        statusBar(showsHistoryHeader: false)
      }
    }
  }

  private func statusBar(showsHistoryHeader: Bool) -> some View {
    VStack(alignment: .leading, spacing: showsHistoryHeader ? 0 : 14) {
      if !showsHistoryHeader {
        Divider()
          .frame(maxWidth: .infinity)
      }

      HStack(alignment: .center, spacing: 8) {
        Button {
          historyPresented.toggle()
        } label: {
          Image(systemName: "info.circle")
            .frame(width: 20, height: 20)
            .contentShape(Circle())
            .pointingHandCursor(circleDiameter: 20)
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .contentShape(Circle())
        .accessibilityLabel(showsHistoryHeader ? "Close recent events" : "Show recent events")
        if showsHistoryHeader {
          Text("Recent events")
            .font(.headline)
            .foregroundStyle(.primary)
          Spacer()
          Text("Last \(events.count)")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text(status)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .opacity(messageOpacity)
          Spacer()
        }
      }
      .padding(.horizontal, horizontalInset)
      .frame(
        maxWidth: .infinity,
        minHeight: showsHistoryHeader ? historyHeaderHeight : nil,
        alignment: .center
      )
    }
    .padding(.bottom, showsHistoryHeader ? 0 : 20)
    .frame(maxWidth: .infinity)
    .background {
      if showsHistoryHeader {
        background
          .overlay(Color.primary.opacity(0.05))
      } else {
        background
      }
    }
    .overlay(alignment: .bottom) {
      if showsHistoryHeader {
        Divider()
      }
    }
    .shadow(color: .black.opacity(0.24), radius: 8, y: -3)
  }

  private var historyDrawer: some View {
    VStack(spacing: 0) {
      statusBar(showsHistoryHeader: true)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
            eventRow(event, isLast: index == events.count - 1)
          }
        }
        .frame(maxWidth: .infinity)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(nsColor: .controlBackgroundColor))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .controlBackgroundColor))
    .overlay {
      EscapeKeyMonitor(onEscape: { historyPresented = false })
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
    .onExitCommand {
      historyPresented = false
    }
  }

  private func eventRow(_ event: StatusEvent, isLast: Bool) -> some View {
    HStack(alignment: .center, spacing: eventColumnSpacing) {
      Text(event.timestamp.formatted(date: .omitted, time: .shortened))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.primary.opacity(0.58))
        .frame(width: timestampColumnWidth, alignment: .leading)
        .textSelection(.enabled)
      Text(event.message)
        .font(.callout)
        .lineLimit(1)
        .truncationMode(.tail)
        .textSelection(.enabled)
    }
    .padding(.horizontal, horizontalInset)
    .frame(
      maxWidth: .infinity,
      minHeight: eventRowHeight,
      maxHeight: eventRowHeight,
      alignment: .leading
    )
    .overlay(alignment: .bottom) {
      if !isLast {
        Divider()
      }
    }
  }
}
