# Engine API evaluation

Decision date: 2026-09-17

## Decision

Keep the GUI's `lope` engine as a separate process. Do not start an
in-process C-library rewrite based on the current evidence.

The structured C operations already isolate presentation from device access,
and the process boundary gives the GUI a versioned, platform-independent data
contract. The measured helper-launch cost is small compared with HID discovery
and device I/O. The GUI now consumes the existing `--format json` contract for
its engine read/write paths. This changes the representation used across the
existing process boundary, not the boundary itself.

## Evidence

### Startup and request cost

The measurement used the existing signed arm64 helper at
`outputs/LOPE.app/Contents/Resources/lope` on 2026-09-17. Each case ran five
times from the repository root. Timing used zsh's `EPOCHREALTIME`; output was
discarded. The host denied Input Monitoring to the helper, so the device list
reported one Logitech vendor interface but no reachable mouse.

| Invocation | Median | Range | What it measures |
| --- | ---: | ---: | --- |
| `/usr/bin/true` | 1.7 ms | 1.5–1.9 ms | Process-launch baseline |
| `lope --format json unsupported-command` | 3.5 ms | 3.1–4.0 ms | Helper launch, dynamic loading, option parsing, and dispatch without HID access |
| `lope list` | 320.4 ms | 317.8–323.8 ms | Human list path plus the host's HID-access failure/retry path |
| `lope --format json list` | 322.6 ms | 317.2–323.1 ms | Structured list path plus the same HID-access failure/retry path |

The invalid structured invocation is a useful lower bound for helper startup,
not a fork-only measurement. The list timings are not an authorized-device
benchmark: `channel_open` retries a denied HID open with two 150 ms handoff
delays. Human and structured list timings are effectively the same, so this
run shows no material JSON/process penalty; it does not establish the latency
of a successful mouse read. An authorized-device benchmark should be repeated
before changing the refresh design.

The GUI also batches the normal profile refresh into one `profiles` request
with DPI and report-rate data. This avoids repeating feature discovery for
headers, profile data, and DPI in separate processes. Live DPI polling is
explicitly limited to one short-lived `current-dpi` request every 500 ms, and
reconnect polling runs every two seconds. The measured helper startup lower
bound is therefore not a reason by itself to keep a HID session open.

### Error handling

The C boundary has a typed `EngineBoundaryError`, named error codes, a
`contract_version`, and distinct exit statuses for success, engine/device
failure, and invalid requests. A structured invocation emits one JSON envelope;
human diagnostics remain on stderr. These properties are documented in
[ENGINE-BOUNDARY.md](ENGINE-BOUNDARY.md) and implemented in
`Sources/C/Core/engine_boundary.c`.

The GUI invokes the structured renderer and validates its versioned response
through `EngineJSON`, while retaining merged diagnostics for status/error
reporting. Human-readable parsing remains limited to direct diagnostic helpers;
the GUI's discovery, refresh, polling, and write paths have no compatibility
fallback to human output. This improves error stability without introducing
C/Swift ABI ownership or a new library API. An in-process design would still
need a Swift error adapter, versioning rules, and a policy for mapping
transport failures, partial writes, and invalid device data.

### Cancellation and failure isolation

The GUI runs blocking `Process` reads on detached utility tasks and checks task
cancellation before publishing a result. Cancelling a task currently does not
terminate the child process or interrupt a C HID request: `EngineRunner` reads
to EOF and waits for process exit, while an invocation lock prevents another
helper from using HID concurrently. This can leave a stale read in flight for
its device timeout, but it also prevents a stale helper from racing a new
selection or an explicit Input Monitoring request.

The separate process supplies a natural crash and kill boundary if explicit
termination is needed later. An in-process library would remove that boundary
and would require a cancellation token/context checked through discovery,
run-loop waits, and every read/write retry. Cancellation during a profile write
would also need transaction semantics because a device can be partially
updated; the existing backup and read-back recovery path must remain intact.
There is no demonstrated user benefit from taking on that complexity now.

### HID-resource ownership

Each structured C operation creates and owns a `HidContext`. Cleanup closes
open channels, clears queued reports, frees callback buffers, releases the
device set and manager, and zeroes the context. The operation then returns
plain `EngineBoundary*` values rather than exposing Core Foundation, IOKit, or
callback ownership to the caller.

This ownership model is a good fit for a short-lived helper and is already
covered by the C test seams. A long-lived in-process session could avoid some
manager/channel reopen work, but would have to define which thread owns the
IOKit run loop, how callbacks and queued reports are synchronized with
Swift concurrency, how TCC access is attributed to the GUI, and how teardown
works when a task or the app exits. The current code has no opaque session API
or lifetime contract to reuse for that purpose.

### Testability

The C self-test runs without hardware through injected HID-context,
discovery, and channel-request implementations; `test_engine_boundary.c`
exercises the typed projections and structured rendering. Swift tests replace
the process boundary with `AppModel.engineRunnerOverride`, and fake executable
scripts cover retry, progress, reconnect, and failure behavior. This gives
both sides deterministic seams while preserving a small amount of real
process orchestration coverage.

An in-process API could make typed calls easier to invoke from Swift tests, but
it would not remove the need to mock HID I/O. It would add C/Swift interop,
threading, and resource-lifetime cases to the test surface before solving a
current test gap.

### Packaging and multi-platform work

The Makefile currently builds the GUI and C engine independently, then places
the GUI executable in `Contents/MacOS/LOPE` and the engine executable in
`Contents/Resources/lope`. The engine links only IOKit, CoreFoundation, and
the system library; the GUI does not need a C module map, bridging header, or
engine symbols. Each executable is signed as part of the app bundle.

Keeping the boundary separate means a future platform can provide a native
engine executable that implements the same versioned contract while the GUI
keeps its typed response model. It does not make the HID port automatic: the
current HID layer and Makefile are macOS-specific and would still need a
platform implementation. An in-process library would couple the GUI build to
that platform-specific C ABI and add interop/module-map, symbol-visibility,
architecture, and signing decisions to every platform port.

The separate binary is a packaging cost, but the current 434 KiB engine is
small and the app already has a two-executable packaging path. No measured
startup or distribution problem justifies replacing it.

## Revisit criteria

Reconsider an in-process or persistent-session API only after evidence shows
one of these concrete benefits:

1. An authorized-device benchmark shows helper launch/context setup is a
   material share of user-visible refresh latency after request batching.
2. The GUI needs a long-lived event stream or cancellation guarantee that
   explicit child-process termination and the current serialized runner cannot
   provide safely.
3. A target platform can link the C engine but cannot package a cooperating
   executable, with that constraint demonstrated in its build environment.

The structured JSON contract is now adopted in the GUI. Keep the C typed
operations independently testable and preserve the process boundary.
