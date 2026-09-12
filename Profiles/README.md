# Logitech G mouse descriptors

Each JSON file describes one exact Logitech G mouse model — not a family. G502 HERO and G502 LIGHTSPEED are separate files, as are G300 and G300s, even where their physical layout is identical: they are different hardware, and one file should never need a slash in its `name` to describe more than one product. The descriptor is deliberately kept outside Swift so a new model can be added without changing the button-label code.

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

## Sources and confidence

Official Logitech product pages and setup/support guides are preferred for physical controls. Public HID++ device catalogs are used for older product IDs. If a legacy mapping is only a conservative physical description, the JSON says so in `profileIO.notes`; a future file with this exact model's full name automatically takes precedence, since matching always prefers the longer, more specific name.
