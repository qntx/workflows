# Release asset naming contract

`contract/release-assets.json` is the machine-readable, producer-side naming
contract for the GitHub Release assets that `release-rust.yml` publishes.
Installers such as qntx/sh parse those names, so the grammar is specified
once here and enforced in self-CI instead of being re-derived per consumer.

## Grammar

```text
<bin>-<version>[-<variant>]-<target>.<ext>
```

- `<bin>` — the binary name, `^[A-Za-z0-9][A-Za-z0-9_-]*$`.
- `<version>` — the tag without its leading `v`,
  `^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$`.
- `<variant>` — optional feature variant, `^[a-z][a-z0-9]*$`.
- `<target>` — one of the contract triples below.
- `<ext>` — the target's archive extension, or a sidecar suffix below.

Everything after `<bin>-<version>-` is inside the release's namespace.
Names outside it are ignored; `SHA256SUMS` is the one such name the contract
defines.

## Targets and archive extensions

| Triple                       | Archive  |
| ---------------------------- | -------- |
| `x86_64-unknown-linux-gnu`   | `tar.gz` |
| `aarch64-unknown-linux-gnu`  | `tar.gz` |
| `x86_64-unknown-linux-musl`  | `tar.gz` |
| `aarch64-unknown-linux-musl` | `tar.gz` |
| `aarch64-apple-darwin`       | `tar.gz` |
| `x86_64-pc-windows-msvc`     | `zip`    |
| `aarch64-pc-windows-msvc`    | `zip`    |

## Sidecars

- `<name>.sha256` — required for every archive: one sha256sum text-mode line
  (64 lowercase hex digits, two spaces, the bare archive name, newline).
- `<name>.cdx.json` — optional CycloneDX SBOM of the binary in the matching
  archive. Named after `<bin>-<version>[-<variant>]-<target>`, never after
  the archive extension, and it carries no `.sha256` sidecar of its own.

## Parse rules

A consumer parses a name only together with the expected `<bin>` and
`<version>`:

1. `SHA256SUMS` is the aggregate checksum file.
2. Any other name that does not start with `<bin>-<version>-` is outside the
   namespace and is ignored (another binary or another version).
3. Inside the namespace, strip the prefix, then the suffix: `.cdx.json`
   (sbom), `.<archive>.sha256` (sha256), or `.<archive>` (archive).
4. The remaining stem is `<target>` or `<variant>-<target>`; `<target>` is a
   listed triple matched as a suffix with a `-` boundary.
5. `<archive>` must be the extension listed for that target.

Drift policy: a name inside the namespace that does not parse is naming
drift, not a skippable extra — fail loudly. In a release dist directory,
every file must parse or be `SHA256SUMS`.

## Archive layout

The `layout` key lists where the binary may sit inside an archive, where
`<stem>` is the archive name without its extension. The flat layout —
`./<bin>` in a `.tar.gz`, `<bin>.exe` at the root of a `.zip`, with any
`LICENSE*` / `README*` files beside it — is what `release-rust.yml`
produces and is the canonical form. The single-top-level-directory layout
(`<stem>/<bin>`, `<stem>/<bin>.exe`) is accepted by consumers only for
releases made outside `release-rust.yml`, such as qntx/nosfry v0.4.0's
hand-written pipeline; `release-rust.yml` never emits it, and the self-CI
drift test fails if its Package step stops producing the canonical layout.
The binary member must be a regular file, with no link entries, absolute
paths or `..` components.

## Versioning

The `version` field in the JSON bumps on breaking grammar changes. Adding a
triple is additive, but consumers must ship the new triple before producers
publish assets for it — an unknown triple is drift, not a warning.

## Canonical copy

This repository owns the contract. `contract/release-assets.json` is
byte-identical to qntx/sh's `apps/sh/contract/release-assets.json` — check
with `cmp` — and `.prettierignore` excludes it from Prettier for that
reason (Prettier would collapse the `layout.members` arrays). After editing
here, sync there and verify:

```sh
gh api repos/qntx/sh/contents/apps/sh/contract/release-assets.json --jq .content | base64 -d | cmp - contract/release-assets.json
```

`contract/release-assets.ts` is the reference parser and CLI
(`check --bin <bin> --version <version> <file-or-name>...`, `triples`), and
the self-CI e2e jobs run it over every real release asset set.
