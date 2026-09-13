# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

- the wake warning pops up in the status footer and it shouldn't, the warning is front and center already
- if the app doesn't have access it needs to open a modal saying this and an option to open system settings. do NOT immediately pop up the system popup. it's also appearing every time the app refreshes when trying to wake mouse.
- on first load it locks to only showing the first mouse it sees when there isn't permission, the dropdown cant see any other wireless mice. The wireless mice also don't need the permission as far as I am aware.
- the app sometimes shows "Paired Logitech Mouse - Lightspeed" instead of the correct device (a G604 in this particular instance)

# LOPE todo list

### 0: Remove references to highlighting all standard mouse buttons

- [ ] Remove references to highlighting all standard mouse buttons anywhere in the swift or C code

**Done when:** there's no more hidden or commented code or features regarding showing all buttons

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

### 8: Preserve recorded key presses that overlap extended keystrokes

- [ ] Keep a key displayed as recorded when a captured keypress also matches an extended-keystroke option; do not replace the recorded value with the dropdown for keys that were actually captured.

**Done when:** Captured overlapping key presses remain visibly recorded, while extended-keystroke choices remain available for keys the user cannot directly access.

### 9: Correctly pad DPI stages when the count jumps

- [ ] Fix `setDPIStageCount` in `AppModel+EditingDPI.swift` so `dpiStages` is padded to the requested count even when the count increases by more than one at a time, such as 1→5.

**Done when:** Increasing the stage count always produces exactly the requested number of stages with valid default values, including multi-stage jumps.

# Ignore below item(s):
