# LOPE todo list

This list turns the product notes into implementation tasks and records what is
known about feasibility from the current code and HID++ protocol. Priority is
ordered as `P0` (correctness/safety), `P1` (high-value UX), and `P2` (polish).

## P0 — safe writes and backup behavior

### [x] 1. Make a save operation batch its changes

**Feasibility: Medium-high, with an important limitation.** The UI already has
one `Save to mouse` action. The previous `AppModel+Writes.swift:applyAll()`
looped over button changes and invoked the engine separately for each one. Each
invocation read, backed up, and wrote a sector. The HID++ onboard-profiles
protocol only commits one sector at a time, so changes in the selected profile
can be combined into one sector write, but a selected-profile sector and the
profile-control sector cannot be made physically atomic together.

**Implementation tasks:**

- [x] Add a batch/apply command or equivalent engine API that loads the
      selected profile sector once, applies all button and DPI mutations in memory,
      recalculates CRC once, writes once, and performs one complete read-back.
- [x] Apply profile enable/disable changes as a separate control-sector batch
      when needed. Keep the UI as one save action and report the number of sectors
      written rather than implying a transaction across sectors.
- [x] Preflight every requested mutation before the first write: supported
      layout, valid raw records, DPI values, profile-state invariant, CRC, and
      device/profile selection.
- [x] Define partial-failure behavior. If a later sector write fails, show
      exactly which sector succeeded and offer restore from the backups created for
      this save operation.
- [x] Add engine/model tests proving that multiple button changes produce one
      profile-sector write and that unchanged sectors are not touched.

**Done when:** one Save action creates a single operation record, makes all
required exact backups before any mutation, writes each affected sector at most
once, verifies each write, and clearly reports any unavoidable multi-sector
partial state.

### [x] 2. Create exact binary backups once, before the first write

**Feasibility: High after the batch design above.** The current backup package
format already stores the complete sector and enough device information for
restore. Backup creation now happens in the batch preflight phase and is
deduplicated by sector.

**Implementation tasks:**

- [x] Identify the unique affected sectors for a save operation.
- [x] Read and save each complete sector before any write, using one operation
      timestamp/ID in the filenames.
- [x] Do not create a second backup for another edit that targets the same
      sector in the same Save operation.
- [x] Keep the existing restore safety checks: matching device/product and
      profile format/sector size, valid target sector, and verified read-back.
- [x] Add failure-path tests for backup creation, first-sector write failure,
      and later-sector write failure.

**Done when:** every affected sector has an exact, restorable binary snapshot
before the first write; no JSON sidecar is required for this safety guarantee.

## P1 — backup and profile UX

### [x] 3. Make backups mouse-specific and filter them to the active mouse

**Feasibility: High for model-level filtering; medium for old/imported files.**
`DeviceChoice` already has a display name and product ID. Binary backup headers
preserve vendor/product metadata, while editable JSON contains the device name
and product ID. The backup index combines those metadata sources with the
sanitized mouse/family name in new filenames; it intentionally does not track
an individual physical mouse.

**Implementation tasks:**

- [x] Add a sanitized mouse identifier to new binary backup names, preferably
      using the display name, for example `G502-X-20260911-021500.bin`.
- [x] Keep names filesystem-safe and bounded; treat same-model mice as one
      compatible backup family rather than assigning each physical mouse a
      unique filename identity.
- [x] Add backup metadata parsing/indexing so the list can compare a backup to
      the selected device. Use embedded binary metadata where available and JSON
      metadata for import files; define a visible “unknown device” state for legacy
      files that cannot be matched safely.
- [x] Filter the Backups tab to the selected mouse by default and offer an
      explicit “show all mice” option for recovery/import workflows.
- [x] Refresh the filtered list when the selected device changes.
- [x] Add tests for two mice, same-model mice, malformed metadata, and legacy
      filenames.

**Done when:** new backups identify their target mouse, changing the active
mouse changes the visible list, and an unmatched backup is never presented as
belonging to the active mouse without an explicit warning.

### [x] 4. Stop generating JSON backup sidecars; use JSON only for import/export

**Feasibility: High.** JSON is now written only by the explicit export
workflow; mouse writes and manual binary dumps do not create JSON sidecars.

**Implementation tasks:**

- [x] Remove sidecar JSON creation from button, DPI, profile-state, batch, and
      manual binary-backup paths.
- [x] Keep `Import JSON…` and `Export JSON…` as explicit profile workflows.
- [x] Change the export default name from `profileN.json` to a sanitized
      `mouse-date-time.json` name, using a stable timestamp format and avoiding
      collisions where practical.
- [x] Decide how existing sidecar JSON files appear: retain them as importable
      files with an “Editable JSON” label, but do not call them backups or create
      new ones.
- [x] Update the Backups help text and list filtering so exact binary backups
      and editable JSON imports are not conflated.

**Done when:** a mouse write creates only the exact binary backup(s), while an
explicit JSON export creates a file named for the mouse and date/time.

## P1 — profile and button discovery

### [x] 5. Expose onboard profile capacity in the loaded UI

