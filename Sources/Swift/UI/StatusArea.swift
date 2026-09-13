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
    VStack(alignment: .leading, spacing: 14) {
      Divider()
        .frame(maxWidth: .infinity)
        .background(background)
        .shadow(color: .black.opacity(0.22), radius: 6, y: -2)

      HStack(alignment: .top) {
        Button {
          historyPresented.toggle()
        } label: {
          Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsHistoryHeader ? "Close recent events" : "Show recent events")
        .pointerCursor()
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
    }
    .padding(.bottom, 20)
    .frame(maxWidth: .infinity)
    .background(background)
    .shadow(color: .black.opacity(0.24), radius: 7, y: -3)
  }

  private var historyDrawer: some View {
    VStack(spacing: 0) {
      statusBar(showsHistoryHeader: true)

      Divider()
        .frame(maxWidth: .infinity)
        .background(background)
        .shadow(color: .black.opacity(0.22), radius: 6, y: 2)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
            VStack(alignment: .leading, spacing: 5) {
              HStack(alignment: .firstTextBaseline, spacing: eventColumnSpacing) {
                Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.primary.opacity(0.58))
                  .frame(width: timestampColumnWidth, alignment: .leading)
                  .textSelection(.enabled)
                Text(event.message)
                  .font(.callout)
                  .fixedSize(horizontal: false, vertical: true)
                  .textSelection(.enabled)
              }
              .padding(.horizontal, horizontalInset)
              if index < events.count - 1 {
                Divider()
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
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
}
