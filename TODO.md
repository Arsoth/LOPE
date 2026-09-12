# LOPE TODO Formatting:

### [ ] {task number}. Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

# LOPE todo list

### [x] 1. Add a polling-rate picker beside the active DPI stages picker

- [x] Query HID++ report-rate support from the connected mouse: use feature `0x8061` when available, otherwise `0x8060`, and use the rates reported for the active connection.
- [x] Add a dropdown showing only the rates supported by that mouse.
- [x] Place the picker to the left of the active stages picker.

**Done when:** The editor displays the mouse's supported polling rates beside the active DPI-stage control and can apply the selected rate safely.

### [x] 2. Hide edit actions while the Profile Editor is active

- [x] Hide the existing Revert edits and Save to mouse buttons in the shared bar when Profile Editor is selected.
- [x] Keep only the device selector and Refresh action in that bar.

**Done when:** Selecting Profile Editor leaves the shared bar with only device selection and refresh; no second Revert edits or Save to mouse controls are added.

### [x] 3. Present the sleeping-mouse state as a modal over blurred loading backgrounds

- [x] Show the sleeping-mouse screen as a modal layered over the current screen instead of replacing the underlying data view.
- [x] Apply a slight blur to all loading-state backgrounds.
- [x] Preserve the underlying screen during transitions between profile-derived mocks, the sleeping-mouse state, and data screens.

**Done when:** The sleeping-mouse state appears as a modal over a slightly blurred background, and loading transitions preserve the underlying screen without visibly jumping between views.

### [ ] 4. Refactor the UI into smaller reusable components

- [ ] Split the large ContentView sections into focused components.
- [ ] Extract repeated controls and layouts into reusable views.
- [ ] Preserve the current behavior and appearance while reducing ContentView's size.

**Done when:** The UI is organized into smaller reusable components without behavior or visual regressions.

# Ignore below item(s):

### [ ] 1. Detect and highlight all standard mouse buttons when possible

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
