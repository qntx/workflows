# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Website URL is `.org` (#29).
- `ops-dependabot` retries `gh pr merge` up to five times when the base branch was modified (#31).
- `ops-dependabot` used GraphQL `enablePullRequestAutoMerge` on `pull_request` (#32), treated `UNSTABLE` as a notice (#33), and introduced a schedule sweep that squash-merges when non-self checks are green (#34). That `pull_request` arm is deleted. The composite always sweeps on `schedule` / `workflow_dispatch`.
- `ops-dependabot` lists Dependabot PR numbers then views one PR at a time so a 50-PR `statusCheckRollup` query cannot exceed GraphQL's 500k node cap (#35).
- `gh pr merge` uses `--repo` and does not pass `--delete-branch` (this action does not checkout) (#36).
- `version-update:lockfile-only` is allowed when `allow-patch` is true (same rank as patch). Bare `lockfile-only` stays unhandled.
- Empty-rollup grace is 900 seconds.
- GraphQL `mergeStateStatus: BEHIND` waits (`wait:behind`); `UNKNOWN` waits (`wait:unknown`). `BLOCKED` stays `skip:BLOCKED`. This workflow never merges required-review PRs. No REST merge, no `--admin`.
- Caller contract: `on: schedule` (`0 4 * * *`) + `workflow_dispatch` only. Drop `pull_request` and any `dependabot[bot]`-only `if:`. Leftover PR runs skip and must not share the sweep concurrency group.
- `ops-dependabot` permission contract: `checks: read` + `actions: read` on caller and callee. Callers schedule daily `0 4 * * *` (04:00 UTC). `statusCheckRollup` GraphQL 403 remains fail and continues later PRs.
- README: `ops-dependabot` cancels overlapping sweeps.
- PR template: document breaks in `docs/MIGRATION.md` and `CHANGELOG.md`; no shims / no dual contracts.
- `self-retag` force-moves annotated `vN` to `origin/main` after squash. Input `target` is deleted.
- `ops-sync` jails canonical `.git` / `.github` path segments after `realpath`, not only `$root/.git` / `$root/.github`.
- `scorecard` checkout is `$/actions/hardened-checkout`.

### Added

- `stale.yml` and `repo-stale.yml` compatibility aliases. `workflow_call` only; they forward to `ops-stale.yml` so unmigrated `@main` callers (qntx-labs) stop failing on a missing file. New callers still use `ops-stale.yml@v2`.

### Removed

- `ops-dependabot` `pull_request` / `pull_request_target` job arm, `dependabot/fetch-metadata`, and composite inputs `pr-labels`, `update-type`, `actor`, `pr-node-id`, `event-name`.

## [2.0.0] - 2026-08-28

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

- `publish-npm` disables `setup-node` cache for bun because empty-string is falsy (the old `== bun && '' || pm` evaluated to `bun`).
- Public `name:` is `<Layer> / <Subject>` (`Release` is the only layer-only name).
- CI job id is `ci` (was `build` or `check`). Publish check-run right half is `publish`. Token vs OIDC (and container attest vs not) are mutex jobs that both set `name: publish`. Callee `jobs.<id>.name` is otherwise unset except `release-rust.yml` `Build ${{ matrix.target }}` and the `self-ci.yml` aggregator `Self / CI`.
- Version inputs are `{tool}-version`. `toolchain` → `rust-version`.
- Secrets are `SCREAMING_SNAKE`. `PYPI_API_TOKEN` → `PYPI_TOKEN`. Sync `token` → `SYNC_TOKEN`. Container `registry-username` / `registry-password` → `REGISTRY_USERNAME` / `REGISTRY_PASSWORD`.
- `foundry-profile` default is `ci` (was `default`).
- `submodules` default is `false` on every `ci-*`. Foundry callers with `lib/` must pass `submodules: true`.
- Node `package-manager` default is `npm` and is not auto-detected.
- `ci-node` default `node-versions` is `["22", "24"]` (drops Node 20). Breaking.
- `bun-version` default is `1.4`. `latest` is not a default.
- `golangci-lint-version` default is `v2.13` (v9 rejects `v2`).
- Container default platforms are `linux/amd64,linux/arm64`. `attest` default is `true`. `push: true` runs job `publish` (attest) or `push` (`attest: false`); `push: false` runs `build`.
- npm/PyPI: token job requests only `contents: read`. OIDC job requests `id-token` (PyPI also `attestations`). Token-only callers that omit `id-token` can run. Empty token is OIDC.
- `ops-stale.yml` is `workflow_call` only. Callers own `schedule`.
- Third-party `uses:` are SHA-pinned (`owner/repo@<40-char-sha> # tag`). Same-repository references use `$/` with no `@ref`.
- Concurrency groups are `qntx-workflows-<stem>-${{ github.repository }}-${{ github.ref }}`, not `${{ github.workflow }}`. Pages and MkDocs groups are distinct.
- Nested `uses:` jobs no longer set `timeout-minutes`. `self-release.yml` matches `v*.*.*` only.
- `ops-sync` rejects source or dest under `.git`/`.github`. rsync also excludes those names. Default dest `.` remains valid. Root sync has no `--delete`.
- Empty `cliff-config` omits the git-cliff `config` key so the action default `cliff.toml` applies.
- `parse-env-block` allowlists build/cross keys only (`CARGO_TARGET_*_LINKER` / `*_RUNNER` / `*_RUSTFLAGS` / `*_RUSTDOCFLAGS` / `*_AR`, `CC`/`CXX`/`*FLAGS`, `RUSTFLAGS`, …).
- `ci-rust` `deny: true` fail-closes on non-Linux. `features` is a flag allowlist (argv/glob, not shell).
- `CARGO_REGISTRY_TOKEN` is set only on the crates publish step.
- `release-rust` prerelease tags set `prerelease` and skip `make_latest`.
- `self-retag` requires `target` major to match `major` and writes an annotated `vN`.
- Dependabot `directories` includes `/` and `/actions/*`.
- zizmor and scorecard SARIF uploads skip fork PRs.
- `hardened-checkout` omits `sparse-checkout` when the value is empty or `.` (non-cone `.` is an empty tree).
- Auto prerelease now requires a hyphen before the token; `-prefix`/`-prepare`/`-arch` are stable; `rc1` still prerelease.

### Added

- `actions/publish-npm` and `actions/publish-pypi` (private). Called from mutex jobs in the public workflows.
- `ci-rust.yml` input `deny` (default `false`) runs `cargo-deny check` when the crate has `deny.toml`.
- `publish-npm.yml` `install-directory` (default `.`) for workspace install and lockfile cache. `working-directory` is the package that is built, tested, and published.
- `setup-uv` v10.0.1 and `codeql-action` v4.37.9.
- `publish-container.yml` (replaces `container-build.yml` / `docker.yml`).
- `ops-stale.yml`, `ops-sync.yml`, `ops-dependabot.yml`.
- `self-ci.yml`, `self-stale.yml`, `self-dependabot.yml`, `self-retag.yml`.
- Private composites under `actions/` (`hardened-checkout`, `apt-install`, `setup-rust`, `parse-env-block`, `protect-sync-path`, `run-trusted-command`, `publish-crates`).
- `docs/CATALOGUE.md`, `docs/CONSUMERS.md`, `docs/MIGRATION.md`, `examples/`.
- `cliff.toml` for git-cliff (conventional commits).
