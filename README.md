# Logitech Onboard Profile Editor (LOPE)

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

The button output menu starts with **Disabled**, **Custom**, and then the
standard mouse and keyboard outputs. Custom opens the record-input workflow:
click the recorded input box and press one key, with any held Ctrl, Shift, Alt,
and Command modifiers captured automatically. The box displays the complete
chord, highlights while recording, and provides an X to cancel without
changing the existing output. The optional extended-key override is available
only when enabled in Settings.
Enable **Show non-standard keyboard keys** in Settings to add hidden keys such
as Insert, F13–F24, and Sleep. The editor displays the
current keyboard-output usage as `X/Y`; the current HID++ keyboard record stores
one key.

### Backups and settings

The Backups tab can load editable JSON, restore an exact binary backup, export
the current editor state, filter by mouse, refresh the list, and open the
configured folder in Finder. **Save to mouse** is the only action that writes to
the mouse.

Settings controls the backup folder, advanced raw HID++ fields, non-standard
keyboard keys, and the color mode. Color mode defaults to **System**; Light is a
soft off-white theme and Dark keeps the colorblind-safe DPI palette.

MX mice are detected but do not show the generic button-editor fallback. Catalog
entries whose onboard format is not validated remain read-only. Unknown
non-MX mice can be displayed with neutral runtime button labels.

Quit G HUB and other mouse remappers while saving so they cannot race LOPE.

## Build and test

From the repository root:

```sh
make
open outputs/LOPE.app
```

Run `make test` for the C and Swift self-tests. See [the development
reference](docs/REFERENCE.md) for the source layout, device behavior,
troubleshooting, and command-line details. Protocol notes are in
[docs/PROTOCOL.md](docs/PROTOCOL.md), and descriptor maintenance is covered by
[Profiles/README.md](Profiles/README.md).
