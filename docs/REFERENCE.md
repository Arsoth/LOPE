# LOPE reference

This document is the complete reference for behavior that is useful when
maintaining or troubleshooting LOPE but does not belong in the short user
README.

## Architecture

The app has three layers:

- `Sources/Swift/App/AppMain.swift`, `Sources/Swift/UI/ContentView.swift`, and the
  focused `Sources/Swift/UI` components provide the SwiftUI
  window, tabs, editor, settings, and status messages. The footer message fades
  after 30 seconds; its info button replaces the footer with a full-width,
  scrollable history drawer whose header is the same footer bar and shows the
  ten most recent status events. Opening the drawer reduces the editor's
  available height rather than covering it.
- `Sources/Swift/Model/AppModel.swift` plus the
  `Sources/Swift/Model/AppModel+*.swift` extensions own device selection,
  refresh state, parsing, backup management, editing, and writes.
- `Sources/C/Core/main.m` is the C HID++ engine entry point.
  The engine is organized into independently compiled modules under `Sources/C`
  (HID, Profiles, Backup, Commands, CLI, and Testing). The GUI invokes the
  bundled engine as a separate process.

Mouse-specific physical layouts and capability metadata are JSON descriptors in
`Profiles/`. `MouseProfileCatalog` loads them from the app bundle and, during
development, from the repository's `Profiles/` directory, then overlays any
descriptors the user has placed in the `Custom Profiles` folder inside the
selected configuration directory (see
`MouseProfileCatalog.shared.customProfilesDirectory`); a custom `id` that matches a
bundled one replaces it, and there is no index file to keep in sync. The
descriptor keeps physical button labels separate from the current output
assignment.

App-wide colors and DPI drag-handle shapes are JSON theme definitions in
`Themes/`. `ThemeCatalog` loads the bundled `light.json` and `dark.json` files,
then overlays valid themes from the `Custom Themes` folder inside the selected
configuration directory. A custom theme with the same `id` replaces its bundled
counterpart. The custom folder is created automatically and contains the
underscore-prefixed `_empty.json` format template; underscore-prefixed files
are ignored by the loader, and the template is recreated when missing.

A descriptor can also be `generated`: written by LOPE itself, for a device
neither the bundle nor the user recognized, with real button records under
placeholder `"Button N"` names (see "Unrecognized mice" below). Catalog
matching (`MouseProfileCatalog.matchingProfile`) only uses a `generated`
descriptor when no built-in or hand-authored one matches the same device, so a
better descriptor added later always takes over automatically.

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

Device names are normalized consistently across the picker, selected-device
summary, and cached refresh state. In particular, marketing prefixes such as
"Tunable RGB Gaming Mouse" are removed from G502 labels while meaningful
variants such as X, PLUS, HERO, and LIGHTSPEED remain.

For receiver-backed mice, the product ID is the paired mouse's WPID from the
receiver pairing record. The receiver's USB product ID remains transport-only:
it selects the receiver interface and routing path, but it is not a mouse
identity and is never serialized into new backup metadata.

LOPE does not request access or show a modal during enumeration. If macOS
reports that a wired HID interface needs Input Monitoring, the picker keeps the
real wired mouse visible. Selecting it explains the permission and opens the
matching System Settings page. The explicit permission action calls
`CGRequestListenEventAccess()` in LOPE.app to request registration with
the Input Monitoring privacy pane before the user enables it. Both buttons
request access from the GUI process and then open the pane, including on
repeated clicks after denial. They do not wait for the CLI or open extra HID
interfaces to trigger registration. macOS owns the permission prompt and list;
the first registration displays macOS's Keystroke Receiving dialog. That
dialog's **Open System Settings** action opens the privacy pane; LOPE does not
also open a second copy of the pane behind it. Once a TCC record exists, later
clicks open Input Monitoring directly. No public API can silently accept or
bypass the first consent step. A successful settings URL launch alone does not
verify registration. Wireless and receiver devices stay usable without this
permission.

Before access is granted, discovery reads only passive HID properties. It does
not inspect parsed HID elements because macOS may open the protected device as
part of that operation and show a Keystroke Receiving prompt during launch.
That protected fallback is available only after Input Monitoring is enabled.

For development testing, removing the Input Monitoring row does not clear
an old Accessibility permission tied to a different signing certificate.
TCC can reject that stale code requirement while evaluating Input Monitoring
through Accessibility. A clean test after changing the signing certificate
requires quitting LOPE, resetting **only LOPE's** `Accessibility` and
`ListenEvent` records with `tccutil reset <service> com.cotyledonlabs.lope`,
and relaunching the signed app. This is a development diagnostic, not an
operation the app performs or a normal setup requirement. Keep the signing
certificate stable between builds.

