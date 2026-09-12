# LOPE reference

This document is the complete reference for behavior that is useful when
maintaining or troubleshooting LOPE but does not belong in the short user
README.

## Architecture

The app has three layers:

- `Sources/AppMain.swift` and `Sources/ContentView.swift` provide the SwiftUI
  window, tabs, editor, settings, and status messages.
- `Sources/LogitechOnboardProfileManagerApp.swift` plus the `AppModel+*.swift`
  extensions own device selection, refresh state, parsing, backup management,
  editing, and writes.
- `Sources/logitech_onboard.m` assembles the C HID++ engine from the focused
  `.inc` modules. The GUI invokes the bundled engine as a separate process.

Mouse-specific physical layouts and capability metadata are JSON descriptors in
`Profiles/`. `MouseProfileCatalog` loads them from the app bundle and, during
development, from the repository's `Profiles/` directory. The descriptor keeps
physical button labels separate from the current output assignment.

The engine enumerates Logitech HID interfaces, discovers HID++ features, reads
the onboard profile descriptor, and validates the selected profile before
exposing it to the editor. Writes are deliberately narrow: the app backs up the
complete affected sector, changes only the requested records, recalculates the
sector CRC, writes in HID++ chunks, and verifies the full sector by reading it
back.

Detailed wire formats, offsets, CRC rules, and implementation references are in
[PROTOCOL.md](PROTOCOL.md).

## Device discovery and permissions

The device picker is built from the engine's stable enumeration output. A
device's display name, connection type, product ID, and HID identity are kept
together so that a refresh cannot accidentally apply one mouse's profile to
another.

LOPE does not request access during enumeration. If macOS reports that a wired
HID interface needs Input Monitoring, the picker adds a non-device entry,
**Allow wired mice — Input Monitoring**. Selecting it explains the permission
and opens the matching System Settings page. Wireless and receiver devices stay
usable without this wired-access entry. The entry is UI-only and is never sent
to the HID engine as a device selector.

Input Monitoring state is refreshed when the app becomes active and after the
settings link is opened. A permission change is followed by an explicit
**Refresh**, which avoids claiming that a profile is absent before the new
permission has been used.

## Refresh and sleeping mice

The initial refresh reads a remembered device when possible, then enumerates the
current device list in the background. A normal Refresh enumerates first and
reads the selected profile with retries; an incomplete profile read is not
presented as a valid empty profile.

For a cataloged mouse with a known onboard-profile capability that is not
reachable, the editor preserves the device identity, clears stale profile data,
shows a wake indicator, and polls once per second for up to 60 seconds. Polling
ends when the requested device is found, when the user selects another device,
or when the timeout expires. Another mouse appearing in the meantime does not
satisfy the requested-device poll.

The G603 and G604 descriptors add device-specific sleep text. The G603 can
sleep very quickly in Endurance mode; the G604 can sleep after several minutes.
The UI tells the user to keep the mouse moving or wake it and then choose
Refresh.

## Device-specific behavior

The catalog contains current and legacy G-series families, with a `profileIO`
section that states whether the onboard format is safe to write. Cataloged
devices with an unverified format are discoverable and readable where possible
but remain read-only. Adding a descriptor is not by itself authorization to
write: its profile layout and save path must be validated first.

MX-series devices are classified by name and known product ID before the
fallback editor is rendered. They can remain visible in discovery, but LOPE
does not invent a G-series physical layout for them and does not show the MX
fallback warning as an apparent missing profile.

An unknown non-MX device uses neutral runtime labels such as Primary click,
Back, and Button 6. The output column always describes the assignment stored in
the selected profile. Device-specific controls, scroll-wheel records, and
non-programmable records are defined in the matching JSON descriptor.

## Editor behavior

### Keyboard outputs

The top-level output menu is ordered as:

1. Disabled
2. Keystroke
3. Standard mouse and keyboard outputs

Function keys and special keys are one keyboard-key list. Keystroke is a keyboard
record workflow: clicking the recorded-input box captures one macOS key event
plus its Ctrl, Shift, Alt, and Command flags. The highlighted box displays the
complete chord and exposes an X that cancels without changing the existing
output. The editor knows the full keyboard usage table for recording, but keeps
the optional extended-key override hidden until the Settings opt-in is enabled.
That opt-in adds keys such as Insert, F13–F24, and Sleep.

The standard HID++ keyboard record has one usage byte and one modifier bitmap.
Macro records use a separate format and remain outside this editor's writable
keyboard-output model.

### DPI and profiles

The DPI editor supports one to five strictly increasing stages, subject to the
values reported by the mouse. Default and DPI-shift stages are separate
one-based selections. Profile toggles cannot disable the final enabled profile.

## Backup lifecycle

The default folder is:

```text
~/Library/Application Support/LOPE/Backups
```

The user can choose another folder from Settings; existing files are not moved.
The Backups tab can open the active folder in Finder.

On the first successful profile read for a mouse, LOPE schedules an exact
binary dump for every readable onboard profile if no matching binary backup is
already present. Each normal save also creates exact pre-write sector backups.
Binary packages preserve bytes the editor does not understand and are the
preferred emergency restore format.

Editable JSON is an explicit import/export format. It includes device metadata,
profile state, friendly physical-control names, the readable output, and the
raw four-byte record. Loading JSON changes only the editor draft; it never
writes to the mouse by itself. Restore and save operations require the selected
device to match the backup metadata.

## Troubleshooting

### No mouse or no profile

- Confirm that the mouse or receiver is connected and powered on.
- Keep wireless mice active and click **Refresh**. For G603/G604, follow the
  wake text and allow the one-minute known-device poll to finish.
- For a wired device, select the Input Monitoring helper entry, enable LOPE in
  **System Settings → Privacy & Security → Input Monitoring**, return to LOPE,
  and click **Refresh**.
- Quit G HUB and other remappers while reading or saving.
- A connected MX mouse without a descriptor is intentionally not shown in the
  generic button editor. A cataloged read-only model is likewise intentional.

### Save or restore problems

LOPE reports a failed write instead of claiming success. If a save stops after
writing one or more sectors, use **Restore backups from this save** or restore
the newest exact binary backup from the Backups tab. Keep the original backup
folder available until recovery is complete.

## Command-line engine

The repository also builds `bin/lope`, a diagnostic tool:

```sh
make
./bin/lope list
./bin/lope info
./bin/lope profiles
./bin/lope current-dpi
./bin/lope self-test
```

Write commands are preview-only unless `--yes` is supplied. The CLI validates
the device-reported format, backs up before writing, writes HID++ chunks, and
verifies readback. The GUI uses the same engine but supplies a stable device
key and keeps low-level diagnostics out of the status bar.

## Development checks

Run the repository checks from its root:

```sh
make
make test
```

`make test` runs the C engine self-test and the Swift metadata/parser test. The
Swift test also validates profile metadata, device classification, appearance
choices, sleep guidance, and the wired-access helper behavior.

For descriptor additions, follow [Profiles/README.md](../Profiles/README.md),
update `Profiles/index.json` when appropriate, and add a focused test before
enabling a new write path.
