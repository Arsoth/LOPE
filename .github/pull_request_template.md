## Summary

<!-- What changed, and why? -->

For mouse descriptor work, use the **Add a mouse profile** template so the
hardware evidence and write-safety details are captured.

## Conventional Commit title

Use this format for the pull request title:

```text
<type>[optional scope][!]: <description>
```

Allowed types are `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, and `test`.

Examples:

- `feat(profiles): add onboard profile export`
- `fix: preserve DPI values when loading a profile`
- `refactor!: remove the legacy profile format`

## Checklist

- [ ] The PR title follows Conventional Commits.
- [ ] I ran `make lint`.
- [ ] I ran `make test-modified` or explained why it is not applicable.
- [ ] I have added or updated tests for behavior changes.
- [ ] I have updated relevant documentation.
- [ ] I have not included build output, credentials, device backups, or other
      local-only files.
