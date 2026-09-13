# Development environment setup

What to install before building, testing, formatting, linting, or measuring
coverage in this repo. All of it is local tooling; nothing here needs
network access once installed.

## Required

- **Xcode**, installed from the App Store (not just the Command Line
  Tools). This repo relies on `xcrun swift-format`, which ships inside
  `Xcode.app`'s toolchain
  (`Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-format`);
  verify it resolves with `xcrun --find swift-format`. Xcode also provides
  `clang`, `swiftc`, `swift`, `codesign`, `llvm-cov`, and `llvm-profdata`
  (used by `make coverage`/`make coverage-check`).
- **Homebrew** (<https://brew.sh>) for the remaining tools:

  ```sh
  brew install clang-format ripgrep fd jq gh
  ```

  - `clang-format` formats/lints the C core (`.clang-format` at repo root).
  - `rg` (ripgrep) and `fd` are the preferred search/find tools (see
    `docs/development-standards.md`).
  - `jq` backs `scripts/check-coverage.sh` and is generally useful for the
    profile JSON under `Profiles/`.
  - `gh` is the preferred way to work with GitHub PRs/issues/CI.

- **A code-signing identity** for `./rebuild-signed.sh`. The Makefile
  auto-detects an "Apple Development" or "Developer ID Application"
  identity from the keychain; if none exists yet, open Xcode once (Settings
  → Accounts → add your Apple ID, or create a self-signed certificate in
  Keychain Access) so `security find-identity -v -p codesigning` returns
  one. Override the detected identity per-build if needed:

  ```sh
  make SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)"
  ```

## One-time repo setup

```sh
make install-hooks
```

Installs `scripts/git-hooks/pre-commit` into `.git/hooks/pre-commit`. It
runs `make format-check`, `make test`, and `make coverage-check` before
every commit. This does not happen automatically per clone/worktree — run
it again after a fresh clone.

The coverage gate defaults to 90% per file (see `docs/development-standards.md`).

## Verifying the toolchain

```sh
make lint      # swift-format + clang-format, check only
make test      # C self-test + swift test
make coverage  # llvm-cov reports for both
./rebuild-signed.sh
```

If any of these fail with a "command not found", re-check the install
steps above rather than working around it — the Makefile does not fall
back to alternate tools.

## GitHub Actions signing and releases

The repository's release workflow is for direct distribution outside the Mac
App Store. It requires a paid Apple Developer Program team and these GitHub
Actions secrets:

- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`: a base64-encoded `.p12`
  export containing the `Developer ID Application` certificate and private
  key.
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`: the password used for that
  `.p12` export.
- `APPLE_ID`: the Apple ID email used for notarization.
- `APPLE_APP_SPECIFIC_PASSWORD`: an app-specific password generated for that
  Apple ID.
- `APPLE_TEAM_ID`: the Apple Developer Team ID.

Create the Developer ID Application certificate in the Apple Developer
account, export it from Keychain Access as a password-protected `.p12`, and
base64-encode that file before saving it as the first secret. Keep the
certificate and notarization credentials only in GitHub Actions secrets; do
not commit them to the repository. The workflow creates an ephemeral
keychain on the macOS runner, signs with hardened runtime and a secure
timestamp, and deletes the keychain after the job.

`Apple Development` is suitable for local development but is not the
distribution identity used here. For a downloadable app, Apple expects a
`Developer ID Application` signature and notarization. The release workflow
does not need a provisioning profile because this app is built directly with
the Makefile and is not sandboxed.

After configuring the secrets, publish a release from the desired `main`
commit with:

```sh
git tag v0.3.0
git push origin v0.3.0
```

The tag version becomes `CFBundleShortVersionString`; the GitHub Actions run
number becomes `CFBundleVersion`.
