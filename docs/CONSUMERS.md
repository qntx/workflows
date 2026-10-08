# Consumer contract

The caller owns `on:`. Callees only declare `workflow_call` inputs, secrets, and outputs.

Pin every public callee at `@v2`. `v2` is the annotated moving major tag; it moves only to published `v2.x.y` release commits. For an immutable pin use `@v2.x.y`. Releases are cut by pushing an annotated `vX.Y.Z` tag on a `main` commit. `v2.0.0` is a historical immutable tag, not the consumer pin.

```yaml
jobs:
  ci:
    uses: qntx/workflows/.github/workflows/ci-rust.yml@v2
```

GitHub intersects caller job `permissions` with the callee. Org `default_workflow_permissions: write` does **not** include `id-token` or `attestations`. OIDC and provenance require those keys on the caller job.

Do not `uses:` anything under `actions/`. Nested `uses:` jobs may set only `name`, `uses`, `with`, `secrets`, `strategy`, `needs`, `if`, `concurrency`, `permissions`. Do not set `timeout-minutes`, `runs-on`, `steps`, or `environment` on the calling job.

`ci-*` callees declare no `concurrency`. Serialisation is the caller's job:

```yaml
jobs:
  ci:
    uses: qntx/workflows/.github/workflows/ci-rust.yml@v2
    concurrency:
      group: ci-${{ github.workflow }}-${{ github.ref }}
      cancel-in-progress: true
```

Do not pass `github.event.*` (issue titles, PR bodies, review comments) into `*-command` inputs. Those run via `bash -c` as the trusted caller.

`ci-rust.yml` `deny: true` requires a Linux runner (cargo-deny-action is Docker). `features` must be `--all-features`, `--no-default-features`, or `--features <list>`. `rust-version` default `''` honours `<working-directory>/rust-toolchain.toml` or `rust-toolchain`, else `stable`; a non-empty value wins over the file. `doc: true` adds `cargo doc --workspace --no-deps` under `RUSTDOCFLAGS="-D warnings"`; `package-check: true` adds `cargo publish --workspace --dry-run --locked`.

`astral-sh/setup-uv` is pinned at v10. This repository sets `enable-cache: true` or `false` explicitly. Do not use `auto`: v10 turns cache off on tag push, `release`, `pull_request_target`, and `workflow_run`.

`dtolnay/rust-toolchain` is pinned to a commit with comment `# v1`. Dependabot may churn when `v1` moves; that is expected.

Check-run names are `{caller-job-id} / {callee job name or id}`. Callees do not set `jobs.<id>.name` except `release-rust.yml` `jobs.build` (`Build <target>`) and this repository's aggregator (`Self / CI`).

`ci-rust`, `ci-foundry`, `publish-crates`, and `release-rust` Linux cross jobs require a Debian-like runner (`ubuntu-*`). apt / GNU `date -u -d` fail-closed on macOS/Windows.

## CI (`ci-*`)

```yaml
permissions:
  contents: read
```

Language CI is `.github/workflows/ci.yml` (job id `ci`). Docs CI is `.github/workflows/ci-docs.yml` (job id `docs`). Do not put a `docs` job in `ci.yml`.

`ci-go.yml` `golangci-lint-version` must be `v2.N`, `v2.N.M`, or `latest`. Do not pass `v2`.

`ci-bun.yml` Test runs `bun run test` when `scripts.test` is defined; otherwise it falls back to a three-level file heuristic plus `bun test`. The heuristic cannot see monorepo tests (`packages/*/tests/*`) and would silently run a different runner than a declared `test` script, so declare `test` explicitly.

`ci-docs.yml` callers use job id `docs`. Do not set `jobs.docs.name` or the required check is `Docs / ci`. Pin `@v2`. Copy `examples/ci-docs.yml`.

```yaml
# .github/workflows/ci-docs.yml
name: Docs

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  docs:
    uses: qntx/workflows/.github/workflows/ci-docs.yml@v2
    permissions:
      contents: read
```

Library `docs/` must pass `validate-docs-tree --lint`. Empty directory is illegal. Minimal stub (replace `example` with the GitHub repo name): `examples/docs-stub/`. Omit `root`. `root: true` is forbidden (`library docs must not set root:true`). Stubs never enter `qntx/docs` `fan-in/manifest.json`.

