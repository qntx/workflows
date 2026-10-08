# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.3.0] - 2026-10-08

### Changed

- `ci-bun.yml` Test runs `bun run test` when `scripts.test` is defined; the file heuristic + `bun test` is only the fallback. The heuristic cannot see monorepo tests (`packages/*/tests/*`) and could run a different runner than the declared script.
- `setup-wasm` package contract drops the single-package `./wasm` layout rules (`exports["."]` must not be wasm, `scripts.build` must not run the wasm build, `prepublishOnly` must equal `<pm> run build:wasm`). `dist-export` accepts `.` for a dedicated wasm package whose root export is the loader. Kept: `files` containing `dist` (with the allowed-entries rule), `sideEffects` `**/*.wasm`, `build:wasm`/`test:wasm` scripts, no `install`/`postinstall`/`prepublish`, `devEngines.packageManager` consistency, dist-export resolving under `dist/` with at least one `dist/*.wasm`.
- `fixtures/bun` is a Bun workspace (`packages/hello`) so `e2e-bun` exercises the `bun run test` script path in a monorepo. `fixtures/wasm` is now the dedicated-package shape (root export is the wasm loader) with `e2e-wasm` `dist-export: .`.

## [2.2.0] - 2026-10-08

### Changed

- `publish-npm.yml` is OIDC trusted-publishing only: the `route` job and token `publish` job are deleted; one job `publish` keeps check-run `{caller} / publish`. `NPM_TOKEN`, `registry-url`, and `provenance` are removed; publish always passes `--provenance` and asserts npm >= 11.5.1 (default `node-version: '24'` ships it).
- `publish-pypi.yml` is token-only: the `route` job and OIDC job are deleted; one job `publish`, `PYPI_TOKEN` becomes required, `attestations` is removed. PyPI trusted publishing cannot reach cross-repo reusable workflows (pypi/warehouse#11096).
- `.github/dependabot.yml`: every ecosystem gains `cooldown: default-days: 7` and a `minor`+`patch` `groups` entry so the open-PR limit stops new updates from being blocked.

### Added

- `examples/dependabot.yml` consumer template: `bun`, `npm`, `cargo`, `github-actions` with `cooldown: default-days: 7` and `minor`+`patch` groups, weekly.

## [2.1.0] - 2026-10-07

### Changed

- `github/codeql-action/upload-sarif` `v4.38.0`.
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
- `ops-sync` jails canonical `.git` / `.github` path segments after `realpath`, not only `$root/.git` / `$root/.github`.
- `scorecard` checkout is `$/actions/hardened-checkout`.
- `ci-docs.yml` no longer identity-checkouts this repository or jails `docs-path` in Python. `$/actions/validate-docs-tree` is self-contained (`package.json` + lockfile; `bun install` at `github.action_path`).
- `stale.yml` and `repo-stale.yml` stay as `workflow_call` forwards to `ops-stale.yml` so unmigrated `@main` callers do not 404. Not a public API. New callers use `ops-stale.yml@v2`.
- Pin every public callee at `@v2` (moving) or `@v2.x.y` (immutable). `v2` moves only to published `v2.x.y` release commits; `v2.0.0` remains a historical immutable tag. Releases are cut by pushing an annotated `vX.Y.Z` tag on a `main` commit.
- `Self / Release` on `vX.Y.Z` push validates the tag (annotated, reachable from `origin/main`), calls `release.yml`, then force-moves annotated `v<major>` to the release commit and verifies the peeled SHA.
- `Self / Retag` is rollback-only: required `tag` input must be an existing annotated `vX.Y.Z` on origin; `v<major>` moves to that tag's commit. The move-to-`origin/main` behaviour is removed.
- `ops-dependabot` sweep: a failed merge is `fail:merge <reason>` and later PRs still run; the job exits non-zero if any PR failed (reported from production 2026-10-07).
- `ops-dependabot` splits `wait:checks` into `wait:checks-pending` and `blocked:checks-failed`, and writes a per-PR decision table to the step summary.
- `ops-dependabot` skips PRs touching `.github/workflows/` as `skip:needs-workflows-token` unless the caller passes `TOKEN` (`github.token` can never hold `workflows` write).
- `ops-dependabot` reports SHA-only `github-actions` bumps as `skip:digest-update <name>` instead of `skip:unhandled-update-type`; they are never auto-merged.
- `ci-*.yml` callees drop workflow-level `concurrency`; callers own `concurrency` (#77). deploy/publish/release/ops callee groups gain `${{ github.workflow }}`.
- `ci-rust.yml` inputs `doc` and `package-check` (#77). `rust-version` default `''` honours `rust-toolchain.toml`/`rust-toolchain` in `working-directory`, else `stable` (#77, #78 fixture coverage).
- `setup-rust` resolves the toolchain in `working-directory` (walks up to `GITHUB_WORKSPACE`), installs `rustup toolchain install` (rustup >= 1.28) or dtolnay, and exports `RUSTUP_TOOLCHAIN` for explicit `rust-version` (#77). `channel.sh` is deleted; `toolchain-file` is a deprecated no-op; outputs are `toolchain`/`rustc` (`channel` aliases `toolchain`); rust-cache gets `workspaces: <working-directory>`.
- `ci-wasm.yml` inputs `rust-checks` (skip fmt/clippy/test), `scripts` (extra package scripts after test/bench), `dist-export` (#78). Package-manager blocks collapse to `"$PM" run`.
- `setup-wasm` skips `wasm-bindgen-cli` when `Cargo.lock` has no `wasm-bindgen` (`lockver.sh` reports `absent`), and checks `dist-export` instead of a hard-coded `./wasm` (#78).
- `publish-crates` drops inline fmt/clippy/build/test (`cargo publish` verifies the build; CI gates the tag) and adds `dry-run` (#78). Dry-run is one `cargo publish -p <each> --locked --dry-run` call so unpublished path deps resolve, and does not need `CARGO_REGISTRY_TOKEN`.
- `release.yml` merges the two download steps (`pattern: ''` is falsy in `actions/download-artifact`) (#78).

### Fixed

- `ops-dependabot`: `gh pr merge` conflicts and exhausted `Base branch was modified` retries wait for the next sweep instead of failing the job.

- `ops-dependabot`: `gh pr merge` conflicts and exhausted `Base branch was modified` retries wait for the next sweep instead of failing the job.
- `dependabot.yml`: use the existing `github_actions` label. Drop `github-actions` and `javascript` (those labels are not in this repository).
- `publish-pypi` checks the dist with `uvx twine` instead of `uv pip install --system twine`, which fails on PEP 668 externally-managed CPython from `setup-uv`.
- `publish-pypi` uploads with `uv publish` instead of `pypa/gh-action-pypi-publish`. Nested Docker actions resolve to `ghcr.io/qntx/workflows:<sha>` and 403.
- `publish-pypi` does not export empty `UV_PUBLISH_URL`; uv treats `''` as an invalid `--publish-url`.
- `setup-wasm` `check-pkg.sh` accepts `files` containing `dist`, `dist/` paths, and top-level `LICEN[CS]E`/`COPYING`/`NOTICE`/`README`/`CHANGELOG` files; anything else is rejected with the offending entry named (#76).

### Added

- `ci-rust-cross.yml` (`CI / Rust cross`, jobs `plan` + `build`): required `targets`/`packages`, `features`, `forbid-deps`, per-target toolchain (wasm32 via `clang`/`lld`, android via `cargo-ndk`, iOS plain `cargo build`) (#78).
- `ci-hermes.yml` (`CI / Hermes`): cached Hermes build pinned by `hermes-commit`, then `bun run <script>` with `HERMES` (#78).
- `ops-dependabot-enable` input `custom-token` flags that `github-token` is caller-supplied.
- `fixtures/{rust,bun,wasm,cross,hermes}` workspaces and `self-ci.yml` `e2e-*` jobs exercise the public workflows for real (#77, #78).
- `setup-rust` input `toolchain-file` (default false) parses `channel` from `rust-toolchain.toml` or a one-line `rust-toolchain` and passes it to dtolnay. Private composite `actions/setup-wasm` installs that toolchain, `wasm-bindgen-cli` from `Cargo.lock`, and the wasm package contract.
- `ci-docs.yml`: reusable Fumadocs library-tree validator (`docs / ci`). Callers must not set `jobs.docs.name`. Implementation is `$/actions/validate-docs-tree` after checkout and setup-bun. Path jail is TypeScript `resolveDocsRoot`. Local/fan-in CLI: `bun install --frozen-lockfile` in `actions/validate-docs-tree`, then `bun validate-docs-tree.ts <docs-dir> --lint`. Root lockfile is repo-dev only.
- `ci-wasm.yml` (`CI / WASM`, job id `ci`): wasm32 toolchain, host fmt/clippy/test, `build:wasm`, `test:wasm`, optional `bench:wasm`. Debian runner. `timeout-minutes` default 30.
- `publish-npm` inputs `wasm` (default false) and `cargo-directory`. Wasm runs `build:wasm` once and `npm publish --ignore-scripts`. Callers set `timeout-minutes` to 30. Default timeout stays 15. Token provenance stays false; OIDC provenance stays true.

### Removed

- `ops-docs-fan-in.yml`. Public-docs fan-in is a `qntx/docs` workflow, not a reusable callee.
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
