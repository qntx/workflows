# Security Policy

This repository is QuantX's reusable GitHub Actions platform. Downstream
repositories invoke files under `.github/workflows/` with
`uses: qntx/workflows/.github/workflows/<file>.yml@<ref>`. Composite actions
under `actions/` are private implementation, not a second public API.

The assets at risk are consumer `GITHUB_TOKEN`s, mapped secrets (registry
tokens, sync tokens), and the CI/CD of every repository that calls these
workflows. This is not a blockchain or smart-contract project.

## Threat model

In scope for this repository:

- **Poisoned default branch.** A change on `main` runs in every consumer that
  tracks a moving ref (`@main` or a moving major tag), with that consumer's
  token and secrets.
- **Unpinned third-party actions.** `uses: owner/repo@<tag-or-branch>` can be
  retagged. Third-party `uses:` in this repository must be
  `owner/repo@<40-character-sha>` with a `# vX.Y.Z` (or branch) comment.
- **Script injection.** Untrusted values (`inputs.*`, `github.*`, `matrix.*`)
  expanded inside `run:` bodies, `GITHUB_ENV`, or shell `eval`. Values belong
  in `env:` and `"$VAR"`; same-repository composites use `$/` with no `@ref`.
- **Credential and path abuse.** Checkout with persisted credentials on jobs
  that do not push; sync jobs that can write `.github/` or `.git` in a
  consumer worktree.

Out of scope:

- Vulnerabilities in third-party actions we pin (report those upstream).
- Consumer-side misconfiguration (missing job `permissions:`, publish jobs
  tracking `@main`).
- Organization GitHub settings (rulesets, secret scanning, Actions review
  policy). Those are operations, not this file.

## Supported versions

Security fixes land on `main`. Historical `v1` / `v1.0.0` tags are
unsupported. Immutable SemVer tags of the current major, once published,
receive fixes as patch releases on that major.

Consumers that pin a moving ref (`@main`, moving major tags) consume every
subsequent commit. Pin a commit SHA or an immutable `vX.Y.Z` tag when the
blast radius of a workflow change matters.

## Reporting a vulnerability

Report privately via [GitHub Security Advisories][advisory] for this
repository, or email [`gitctrlx@gmail.com`][email] if that is more suitable.

**Do not** file public GitHub issues, discussions, or pull requests for
unfixed vulnerabilities.

There is no bug bounty. We will work with reporters to handle findings.

Include as much of the following as you can:

- Kind of issue (for example: poisoned workflow, unpinned action, `run:`
  injection, over-broad `permissions`, path overwrite)
- Full paths of the affected workflow or composite
- Location (tag, branch, commit, or URL)
- Consumer `uses:` ref and any inputs/secrets required to reproduce
- Step-by-step reproduction
- Proof of concept (if available)
- Impact: which consumer tokens or registries an attacker could reach

We aim to acknowledge reports within 3 working days. Confirmed issues get a
GitHub Security Advisory. This project follows a 90-day disclosure timeline.

Questions about reporting: [`gitctrlx@gmail.com`][email].

[advisory]: https://github.com/qntx/workflows/security/advisories/new
[email]: mailto:gitctrlx@gmail.com
