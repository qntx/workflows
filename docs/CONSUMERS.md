# Consumer contract

The caller owns `on:`. Callees only declare `workflow_call` inputs, secrets, and outputs.

Pin CI and ops at `@v2`. Pin publish, release, and deploy at `@v2.0.0`.

```yaml
jobs:
  ci:
    uses: qntx/workflows/.github/workflows/ci-rust.yml@v2
```

GitHub intersects caller job `permissions` with the callee. Org `default_workflow_permissions: write` does **not** include `id-token` or `attestations`. OIDC and provenance require those keys on the caller job.

Do not `uses:` anything under `actions/`. Nested `uses:` jobs may set only `name`, `uses`, `with`, `secrets`, `strategy`, `needs`, `if`, `concurrency`, `permissions`. Do not set `timeout-minutes`, `runs-on`, `steps`, or `environment` on the calling job.

Do not pass `github.event.*` (issue titles, PR bodies, review comments) into `*-command` inputs. Those run via `bash -c` as the trusted caller.

`ci-rust.yml` `deny: true` requires a Linux runner (cargo-deny-action is Docker). `features` must be `--all-features`, `--no-default-features`, or `--features <list>`.

`astral-sh/setup-uv` is pinned at v10. This repository sets `enable-cache: true` or `false` explicitly. Do not use `auto`: v10 turns cache off on tag push, `release`, `pull_request_target`, and `workflow_run`.

`dtolnay/rust-toolchain` is pinned to a commit with comment `# v1`. Dependabot may churn when `v1` moves; that is expected.

Check-run names are `{caller-job-id} / {callee job name or id}`. Callees do not set `jobs.<id>.name` except `release-rust.yml` `jobs.build` (`Build <target>`) and this repository's aggregator (`Self / CI`).

`ci-rust`, `ci-foundry`, `publish-crates`, and `release-rust` Linux cross jobs require a Debian-like runner (`ubuntu-*`). apt / GNU `date -u -d` fail-closed on macOS/Windows.

## CI (`ci-*`)

```yaml
permissions:
  contents: read
```

`ci-go.yml` `golangci-lint-version` must be `v2.N`, `v2.N.M`, or `latest`. Do not pass `v2`.

## Publish / npm

OIDC (no `NPM_TOKEN`):

```yaml
permissions:
  contents: read
  id-token: write
```

Token-only (`NPM_TOKEN` set). Provenance is off. The token job requests only `contents: read`. Do not grant `id-token`:

```yaml
permissions:
  contents: read
secrets:
  NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```

Former `publish-npm-bun.yml` callers pass `package-manager: bun`.

Monorepo: install the workspace at the repository root, publish one package per job. Do not set `working-directory` to the package and expect `npm ci` to run there.

```yaml
jobs:
  publish:
    strategy:
      fail-fast: false
      matrix:
        package: [packages/a, packages/b]
    uses: qntx/workflows/.github/workflows/publish-npm.yml@v2.0.0
    permissions:
      contents: read
      id-token: write
    with:
      install-directory: .
      working-directory: ${{ matrix.package }}
      package-manager: pnpm
```

Each npm package needs its own Trusted Publisher (or `NPM_TOKEN`). Caller owns which packages to publish; this workflow does not scan git diffs or run Changesets.

## Publish / PyPI

OIDC (no `PYPI_TOKEN`):

```yaml
permissions:
  contents: read
  id-token: write
  attestations: write
```

Token-only (`PYPI_TOKEN` set). Attestations are off. The token job requests only `contents: read`. Do not grant `id-token` or `attestations`:

```yaml
permissions:
  contents: read
secrets:
  PYPI_TOKEN: ${{ secrets.PYPI_TOKEN }}
```

The workflow secret id is `PYPI_TOKEN`, not `PYPI_API_TOKEN`.

## Publish / crates.io

No OIDC.

```yaml
permissions:
  contents: read
secrets:
  CARGO_REGISTRY_TOKEN: ${{ secrets.CARGO_REGISTRY_TOKEN }}
```

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

The caller owns `schedule`. `ops-stale.yml` has no cron.

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
  pull_request:
  schedule:
    - cron: '*/15 * * * *'
  workflow_dispatch:
permissions:
  contents: write
  pull-requests: write
```

Caller owns `on:`. `ops-dependabot.yml` has no cron. Prefer `pull_request` (Dependabot branches are in-repo). `pull_request_target` is allowed but the callee never checks out the PR. Do not add a checkout step on the caller job.

`pull_request` tries `enablePullRequestAutoMerge`. That mutation rejects `UNSTABLE` (pending or failing optional checks). This org does not set required checks, so the arm step is a no-op and must not fail. `check_suite` / `check_run` do not trigger workflows when the suite was created by GitHub Actions, so they cannot be the merge-when-green signal.

`schedule` (and `workflow_dispatch`) lists open Dependabot PRs and squash-merges those whose other checks are green. No other checks after a 5-minute grace means the repo has no PR CI; then it merges. Does **not** approve. If rulesets require reviews, add a bypass for Dependabot or pass `TOKEN` (PAT/App) that can merge; do not use this workflow to rubber-stamp CODEOWNERS.

The caller job `if:` must allow `schedule` / `workflow_dispatch`. A `dependabot[bot]`-only `if:` skips the sweep.

Defaults: squash; `semver-patch` and `semver-minor` on; `semver-major` off. Omit `TOKEN` to use `github.token`.

Secret id is `TOKEN`.
