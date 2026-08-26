# Migration

No shims. Old filenames are deleted. Change every `uses:` in the same window. Pin the new path at `@<sha>` (40-character commit of this repository). Do not pin a moving major tag that has not been created.

## File mapping

| Old                           | New                           | `with` / `secrets`                                                                                                    | Caller `permissions`                                                                 | Required check-run                                                                                    |
| ----------------------------- | ----------------------------- | --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| `ci-rust.yml@main`            | `ci-rust.yml@<sha>`           | Keep `submodules: true` where used. `toolchain` → `rust-version`.                                                     | `contents: read`                                                                     | `ci / build` → `ci / ci`                                                                              |
| `ci-bun.yml@main`             | `ci-bun.yml@<sha>`            | Default `bun-version` is `1.4`. Do not pass `latest`.                                                                 | `contents: read`                                                                     | `ci / build` → `ci / ci`                                                                              |
| `ci-foundry.yml@main`         | `ci-foundry.yml@<sha>`        | **Required `submodules: true`** when `lib/` is a submodule. Add `[profile.ci]` or pass `foundry-profile: default`.    | `contents: read`                                                                     | `ci / Foundry project` → `ci / ci`                                                                    |
| `ci-node.yml@main`            | `ci-node.yml@<sha>`           | `package-manager` default `npm`. Not auto-detected.                                                                   | `contents: read`                                                                     | `ci / build` → `ci / ci`                                                                              |
| `python.yml@main`             | `ci-python.yml@<sha>`         | `python-version: '3.13'` still valid.                                                                                 | `contents: read`                                                                     | `call-ci / build` → `call-ci / ci`                                                                    |
| `publish-crates.yml@main`     | `publish-crates.yml@<sha>`    | `packages` / `timeout-minutes` kept. `toolchain` → `rust-version`.                                                    | `contents: read` + `CARGO_REGISTRY_TOKEN`                                            | `publish / Build, Test & Publish` → `publish / publish`                                               |
| `publish-npm.yml@main`        | `publish-npm.yml@<sha>`       | Unchanged filename. OIDC callers must grant `id-token: write`.                                                        | OIDC: `contents: read` + `id-token: write`. Token: `contents: read`.                 | `publish / Build & Publish` → `publish / publish`                                                     |
| `publish-npm-bun.yml@main`    | `publish-npm.yml@<sha>`       | **`package-manager: bun`**.                                                                                           | OIDC: must add `id-token: write`.                                                    | `publish / Build & Publish` → `publish / publish`                                                     |
| `python-publish.yml@main`     | `publish-pypi.yml@<sha>`      | Secret id **`PYPI_TOKEN`** (repo may dual-write the old secret).                                                      | Token-only: `contents: read`. OIDC: add `id-token` + `attestations`.                 | `call-publish / Build & Publish` → `call-publish / publish`                                           |
| `publish-pypi.yml@main`       | `publish-pypi.yml@<sha>`      | `PYPI_API_TOKEN` → `PYPI_TOKEN`.                                                                                      | Same as row above.                                                                   | `publish / Build & Publish` → `publish / publish`                                                     |
| `docker.yml@main`             | `publish-container.yml@<sha>` | Keep `no-cache: true`. Suggest `platforms: linux/amd64`. No OIDC → **`attest: false`**.                               | `contents: read` + `packages: write`; attest also needs `id-token` + `attestations`. | `docker / build` → `docker / publish`                                                                 |
| `container-build.yml@main`    | `publish-container.yml@<sha>` | Secrets `registry-username` / `registry-password` → `REGISTRY_USERNAME` / `REGISTRY_PASSWORD`. `attest` default true. | Same as docker row.                                                                  | `build / build` → `{job} / publish` (default `push: true`)                                            |
| `release.yml@main`            | `release.yml@<sha>`           | None required.                                                                                                        | `contents: write`                                                                    | `release / release`                                                                                   |
| `release-rust.yml@main`       | `release-rust.yml@<sha>`      | `bin` / `package` / `cross-*` kept. `toolchain` → `rust-version`.                                                     | `contents: write`                                                                    | Matrix `release / Build <target>` unchanged. `release / Publish GitHub Release` → `release / release` |
| `deploy-pages.yml@main`       | `deploy-pages.yml@<sha>`      | `bun-version` default `1.4`.                                                                                          | `contents: read` + `pages: write` + `id-token: write`                                | `deploy / build` and `deploy / deploy`                                                                |
| `deploy-mkdocs.yml@main`      | `deploy-mkdocs.yml@<sha>`     | None required.                                                                                                        | `contents: write`                                                                    | `deploy / deploy`                                                                                     |
| `repo-stale.yml@main`         | `ops-stale.yml@<sha>`         | None required. Caller owns `schedule`.                                                                                | `issues: write` + `pull-requests: write`                                             | `{caller-job} / stale`                                                                                |
| `stale.yml@main`              | `ops-stale.yml@<sha>`         | None required. openai-python caller job id is `close-stale`.                                                          | Same as repo-stale.                                                                  | `close-stale / stale` (openai-python); other repos: `{caller-job} / stale`                            |
| `repo-sync-folder.yml@main`   | `ops-sync.yml@<sha>`          | Secret `token` → `SYNC_TOKEN` (omit to use `github.token`).                                                           | `contents: write`                                                                    | `sync / sync`                                                                                         |
| `gen-openapi-client.yml@main` | **deleted**                   | No replacement. No `gen-` prefix.                                                                                     | —                                                                                    | —                                                                                                     |

