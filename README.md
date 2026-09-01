<!-- markdownlint-disable MD033 MD041 MD036 -->

# Workflows

Reusable GitHub Actions workflows for QuantX repositories.

The public contract is only `.github/workflows/*.yml` with `on.workflow_call`. The caller owns `on:` (push, pull_request, tags, schedule). `actions/` is private implementation; do not `uses:` it from other repositories.

Pin CI and ops `uses:` at `@v2`. Pin publish, release, and deploy at `@v2.0.0`.

Hardening in every public workflow:

- Job-level permissions (union at workflow top-level).
- Third-party `uses:` pinned to `owner/repo@<40-char-sha> # vX.Y.Z`.
- Same-repository references use `$/` with no `@ref`.
- `actions/checkout` via `$/actions/hardened-checkout` with `persist-credentials: false` unless the job pushes.
- Explicit `timeout-minutes` on every concrete job.
- CI cancels in-flight runs; publish / release / deploy / ops do not. `ops-dependabot` cancels overlapping sweeps.

## Catalogue

See [docs/CATALOGUE.md](docs/CATALOGUE.md) for `name:`, job ids, and inputs. Permissions: [docs/CONSUMERS.md](docs/CONSUMERS.md). Cutover: [docs/MIGRATION.md](docs/MIGRATION.md). Copy-paste callers: [examples/](examples/).

### CI

| Workflow         | Purpose                                                                                   |
| ---------------- | ----------------------------------------------------------------------------------------- |
| `ci-bun.yml`     | Bun install / lint / typecheck / build / test. `bun-version` default `1.4`, not `latest`. |
| `ci-foundry.yml` | Forge `fmt --check` / `build --sizes` / `test -vvv`. Profile default `ci`.                |
| `ci-go.yml`      | `go mod tidy` drift check, `vet`, optional golangci-lint, race tests.                     |
| `ci-node.yml`    | Matrix across Node versions. `package-manager` is `npm` / `pnpm` / `yarn`, not detected.  |
| `ci-python.yml`  | uv install, ruff + pytest. `pyproject.toml` or `requirements.txt`.                        |
| `ci-rust.yml`    | `fmt` / `clippy -D warnings` / `build` / `test`. Optional apt and `deny` (cargo-deny).    |

CI job id is `ci`. Version inputs are `{tool}-version` (`rust-version`, `node-version`, …). `submodules` defaults to `false`. Foundry repos with `lib/` as a git submodule must pass `submodules: true`.

### Publish

| Workflow                | Purpose                                                                                                        |
| ----------------------- | -------------------------------------------------------------------------------------------------------------- |
| `publish-npm.yml`       | npm / pnpm / yarn / bun. Workspace install at `install-directory`; publish one package at `working-directory`. |
| `publish-pypi.yml`      | Empty `PYPI_TOKEN` → OIDC + attestations. Token path never attestations.                                       |
| `publish-crates.yml`    | `cargo publish --locked`, skip-if-exists, 429 retry. `CARGO_REGISTRY_TOKEN` required.                          |
| `publish-container.yml` | Dual-arch OCI push, SBOM, provenance. `attest` default `true`.                                                 |

Publish job id is `publish`. `publish-container.yml` splits mutually exclusive `build` (`push: false`) and `publish` (`push: true`) jobs.

### Release

| Workflow           | Purpose                                                                                            |
| ------------------ | -------------------------------------------------------------------------------------------------- |
| `release.yml`      | Tag → GitHub Release with git-cliff. Optional asset glob / artifact download.                      |
| `release-rust.yml` | Five-target binary matrix, then GitHub Release. `jobs.build.name` is `Build ${{ matrix.target }}`. |

### Deploy

| Workflow            | Purpose                                                                 |
| ------------------- | ----------------------------------------------------------------------- |
| `deploy-pages.yml`  | Bun build + `actions/deploy-pages`. Pull requests run `build` only.     |
| `deploy-mkdocs.yml` | uv-installed MkDocs via `mkdocs gh-deploy --force` (pushes `gh-pages`). |

### Ops

| Workflow             | Purpose                                                            |
| -------------------- | ------------------------------------------------------------------ |
| `ops-stale.yml`      | `actions/stale`. `workflow_call` only; the caller owns `schedule`. |
| `ops-sync.yml`       | Mirror a folder from another repository. Secret `SYNC_TOKEN`.      |
| `ops-dependabot.yml` | Schedule squash-merge when green. No auto-merge arm.               |

### This repository only

Do not `uses:` these from other repositories.

| Workflow              | Purpose                                                                 |
| --------------------- | ----------------------------------------------------------------------- |
| `self-ci.yml`         | actionlint, zizmor, pinact, format, composite tests.                    |
| `self-release.yml`    | Annotated `v*.*.*` tags → `release.yml`.                                |
| `self-stale.yml`      | This repository's stale cron.                                           |
| `self-dependabot.yml` | Auto-merge this repository's Dependabot PRs.                            |
| `self-retag.yml`      | Post-squash operator: force-move annotated `v<major>` to `origin/main`. |

## Usage

Pin CI and ops at `@v2`. Pin publish, release, and deploy at `@v2.0.0`.

```yaml
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  ci:
    uses: qntx/workflows/.github/workflows/ci-node.yml@v2
    with:
      node-versions: '["22", "24"]'
      package-manager: npm
```

```yaml
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  ci:
    uses: qntx/workflows/.github/workflows/ci-foundry.yml@v2
    with:
      submodules: true
      # foundry-profile defaults to ci; set default if foundry.toml has no [profile.ci].
```

```yaml
on:
  push:
    tags: ['v*.*.*']

permissions:
  contents: read
  id-token: write

jobs:
  publish:
    uses: qntx/workflows/.github/workflows/publish-npm.yml@v2.0.0
```

```yaml
on:
  push:
    tags: ['v*.*.*']

permissions:
  contents: write

jobs:
  release:
    uses: qntx/workflows/.github/workflows/release.yml@v2.0.0
```

```yaml
on:
  push:
    branches: [main]

permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  deploy:
    uses: qntx/workflows/.github/workflows/deploy-pages.yml@v2.0.0
    with:
      path: dist
```

Caller job permissions are intersected with the callee. Token-only npm/PyPI does not need `id-token`. OIDC publish and Pages deploy do. Exact blocks: [docs/CONSUMERS.md](docs/CONSUMERS.md).

## License

This project is licensed under the [MIT License](LICENSE).

---

<div align="center">

A **[QuantX](https://qntx.org)** open-source project.

<a href="https://qntx.org"><img alt="QuantX" width="369" src="https://raw.githubusercontent.com/qntx/.github/main/profile/qntx.svg" /></a>

Code is law. We write both.

</div>
