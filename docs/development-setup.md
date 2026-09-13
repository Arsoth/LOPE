# Local development setup

This guide covers the tools needed to build and test LOPE locally. For the
complete contribution workflow, including branches and pull requests, see
[`contributing.md`](../contributing.md).

## Required tools

- **Xcode**, installed from the App Store (not just the Command Line
  Tools). This repo relies on `xcrun swift-format`, which ships inside
  `Xcode.app`'s toolchain
  (`Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-format`);
  verify it resolves with `xcrun --find swift-format`. Xcode also provides
  `clang`, `swiftc`, `swift`, `codesign`, `llvm-cov`, and `llvm-profdata`
  (used by `make coverage`/`make coverage-check`).
- **Homebrew** (<https://brew.sh>) for the remaining tools:

  ```sh
  brew install clang-format ripgrep fd jq
  ```

  - `clang-format` formats/lints the C core (`.clang-format` at repo root).
  - `rg` (ripgrep) and `fd` are the preferred search/find tools (see
    `docs/development-standards.md`).
  - `jq` is useful for inspecting the profile JSON under `Profiles/`.

The Makefile uses an available local signing identity when one exists and
falls back to an ad hoc signature. You do not need a Developer ID certificate
to build or test a change locally.

## One-time repo setup

```sh
make install-hooks
```

Installs `scripts/git-hooks/pre-commit` into `.git/hooks/pre-commit`. It runs
formatting checks and the changed-files test/coverage gate before every
commit. This does not happen automatically per clone/worktree, so run it
again after a fresh clone.

The coverage gate defaults to 90% per file (see `docs/development-standards.md`).

## Verify the toolchain

```sh
make lint      # swift-format + clang-format, check only
make test      # C self-test + swift test
make test-modified  # related tests and coverage for current changes
make coverage  # llvm-cov reports for both
make app
```

If a command is missing, re-check the install steps above. Hardware-facing
work also requires a compatible mouse or receiver; ordinary unit tests do not.
