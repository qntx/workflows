## Description

<!-- What changed and why. -->

## Checklist

- [ ] Third-party `uses:` are SHA-pinned (`owner/repo@<40-char-sha> # vX.Y.Z`). Same-repository references use `$/` with no `@ref`.
- [ ] `run:` bodies do not interpolate `${{ }}` (pass untrusted values through `env:`).
- [ ] `CHANGELOG.md` updated for user-visible changes.
- [ ] Breaking changes are documented in `docs/MIGRATION.md` and `CHANGELOG.md`. No shims / no dual contracts.
