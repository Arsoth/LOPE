// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

struct CenteredAppModal<Actions: View>: View {
  let title: String
  let message: String
  let symbol: String
  let onDefaultAction: () -> Void
  let onCancel: () -> Void
  let actions: () -> Actions

  init(
    title: String,
    message: String,
    symbol: String = "info.circle",
    onDefaultAction: @escaping () -> Void = {},
    onCancel: @escaping () -> Void = {},
    @ViewBuilder actions: @escaping () -> Actions
  ) {
    self.title = title
    self.message = message
    self.symbol = symbol
    self.onDefaultAction = onDefaultAction
    self.onCancel = onCancel
    self.actions = actions
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: symbol)
          .font(.title2)
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 6) {
          Text(title)
            .font(.headline)
          Text(message)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
      }
      HStack {
        Spacer()
        actions()
      }
    }
    .padding(22)
    .frame(width: 430)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.primary.opacity(0.14), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.24), radius: 24, y: 10)
    .background(
      ModalKeyboardHandler(
        onDefaultAction: onDefaultAction,
        onCancel: onCancel
      )
    )
  }
}
