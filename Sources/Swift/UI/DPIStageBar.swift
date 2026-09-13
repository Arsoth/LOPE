// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import Foundation
import SwiftUI

struct DPIStageBar: View {
  let stages: [String]
  let defaultStage: Int
  let shiftStage: Int
  let capabilities: DPICapabilities
  let isLoading: Bool
  let validationMessage: String?
  let onDragValue: (Int, Int) -> Int
  let onDragEnded: () -> Void
  let onAdjust: (Int, DPICapabilities.AdjustmentDirection) -> Void
  let onTextChange: (Int, String) -> Void
  let onCommitText: (Int) -> Void
  let onSetDefault: (Int) -> Void
  let onSetShift: (Int) -> Void
  let onDelete: (Int) -> Void

  @State var editingStage: DPIStageSelection?
  @State var presentedStage: DPIStageSelection?
  @State var fadingStage: DPIStageSelection?
  @State var draggingStage: Int?
  @State var activeDragX: CGFloat?
  @State var lastDragUpdate: DPIStageDragUpdate?
  @State var popupFrame: CGRect?
  @State var popoverContentOpacity = 1.0
  @FocusState var focusedStageIndex: Int?

  let stageSwitchDuration: TimeInterval = 0.08
  // Reserve symmetric space for localized endpoint values up to 999,999.
  let endpointLabelWidth: CGFloat = 56
  let trackToEndpointSpacing: CGFloat = 12
  let endpointCenterAdjustment: CGFloat = 4.5

  var trackInset: CGFloat {
    endpointLabelWidth + trackToEndpointSpacing
  }

  let validationIconSize: CGFloat = 14

  // Match the warning icon center to the center of the minimum endpoint
  // label, accounting for the label's small visual offset.
  var validationLeadingInset: CGFloat {
    trackInset / 2 - endpointCenterAdjustment - validationIconSize / 2
  }
}
