# LOPE TODO Formatting:

### [ ] {task number}. Task summary

- [ ] task 1
- [ ] task 2

**Done when:** {Acceptance Criteria}

# LOPE TODO Ingest:

- backups should use subdirectories for the mice models (but still identify the model based on file name as well for sanity), and exporting and importing json should default to documents folder not backups folder

# LOPE todo list

### [ ] 1. Require a primary click before saving a profile

- [ ] Define how the primary-click output is recognized across presets, raw
      records, and imported JSON.
- [ ] Block every mouse-write path when the selected profile has no assigned
      primary click, including button-only and combined saves.
- [ ] Show an actionable validation message and identify the profile that needs
      a primary click assignment.
- [ ] Add regression coverage proving rejected saves do not invoke the write
      engine and valid primary-click assignments continue to save normally.

**Done when:** A profile cannot be written to the mouse unless its primary
click is assigned, the editor explains how to fix the validation failure, and
the guard is covered for all save entry points.

### [ ] 2. Make onboard DPI dragging smooth and responsive

- [ ] Reproduce the current delay, stutter, or handle-position mismatch while
      dragging DPI stages on supported mice.
- [ ] Trace pointer events, value snapping, stage reordering, and SwiftUI view
      updates to identify the source of lag or dropped intermediate positions.
- [ ] Update the interaction path so the dragged handle tracks continuously
      without blocking work or applying redundant updates.
- [ ] Preserve supported-value snapping, strict stage ordering, default/shift
      assignments, accessibility behavior, and text editing.
- [ ] Add regression coverage for continuous drag updates and stage crossings,
      then verify the interaction on representative supported DPI ranges.

**Done when:** A DPI handle follows the pointer continuously without visible
delay or stuttering, including while crossing other stages, and all existing
validation and stage-ordering behavior remains intact.

### [ ] 3. Add onboard RGB profile editing for supported G-series mice

- [ ] Determine which G-series mice and onboard profile formats expose writable
      RGB zones, and document the capability and zone names in the device
      descriptors.
- [ ] Define a safe read/write representation for per-profile RGB zone colors,
      including validation for unsupported or read-only devices.
- [ ] Show an RGB settings row only for profiles and devices that advertise the
      capability, with a color swatch and zone name for each zone.
- [ ] Open a color-wheel picker when a zone is clicked and apply one color to
      all zones when the row is Shift-clicked.
- [ ] Include RGB changes in save, backup, import/export, and read-back
      verification flows where the profile format supports them.
- [ ] Add focused tests for capability gating, color conversion, per-zone
      editing, Shift-click all-zone editing, and unsupported devices.

**Done when:** Supported G-series onboard RGB profiles expose editable named
zones with individual and Shift-click all-zone color selection, changes save
and verify safely, and unsupported profiles show no RGB controls or write path.

### [ ] 4. Organize backups by mouse model and keep JSON in Documents

- [ ] Store backups in a subdirectory named for the compatible mouse model.
- [ ] Keep the mouse model in every backup filename as a secondary sanity check.
- [ ] Default JSON import and export panels to the user's Documents folder
      instead of the backup directory.
- [ ] Preserve device matching, backup discovery, and restore behavior across
      the model subdirectories.

**Done when:** Binary backups are grouped under the correct mouse-model
directory and still carry the model in their filenames, while JSON import and
export default to Documents without breaking discovery or restore flows.

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
