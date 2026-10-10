# fixtures/release

Standalone workspace consumed by the `e2e-release-rust` Self-CI job: it drives
`.github/workflows/release-rust.yml` end to end with `working-directory:
fixtures/release`, `bin: fixture-bin`, `package: fixture-bin`. The `e2e-release-rust-verify`
job then downloads the `dist-*` artifacts and verifies every `*.sha256` the way a
release consumer would.
