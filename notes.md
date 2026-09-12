# LOPE todo list

### [ ] 7. Detect and highlight all standard mouse buttons when possible

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

**Done when:** every standard button that macOS exposes is mapped and
highlighted correctly; unsupported or ambiguous controls are reported clearly
and never mapped by guesswork.

### [ ] 8. Overhaul the README and documentation split

- [ ] Rewrite the README around user usability and day-to-day app usage.
- [ ] Keep build instructions in the README only as far as needed to build the app.
- [ ] Move all other material—architecture, implementation details, troubleshooting,
      and device-specific behavior—into the documentation.
- [ ] Review both after the rewrite to remove duplicated or contradictory guidance.

**Done when:** the README is a concise user and build guide, while the docs are the
complete reference for everything else.

### [ ] 9. Rework keyboard-output selection and custom key recording

- [ ] Combine function keys and special keys into one keyboard-output dropdown.
- [ ] List modifiers before the key choices so the resulting selection reads
      logically.
- [ ] Order the top-level choices as Disabled, Custom, then the remaining standard
      keys.
- [ ] Make Custom expose only the record-input option instead of treating it as a
      normal key choice.
- [ ] Add a Settings checkbox that enables non-standard keys in the override
      dropdown; include keys such as F13 and above when enabled.

**Done when:** the default dropdown is ordered and understandable, custom output uses
the recording flow, and non-standard keys are opt-in through Settings.

### [ ] 10. Determine and surface keyboard-output limits

- [ ] Determine how many keys can be stored in a keyboard output for each supported
      mouse, including the maximum output length.
- [ ] Add the per-mouse maximum to the profile data.
- [ ] Enforce the stored limit when editing or recording keyboard output.
- [ ] Show the current length and maximum at the end of the text field, using a clear
      format such as `X/Y`.

**Done when:** every supported mouse has an accurate stored limit and the editor
shows the user how much of that limit the current output uses.

### [ ] 11. Improve onboard-profile refresh guidance

- [ ] Document the sleep time of verious mice as needed (especially the G603) and explain that the mouse must be kept active.
- [ ] Tell the user to keep the mouse active and then click Refresh when checking for
      the onboard profile.
- [ ] Avoid reporting that no onboard profile exists before this refresh flow has had
      a chance to complete.

**Done when:** G603 users receive the device-specific sleep and refresh instructions
instead of a premature "no onboard profile" message.

### [ ] 12. Remove fallback UI for MX mice

- [ ] Detect MX mice before rendering the fallback UI.
- [ ] Hide the fallback UI for MX mice.
- [ ] Remove the bottom warning for MX mice as well.
- [ ] Verify that fallback UI and warnings still appear correctly for devices that
      actually need them.

**Done when:** MX mice show neither the fallback UI nor the bottom warning, without
changing the behavior for other devices.

### [ ] 13. Add a lightmode tot he app selectable in system preferences - defaulting to match system

- [ ] lightmode should be off white, not pure eye searing white.
- [ ] defaults to system preference (most OS's expose this).
- [ ] dark mode and light mode should be colorblind safe by default

**Done when:** there's a light and a dark mode that are both colorblind safe defaulting to current OS preferences

### [ ] 14. add a mock device which is "alow access for wired mice" if system access is not already approved

- [ ] if wireless (bluetooth, USB receiver), no system permissions needed, so lope will work fine
- [ ] add a mock device at the bottom of the list which is "allow wired mice" (may need better verbiage) which on selection opens a popup giving instructions and a button to launch system preferences and add LOPE to the allow list which the user can then enable

**Done when:** device dropdown, permissions popup.

### [ ] 15. open backups in finder button

- [ ] add a button that opens the backups directory in Finder

**Done when:** there's a button that opens the backups directory in finder in the backups page
