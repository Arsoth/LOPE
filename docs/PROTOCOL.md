# Protocol notes

This utility intentionally implements only the small subset needed for safe inspection and a one-record onboard edit.

## HID++ transport

The Logitech vendor HID interface uses report ID `0x10` for short frames and `0x11` for long frames. On macOS, numbered output reports include that ID as the first byte of the buffer and also pass it as the IOKit report-ID argument. The remaining wire payload is:

```text
device number, feature index, function/software-id, parameters...
```

The tool uses software ID `0x0B`, probes receiver slots `1..6` and direct devices as `0xFF`, then discovers HID++ 2.0 features through `ROOT (0x0000)` and `FEATURE_SET (0x0001)`.

macOS can expose a Logitech mouse's HID++ reports in an interface whose primary
collection is keyboard-like. Interface selection therefore scans the raw HID
report descriptor for vendor page `0xFF00` together with report IDs `0x10` and
`0x11`; it does not assume that `PrimaryUsagePage` identifies HID++.

## Onboard profiles

Feature `0x8100` is queried with:

* `0x00`: get profile memory, format, count, and sector sizing;
* `0x50`: read 16 bytes at a sector and offset;
* `0x60`: start a sector write;
* `0x70`: write up to 16 bytes;
* `0x80`: commit the pending write.

The descriptor bytes used by the tool are:

```text
0      memory kind
1      profile format
2      macro format
3      profile count
4      out-of-band flag
5      normal button count
6      sector count
7..8   sector size, big endian
9      shift/button layout flags
```

Profile headers are four-byte records in the control sector: big-endian sector number, enabled byte, and one reserved byte. The descriptor does not generally expose a trustworthy active-profile field, so the tool displays all headers and requires an explicit profile number before writing when more than one slot exists. Profile-state writes change only the enabled byte for the selected header, after backing up and validating the complete control sector; the last enabled profile cannot be disabled.

## Sector CRC

The final two bytes of a sector store CRC-16/CCITT-FALSE in big-endian order. The polynomial is `0x1021`, initial value `0xFFFF`, no reflection, no final XOR. The CRC covers every byte before the stored checksum.

## Button records

The standard `SEND` record is four bytes:

```text
80, mapping type, value high, value low
```

Mapping type `0x01` is a mouse-button bitmask; type `0x02` is a keyboard usage plus modifier byte; type `0x03` is a consumer usage. For example, the target binding is:

```text
80 02 04 2B   # left Alt + Tab
80 02 04 68   # left Alt + F13
```

The four bytes are behavior, mapping type, modifier bitmap, and keyboard
usage. A `SEND` keyboard record is a one-click press/release chord; it does
not preserve a modifier state across separate button clicks.

Known profile layouts place the normal button array at offset 32 for older formats and offset 48 for newer formats. This project first checks the reported format’s candidate, validates every record, and only permits writes when the result is unambiguous.

## Adjustable DPI

The GUI’s DPI editor combines two checks. First, feature `0x2201` reports the
device’s supported sensor values and current value. The utility refuses a
requested stage that the mouse does not report, and currently supports only a
single-sensor layout.

Second, the selected onboard sector must pass the CRC check and match the
validated format-3/4/5 DPI layout: one to five little-endian 16-bit stages
at sector offsets `3..12`. Active stages are strictly increasing; the inactive
sentinel is firmware-specific. G102/G203 and G603 firmware use `0x0000`, while
some newer layouts use `0xFFFF`. The one-based default and DPI-shift stage
indexes are stored at offsets `1` and `2`. These are detected from the returned
descriptor and bytes, with a known-device fallback for a fully populated table;
they are not assumed for an unknown format. A DPI write compacts active stages
from slot zero, clears trailing unused slots with the selected sentinel,
recalculates the sector CRC, and verifies the complete sector after the write.

## Sources

These are implementation references, not Logitech guarantees for every firmware revision:

* [Solaar HID++ 2.0 feature implementation](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/hidpp20.py) — GPL-2.0-or-later
* [libratbag HID++ 2.0 headers](https://github.com/libratbag/libratbag/blob/master/src/hidpp20.h) — MIT
* [lowtech HID++ transport](https://github.com/orthory/lowtech/blob/main/src/hidpp.rs) — GPL-2.0-or-later
* [lowtech onboard implementation](https://github.com/orthory/lowtech/blob/main/src/onboard.rs) — GPL-2.0-or-later
* [omm.py reference implementation](https://github.com/lexr1/omm.py) — GPL-3.0 (GitHub-detected)

No source files from these projects are included in this repository. See
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) for the compatibility and
attribution review.
