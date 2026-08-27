# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Breaking rewrite of the reusable workflow platform. No compatibility shims. Old filenames are deleted. Ops cuts annotated `v2.0.0` and retags `v2`. Pin CI and ops at `@v2`. Pin publish, release, and deploy at `@v2.0.0`.

### Removed

- `gen-openapi-client.yml`. OpenAPI client generation is gone. No `PAT_TOKEN`, no GitHub App, no `gen-` prefix, no replacement workflow.
- `publish-npm-bun.yml`. Call `publish-npm.yml` with `package-manager: bun`.
- `container-build.yml`. Call `publish-container.yml`.
- `repo-stale.yml` and `stale.yml`. Call `ops-stale.yml`. This repository's cron is `self-stale.yml`.
- `repo-sync-folder.yml`. Call `ops-sync.yml`.
- `ci-cpp.yml` and `ci-dart.yml`. No replacement.
- Restored-name shims were never added. Already-deleted `python.yml`, `python-publish.yml`, and `docker.yml` stay deleted (`ci-python.yml`, `publish-pypi.yml`, `publish-container.yml`).

### Changed

- Public `name:` is `<Layer> / <Subject>` (`Release` is the only layer-only name).
- CI job id is `ci` (was `build` or `check`). Publish job id is `publish`. Callee `jobs.<id>.name` is unset except `release-rust.yml` `Build ${{ matrix.target }}` and the `self-ci.yml` aggregator `Self / CI`.
- Version inputs are `{tool}-version`. `toolchain` → `rust-version`.
- Secrets are `SCREAMING_SNAKE`. `PYPI_API_TOKEN` → `PYPI_TOKEN`. Sync `token` → `SYNC_TOKEN`. Container `registry-username` / `registry-password` → `REGISTRY_USERNAME` / `REGISTRY_PASSWORD`.
- `foundry-profile` default is `ci` (was `default`).
- `submodules` default is `false` on every `ci-*`. Foundry callers with `lib/` must pass `submodules: true`.
- Node `package-manager` default is `npm` and is not auto-detected.
- `bun-version` default is `1.4`. `latest` is not a default.
- `golangci-lint-version` default is `v2`.
- Container default platforms are `linux/amd64,linux/arm64`. `attest` default is `true`. `push: true` (default) runs job `publish`, not `build`.
- npm/PyPI: non-empty token never passes `--provenance` / attestations and does not require caller `id-token`. Empty token is OIDC and does.
- `ops-stale.yml` is `workflow_call` only. Callers own `schedule`.
- Third-party `uses:` are SHA-pinned (`owner/repo@<40-char-sha> # tag`). Same-repository references use `$/` with no `@ref`.
- Concurrency groups are `qntx-workflows-<stem>-${{ github.repository }}-${{ github.ref }}`, not `${{ github.workflow }}`. Pages and MkDocs groups are distinct.
- Nested `uses:` jobs no longer set `timeout-minutes`. `self-release.yml` matches `v*.*.*` only.

### Added

- `ci-rust.yml` input `deny` (default `false`) runs `cargo-deny check` when the crate has `deny.toml`.
- `publish-container.yml` (replaces `container-build.yml` / `docker.yml`).
- `ops-stale.yml`, `ops-sync.yml`.
- `self-ci.yml`, `self-stale.yml`, `self-retag.yml`.
- Private composites under `actions/` (`hardened-checkout`, `apt-install`, `setup-rust`, `parse-env-block`, `protect-sync-path`, `run-trusted-command`, `publish-crates`).
- `docs/CATALOGUE.md`, `docs/CONSUMERS.md`, `docs/MIGRATION.md`, `examples/`.
- `cliff.toml` for git-cliff (conventional commits).