## Breaking input and secret renames

| Old                                            | New                                                                           |
| ---------------------------------------------- | ----------------------------------------------------------------------------- |
| `toolchain`                                    | `rust-version` (`ci-rust`, `publish-crates`, `release-rust`)                  |
| `sdk`                                          | `dart-version`                                                                |
| `PYPI_API_TOKEN`                               | `PYPI_TOKEN`                                                                  |
| `token` (`repo-sync-folder`)                   | `SYNC_TOKEN`                                                                  |
| `registry-username` / `registry-password`      | `REGISTRY_USERNAME` / `REGISTRY_PASSWORD`                                     |
| `publish-npm-bun.yml`                          | `publish-npm.yml` + `package-manager: bun`                                    |
| `foundry-profile` default `default`            | default `ci`                                                                  |
| C++ / Foundry implicit `submodules: recursive` | `submodules: false`. Foundry `lib/` callers **must** pass `submodules: true`. |
| Node package manager auto-detect               | `package-manager` default `'npm'`                                             |
| `bun-version: latest`                          | default `'1.4'`                                                               |
| `docker.yml` single-arch amd64                 | `publish-container.yml` default `linux/amd64,linux/arm64`, `attest: true`     |
| CI job id `build` / `check`                    | `ci`                                                                          |
| Callee `jobs.<id>.name` display strings        | unset (check-run right half is the job id)                                    |

## Deleted names (not restored)

`python.yml`, `python-publish.yml`, `docker.yml`, `publish-npm-bun.yml`, `container-build.yml`, `gen-openapi-client.yml`, `repo-stale.yml`, `stale.yml`, `repo-sync-folder.yml`, plus historical `bun.yml`, `c-cpp.yml`, `foundry.yml`, `go.yml`, `node.js.yml`, `dart.yml`, `npm-publish.yml`, `bun-publish.yml`, `rust.yml`, `rust-publish.yml`, `rust-cd.yml`, `github-pages.yml`, `sync-repo-folder.yml`.

## Post-cutover scan

```bash
gh search code --owner qntx 'qntx/workflows/.github/workflows' --limit 200
```

Must not reappear: `python.yml`, `docker.yml`, `publish-npm-bun.yml`, `container-build.yml`, `repo-stale.yml`, `stale.yml@`, `repo-sync-folder.yml`, `gen-openapi`.