`docs/meta.json`:

```json
{
  "title": "example",
  "description": "Documentation stub.",
  "pages": ["index"]
}
```

`docs/index.mdx`:

```mdx
---
title: example
description: Documentation stub.
---

Documentation stub.
```

Fan-in and local runs spawn the CLI. Do not `import()` the module. Do not `bun install` at the workflows root for the validator:

```bash
cd actions/validate-docs-tree
bun install --frozen-lockfile
bun validate-docs-tree.ts "$docsDir" --lint
```

`--lint` loads sibling `docs-tree.markdownlint.jsonc`. Absolute `<docs-dir>` is allowed.

### ci-wasm

Rust-free CI stays `ci-bun.yml`. Wasm CI is a sibling job. Caller job id `wasm`. Do not set `jobs.wasm.name`. Check-run is `wasm / ci`. Pin `@v2`. `@v2` does not move on merge; it moves to the published `v2.x.y` commit when a release is cut. Do not `uses:` `actions/setup-wasm`. Bindgen version is not an input.

`timeout-minutes` may be omitted (default 30). `bun-version` may be omitted (default `1.4`, not `latest`, not `1.4.0`). `package-manager` is `bun` or `npm`. Copy `examples/ci-wasm.yml`.

Inputs: `runs-on` (`ubuntu-latest`), `timeout-minutes` (`30`), `working-directory` (`.`), `install-directory` (`.`), `cargo-directory` (`.`), `submodules` (`false`), `package-manager` (`bun`), `bun-version` (`1.4`), `node-version` (`24`, not installed on the bun path), `bench` (`false`), `rust-checks` (`true`; set `false` when a sibling `ci-rust` job already runs fmt/clippy/test), `scripts` (`''`; whitespace-separated extra package scripts run after `test:wasm`/`bench:wasm`), `dist-export` (`./wasm`; `.` selects the root export of a dedicated wasm package), `targets` (`wasm32-unknown-unknown`), `apt-packages` (`clang lld llvm`).

`setup-wasm` package contract: `files` is an array containing `dist` (other entries must be `dist/` paths or top-level license/readme/changelog files); `sideEffects` contains `**/*.wasm`; `scripts.build:wasm` and `scripts.test:wasm` exist; `install`/`postinstall`/`prepublish` scripts are forbidden; `devEngines.packageManager`, when present, must name the same package manager with `onFail: ignore`. The `dist-export` exports key must resolve to a file under `dist/` and at least one `dist/*.wasm` must exist. `prepublishOnly` is not part of the contract — `publish-npm.yml` builds wasm itself and publishes with `--ignore-scripts`.

### ci-rust-cross

