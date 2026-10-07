# Catalogue

Closed public prefixes: `ci-` / `publish-` / `release` / `deploy-` / `ops-`. Private prefix: `self-`. New files add a suffix under an existing prefix; they do not invent a new public prefix.

`name:` is `<Layer> / <Subject>`. The only exception is `release.yml` → `Release` (the workflow is the layer).

Callee jobs do not set `jobs.<id>.name` unless noted. GitHub required checks match `{caller-job-id} / {callee job name or id}`. Mutex publish jobs set `name: publish` so the check-run right half stays `publish`.

## Public API

Consumers pin every public file at `@v2`. `@v2` moves only to published `v2.x.y` release commits (see [Releasing](#releasing)).

| File                    | `name:`               | Job ids                        | Purpose                                                                                                                                                                           |
| ----------------------- | --------------------- | ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ci-bun.yml`            | `CI / Bun`            | `ci`                           | Bun install / lint / typecheck / build / test. `bun-version` default `1.4`.                                                                                                       |
| `ci-foundry.yml`        | `CI / Foundry`        | `ci`                           | Forge fmt / build --sizes / test. `foundry-profile` default `ci`.                                                                                                                 |
| `ci-go.yml`             | `CI / Go`             | `ci`                           | `go mod tidy` drift, `vet`, optional golangci-lint (`golangci-lint-version` default `v2.13`), race.                                                                               |
| `ci-node.yml`           | `CI / Node.js`        | `ci`                           | Node version matrix. `package-manager`: `npm` / `pnpm` / `yarn`. Not auto-detected.                                                                                               |
| `ci-python.yml`         | `CI / Python`         | `ci`                           | uv + ruff + pytest. `pyproject.toml` or `requirements.txt`.                                                                                                                       |
| `ci-rust.yml`           | `CI / Rust`           | `ci`                           | fmt / clippy `-D warnings` / build / test. Optional `deny` (cargo-deny), `doc`, `package-check`. Debian-like runner.                                                              |
| `ci-docs.yml`           | `CI / Docs`           | `ci`                           | Validate a Fumadocs library tree (`docs-path` default `docs`). `bun-version` default `1.4`.                                                                                       |
| `ci-wasm.yml`           | `CI / WASM`           | `ci`                           | wasm32 toolchain, optional host fmt/clippy/test (`rust-checks`), `build:wasm`, `test:wasm`, optional `bench:wasm` and `scripts`. Debian runner. `package-manager` `bun` or `npm`. |
| `ci-rust-cross.yml`     | `CI / Rust cross`     | `plan`, `build`                | `cargo build --target` matrix over required `targets`/`packages`; ios → macos-latest, android → cargo-ndk on ubuntu, wasm32 → clang. Optional `forbid-deps` cargo-tree gate.      |
| `ci-hermes.yml`         | `CI / Hermes`         | `ci`                           | Builds facebook/hermes at a pinned `hermes-commit` (cached per commit), runs `script` with `HERMES` set.                                                                          |
| `publish-npm.yml`       | `Publish / npm`       | `route`, `publish` \| `oidc`   | `route` picks token vs OIDC. Token job `publish`; OIDC job `oidc`. Both `name: publish`. Optional `wasm` (default false); `--ignore-scripts` only on that path.                   |
| `publish-pypi.yml`      | `Publish / PyPI`      | `route`, `publish` \| `oidc`   | `route` picks token vs OIDC. Token job `publish`; OIDC job `oidc`. Both `name: publish`.                                                                                          |
| `publish-crates.yml`    | `Publish / crates.io` | `publish`                      | `cargo publish --locked`, skip-if-exists, 429 retry. No inline CI. `dry-run` publishes in one topological invocation without a token.                                             |
| `publish-container.yml` | `Publish / container` | `build` \| `publish` \| `push` | `build` if `push: false`. `publish` if push+attest. `push` if push and `attest: false` (`name: publish`).                                                                         |
| `release.yml`           | `Release`             | `release`                      | git-cliff changelog + GitHub Release.                                                                                                                                             |
| `release-rust.yml`      | `Release / Rust`      | `build`, `release`             | Five-target matrix. `jobs.build.name`: `Build ${{ matrix.target }}`.                                                                                                              |
| `deploy-pages.yml`      | `Deploy / Pages`      | `build`, `deploy`              | Bun build + Pages artifact API. `deploy` skipped on `pull_request`.                                                                                                               |
| `deploy-mkdocs.yml`     | `Deploy / MkDocs`     | `deploy`                       | `mkdocs gh-deploy --force` (branch push, not Pages artifact).                                                                                                                     |
| `ops-stale.yml`         | `Ops / Stale`         | `stale`                        | `actions/stale`. `workflow_call` only.                                                                                                                                            |
| `ops-sync.yml`          | `Ops / Sync`          | `sync`                         | Folder mirror. Jail is canonical `.git` / `.github` segments after `realpath`, not worktree-root prefix only. rsync also excludes those names.                                    |
| `ops-dependabot.yml`    | `Ops / Dependabot`    | `merge`                        | Schedule squash-merge green Dependabot PRs. No auto-merge arm. No checkout. Caller owns `on:`.                                                                                    |

Shared CI inputs (declared on every `ci-*`): `runs-on` (default `ubuntu-latest`), `working-directory` (`.`), `submodules` (`false`), `timeout-minutes` (`20`; `30` on rust / foundry / wasm).

`ci-docs.yml` extra inputs: `bun-version` (default `1.4`), `docs-path` (default `docs`, relative to `working-directory`). Those paths are jailed inside `GITHUB_WORKSPACE`. Fan-in/local CLI: `bun install --frozen-lockfile` in `actions/validate-docs-tree`, then `bun validate-docs-tree.ts <docs-dir> --lint`. Do not `bun install` at the workflows root for the validator.

`ci-rust.yml` extra inputs: `rust-version` (default `''`: honours `<working-directory>/rust-toolchain.toml` or `rust-toolchain`, else `stable`; a non-empty value wins over the file via `RUSTUP_TOOLCHAIN`), `features` (default `--all-features`), `deny` (`false`), `deny-args` (`--all-features`), `doc` (`false`), `package-check` (`false`), `apt-packages` (`''`). `publish-crates.yml` and `release-rust.yml` share the `rust-version` default `''` semantics.

`ci-*` workflows declare no `concurrency`; serialisation is the caller's job (`concurrency` is allowed on the `uses:` job). deploy / publish / release / ops callees keep their groups and key them on `${{ github.workflow }}`.

`ci-wasm.yml` extra inputs: `install-directory` (`.`), `cargo-directory` (`.`), `package-manager` (`bun` or `npm`), `bun-version` (`1.4`), `node-version` (`24`, npm path only), `bench` (`false`), `rust-checks` (`true`), `scripts` (`''`, whitespace-separated package scripts run after test/bench), `dist-export` (`./wasm`), `targets` (`wasm32-unknown-unknown`), `apt-packages` (`clang lld llvm`). No `wasm-bindgen-version`. `wasm-bindgen-cli` install is skipped when the lockfile has no `wasm-bindgen` package. `publish-npm.yml` `wasm` defaults false. Callers that set `wasm: true` set `timeout-minutes: 30`. The publish timeout default stays 15.

Acceptance grep must print nothing. `actions/setup-wasm/fixtures/`, `actions/setup-wasm/test.sh`, `actions/setup-rust/test.sh`, and `fixtures/rust/rust-toolchain.toml` may contain `0.2.122` and `1.94`.

```bash
grep -RInE '0\.2\.122|1\.94' \
  .github/workflows/ci-wasm.yml \
  .github/workflows/publish-npm.yml \
  actions/publish-npm \
  actions/setup-rust/action.yml \
  actions/setup-rust/plan.sh \
  actions/setup-rust/jail.sh \
  actions/setup-rust/install.sh \
  actions/setup-wasm/action.yml \
  actions/setup-wasm/lockver.sh \
  actions/setup-wasm/check-pkg.sh \
  actions/setup-wasm/check-cdylib.sh \
  actions/setup-wasm/check-dist.sh \
  actions/setup-wasm/jail.sh
```

## Private (`self-*`)

Not a consumer API. Required check-run name for this repository is `Self / CI`.

| File                  | `name:`             | Job ids                                                                                                                                                                                              | Purpose                                                                                             |
| --------------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `self-ci.yml`         | `Self / CI`         | `actionlint`, `zizmor`, `pinact`, `format`, `composites`, `tests`, `docs`, `e2e-rust`, `e2e-rust-minimal`, `e2e-bun`, `e2e-wasm`, `e2e-cross`, `e2e-publish-crates`, `e2e-hermes`, `scorecard`, `ci` | Lint the tree and run the `fixtures/` e2e jobs. Aggregator job `ci` has `name: Self / CI`.          |
| `self-release.yml`    | `Self / Release`    | `validate`, `release`, `retag`                                                                                                                                                                       | `on.push.tags: ['v*.*.*']`: validate annotated `vX.Y.Z` on `main`, `release.yml`, retag `v<major>`. |
| `self-stale.yml`      | `Self / Stale`      | `stale`                                                                                                                                                                                              | Cron `30 1 * * *` → `$/.github/workflows/ops-stale.yml`.                                            |
| `self-dependabot.yml` | `Self / Dependabot` | `merge`                                                                                                                                                                                              | `on: schedule` + `workflow_dispatch` → `$/.github/workflows/ops-dependabot.yml`.                    |
| `self-retag.yml`      | `Self / Retag`      | `retag`                                                                                                                                                                                              | Rollback only: force-move annotated `v<major>` to the input `vX.Y.Z` tag's commit.                  |

`scorecard` is `continue-on-error: true` and is not in the aggregator `needs`.

## Releasing

Push an annotated `vX.Y.Z` tag on a `main` commit:

```bash
git switch main && git pull --ff-only
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

`Self / Release` validates the tag (annotated, commit reachable from `origin/main`), publishes the GitHub Release, and force-moves `v<major>` to the release commit. Consumers pin `@v2` (moving) or `@v2.x.y` (immutable). Roll back a bad `v<major>` with `Self / Retag` (`tag` input: an existing `vX.Y.Z` tag).

## Compatibility aliases

Not a public API. Do not pin new callers here.

| File             | Forwards to     | Why it exists                                                                                          |
| ---------------- | --------------- | ------------------------------------------------------------------------------------------------------ |
| `stale.yml`      | `ops-stale.yml` | Unmigrated `uses: …/stale.yml@main` (qntx-labs). Missing file made those scheduled runs fail and mail. |
| `repo-stale.yml` | `ops-stale.yml` | Same for `uses: …/repo-stale.yml@main`.                                                                |