**Feasibility: High.** The native engine already reads `ProfileInfo.profile_count`
from HID++ feature `0x8100`; it now emits that value as a stable
`Profile capacity: N` line. The Swift model stores the effective capacity and
tracks whether it was reported or derived from readable headers.

**Implementation tasks:**

- [x] Emit a stable machine-readable line such as `Profile capacity: N` in the
      engine output used by the GUI, or add a dedicated metadata command/result.
- [x] Parse and store `onboardProfileCapacity` in `AppModel`; fall back to the
      number of readable headers if older engine output does not include it.
- [x] Show it during/after load, for example `Onboard profiles (2 of 5
    supported)` or `Profile 1 of 1`, and make the distinction between capacity and
      readable slots clear.
- [x] Keep the UI honest for devices that report unavailable or inconsistent
      profile metadata.
- [x] Add parser tests for capacity, missing capacity, malformed values, and
      CRLF output.

**Done when:** the user can see the mouse’s reported onboard profile capacity
as soon as profile loading completes, without mistaking it for the number of
currently readable/available profile headers.

### [x] 6. Hide redundant profile selectors for one-profile mice

**Feasibility: High and low risk.** The app already knows the number of
discovered profile headers. The top-level profile `Picker` in `ContentView`
should be conditional on `profiles.count > 1`; the editor must continue to
load profile 1 normally.

**Implementation tasks:**

- [x] Hide the top header profile picker when only one profile is available.
- [x] Hide or simplify profile-cycle/enable controls when there is only one
      profile, while preserving the invariant that the sole profile cannot be
      disabled.
- [x] Use the capacity label from item 5 where it gives useful context without
      reintroducing a selector.
- [x] Test switching from a multi-profile mouse to a one-profile mouse and back
      without leaving a stale profile number or stale edits.

**Done when:** one-profile devices have no redundant profile selector, and
multi-profile devices retain the current picker and profile-state controls.

## P2 — button highlighting coverage

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

## P2 — DPI editor visualization

### [ ] 8. Replace the plain DPI stage row with a multi-handle DPI bar

**Feasibility: Medium-high for visualization; medium for drag editing.** The
current editor already supports one to five stages, stage text fields, and
default/DPI-shift selectors. The protocol stores one to five strictly
increasing 16-bit stage values plus one-based default and shift indexes, with
unused slots cleared. A visual bar is therefore compatible, but “enable a
handle” must map to the contiguous `dpiCount` representation and drag values
must respect the mouse’s supported DPI values.

**Implementation tasks:**

- [ ] Parse supported DPI values/ranges into typed model data instead of keeping
      them only in the display string `dpiDetails`.
- [ ] Design a SwiftUI bar with one handle per active stage, a clear add/remove
      or enabled-stage affordance, and a text field for exact DPI entry.
- [ ] Snap dragged handles to supported values where the device reports a
      discrete list or step; otherwise use the supported min/max and validate the
      result before saving.
- [ ] Preserve strict ordering, one-to-five active stages, valid default/shift
      indexes, and the existing `0xFFFF` unused-stage behavior.
- [ ] Distinguish the default and DPI-shift stages visually with stable shapes
      or badges, while handling the case where both refer to the same stage.
- [ ] Retain accessible text/picker controls as an alternative to drag-only
      interaction and test keyboard editing, invalid input, duplicate values, and
      stage removal.

**Done when:** the bar is a clearer visualization and a reliable editor, every
drag/text change produces the same validated protocol representation as the
current controls, and the user can identify default and DPI-shift stages at a
glance.

## Suggested delivery order

1. Batch/preflight writes and exact backups (items 1–2).
2. Remove JSON sidecars and improve backup naming/filtering (items 3–4).
3. Add profile capacity metadata and one-profile UI behavior (items 5–6).
4. Revisit button highlighting only when a reliable event-to-profile mapping is available (item 7).
5. Build the DPI bar after the typed DPI capability model exists (item 8).

## Relevant current files

- `Sources/AppModel+Writes.swift` — save, backup, import, and export flows.
- `Sources/ContentView.swift` — profile selector, backup UI, and DPI editor.
- `Sources/LogitechOnboardProfileManagerApp.swift` — published state and
  change detection.
- `Sources/AppModel+Parsing.swift` — engine output parsing and backup naming.
- `Sources/logitech_onboard_commands_mutate.inc` and
  `Sources/logitech_onboard_profile_io.inc` — sector mutation/write behavior.
- `docs/PROTOCOL.md` — current HID++ and onboard-sector constraints.

unprocessed notes:

- readme file and docs need overhauls again. Readme should be usability and at most how to build the app, docs should be everything else.
- custom keyboard output is still weird. should we just combine function and special keys into one long dropdown? And put the modifiers before the keys so it's more logical what it is.
- how many keys can be stored in a keyboard output anyway? what's the max length per mouse, that should be added to profile data. And shown as an X of Y or X/Y etc label at the end or similar of the textbox.
- for the 603, specify the sleep time / that you need ot keep mouse active then click refresh instead of saying there's no onboard profile
- don't show fallback UI for MX mice, the bottom warning shouldn't be there either
- put disabled, custom, then the rest of the keys
- custom should just have a record input option, and settings should have a checkbox to display non-standard keys in an override dropdown (F13 onwards for the most part)
