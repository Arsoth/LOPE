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

### [x] 9. Rework keyboard-output selection and custom key recording

- [x] Combine function keys and special keys into one keyboard-output dropdown.
- [x] List modifiers before the key choices so the resulting selection reads
      logically.
- [x] Order the top-level choices as Disabled, Custom, then the remaining standard
      keys.
- [x] Make Custom expose only the record-input option instead of treating it as a
      normal key choice.
- [x] Add a Settings checkbox that enables non-standard keys in the override
      dropdown; include keys such as F13 and above when enabled.

**Done when:** the default dropdown is ordered and understandable, custom output uses
the recording flow, and non-standard keys are opt-in through Settings.

### [x] 10. Determine and surface keyboard-output limits

- [x] Determine how many keys can be stored in a keyboard output for each supported
      mouse, including the maximum output length.
- [x] Add the per-mouse maximum to the profile data.
- [x] Enforce the stored limit when editing or recording keyboard output.
- [x] Show the current length and maximum at the end of the text field, using a clear
      format such as `X/Y`.

**Done when:** every supported mouse has an accurate stored limit and the editor
shows the user how much of that limit the current output uses.

### [x] 11. Improve onboard-profile refresh guidance

- [x] Document the sleep time of various mice as needed (especially the G603) and explain that the mouse must be kept active.
- [x] Tell the user to keep the mouse active and then click Refresh when checking for
      the onboard profile.
- [x] Avoid reporting that no onboard profile exists before this refresh flow has had
      a chance to complete.

**Done when:** G603 and G604 users receive the device-specific sleep and refresh instructions
instead of a premature "no onboard profile" message.

### [x] 12. Remove fallback UI for MX mice

- [x] Detect MX mice before rendering the fallback UI.
- [x] Hide the fallback UI for MX mice.
- [x] Remove the bottom warning for MX mice as well.
- [x] Verify that fallback UI and warnings still appear correctly for devices that
      actually need them.

**Done when:** MX mice show neither the fallback UI nor the bottom warning, without
changing the behavior for other devices.

### [x] 13. Add a lightmode to the app selectable in system preferences - defaulting to match system

- [x] lightmode should be off white/light grey, not pure eye searing white.
- [x] defaults to system preference (most OS's expose this).
- [x] dark mode and light mode should be colorblind safe by default - the DPI colors are currently safe and work in both modes, do not change.

**Done when:** there's a light and a dark mode that are both colorblind safe defaulting to current OS preferences

### [x] 14. add a mock device which is "alow access for wired mice" if system access is not already approved

- [x] if wireless (bluetooth, USB receiver), no system permissions needed, so lope will work fine
- [x] add a mock device at the bottom of the list which is "allow wired mice" (may need better verbiage) which on selection opens a popup giving instructions and a button to launch system preferences and add LOPE to the allow list which the user can then enable

**Done when:** device dropdown, permissions popup.

### [x] 15. open backups in finder button

- [x] add a button that opens the backups directory in Finder

**Done when:** there's a button that opens the backups directory in finder in the backups page

### [x] 16. create an initial backup of each mouses onboard profiles if one doesn't already exist

- [x] create an initial backup of each mouses onboard profiles if one doesn't already exist

**Done when:** an initial connection of a mouse creates a profile backup

### [x] 17. mice with known onboard profile capabilities should not say there isn't one if the mouse isn't connected

- [x] display an indicator to wake the mouse my turning it on or giving it a little shake, run a refresh on that mouse once a second until it's detected or 60 seconds have passed (or they switch to a different mouse)

**Done when:** see checkbox.

### [x] 18. Overhaul the README and documentation split

- [x] Rewrite the README around user usability and day-to-day app usage.
- [x] Keep build instructions in the README only as far as needed to build the app.
- [x] Move all other material—architecture, implementation details, troubleshooting,
      and device-specific behavior—into the documentation.
- [x] Review both after the rewrite to remove duplicated or contradictory guidance.

**Done when:** the README is a concise user and build guide, while the docs are the
complete reference for everything else.
