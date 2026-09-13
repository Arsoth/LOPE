# LOPE TODO Formatting:

### {task number}: Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

- FEAT: check if it's possible to detect a wired mouse the app don't have permission to pull data from (ideally if it's a logitech specifically), and pop up a (not yet created) permission request modal with a "open system preferences" button if so. this should completely replace the no mouse detected logic that does that in the device picker
- FEAT: when refreshing a sleeping mouse, just keep the refresh button disabled, don't periodically re-enable it when timing lands on returned query and delay till next.
- FIX: the bottom footer shadows are still a bit wonky, need to fix those
- FIX: sometimes refresh sticks on a sleeping mouse and the app only shows that mouse with no way to move out without exiting the app completely
- FEAT: multiple open window instance and tabs inside the app from swift are not needed, that can cause cross ownership of files and adds to complexity.
- FEAT: expand the wireless mice sleep shake awake notification to _any_ non-wired mice
- FEAT: alphabetize the expanded keyboard keys, but also keep them grouped, so do [all the keyboard bits on a 100%, home, end, arrows etc], [all the F13+ keys], [media keys (I notice play/next/etc aren't there?)], [all the other weird keys]
- FEAT: if you record a keypress that happens to also match what is in the extended keystrokes, leave it showing as recorded, don't override visually to the dropdown. That's for keys you don't have easy access to, not ones you do (but there's no way to know which keys the current keyboard exposes as far as I'm aware?)

# LOPE todo list

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
