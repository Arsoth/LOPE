// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import SwiftUI

extension DPIStageBar {
  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .topLeading) {
        if editingStage != nil {
          EscapeKeyMonitor(onEscape: dismissStageEditor)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }

        Capsule()
          .fill(DPIStagePalette.bar)
          .frame(height: 4)
          .overlay {
            Capsule()
              .stroke(.white.opacity(0.12), lineWidth: 0.5)
          }
          .frame(width: max(proxy.size.width - trackInset * 2, 1))
          .position(x: proxy.size.width / 2, y: 43)

        ForEach(tickValues, id: \.self) { value in
          Rectangle()
            .fill(.secondary.opacity(0.52))
            .frame(width: 1, height: 10)
            .position(x: position(for: value, width: proxy.size.width), y: 43)
        }

        ForEach(Array(stages.enumerated()).filter { Int($0.element) != nil }, id: \.offset) {
          item in
          stageHandle(index: item.offset, text: item.element, width: proxy.size.width)
        }

        DPIStageInteractionLayer(
          isActive: draggingStage != nil,
          targets: interactionTargets(width: proxy.size.width),
          onTap: { index in
            presentStageEditor(index)
          },
          onBackgroundClick: {
            if editingStage != nil {
              dismissStageEditor()
            }
          },
          onDragBegan: { index, x in
            if editingStage != nil {
              dismissStageEditor()
            }
            draggingStage = index
            lastDragUpdate = nil
            updateDrag(at: x, width: proxy.size.width)
          },
          onDragChanged: { x in
            updateDrag(at: x, width: proxy.size.width)
          },
          onDragEnded: { x in
            updateDrag(at: x, width: proxy.size.width)
            finishDrag()
          }
        )
        .frame(width: proxy.size.width, height: 86)
        .position(x: proxy.size.width / 2, y: 43)
        .zIndex(30)

        ZStack {
          HStack(spacing: 0) {
            Text(capabilities.minimum.map(formattedDPIValue) ?? formattedDPIValue(100))
              .frame(width: trackInset, alignment: .center)
              .offset(x: -endpointCenterAdjustment)
            Spacer()
            Text(capabilities.maximum.map(formattedDPIValue) ?? formattedDPIValue(65535))
              .frame(width: trackInset, alignment: .center)
              .offset(x: endpointCenterAdjustment)
          }
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: proxy.size.width)
          .position(x: proxy.size.width / 2, y: 43)
        }

        dpiLegend
          .position(x: proxy.size.width / 2, y: 93)

        if let validationMessage {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
              .frame(width: validationIconSize, height: validationIconSize)
            Text(validationMessage)
              .lineLimit(1)
              .truncationMode(.tail)
          }
          .font(.body)
          .foregroundStyle(.orange)
          .frame(
            width: max(proxy.size.width - validationLeadingInset, 1),
            alignment: .leading
          )
          .position(
            x: validationLeadingInset + max(proxy.size.width - validationLeadingInset, 1) / 2,
            y: 93
          )
          .allowsHitTesting(false)
          .zIndex(4)
        }

      }
      // Keep one bubble alive while moving between stages. Replacing
      // separate per-stage popovers was the source of the occasional
      // remove/insert flicker and focus handoff.
      .overlay(alignment: .bottomLeading) {
        if !isLoading,
          let editingStage,
          stages.indices.contains(editingStage.index)
        {
          let value = Int(stages[editingStage.index]) ?? capabilities.minimum ?? 800
          let popoverWidth: CGFloat = 230
          let markerX = position(for: value, width: proxy.size.width)
          let popoverX = min(
            max(markerX - popoverWidth / 2, 0),
            max(proxy.size.width - popoverWidth, 0)
          )
          // Keep the arrow clear of the rounded bottom corners when
          // a stage is close to either end of the track. A small
          // offset is preferable to letting the arrow straddle the
          // curve and makes the anchor read as intentional.
          let arrowEdgeClearance: CGFloat = 36
          let arrowX = min(
            max(markerX - popoverX, arrowEdgeClearance),
            popoverWidth - arrowEdgeClearance
          )
          VStack(spacing: -1) {
            ZStack(alignment: .topLeading) {
              if let fadingStage,
                stages.indices.contains(fadingStage.index)
              {
                stagePopover(index: fadingStage.index, isInteractive: false)
                  .opacity(1 - popoverContentOpacity)
                  .allowsHitTesting(false)
              }
              if let presentedStage,
                stages.indices.contains(presentedStage.index)
              {
                stagePopover(index: presentedStage.index, isInteractive: true)
                  .opacity(popoverContentOpacity)
              }
            }
            .frame(width: 230)
            DPIStageTriangle()
              .fill(Color.black.opacity(0.86))
              .frame(width: 22, height: 11)
              .rotationEffect(.degrees(180))
              .offset(x: arrowX - popoverWidth / 2)
          }
          .frame(width: 230)
          .background {
            GeometryReader { popupProxy in
              Color.clear.preference(
                key: DPIStagePopupFrameKey.self,
                value: popupProxy.frame(in: .named("dpiBar"))
              )
            }
          }
          .compositingGroup()
          .offset(
            x: popoverX,
            y: -(proxy.size.height - 24)
          )
          .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
          .zIndex(100)
        }
      }
      .coordinateSpace(name: "dpiBar")
      .overlay {
        DPIStageOutsideClickMonitor(
          isActive: editingStage != nil,
          excludedFrame: popupFrame,
          onOutsideClick: dismissStageEditor
        )
        .frame(width: proxy.size.width, height: proxy.size.height)
        .allowsHitTesting(false)
      }
      .onPreferenceChange(DPIStagePopupFrameKey.self) { frame in
        popupFrame = frame
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("DPI stage bar")
    .onChange(of: isLoading) { loading in
      if loading { dismissStageEditor() }
    }
    .onChange(of: editingStage) { newValue in
      focusedStageIndex = newValue?.index
    }
    .onChange(of: focusedStageIndex) { newValue in
      if newValue == nil, let editingStage {
        onCommitText(editingStage.index)
      }
    }
  }
}
