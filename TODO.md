# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:


# LOPE todo list

### 0: Remove references to highlighting all standard mouse buttons

- [ ] Remove references to highlighting all standard mouse buttons anywhere in the swift or C code

**Done when:** there's no more hidden or commented code or features regarding showing all buttons

### 1: Handle missing permissions without blocking wireless discovery

- [ ] When the app cannot query a connected wired mouse because required access is missing, identify the inaccessible device when possible and show an explanatory in-app modal with an “Open System Settings” button instead of immediately triggering the native system permission prompt. Keep the device picker from locking onto the first mouse found, and continue discovering supported wireless mice independently of wired-device permission.

**Done when:** An inaccessible supported wired mouse produces the app-owned permission modal, the button opens the relevant System Settings location, no automatic native permission prompt appears, refresh attempts do not repeatedly present the same permission flow, the generic no-mouse-detected flow is gone, and all discoverable supported wireless mice remain listed and selectable on first load.

### 2: Keep the sleeping-mouse refresh flow usable

- [ ] Keep the refresh button disabled throughout refresh polling for a sleeping mouse instead of periodically re-enabling it when a returned query lands during the delay interval, and recover cleanly if the mouse remains asleep.

**Done when:** The refresh button remains disabled until the refresh operation times out after 60 seconds or the mouse becomes available, and a sleeping mouse cannot leave the app showing only that mouse without a usable recovery or device-selection state.

### 3: Fix the header shadows

- [ ] Correct the rendering and layout of the header shadows.

**Done when:** Header shadows appear over main content.

### 4: Simplify app window and tab ownership

- [ ] Remove unnecessary support for multiple Swift-created app windows and in-app tabs so files cannot have conflicting ownership and the app has a simpler single-instance workflow.

**Done when:** The app exposes one clear window/workflow, and opening or activating the app does not create competing windows or tabs that can own the same files.

### 5: Show one sleep shake-awake notification for all non-wired mice

- [ ] Expand the sleep shake-awake notification to cover every non-wired mouse type, and remove any duplicate copy of the warning from the status footer when it is already shown prominently in the main interface.

**Done when:** Any supported non-wired mouse that enters the relevant sleeping state receives one front-and-center notification, wired mice do not receive it, and the warning is not duplicated in the status footer.

### 6: Group and alphabetize expanded keyboard keys

- [ ] Alphabetize expanded keyboard keys while keeping them grouped into standard full-size keyboard keys, F13-and-later keys, media keys, and other unusual keys; include available media keys such as play and next.

**Done when:** The expanded-key list is deterministic, alphabetized within the intended groups, and contains the supported media keys.

### 7: Preserve recorded key presses that overlap extended keystrokes

- [ ] Keep a key displayed as recorded when a captured keypress also matches an extended-keystroke option; do not replace the recorded value with the dropdown for keys that were actually captured.

**Done when:** Captured overlapping key presses remain visibly recorded, while extended-keystroke choices remain available for keys the user cannot directly access.

### 8: Correctly pad DPI stages when the count jumps

- [ ] Fix `setDPIStageCount` in `AppModel+EditingDPI.swift` so `dpiStages` is padded to the requested count even when the count increases by more than one at a time, such as 1→5.

**Done when:** Increasing the stage count always produces exactly the requested number of stages with valid default values, including multi-stage jumps.

### 9: Display the correct model name for paired mice

- [ ] Prefer the actual device model identity over the generic “Paired Logitech Mouse - Lightspeed” label when identifying a paired mouse.

**Done when:** A paired mouse with identifiable model metadata, such as a G604, is shown by its correct model name, while the generic label is used only when no more specific identity is available.

### 10: Add a structured GUI-to-engine contract

- [ ] Add machine-readable output, such as versioned JSON, or a typed C API for data consumed by the GUI so Swift does not need to parse human-readable CLI output with regular expressions. Keep the human-readable CLI output available for diagnostics.

**Done when:** Device, profile, DPI, and write-operation data used by the GUI crosses a documented structured boundary, malformed or unsupported responses produce clear errors, and the existing diagnostic CLI remains readable.

### 11: Split shared C types from platform-specific headers

- [ ] Break up the shared C header so protocol constants and engine data types are separated from IOKit, CoreFoundation, POSIX, and other platform-specific imports; remove the need for unrelated C modules to include a broad “everything” header.

**Done when:** C modules include only the declarations and platform dependencies they use, protocol and profile code can be tested without unrelated HID declarations, and the existing C self-test still passes.

### 12: Separate C engine operations from CLI presentation

- [ ] Separate device/profile/backup operations from command-line parsing and `printf` output so the C engine can return typed results and errors independently of the CLI.

**Done when:** CLI formatting is confined to the CLI layer, engine operations have reusable result and error paths, and both the command-line tool and GUI-facing boundary use the same operation implementations.

### 13: Isolate profile and backup codecs from HID transport

- [ ] Extract pure profile parsing, byte encoding, CRC handling, and backup-format logic from live-device reads and writes so these codecs operate on byte buffers independently of IOKit.

**Done when:** Profile and backup transformations can be tested without a connected mouse, transport code only handles device communication, and byte-level tests cover parsing, encoding, CRCs, and backup validation.

### 14: Evaluate an in-process engine API after the C boundaries are clean

- [ ] Measure the cost and complexity of the separate `lope` process after the structured boundary and C layering work are complete, then decide whether the GUI should continue using the process boundary or use a typed in-process C library API.

**Done when:** The decision is documented with evidence covering startup cost, error handling, cancellation, HID-resource ownership, testability, and packaging; no process-boundary rewrite is started without a demonstrated benefit.

# Ignore below item(s):
