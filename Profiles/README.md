# Logitech G mouse descriptors

Each JSON file describes one exact Logitech G mouse model — not a family. G502 HERO and G502 LIGHTSPEED are separate files, as are G300 and G300s, even where their physical layout is identical: they are different hardware, and one file should never need a slash in its `name` to describe more than one product. The descriptor is deliberately kept outside Swift so a new model can be added without changing the button-label code. For the pull-request workflow, use the [mouse profile contribution guide](../contributing.md#adding-a-mouse-profile).

The G502 generation is split by hardware identity: `g502-proteus-spectrum.json`
is the RGB wired C332 model, `g502-proteus-core.json` is the non-RGB wired C07D
model, and `g502-hero.json` is the HERO C08B model. Keep these descriptors
separate even though their physical button order is similar.

Several other generations are split the same way, one file per sensor/SKU
revision even when the physical shell and button order are identical:
`g403.json` (original PMW3366, C082), `g403-prodigy.json` (wired-only PMW3366
budget SKU, C083), and `g403-hero.json` (HERO sensor, C08F); `g703.json`
(original PMW3366, C087) and `g703-hero.json` (HERO sensor, C090); `g903.json`
(original PMW3366, C086) and `g903-hero.json` (HERO sensor, C091); `g303.json`
(C080) and `g303-shroud.json` (cosmetic Shroud Edition, C097). A device's
reported product ID is the only reliable way to tell these apart — do not
assume a sensor generation from the marketing name alone. Also watch for
Logitech's own USB *receiver* dongle IDs (e.g. "Lightspeed Receiver" C539,
"Cordless Mouse Receiver" C537) showing up in research sources: those
identify the dongle, not any specific paired mouse, and must never be used as
a descriptor's `productIDs`.

## Adding a mouse

1. Copy the closest physical layout into a new JSON file, named for the exact model (e.g. `g102.json`, not a combined `g102-g203.json`).
2. Give it a unique `id` and a display `name` naming that one model only.
3. Add the exact device-name fragments and, when known, product IDs under `match`. If this model's name is itself a substring of a sibling model's name (for example "PRO X SUPERLIGHT 2" inside "PRO X SUPERLIGHT 2C"), no special handling is needed: matching always prefers the longer, more specific name match over the shorter one.
4. List profile-array positions under `buttons`. These are the runtime profile record numbers, not necessarily the names printed on the shell.
5. If the firmware exposes vertical wheel motion as extra profile records, map their record numbers to labels under `scrollWheelButtonLabels`. They remain visible and editable, and also stay available as output presets.
6. If the profile record list includes known non-programmable controls, list their runtime record numbers under `hiddenProfileButtonNumbers` so they are preserved in the device data but not offered for editing.
7. Fill in `profileIO`. Use the standard HID++ 0x8100 values only after a real profile read has confirmed them. The editor detects the modern G-Shift bank from device-reported shift flags and validated records. It also contains a narrow G603 format-3 fallback because that model can expose and save G-Shift onboard without setting the shift flag; the second bank must still validate before the UI enables it. Do not hard-code generic G-Shift support in a descriptor. A verified device-specific legacy writer may use its own explicit save strategy; otherwise set `profileIO.supported` to `false` and `save.strategy` to `read-only`.
8. Put source links in `sources`. There is no index file to update: the app discovers every JSON file in this directory on its own.

The app loads the JSON files from the bundled `MouseProfiles` directory (falling back to `Profiles/` in the current working directory during development), then overlays anything in the user's `Custom Profiles` folder inside the selected configuration directory. A custom descriptor whose `id` matches a bundled one replaces it; any other `id` is added to the catalog. Unknown devices continue to use the runtime-detected generic mapping.

### Generated placeholders

A descriptor in the custom profiles folder may have `"generated": true`. LOPE writes these itself, from the app's **Create profile** button, for a mouse that matched nothing else: real button-record numbers under placeholder `"Button N"` names, an `id` like `auto-<device>`, and whatever DPI range was read live. `MouseProfileCatalog.matchingProfile` treats a generated descriptor as a last resort — it is only used when no built-in or hand-authored descriptor matches the same device, so adding a real file for that mouse (this one, following the steps above) automatically takes over without deleting the generated one. Do not set `generated` by hand in a file you are authoring; it exists only to mark LOPE's own placeholders as less trustworthy than a person's.

## `profileIO` fields

The common modern writer uses feature `0x8100`, reads info with `0x00`, reads sectors with `0x50`, and writes with `0x60` / `0x70` / `0x80`. It backs up the complete sector, preserves bytes it does not understand, recalculates CRC-16/CCITT-FALSE, and verifies the full sector after writing. Those details remain in every modern descriptor so a future device-specific implementation has a single place to compare load/save requirements.

The catalog marks G600, G700, G700s, and newer unverified firmware families
read-only. G600 has a dedicated legacy feature-report reader that preserves the
separate normal and G-Shift banks for inspection and backup, but its save path
is not enabled until DPI, RGB, and profile-state support are implemented too.

## `referenceProfile` (optional)

A descriptor may carry a `referenceProfile` block recording a known-good button/DPI/report-rate/RGB configuration, distinct from `profileIO` (which describes the transport, not any particular values). `source` records exactly how trustworthy that data is:

- `verifiedFactoryReset` — captured by triggering the manufacturer's own onboard-memory reset on real hardware and reading back the result. This is the only source the app offers as a one-click **Restore reference profile** write, gated by `MouseProfileDescriptor.canRestoreReferenceProfile` (requires this source *and* `profileIO.canSave`).
- `userConfiguration` — a real device's current configuration, useful as a cross-check but not a factory default.
- `manufacturerSpec` — from a published spec sheet rather than a device read.
- `communityReverseEngineering` — from a third-party RE project rather than this device.
- `unknown` — the default when `source` is omitted; never offered as a write.

`buttons` maps profile-array button numbers to their onboard raw record (same 8-hex-digit format as everywhere else). `dpi` is optional (`stages`/`defaultStage`/`shiftStage`, same 1-based stage-index convention as `EditableBackup.DPI`). `reportRateHz` is optional. `rgbZones` is optional and maps a zone index to an effect `mode` name (`disabled`/`static`/`pulse`/`cycle`/`wave`/`breathe`/`ripple`) and, only when actually observed, a `color` hex string — do not fabricate a color for an effect mode (like a color-cycle) whose stored color bytes were never directly confirmed; recording the mode alone and leaving `color` absent is preferred over guessing.

## Sources and confidence

Official Logitech product pages and setup/support guides are preferred for physical controls. Public HID++ device catalogs are used for older product IDs. If a legacy mapping is only a conservative physical description, the JSON says so in `profileIO.notes`; a future file with this exact model's full name automatically takes precedence, since matching always prefers the longer, more specific name.
