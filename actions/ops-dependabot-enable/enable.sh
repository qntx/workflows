#!/usr/bin/env bash
# Policy + enablePullRequestAutoMerge. Sourced by test.sh (skip main).
set -euo pipefail

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Prints "merge" or "skip:<reason>" on stdout. Errors to stderr, return 2.
ops_dependabot_decide() {
  if [ "${ACTOR:-}" != 'dependabot[bot]' ]; then
    echo 'ops-dependabot: actor is not dependabot[bot]' >&2
    return 2
  fi

  case "${MERGE_METHOD:-}" in
    squash | merge | rebase) ;;
    *)
      echo "ops-dependabot: merge-method must be squash, merge, or rebase" >&2
      return 2
      ;;
  esac

  if [ -n "${EXEMPT_LABELS:-}" ] && [ -n "${PR_LABELS:-}" ]; then
    local raw_e e raw_h h
    local -a exempt have
    IFS=',' read -ra exempt <<<"$EXEMPT_LABELS"
    IFS=',' read -ra have <<<"$PR_LABELS"
    for raw_e in "${exempt[@]}"; do
      e="$(trim "$raw_e")"
      [ -z "$e" ] && continue
      for raw_h in "${have[@]}"; do
        h="$(trim "$raw_h")"
        if [ -n "$h" ] && [ "$h" = "$e" ]; then
          printf 'skip:exempt-label %s\n' "$e"
          return 0
        fi
      done
    done
  fi

  local allowed=0
  case "${UPDATE_TYPE:-}" in
    version-update:semver-patch)
      [ "${ALLOW_PATCH:-}" = true ] && allowed=1
      ;;
    version-update:semver-minor)
      [ "${ALLOW_MINOR:-}" = true ] && allowed=1
      ;;
    version-update:semver-major)
      [ "${ALLOW_MAJOR:-}" = true ] && allowed=1
      ;;
    *)
      printf 'skip:unhandled-update-type %s\n' "${UPDATE_TYPE:-}"
      return 0
      ;;
  esac

  if [ "$allowed" -ne 1 ]; then
    printf 'skip:update-type-disabled %s\n' "$UPDATE_TYPE"
    return 0
  fi

  printf 'merge\n'
}

ops_dependabot_enable() {
  local method
  method="$(printf '%s' "$MERGE_METHOD" | tr '[:lower:]' '[:upper:]')"
  if [ -z "${PR_NODE_ID:-}" ]; then
    echo 'ops-dependabot: PR_NODE_ID is empty' >&2
    return 2
  fi
  # enablePullRequestAutoMerge, not mergePullRequest. gh pr merge --auto
  # calls mergePullRequest when GitHub already considers the PR mergeable
  # (no required checks), which races a stale merge SHA.
  gh api graphql \
    -f query='mutation($id:ID!,$m:PullRequestMergeMethod!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:$m}){pullRequest{autoMergeRequest{enabledAt mergeMethod}}}}' \
    -f id="$PR_NODE_ID" \
    -f m="$method"
}

ops_dependabot_main() {
  local decision
  decision="$(ops_dependabot_decide)"
  case "$decision" in
    merge)
      local out
      if out="$(ops_dependabot_enable 2>&1)"; then
        printf '%s\n' "$out"
        return 0
      fi
      if printf '%s\n' "$out" | grep -Eqi 'already enabled|Pull request Auto merge is already enabled'; then
        echo '::notice::ops-dependabot: auto-merge already enabled'
        return 0
      fi
      printf '%s\n' "$out"
      return 1
      ;;
    skip:*)
      echo "::notice::ops-dependabot: ${decision#skip:}"
      return 0
      ;;
    *)
      echo "ops-dependabot: unexpected decision '${decision}'" >&2
      return 2
      ;;
  esac
}

if [ "${OPS_DEPENDABOT_SOURCE:-}" != 1 ]; then
  ops_dependabot_main
fi
