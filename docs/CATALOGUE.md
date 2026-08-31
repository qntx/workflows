# Catalogue

Closed public prefixes: `ci-` / `publish-` / `release` / `deploy-` / `ops-`. Private prefix: `self-`. New files add a suffix under an existing prefix; they do not invent a new public prefix.

`name:` is `<Layer> / <Subject>`. The only exception is `release.yml` → `Release` (the workflow is the layer).

Callee jobs do not set `jobs.<id>.name` unless noted. GitHub required checks match `{caller-job-id} / {callee job name or id}`. Mutex publish jobs set `name: publish` so the check-run right half stays `publish`.

## Public API

| File                    | `name:`               | Job ids                        | Purpose                                                                                                   |
| ----------------------- | --------------------- | ------------------------------ | --------------------------------------------------------------------------------------------------------- |
| `ci-bun.yml`            | `CI / Bun`            | `ci`                           | Bun install / lint / typecheck / build / test. `bun-version` default `1.4`.                               |
| `ci-foundry.yml`        | `CI / Foundry`        | `ci`                           | Forge fmt / build --sizes / test. `foundry-profile` default `ci`.                                         |
| `ci-go.yml`             | `CI / Go`             | `ci`                           | `go mod tidy` drift, `vet`, optional golangci-lint (`golangci-lint-version` default `v2.13`), race.       |
| `ci-node.yml`           | `CI / Node.js`        | `ci`                           | Node version matrix. `package-manager`: `npm` / `pnpm` / `yarn`. Not auto-detected.                       |
| `ci-python.yml`         | `CI / Python`         | `ci`                           | uv + ruff + pytest. `pyproject.toml` or `requirements.txt`.                                               |
| `ci-rust.yml`           | `CI / Rust`           | `ci`                           | fmt / clippy `-D warnings` / build / test. Optional `deny` (cargo-deny). Debian-like runner.              |
| `publish-npm.yml`       | `Publish / npm`       | `route`, `publish` \| `oidc`   | `route` picks token vs OIDC. Token job `publish`; OIDC job `oidc`. Both `name: publish`.                  |
| `publish-pypi.yml`      | `Publish / PyPI`      | `route`, `publish` \| `oidc`   | `route` picks token vs OIDC. Token job `publish`; OIDC job `oidc`. Both `name: publish`.                  |
| `publish-crates.yml`    | `Publish / crates.io` | `publish`                      | `cargo publish --locked`, skip-if-exists, 429 retry. `CARGO_REGISTRY_TOKEN` required.                     |
| `publish-container.yml` | `Publish / container` | `build` \| `publish` \| `push` | `build` if `push: false`. `publish` if push+attest. `push` if push and `attest: false` (`name: publish`). |
| `release.yml`           | `Release`             | `release`                      | git-cliff changelog + GitHub Release.                                                                     |
| `release-rust.yml`      | `Release / Rust`      | `build`, `release`             | Five-target matrix. `jobs.build.name`: `Build ${{ matrix.target }}`.                                      |
| `deploy-pages.yml`      | `Deploy / Pages`      | `build`, `deploy`              | Bun build + Pages artifact API. `deploy` skipped on `pull_request`.                                       |
| `deploy-mkdocs.yml`     | `Deploy / MkDocs`     | `deploy`                       | `mkdocs gh-deploy --force` (branch push, not Pages artifact).                                             |
| `ops-stale.yml`         | `Ops / Stale`         | `stale`                        | `actions/stale`. `workflow_call` only.                                                                    |
| `ops-sync.yml`          | `Ops / Sync`          | `sync`                         | Folder mirror. Source or dest under `.git`/`.github` is rejected. rsync also excludes those names.        |
| `ops-dependabot.yml`    | `Ops / Dependabot`    | `merge`                        | `enablePullRequestAutoMerge` via `$/actions/ops-dependabot-enable`. No checkout. Does not approve. Caller owns `on:`. |

Shared CI inputs (declared on every `ci-*`): `runs-on` (default `ubuntu-latest`), `working-directory` (`.`), `submodules` (`false`), `timeout-minutes` (`20`; `30` on rust / foundry).

## Private (`self-*`)

Not a consumer API. Required check-run name for this repository is `Self / CI`.

| File                  | `name:`             | Job ids                                                                     | Purpose                                                         |
| --------------------- | ------------------- | --------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `self-ci.yml`         | `Self / CI`         | `actionlint`, `zizmor`, `pinact`, `format`, `composites`, `scorecard`, `ci` | Lint the tree. Aggregator job `ci` has `name: Self / CI`.       |
| `self-release.yml`    | `Self / Release`    | `release`                                                                   | `on.push.tags: ['v*.*.*']` → `$/.github/workflows/release.yml`. |
| `self-stale.yml`      | `Self / Stale`      | `stale`                                                                     | Cron `30 1 * * *` → `$/.github/workflows/ops-stale.yml`.        |
| `self-dependabot.yml` | `Self / Dependabot` | `merge`                                                                     | `on: pull_request` → `$/.github/workflows/ops-dependabot.yml`.  |
| `self-retag.yml`      | `Self / Retag`      | `retag`                                                                     | Force-move `v<major>` to an existing annotated `vX.Y.Z` tag.    |

`scorecard` is `continue-on-error: true` and is not in the aggregator `needs`.
