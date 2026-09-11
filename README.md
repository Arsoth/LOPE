# Logitech Onboard Profile Editor (LOPE)

LOPE is a small Mac app for changing what Logitech mouse buttons do when the mouse is using its own onboard memory.

It is intended for Logitech gaming mice and other Logitech mice that expose editable onboard profiles through HID++. It has been developed around the G502 X and is designed to discover each mouse's capabilities instead of assuming every Logitech model has the same layout.

It does not use G HUB or Logitech Onboard Memory Manager. It runs natively on Apple Silicon Macs.

## Getting started

You need macOS 13 or newer, Xcode Command Line Tools, and a Logitech mouse connected by USB or its receiver.

Build and open the app:

```sh
make
open outputs/LOPE.app
```

The build automatically uses an installed Apple Development or Developer ID signing identity when one is available. This keeps Input Monitoring permission across rebuilds. If the build reports an ad-hoc signature, install a development certificate through Xcode or pass the identity explicitly:

```sh
security find-identity -v -p codesigning
make SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)"
```

Ad-hoc builds (`Signature=adhoc`) may need to be added to Input Monitoring again after the executable changes because macOS treats each version as a different code identity.

The first time macOS blocks the mouse, open **System Settings**, go to **Privacy & Security**, open **Input Monitoring**, and enable **LOPE**. The app's no-device screen has a button that opens that settings page for you.

Quit G HUB while making changes. Two programs trying to edit the mouse at the same time can undo each other's work.

## The app

### Buttons

The Buttons tab puts profiles, button assignments, and DPI settings together.

1. Choose the mouse from the Device menu if more than one Logitech device is connected.
2. Choose the onboard profile you want to edit.
3. Pick an output for each button.
4. Change DPI stages if you want to.
5. Press **Save to mouse**.

Changes stay in the editor until you press Save to mouse. That button creates a backup automatically before writing anything.

The app uses the physical control name, not the current assignment. Physical mappings live in one JSON descriptor per G-series mouse family under [Profiles/](Profiles/). This keeps unusual layouts—such as the two G502 generations, G600's G-Shift layer, G604's two-row thumb grid, and ambidextrous G903/PRO mice—separate and makes future devices additive.

Unknown mice use neutral names such as Primary click, Back, and Button 6 when their physical layout is not in the list of profiles. The output beside the name always shows what that profile will do.

The DPI editor supports one to five stages. If you prefer two stages, choose **2 of 5** and fill in those two values. The default stage and DPI Shift stage are selected separately.

### Custom keyboard output

Choose **Custom** when you want a keyboard shortcut.

- Check Ctrl, Shift, Alt, or Command.
- Type a key name such as `A`, `Tab`, or `F13`.
- Or choose an F key or a special key such as Enter, Backspace, Delete, or an arrow.

For example, check Alt and choose Tab to make one mouse click send Alt+Tab. The mouse sends that shortcut as a normal press and release. It cannot hold Alt after one click and tap Tab on later clicks. That needs a stateful macro or a Mac-side remapper.

### Profiles

The profile list shows which onboard profiles are enabled. Disabling one removes it from the mouse's profile cycle but leaves its contents in the mouse. The app will not let you disable the last enabled profile.

### Backups

The Backups tab shows backups for the selected mouse by default. Turn on
**Show backups for all mice** when recovering or importing a file from another
mouse. Files that cannot be matched safely are labeled **Unknown device** and
are never presented as belonging to the selected mouse.

There are two kinds of files:

- **Exact binary** backups are automatic safety copies. Restore one when you want to put the mouse back exactly as it was.
- **Editable JSON** files are readable profile descriptions. Load one into the editor, review the changes, and press Save to mouse when you are ready.

Each **Save to mouse** operation creates a binary backup before any write. New
binary names include a sanitized mouse/family name, while the binary header
retains product metadata for matching older files. Compatible same-model mice
share the same backup family; LOPE does not encode a physical mouse identity
in the filename. A binary backup preserves bytes the app does not understand,
so it remains the most reliable emergency restore. JSON is the convenient
format for reading and editing button assignments and DPI values.

You can also use **Export JSON** to save the current editor contents, or
**Import JSON** to load a file someone edited. Export defaults to a sanitized
`mouse-YYYYMMDD-HHmmss.json` name and includes the mouse name and product
metadata. Importing JSON does not write to the mouse by itself.

The JSON includes the raw four-byte record as well as its friendly name. Standard outputs can be changed by editing `output`. Custom or unfamiliar outputs can be changed by editing `raw`, for example:

```json
{
	"number": 4,
	"physicalControl": "Back / thumb",
	"output": "Left Alt + Tab",
	"raw": "8002042B"
}
```

The app validates the file before accepting it. Invalid button records, impossible DPI values, an unknown JSON version, or a file that disables every profile are rejected. You still review the result in the editor before saving.

New installations use this default backup folder:

```text
~/Library/Application Support/LOPE/Backups
```

Change it from Settings. Existing files are not moved when you choose a different folder.
Binary backups use the `.logiob` extension.

### Settings

Settings lets you choose the backup folder and turn on **Show raw HID++ fields**. The raw fields and profile sector numbers are hidden during normal use because most people do not need them. Turn them on when investigating a device or working with a custom record.

## Which mice work

The app looks for Logitech HID++ devices and then asks each device what it supports. A mouse can be detected without having editable onboard profiles. In that case the app shows the mouse but explains that there is no compatible onboard profile to edit.

The profile editor is intended to work with any Logitech model that exposes the standard onboard profile feature and a layout the app can validate. The catalog contains mappings for current and legacy G-series families, but profile writes remain enabled only for layouts whose HID++ storage has been validated. G600, G700/G700s, and newer HITS/LIGHTFORCE families are named and discoverable but remain read-only until their layer or firmware-specific save format is implemented. Unknown non-MX mice fall back to runtime button numbers; MX-series mice stay out of the button editor until a dedicated profile JSON describes their layout.

## If something goes wrong

If the app says no mouse is detected:

1. Make sure the mouse or receiver is connected.
2. Press **Open Input Monitoring Settings** on the empty screen.
3. Enable the app, return to it, and press **Refresh**.
4. Quit G HUB before trying again.

If a save fails, the status message names the problem and the app does not pretend the write succeeded. If a write reaches the mouse but readback verification fails, restore the newest exact binary backup from the Backups tab.

## Command line tool

The repository also builds a diagnostic command line tool:

```sh
make build
./lope list
./lope info
./lope profiles
./lope self-test
```

Write commands are preview-only unless `--yes` is supplied. The tool checks the device's reported profile format, validates the CRC, backs up the complete sector, writes in HID++ chunks, and reads the sector back before reporting success.

## Development notes

The project source is in `Sources/`. `Sources/AppMain.swift` defines the LOPE SwiftUI app, while `Sources/logitech_onboard.m` contains the macOS HID++ engine. Protocol notes and research links are in [docs/PROTOCOL.md](docs/PROTOCOL.md). License and third-party attribution details are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Run the local checks with:

```sh
make clean
make
./bin/lope self-test
```
