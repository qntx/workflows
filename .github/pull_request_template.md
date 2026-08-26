## Description

<!-- What changed and why. -->

## Checklist

- [ ] Third-party `uses:` are SHA-pinned (`owner/repo@<40-char-sha> # vX.Y.Z`). Same-repository references use `$/` with no `@ref`.
- [ ] `run:` bodies do not interpolate `${{ }}` (pass untrusted values through `env:`).
- [ ] `CHANGELOG.md` updated for user-visible changes.
- [ ] Public `workflow_call` inputs, secrets, and outputs stay compatible, or the break is documented for consumers.
