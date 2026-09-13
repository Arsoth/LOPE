# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

# LOPE todo list

### 1: Detect connected mice blocked by missing permissions

- [ ] Detect a connected wired mouse that the app cannot query, preferably identifying Logitech devices, and show a permission request modal with an “Open System Settings” button, replacing the device picker’s generic no-mouse-detected state.

**Done when:** An inaccessible supported mouse produces the permission flow, the button opens the relevant System Settings location, and the generic no-mouse-detected flow is no longer in existence.

### 2: Keep refresh disabled while a mouse is sleeping

- [ ] Keep the refresh button disabled throughout refresh polling for a sleeping mouse instead of periodically re-enabling it when a returned query lands during the delay interval.

**Done when:** The refresh button remains disabled until the refresh operation times out after the 60s or the mouse becomes available.

### 3: Fix the header shadows

- [ ] Correct the rendering and layout of the header shadows.

**Done when:** Header shadows appear over main content.

### 4: Recover from a refresh stuck on a sleeping mouse

- [ ] Fix the refresh flow so a sleeping mouse cannot leave the app showing only that mouse with no way to recover without quitting.

**Done when:** A refresh against a sleeping mouse either recovers or returns to a usable device-selection state without requiring the app to exit.

### 5: Simplify app window and tab ownership

- [ ] Remove unnecessary support for multiple Swift-created app windows and in-app tabs so files cannot have conflicting ownership and the app has a simpler single-instance workflow.

**Done when:** The app exposes one clear window/workflow, and opening or activating the app does not create competing windows or tabs that can own the same files.

### 6: Show the sleep shake-awake notification for all non-wired mice

- [ ] Expand the wireless-mouse sleep shake-awake notification to cover every non-wired mouse type.

**Done when:** Any supported non-wired mouse that enters the relevant sleeping state receives the notification, while wired mice do not.

### 7: Group and alphabetize expanded keyboard keys

- [ ] Alphabetize expanded keyboard keys while keeping them grouped into standard full-size keyboard keys, F13-and-later keys, media keys, and other unusual keys; include available media keys such as play and next.

**Done when:** The expanded-key list is deterministic, alphabetized within the intended groups, and contains the supported media keys.

### 8: Preserve recorded keypresses that overlap extended keystrokes

- [ ] Keep a key displayed as recorded when a captured keypress also matches an extended-keystroke option; do not replace the recorded value with the dropdown for keys that were actually captured.

**Done when:** Captured overlapping keypresses remain visibly recorded, while extended-keystroke choices remain available for keys the user cannot directly access.

### 9: Correctly pad DPI stages when the count jumps

- [ ] Fix `setDPIStageCount` in `AppModel+EditingDPI.swift` so `dpiStages` is padded to the requested count even when the count increases by more than one at a time, such as 1→5.

**Done when:** Increasing the stage count always produces exactly the requested number of stages with valid default values, including multi-stage jumps.

# Ignore below item(s):

### 0: Detect and highlight all standard mouse buttons when possible

**Status: Deferred.** AppKit testing on G502 X and G604 exposed only buttons
1–3, and the attempted HID report monitor did not provide a dependable
button-to-profile-row mapping. The experimental implementation was removed;
the UI location is preserved as a commented future expansion below the footer.
Some Logitech controls (DPI, profile, G-Shift, and vendor-specific buttons) may
not generate ordinary macOS mouse-button events at all. A lower-level HID event
path would require more permission handling and may still not reveal the
firmware’s logical profile-record number.

**Implementation tasks:**

- [x] Capture the AppKit limitation on representative G502 X/G604 hardware.
- [x] Evaluate the existing HID-level watch path and the experimental app
      monitor; neither produced a sufficiently reliable profile-row mapping for
      this UI.
- [x] Remove the experimental monitor and comment out the UI with a future-
      expansion note rather than shipping misleading highlighting.
- [ ] Revisit only when a reliable standard/vendor event-to-profile mapping is
      available, with regression coverage for buttons 1–8 and unsupported
      controls.