Cross-target `cargo build` matrix for `targets` (required, whitespace-separated triples) and `packages` (required, whitespace-separated names). `*-apple-ios*` runs on `macos-latest`; android targets run via `cargo-ndk` on `ubuntu-latest` (uses the runner's `ANDROID_NDK_LATEST_HOME`); everything else on `ubuntu-latest`. `features` defaults `--no-default-features`. `forbid-deps` lists crate names that must not appear in `cargo tree -e normal` for any package/target.

```yaml
jobs:
  cross:
    uses: qntx/workflows/.github/workflows/ci-rust-cross.yml@v2
    permissions:
      contents: read
    with:
      targets: wasm32-unknown-unknown aarch64-apple-ios aarch64-linux-android
      packages: my-crate
      forbid-deps: tokio
```

### ci-hermes

Builds facebook/hermes at `hermes-commit` (required, 40 lowercase hex) on ubuntu, caches the build per commit, then runs `script` (default `smoke:hermes`) with `HERMES` pointing at the built CLI. An uncached build is slow; keep `timeout-minutes` generous.

```yaml
jobs:
  hermes:
    uses: qntx/workflows/.github/workflows/ci-hermes.yml@v2
    permissions:
      contents: read
    with:
      hermes-commit: 3477757eb2475555cf8d8df24bfb1deb0613880d
```

```yaml
# Caller owns on:. Pin at @v2.
# ci-bun stays the Rust-free job. This job is the wasm build.
# Required check-run: wasm / ci. Do not set jobs.wasm.name.
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

jobs:
  ci:
    uses: qntx/workflows/.github/workflows/ci-bun.yml@v2
    permissions:
      contents: read

  wasm:
    uses: qntx/workflows/.github/workflows/ci-wasm.yml@v2
    permissions:
      contents: read
    with:
      package-manager: bun
      bench: true
```

## Publish / npm

OIDC trusted publishing only; `npm publish` always runs with `--provenance`. A version that is already on the registry is skipped with a notice, so reruns after a partial release and a first version published by hand (npm only allows configuring a Trusted Publisher for an existing package) stay green:

```yaml
permissions:
  contents: read
  id-token: write
```

Each npm package needs its own Trusted Publisher on npmjs.com naming the **caller repository** and the **caller workflow filename** (the file that `uses:` `publish-npm.yml`). The caller job must grant `id-token: write`. There is no `NPM_TOKEN` path and no `registry-url` input: trusted publishing exists only on registry.npmjs.org. The npm CLI must be >= 11.5.1 (default `node-version: '24'` ships it); the job fails clearly otherwise.

Former `publish-npm-bun.yml` callers pass `package-manager: bun`.

Monorepo: install the workspace at the repository root, publish one package per job. Do not set `working-directory` to the package and expect `npm ci` to run there.

```yaml
jobs:
  publish:
    strategy:
      fail-fast: false
      matrix:
        package: [packages/a, packages/b]
    uses: qntx/workflows/.github/workflows/publish-npm.yml@v2
    permissions:
      contents: read
      id-token: write
    with:
      install-directory: .
      working-directory: ${{ matrix.package }}
      package-manager: pnpm
```

Each npm package needs its own Trusted Publisher. Caller owns which packages to publish; this workflow does not scan git diffs or run Changesets.

### wasm

Set `wasm: true` only together with `timeout-minutes: 30` (`with:`, not a job key). That path runs `setup-wasm` in the publish job, runs `build:wasm` once, and adds `--ignore-scripts`. `wasm: false` keeps the current publish path and the 15 minute timeout. Do not pass a bindgen version. Do not `uses:` `actions/setup-wasm`. `@v2` does not move on merge. Copy `examples/publish-npm-wasm.yml`.

```yaml
# Caller owns on:. Pin at @v2.
# OIDC. Do not set environment, runs-on, or steps.
# Required check-run on a tag: publish / publish.
name: Publish

on:
  push:
    tags: ['v*.*.*']

permissions:
  contents: read
  id-token: write

jobs:
  publish:
    uses: qntx/workflows/.github/workflows/publish-npm.yml@v2
    permissions:
      contents: read
      id-token: write
    with:
      package-manager: bun
      wasm: true
      timeout-minutes: 30
```

## Publish / PyPI

Token only; `PYPI_TOKEN` is required:

```yaml
permissions:
  contents: read
secrets:
  PYPI_TOKEN: ${{ secrets.PYPI_TOKEN }}
```

PyPI trusted publishing does not support reusable workflows from another repository ([pypi/warehouse#11096](https://github.com/pypi/warehouse/issues/11096)), so an OIDC path can never succeed from a caller repo. Do not grant `id-token` or `attestations`.

The workflow secret id is `PYPI_TOKEN`, not `PYPI_API_TOKEN`.

## Publish / crates.io

No OIDC. The workflow does not re-run fmt/clippy/build/test — `cargo publish` verifies the package build and CI already gates the tagged commit.

```yaml
permissions:
  contents: read
secrets:
  CARGO_REGISTRY_TOKEN: ${{ secrets.CARGO_REGISTRY_TOKEN }}
```

`dry-run: true` runs `cargo publish -p <each> --dry-run --locked` in one invocation (topological order, unpublished path deps resolve between listed members) and does not need `CARGO_REGISTRY_TOKEN`.

## Publish / container

GHCR + attest (`attest` default `true`):

```yaml
permissions:
  contents: read
  packages: write
  id-token: write
  attestations: write
```

Push without attest (no OIDC, or Docker Hub with `REGISTRY_*`):

```yaml
permissions:
  contents: read
  packages: write # omit packages: write for a non-GHCR registry
```

```yaml
with:
  attest: false
```

Default `push: true` runs job `publish` when `attest: true`, or job `push` (`name: publish`) when `attest: false`. `push: false` runs job `build`. Default platforms are `linux/amd64,linux/arm64`. Pin `platforms: linux/amd64` to skip QEMU.

## Deploy / Pages

```yaml
permissions:
  contents: read
  pages: write
  id-token: write
```

The `deploy` job is the one that needs `pages: write` + `id-token: write`. It is skipped on `pull_request`.

## Deploy / MkDocs

```yaml
permissions:
  contents: write
```

## Release

`release.yml` and `release-rust.yml`.

```yaml
permissions:
  contents: write
```

## Ops / Stale

```yaml
permissions:
  issues: write
  pull-requests: write
```

The caller owns `schedule`. `ops-stale.yml` has no cron. `stale.yml` and `repo-stale.yml` are compatibility aliases that forward to `ops-stale.yml` for unmigrated `@main` callers.

## Ops / Sync

```yaml
permissions:
  contents: write
secrets:
  SYNC_TOKEN: ${{ secrets.SYNC_TOKEN }} # optional; falls back to github.token
```

## Ops / Dependabot

```yaml
on:
  schedule:
    - cron: '0 4 * * *'
  workflow_dispatch:
```

```yaml
permissions:
  contents: write
  pull-requests: write
  checks: read
  actions: read
jobs:
  merge:
    permissions:
      contents: write
      pull-requests: write
      checks: read
      actions: read
    uses: qntx/workflows/.github/workflows/ops-dependabot.yml@v2
```

Caller owns `on:`. `ops-dependabot.yml` has no cron and does not encode visibility. Do not add a checkout step on the caller job. Nested `uses:` jobs must not set `timeout-minutes`, `runs-on`, or `steps`. No `if:` on the caller job.

`schedule` (and `workflow_dispatch`) lists open Dependabot PRs and squash-merges those whose other checks are green. Empty non-self rollup after 900s means the repo has no PR CI; then it merges. Does **not** approve.

`statusCheckRollup` GraphQL 403 is fail until callers grant `checks: read` and `actions: read` on the caller job (GitHub intersects with the callee). Later PRs in the same sweep still run.

Rulesets that require reviews mean this workflow never merges those PRs (`skip:BLOCKED`). GraphQL `mergeStateStatus` is actor-agnostic. Do not pass `--admin` and do not call REST `PUT /pulls/{n}/merge`. Merge by hand, or stop requiring reviews for Dependabot.

Leftover caller `pull_request` / `pull_request_target` skips the job. That run must not share the sweep concurrency group; the callee keeps `…-${{ github.event.pull_request.number || 'sweep' }}`.

Defaults: squash; `semver-patch`, `version-update:lockfile-only`, and `semver-minor` on; `semver-major` off. Omit `TOKEN` to use `github.token`.

`TOKEN` is required to merge PRs that touch `.github/workflows/`: `github.token` can never hold the `workflows` permission, and the sweep reports `skip:needs-workflows-token` for those PRs instead of attempting the merge. Use a GitHub App installation token or fine-grained PAT with `Contents`, `Pull requests`, and `Workflows` write (plus `checks` + `actions` read for the rollup query). `TOKEN` is also for when `github.token` cannot merge at all (branch allowlist that excludes `GITHUB_TOKEN`), not for reviews.

Failed checks are `blocked:checks-failed`; pending checks are `wait:checks-pending`. A failed merge is `fail:merge` and the sweep continues with the remaining PRs, then exits non-zero. SHA-only `github-actions` bumps report `skip:digest-update` and are never auto-merged. The step summary lists a per-PR decision table plus counters.

Secret id is `TOKEN`.

## Dependabot configuration

Copy `examples/dependabot.yml` to `.github/dependabot.yml` and keep only the ecosystems the repository uses (`bun` or `npm`, `cargo`, `github-actions`).

- `cooldown: default-days: 7` enforces the org rule that adopted releases are at least 7 days old.
- A `groups` entry per ecosystem folds `minor` + `patch` bumps into one PR (majors stay individual and manual). Without grouping, the default 5-open-PR limit saturates and new updates stop being proposed.
- `ops-dependabot` merges a grouped PR by its **highest** update type: `ops_dependabot_parse_update_type` picks the maximum `version-update:semver-*` across the footer entries, so a group containing a minor is gated by `allow-minor` even when the rest are patches.
- PRs touching `.github/workflows/` need the `TOKEN` secret (see above).
