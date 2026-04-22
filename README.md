<!-- markdownlint-disable MD033 MD041 MD036 -->

# Workflows

Reusable GitHub Actions workflows distributed across QNTX repositories.

All workflows are invoked via `workflow_call` and share a common hardening baseline:

- Minimal top-level `permissions` (`contents: read` by default).
- Explicit `concurrency` groups (CI cancels in-flight runs, CD/Publish/Release/Deploy queue).
- Explicit `timeout-minutes` on every job.
- `actions/checkout` runs with `persist-credentials: false` unless a push is required.
- Third-party actions pinned to major tags and auto-updated by Dependabot.

## Catalogue

### CI (continuous integration)

| Workflow         | Purpose                                                                                   |
| ---------------- | ----------------------------------------------------------------------------------------- |
| `ci-bun.yml`     | Bun install/lint/build/test for monorepo-aware Bun projects.                              |
| `ci-cpp.yml`     | CMake + ccache build with optional ctest, parameterised apt packages.                     |
| `ci-dart.yml`    | `dart format`/`analyze --fatal-infos`/`test`.                                             |
| `ci-foundry.yml` | Foundry `fmt --check`/`build --sizes`/`test -vvv` with the `ci` profile.                  |
| `ci-go.yml`      | `go mod tidy` drift check, `vet`, optional `golangci-lint`, race tests.                   |
| `ci-node.yml`    | Matrix build across configurable Node.js versions; npm/pnpm/yarn auto-detect.             |
| `ci-python.yml`  | `uv`-powered install with ruff + pytest; supports `pyproject.toml` or `requirements.txt`. |
| `ci-rust.yml`    | `fmt`/`clippy -D warnings`/`build`/`test` with `Swatinem/rust-cache`.                     |

### Publish (package registries)

| Workflow              | Purpose                                                                             |
| --------------------- | ----------------------------------------------------------------------------------- |
| `publish-npm.yml`     | npm OIDC Trusted Publishing with provenance; falls back to `NPM_TOKEN` if supplied. |
| `publish-npm-bun.yml` | Same as above but builds and tests with Bun.                                        |
| `publish-pypi.yml`    | PyPI OIDC Trusted Publishing with attestations via `pypa/gh-action-pypi-publish`.   |
| `publish-crates.yml`  | `cargo publish` with sparse-index polling (no hard-coded sleep).                    |

### Release (GitHub Release + changelog)

| Workflow           | Purpose                                                                                                                                                 |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `release.yml`      | Generic tag → GitHub Release with `git-cliff` changelog. Optional asset upload via `files` glob or `download-artifacts`. Suitable for any repository.   |
| `release-rust.yml` | Cross-platform Rust binary matrix (Linux x86_64/arm64, macOS arm64, Windows x86_64/arm64) with `git-cliff` changelog and `softprops/action-gh-release`. |

### Deploy (hosted sites)

| Workflow            | Purpose                                                                      |
| ------------------- | ---------------------------------------------------------------------------- |
| `deploy-pages.yml`  | Bun build + `actions/deploy-pages` for SPA/static sites. PR runs build only. |
| `deploy-mkdocs.yml` | `uv`-installed MkDocs deployed via `mkdocs gh-deploy --force`.               |

### Containers

| Workflow              | Purpose                                                                                                                                                     |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `container-build.yml` | Multi-arch (linux/amd64, linux/arm64) OCI build with SBOM, provenance, and `actions/attest-build-provenance`. Auto-detects `Dockerfile` or `Containerfile`. |

### Code generation

| Workflow                 | Purpose                                                                                                                                        |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `gen-openapi-client.yml` | Unified OpenAPI client generator. Select via `generator` input (`go`, `python`, `rust`, `typescript-axios`, `dart-dio`, `c`, `cpp-qt-client`). |

### Repository tooling

| Workflow               | Purpose                                                              |
| ---------------------- | -------------------------------------------------------------------- |
| `repo-stale.yml`       | Closes stale issues/PRs via `actions/stale`.                         |
| `repo-sync-folder.yml` | Mirrors a folder from another repository with protected-path guards. |

## Usage

Invoke a workflow from any consumer repository via `uses:`:

```yaml
jobs:
  ci:
    uses: qntx/workflows/.github/workflows/ci-node.yml@main
    with:
      node-versions: '["22", "24"]'
```

```yaml
jobs:
  deploy:
    uses: qntx/workflows/.github/workflows/deploy-pages.yml@main
    with:
      path: dist
```

```yaml
jobs:
  publish:
    uses: qntx/workflows/.github/workflows/publish-npm.yml@main
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }} # optional, OIDC is used when omitted
```

```yaml
jobs:
  regen-go:
    uses: qntx/workflows/.github/workflows/gen-openapi-client.yml@main
    with:
      generator: go
      spec-path: apis/spec/openapi.yaml
      client-repo: qntx/my-api-go
      package-name: my-api
    secrets:
      PAT_TOKEN: ${{ secrets.PAT_TOKEN }}
```

A generic tag-triggered release (works for docs, libraries, contracts, anything):

```yaml
on:
  push:
    tags: ['v*']

jobs:
  release:
    uses: qntx/workflows/.github/workflows/release.yml@main
    # Optional: attach build outputs to the release.
    # with:
    #   files: |
    #     dist/*.tar.gz
    #     dist/*.whl
```

See each workflow's `inputs:` and `secrets:` blocks for the full parameter list.

## License

This project is licensed under the [MIT License](LICENSE).

---

<div align="center">

A **[QNTX](https://qntx.fun)** open-source project.

<a href="https://qntx.fun"><img alt="QNTX" width="369" src="https://raw.githubusercontent.com/qntx/.github/main/profile/qntx-banner.svg" /></a>

<!--prettier-ignore-->
Code is law. We write both.

</div>
