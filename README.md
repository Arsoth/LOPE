# LOPE — an open-source Logitech G-series onboard profile editor for macOS

LOPE is an independent open-source project and is not affiliated with, sponsored by, or endorsed by Logitech.

LOPE is a native macOS app for editing the onboard button, keyboard, DPI, and
profile settings exposed by compatible Logitech mice. It talks directly to the
mouse; Logitech G HUB and Onboard Memory Manager are not required.

## Use LOPE

Requirements: macOS 13 or newer, a Logitech mouse or receiver, and (for a
source build) Xcode Command Line Tools.

1. Connect the mouse or receiver and open LOPE.
2. Choose a device if more than one is listed. Wireless and receiver-connected
   mice work without an extra permission. If a wired mouse needs access, choose
   **Allow wired mice — Input Monitoring** and enable LOPE in System Settings.
3. Keep a wireless mouse awake while it is being read, then click **Refresh**.
   The G603 and G604 show device-specific sleep guidance and retry a missing
   known device for up to 60 seconds.
4. Choose an onboard profile, edit button outputs or DPI stages, and press
   **Save to mouse**.

LOPE creates an initial exact binary backup for each readable onboard profile
when it first connects to a mouse. Every later save also backs up the sectors it
will change. Use **Backups → Open in Finder** to inspect the backup folder.

### Keyboard outputs

The button output menu starts with **Disabled**, **Keystroke**, and then the
standard mouse and keyboard outputs. Keystroke opens the record-input workflow:
click the recorded input box and press one key, with any held Ctrl, Shift, Alt,
and Command modifiers captured automatically. The box displays the complete
chord, highlights while recording, and provides an X to cancel without
changing the existing output. The optional extended-key override is available
only when enabled in Settings.
Enable **Show non-standard keyboard keys** in Settings to add hidden keys such
as Insert, F13–F24, Sleep, and so many more. The editor displays the
current keyboard-output usage as `X/Y`; the current HID++ keyboard record stores
one key.

### Backups and settings

The Backups tab can load editable JSON, restore an exact binary backup, export
the current editor state, filter by mouse, refresh the list, and open the active
backup folder in Finder. **Save to mouse** is the only action that writes to the
mouse.

Settings controls the configuration directory, which contains separate
`Backups` and `Custom Profiles` folders, along with advanced raw HID++ fields,
non-standard keyboard keys, and the color mode. Color mode defaults to
**System**; Light is a soft off-white theme and Dark keeps the colorblind-safe
DPI palette. Settings also shows how many mice are built in and can open the
custom profiles folder, which starts with an example file showing the format.

MX mice are detected but do not show the generic button-editor fallback, and
catalog entries whose onboard format is not validated remain read-only. Their
button and gesture behavior is normally managed by Logi Options+ on the host
rather than verified onboard flash, so LOPE will not guess at it even when a
device answers an onboard-profile read.

Unknown non-MX mice can be displayed with neutral runtime button labels
immediately, with no descriptor required. A **Create profile** button lets
LOPE write what it already read — the real button records, under generic
names — into the custom profiles folder, so that mouse is recognized on every
later launch. Rename the generated controls in the custom profiles folder
whenever you like; a built-in or hand-authored profile for the same mouse
always takes priority over a generated one.

Quit G HUB and other mouse remappers while saving so they cannot race LOPE.

### Confirmed functional mice

This is the deliberately narrow list of mice whose complete LOPE feature set
has been tested and confirmed as working. It includes G-Shift wherever the
mouse exposes it, along with the other supported onboard features.

| Mouse        | Status                               |
| ------------ | ------------------------------------ |
| G502 X wired | Confirmed and tested 100% functional |
| G504         | Confirmed and tested 100% functional |
| G603         | Confirmed and tested 100% functional |

Other catalog entries are not part of this confirmation list unless their
complete read/write feature set has been tested.

## Build and test

From the repository root:

```sh
make
open outputs/LOPE.app
```

Run `make test` for the C self-test binary and the Swift XCTest suite (via
`swift test`). Run `make format` to apply `swift-format`/`clang-format`, or
`make lint` to check formatting without changing files. Run `make coverage`
for an `llvm-cov` report, or `make coverage-check` to enforce the per-file
minimums (see [docs/development-standards.md](docs/development-standards.md)
for what's actually enforced and why Swift has no branch-coverage numbers).
`make install-hooks` installs a pre-commit hook that runs the format, test,
and coverage checks (see
[docs/development-standards.md](docs/development-standards.md)). See
[docs/development-setup.md](docs/development-setup.md) for
required tooling, [the development reference](docs/REFERENCE.md) for the
source layout, device behavior, troubleshooting, and command-line details.
Protocol notes are in [docs/PROTOCOL.md](docs/PROTOCOL.md), and descriptor
maintenance is covered by [Profiles/README.md](Profiles/README.md).