Keyboard recording uses an app-local event monitor while LOPE is active, so it
does not request Input Monitoring. It does not capture keys from other apps.

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
reachable, the editor preserves the device identity and current profile-derived
surface, blurs that surface slightly, shows a wake modal over it, and polls once
per second for up to 60 seconds. Polling ends when the requested device is found,
when the user selects another device, or when the timeout expires. Another mouse
appearing in the meantime does not satisfy the requested-device poll.

While discovery or the wake poll is in progress, the visible editor surface is
provisional: it may contain catalog-derived placeholders or the previous
profile. DPI validation, live-DPI display, and profile/catalog warning banners
stay hidden until a profile read has latched the selected mouse's data.

The Configure tab shows a polling-rate picker beside the active DPI-stage
control when the connected mouse reports HID++ report-rate support. The native
engine prefers feature `0x8061` and its active-connection rate list, falling
back to `0x8060`. Selecting a rate creates a pending change; Save writes the
selected profile's report interval in the same backed-up, CRC-protected sector
transaction as DPI, button, and RGB changes, then verifies the complete sector
read-back. The profile format stores whole-millisecond intervals, so the GUI
offers only rates up to 1000 Hz for onboard-profile saves. The standalone
`set-report-rate` command remains a connection-level diagnostic rather than the
GUI's profile-save path.

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

