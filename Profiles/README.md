# Logitech G mouse descriptors

Each JSON file describes one Logitech G mouse family. The descriptor is deliberately kept outside Swift so a new model can be added without changing the button-label code.

## Adding a mouse

1. Copy the closest physical layout into a new JSON file.
2. Give it a unique `id` and a display `name`.
3. Add the exact device-name fragments and, when known, product IDs under `match`.
4. List profile-array positions under `buttons`. These are the runtime profile record numbers, not necessarily the names printed on the shell.
5. If the firmware exposes vertical wheel motion as extra profile records, map their record numbers to labels under `scrollWheelButtonLabels`. They remain visible and editable, and also stay available as output presets.
6. If the profile record list includes known non-programmable controls, list their runtime record numbers under `hiddenProfileButtonNumbers` so they are preserved in the device data but not offered for editing.
7. Fill in `profileIO`. Use the standard HID++ 0x8100 values only after a real profile read has confirmed them. The editor detects the modern G-Shift bank from the device-reported shift flags and validated records, so do not hard-code G-Shift support in a descriptor. A verified device-specific legacy writer may use its own explicit save strategy; otherwise set `profileIO.supported` to `false` and `save.strategy` to `read-only`.
8. Add the file name to `index.json` and put source links in `sources`.

The app loads the JSON files from the bundled `MouseProfiles` directory. During development it also reads `Profiles/` from the current working directory. Unknown devices continue to use the runtime-detected generic mapping.

## `profileIO` fields

The common modern writer uses feature `0x8100`, reads info with `0x00`, reads sectors with `0x50`, and writes with `0x60` / `0x70` / `0x80`. It backs up the complete sector, preserves bytes it does not understand, recalculates CRC-16/CCITT-FALSE, and verifies the full sector after writing. Those details remain in every modern descriptor so a future device-specific implementation has a single place to compare load/save requirements.

The catalog marks G600, G700/G700s, and newer unverified firmware families
read-only. G600 has a dedicated legacy feature-report reader that preserves the
separate normal and G-Shift banks for inspection and backup, but its save path
is not enabled until DPI, RGB, and profile-state support are implemented too.

## Sources and confidence

Official Logitech product pages and setup/support guides are preferred for physical controls. Public HID++ device catalogs are used for older product IDs. If a legacy mapping is only a conservative physical description, the JSON says so in `profileIO.notes`; a future more-specific file can override it with a higher `match.priority`.
