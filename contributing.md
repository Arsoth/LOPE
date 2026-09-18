# Contributing to LOPE

Thanks for helping improve LOPE. Contributions should be small, focused, and
easy to review. The project is a native macOS app, with a C HID++ engine, a
SwiftUI/AppKit interface, and JSON descriptors for individual Logitech G
mice.

## Get the repository

LOPE requires macOS 13 or newer and the full Xcode installation. Install the
remaining local tools with Homebrew:

```sh
brew install clang-format ripgrep fd jq
```

Clone the repository and create a branch for your change:

```sh
git clone https://github.com/Arsoth/LOPE.git
cd LOPE
git switch -c type/short-description
```

If you will contribute without write access, use the URL for your fork in the
`git clone` command.

Install the optional local pre-commit hook, then build the app:

```sh
make install-hooks
make
open outputs/LOPE.app
```

A local Developer ID certificate is not required. The Makefile uses an
available signing identity or falls back to ad hoc signing.

## Make changes

Start with the relevant documentation:

- `Sources/C/` contains the HID++ engine and command-line tool.
- `Sources/Swift/Model/` contains application state, parsing, editing, and
  write logic.
- `Sources/Swift/UI/` contains the user interface.
- `Profiles/` contains one JSON descriptor per exact mouse model.
- [`docs/REFERENCE.md`](docs/REFERENCE.md) describes runtime behavior and
  architecture.
- [`docs/PROTOCOL.md`](docs/PROTOCOL.md) documents the onboard profile format.
- [`docs/development-standards.md`](docs/development-standards.md) describes
  formatting, tests, and coverage expectations.

Keep generated build output, local configuration, credentials, and device
backups out of commits. Do not include secrets or private hardware data in
issues or pull requests.

### Adding a mouse profile

Use this path when adding or improving a descriptor in `Profiles/`:

1. Confirm the exact model. Add one file for one model; do not combine sibling
   models in a family descriptor.
2. Copy the closest physical layout, then set a unique `id`, exact `name`,
   device-name matches, and known product IDs.
3. Verify the runtime profile record numbers for every editable control. Add
   scroll-wheel records and hidden non-programmable records where applicable.
4. Keep `profileIO.supported` false and use `read-only` unless the onboard
   layout and the complete save/read-back path have been tested on real
   hardware. A descriptor alone is not evidence that writing is safe.
5. Add source links and explain uncertainty in `profileIO.notes`.
6. Add or update focused tests when the descriptor changes matching, parsing,
   or write behavior.

The detailed descriptor fields and safety rules are in
[`Profiles/README.md`](Profiles/README.md). A pull request for a profile can
use the dedicated **Add a mouse profile** template.

## Check your work

Run the checks relevant to your change before opening a pull request:

```sh
make lint              # check Swift and C formatting
make test-modified     # focused tests and coverage for changed code
make test              # complete C and Swift test suites
make coverage-check    # complete coverage gate
```

Use `make format` to apply the repository's formatters. For documentation-only
changes, run the formatter if source-format configuration or code blocks were
affected; no test run is needed when there is no related test.

If you changed production code, add tests for reachable behavior and relevant
edge cases. Keep hardware-dependent verification separate from unit tests and
describe the hardware and connection type in the pull request.

## Open a pull request

Commit the focused change and push your branch. If you do not have permission
to push to the repository, push the branch to your fork instead.

```sh
git add path/to/changed/files
git commit -m "type(scope): describe the change"
git push -u origin type/short-description
```

Open a pull request against `main`. Use **Code change** for general source or
documentation work, or **Add a mouse profile** for descriptor/device-profile
work. Include:

- what changed and why;
- the tests and checks you ran, including any failures or limitations;
- links to related issues;
- hardware details and evidence for mouse-profile or device-support changes.

Pull request titles use this format:

```text
<type>[optional scope][!]: <description>
```

Allowed types are `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`,
`refactor`, `revert`, `style`, and `test`. Keep the title concise and use the
imperative mood, for example `feat(profiles): add G703 descriptor`.

Before requesting review, make sure the relevant checks pass, documentation
is current, and the branch contains only the intended changes. Maintainers
may ask for additional hardware verification before enabling a write path.