The `G502 Proteus Spectrum` descriptor represents the wired Spectrum model
(product 0xC332), using its original button layout and validated legacy RGB
zones (Logo and DPI-indicator, in that zone-index order). The catalog keeps
`G502 Proteus Core` (0xC07D), `G502 HERO` (0xC08B), LIGHTSPEED, and X as
separate descriptors so their product identities and capabilities cannot be
confused. Its descriptor also carries a `referenceProfile` (see
[Profiles/README.md](../Profiles/README.md#referenceprofile-optional))
captured by factory-resetting a real device from Logitech G HUB and reading
back the result — the only data source trusted enough to back the **Restore
reference profile** button described below.

MX-series devices are classified by name and known product ID before the
fallback editor is rendered. They can remain visible in discovery, but LOPE
does not invent a G-series physical layout for them and does not show the MX
fallback warning as an apparent missing profile; the button editor stays
hidden regardless of what a raw onboard-profile read returns. MX button and
gesture behavior is normally managed by Logi Options+ on the host rather than
verified onboard flash, so a device answering the feature 0x8100 query is not
evidence that editing or writing back would be safe or meaningful — only a
human-authored, hardware-validated descriptor may enable the editor for this
device class (`AppModel.createGeneratedProfile()` refuses outright for a
device classified as MX; see "Unrecognized mice" below).

An unknown non-MX device uses neutral runtime labels such as Primary click,
Back, and Button 6, and the button editor is already usable without any
descriptor. The output column always describes the assignment stored in the
selected profile. Device-specific controls, scroll-wheel records, and
non-programmable records are defined in the matching JSON descriptor.

### Unrecognized mice

`AppModel.createGeneratedProfile()` turns that blind session into a real,
persisted descriptor: it reads the button-record numbers already visible in
`normalButtonRows`/`gShiftButtonRows`, the current DPI range, and the
connected device's name and product ID, then writes a `generated: true`
descriptor to the custom profiles folder under an `auto-<device>` id and
reloads the catalog (`MouseProfileCatalog.reload`) so the device is recognized
immediately, without an app restart. Buttons keep their placeholder
`"Button N"` names until a person edits the file — the device is only
readable well enough to enumerate its records, not to know what a person calls
each one. The UI offers this as a **Create profile** button in the read-only
banner above the button list for an unmatched non-MX device. It is a no-op
while `hasSpecificMouseProfile` is already true, before any button records
have been read, or for a device classified as MX-series (see above).

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
That opt-in adds keys such as Insert, F13–F24, bare modifier usages, and Sleep.
When a modifier usage is selected as the key itself, the matching Ctrl, Shift,
Alt, or Command chord toggle remains visible but is disabled to prevent sending
the same modifier twice.

The standard HID++ keyboard record has one usage byte and one modifier bitmap.
Macro records use a separate format and remain outside this editor's writable
keyboard-output model.

### DPI and profiles

The DPI editor supports one to five strictly increasing stages, subject to the
values reported by the mouse. Default and DPI-shift stages are separate
one-based selections. Profile toggles cannot disable the final enabled profile.

### RGB editing

For a device whose descriptor advertises writable RGB zones, each zone has an
independently editable solid color and effect mode (Disabled, Solid, Pulse,
Cycle, Wave, Breathe, Ripple — see
[Legacy onboard RGB records](PROTOCOL.md#legacy-onboard-rgb-records)). Color
and mode are staged and saved separately (`--rgb-change` / `--rgb-mode-change`)
but land in the same batched sector write as any other pending change. An
effect ID the device reports but this editor has no name for (a handful of
unnamed IDs the firmware still accepts) displays as Disabled rather than
disappearing from the editor.

A descriptor with a `referenceProfile` sourced from an actual verified factory
reset (see [Profiles/README.md](../Profiles/README.md#referenceprofile-optional))
offers a **Restore reference profile** action that loads its recorded button
assignments, DPI table, report rate, and RGB effect modes into the editor's
drafts for review — it does not write anything until the normal Save action is
used afterward, and it never touches RGB color, since the recorded reference
data intentionally omits colors that were never directly confirmed on a real
device (e.g. the color bytes underlying a cycling rainbow effect).

### G-Shift button assignments

For a profile whose reported modern layout includes a validated G-Shift bank,
the button editor shows Normal and G-Shift layers. Each layer has its own
drafts, and saving sends both changed banks in the same profile-sector update.
The G-Shift layer is enabled from the mouse’s reported layout and validated
records; it is not inferred from the product name. Legacy formats with a
different storage scheme remain read-only until their writer is implemented.

The G600 is supported for read-only inspection through its dedicated legacy
feature-report reader. It keeps the normal and G-Shift assignments as separate
20-button layers and can back up the complete selected profile report. Its
profile saves remain disabled until DPI, RGB, and profile-state support are
implemented as well.

## Backup and profile storage lifecycle

The default configuration directory is:

```text
~/Library/Application Support/LOPE
```

The configuration directory contains separate `Backups`, `Custom Profiles`, and
`Custom Themes` subdirectories. The user can choose another configuration directory from
Settings; existing files are not moved. The Backups tab can open the active
backup folder in Finder, and Settings can open the active custom profiles folder.

The custom profiles folder is seeded on first creation with `_example-mouse.json`
(a valid, fully-formatted descriptor excluded from loading by its leading
underscore) and a `README.md` explaining the override rule, so a contributor
never has to leave the app to see the expected format.

On the first successful profile read for a mouse, LOPE schedules an exact
binary dump for every readable onboard profile if no matching binary backup is
already present. Each normal save also creates exact pre-write sector backups.
Binary packages preserve bytes the editor does not understand and are the
preferred emergency restore format.

Editable JSON is an explicit import/export format. It includes device metadata,
profile state, friendly physical-control names, the readable output, the
layer (`normal` or `gShift`), and the raw four-byte record. Loading JSON changes
only the editor draft; it never writes to the mouse by itself. Restore and save
operations require the selected device to match the backup metadata.

Receiver-backed binary packages may contain the receiver's product ID rather
than the paired mouse's model ID. When that ID is shared by multiple models,
LOPE uses the model name in the backup filename (and in JSON metadata when
present) before falling back to product-ID matching, so G603 and G604 backups
remain separated.

## Troubleshooting

### No mouse or no profile

- Confirm that the mouse or receiver is connected and powered on.
- Keep wireless mice active and click **Refresh**. For G603/G604, follow the
  wake text and allow the one-minute known-device poll to finish.
- For a wired device, select the real mouse entry and use its Input Monitoring
  action. Enable LOPE in **System Settings → Privacy & Security → Input
  Monitoring**, return to LOPE, and click **Refresh**.
- Quit G HUB and other remappers while reading or saving.
- A connected MX mouse without a descriptor is intentionally not shown in the
  generic button editor, and **Create profile** intentionally refuses to
  generate one for it. A cataloged read-only model is likewise intentional.

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

The GUI-facing structured process contract is documented in
[ENGINE-BOUNDARY.md](ENGINE-BOUNDARY.md). Human CLI output remains the default
for diagnostics.

## Development checks

Run the repository checks from its root:

```sh
make
make test
make lint             # swift-format + clang-format, check only
make format           # swift-format + clang-format, writes changes
make coverage         # llvm-cov report for the C core and Swift tests
make coverage-check   # fails, listing every file below threshold
```

`make test` runs the C engine self-test (`./lope self-test`) and the Swift
XCTest suite (`swift test`, defined by `Package.swift` and
`Sources/Swift/Tests/*.swift`). The Swift tests validate profile metadata, device
classification, appearance choices, sleep guidance, DPI/polling-rate
parsing, backup-storage paths, RGB handling, and the write-validation guards
in `AppModel`.

`make install-hooks` installs a pre-commit hook (from
`scripts/git-hooks/pre-commit`) that runs formatting plus the changed-file
`make test-modified` test and coverage gate before every commit; run it once
per clone. Automated pull requests require four separate checks: `PR Title`,
`Formatting`, `Tests`, and `Coverage`. The coverage gate is deliberately
strict (90% per file by default) — see
[development-standards.md](development-standards.md#coverage).

For descriptor additions, follow [Profiles/README.md](../Profiles/README.md)
and add a focused test before enabling a new write path.
