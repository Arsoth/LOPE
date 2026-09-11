// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026

import AppKit
import ApplicationServices
import Foundation

@MainActor
extension AppModel {
    private var mouseButtonEventMask: NSEvent.EventTypeMask {
        [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    }

    func setHighlightButtonPresses(_ enabled: Bool) {
        highlightButtonPresses = enabled
        UserDefaults.standard.set(
            enabled,
            forKey: "\(AppConstants.defaultsPrefix).highlightButtonPresses"
        )

        if enabled {
            if !inputMonitoringAuthorized {
                CGRequestListenEventAccess()
                updateInputMonitoringAuthorization()
            }
            if inputMonitoringAuthorized {
                startButtonPressMonitor()
                status = "Button highlighting is on. Press a mouse button to preview its row."
            } else {
                status = "Button highlighting is on. Enable Input Monitoring for LOPE, then return to the app."
            }
        } else {
            stopButtonPressMonitor()
            highlightedButtonID = nil
            highlightExpiryTask?.cancel()
            highlightExpiryTask = nil
            status = "Button highlighting is off."
        }
    }

    func refreshButtonPressMonitor() {
        guard highlightButtonPresses else { return }
        if inputMonitoringAuthorized {
            startButtonPressMonitor()
        } else {
            stopButtonPressMonitor()
        }
    }

    func handleButtonPress(_ buttonID: Int) {
        guard highlightButtonPresses,
              buttons.contains(where: { $0.id == buttonID }) else { return }

        highlightedButtonID = buttonID
        highlightExpiryTask?.cancel()
        highlightExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, let self else { return }
            self.highlightedButtonID = nil
            self.highlightExpiryTask = nil
        }
    }

    func startButtonPressMonitor() {
        guard globalMouseMonitor == nil, localMouseMonitor == nil else { return }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseButtonEventMask) { [weak self] event in
            let buttonID = event.buttonNumber + 1
            DispatchQueue.main.async {
                self?.handleButtonPress(buttonID)
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseButtonEventMask) { [weak self] event in
            let buttonID = event.buttonNumber + 1
            self?.handleButtonPress(buttonID)
            return event
        }
    }

    func stopButtonPressMonitor() {
        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            self.globalMouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            self.localMouseMonitor = nil
        }
    }
}
