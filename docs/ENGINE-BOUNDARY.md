# Engine boundary

The C engine exposes a versioned process boundary for GUI-facing reads and
writes. Invoke a supported command with `--format json` (or the `--json`
alias):

```sh
./bin/lope --format json list
./bin/lope --format json --device-key 1234-5678-FF --summary-only \
  --with-dpi --with-report-rate profiles
./bin/lope --format json --device-key 1234-5678-FF current-dpi
./bin/lope --format json --device-key 1234-5678-FF --profile 1 apply --yes \
  --button-change normal:4:80010004
```

The contract is intentionally separate from the human CLI renderer. The
engine operation first produces typed C values (`EngineBoundary*` in
`Sources/C/Core/engine_boundary.h`); the boundary layer serializes those
values as JSON. A structured invocation writes exactly one JSON document to
stdout. Transport and validation diagnostics remain readable on stderr, and
the existing commands without `--format json` retain their human-readable
stdout.

## Envelope

Every response has this top-level shape:

```json
{
  "contract_version": 1,
  "ok": true,
  "kind": "device_list"
}
```

`contract_version` is the process-boundary version and is independent of
HID++ protocol versions and `.logiob` backup versions. A GUI must reject an
unknown version rather than guessing field meanings. A failed operation uses
the same envelope with `ok: false` and an error object:

```json
{
  "contract_version": 1,
  "ok": false,
  "error": {
    "code": "profile_unavailable",
    "message": "onboard profile headers were not readable or valid"
  }
}
```

The process exit status is zero for a successful operation (including an
`apply` preview), one for an engine/device/I/O failure, and two for an invalid
request or unsupported structured command. The diagnostic text on stderr is
the more detailed explanation when an operation fails.

## Supported response kinds

`device_list` contains `devices`, `device_count`, and
`vendor_interface_count`. Each device contains the numeric `vendor_id`,
`product_id`, `device_number`, `request_device_number`, and `protocol`, plus
the display `name`, `connection`, and stable `device_key`. The `index` is the
same logical index used by the diagnostic `list` command.

`profiles` contains the selected device, device-reported
`profile_capacity`, validated `headers`, and `selected_profile`. The selected
profile includes its sector and enable state, descriptor counts and sizes,
CRC state, validated layout flags, raw four-byte button records with their
`normal`/`gShift` layer, onboard DPI stages/default/shift indexes, and RGB
zone mode/color values. When requested, `dpi` contains the sensor count,
supported values, current sensor DPI, and an explicit capability error string;
`report_rate` has the equivalent report-rate capability/current-value fields.

`dpi` contains the selected device and sensor DPI data. Unless `--sensor-only`
is used, it also contains the selected onboard profile when that profile is
available. `current_dpi` is the same typed sensor result without the optional
onboard-profile section.

`write` is returned by the combined `apply` operation. It contains the
operation ID, selected device, profile number, whether changes were effective,
whether the invocation was a preview, planned sectors and their lengths,
backup path/state, completion state, and the number of sectors verified by
read-back. A preview never creates a backup and reports `dry_run: true`.

The structured path currently covers `list`, `profiles`, `dpi`,
`current-dpi`, and `apply`, which are the data paths used by the GUI. Other
diagnostic commands remain available in human mode and return an explicit
`unsupported` structured error instead of leaking human output into a JSON
stream.
