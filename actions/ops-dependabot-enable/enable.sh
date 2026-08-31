#!/usr/bin/env bash
# Policy + GitHub merge. Sourced by test.sh (skip main).
set -euo pipefail

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

ops_dependabot_now() {
  if [ -n "${NOW_EPOCH:-}" ]; then
    printf '%s' "$NOW_EPOCH"
    return
  fi
  date +%s
}

# Prints age in seconds, or empty on parse failure.
ops_dependabot_age_seconds() {
  local created="$1"
  python3 -c '
import datetime, sys
raw = sys.argv[1].replace("Z", "+00:00")
created = datetime.datetime.fromisoformat(raw)
if created.tzinfo is None:
    created = created.replace(tzinfo=datetime.timezone.utc)
now = datetime.datetime.fromtimestamp(int(sys.argv[2]), datetime.timezone.utc)
print(int((now - created).total_seconds()))
' "$created" "$(ops_dependabot_now)" 2>/dev/null || true
}

# Highest version-update:semver-* in text, else empty.
ops_dependabot_parse_update_type() {
  local text="$1" t best= rank=0 r
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    r=0
    case "$t" in
      version-update:semver-major) r=3 ;;
      version-update:semver-minor) r=2 ;;
      version-update:semver-patch) r=1 ;;
      *) continue ;;
    esac
    if [ "$r" -gt "$rank" ]; then
      rank="$r"
      best="$t"
    fi
  done < <(printf '%s\n' "$text" | grep -oE 'version-update:semver-(patch|minor|major)' || true)
  printf '%s' "$best"
}

# Prints "merge" or "skip:<reason>" on stdout. Errors to stderr, return 2.
ops_dependabot_decide() {
  case "${ACTOR:-}" in
    'dependabot[bot]' | 'app/dependabot') ;;
    *)
      printf 'skip:actor %s\n' "${ACTOR:-}"
      return 0
      ;;
  esac

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

# JSON object or PR with .statusCheckRollup[].
# Ignore this workflow's checks so a pending merge job cannot deadlock the rollup.
ops_dependabot_others_json() {
  printf '%s' "$1" | jq -c '
    def ours:
      ((.workflowName // "") | test("dependabot"; "i"))
      or ((.name // "") | test("^(.* / )?merge$"));
    [.statusCheckRollup[]? | select(ours | not)]
  '
}

ops_dependabot_has_other_checks() {
  local others
  others="$(ops_dependabot_others_json "$1")"
  [ "$(printf '%s' "$others" | jq 'length')" -gt 0 ]
}

# 0 = every non-self check is a completed success/skipped/neutral (or there are none).
ops_dependabot_rollup_ok() {
  local others
  others="$(ops_dependabot_others_json "$1")"
  printf '%s' "$others" | jq -e '
    def ok:
      if (.__typename == "StatusContext") or (has("state") and (has("conclusion") | not)) then
        .state == "SUCCESS"
      else
        .status == "COMPLETED"
        and (.conclusion == "SUCCESS" or .conclusion == "SKIPPED" or .conclusion == "NEUTRAL")
      end;
    length == 0 or all(ok)
  ' >/dev/null
}

# $1 PR JSON. $2 optional raw commit/PR text used as update-type source.
# Prints merge | skip:* | wait:* . Return 2 only for caller config errors.
ops_dependabot_evaluate() {
  local pr="$1" text="${2:-}"

  if [ "$(printf '%s' "$pr" | jq -r '.isDraft // false')" = true ]; then
    echo 'skip:draft'
    return 0
  fi

  ACTOR="$(printf '%s' "$pr" | jq -r '.author.login // empty')"
  PR_LABELS="$(printf '%s' "$pr" | jq -r '[.labels[]?.name] | join(",")')"

  local mergeable state
  mergeable="$(printf '%s' "$pr" | jq -r '.mergeable // empty')"
  state="$(printf '%s' "$pr" | jq -r '.mergeStateStatus // empty')"
  case "$mergeable" in
    CONFLICTING)
      echo 'skip:conflicts'
      return 0
      ;;
  esac
  case "$state" in
    DIRTY)
      echo 'skip:dirty'
      return 0
      ;;
    BLOCKED | DRAFT)
      echo "skip:${state}"
      return 0
      ;;
  esac

  if [ -z "$text" ]; then
    text="$(printf '%s' "$pr" | jq -r '.body // empty')"
  fi
  UPDATE_TYPE="$(ops_dependabot_parse_update_type "$text")"

  local decision
  decision="$(ops_dependabot_decide)"
  case "$decision" in
    merge) ;;
    skip:*)
      printf '%s\n' "$decision"
      return 0
      ;;
    *)
      echo "ops-dependabot: unexpected decision '${decision}'" >&2
      return 2
      ;;
  esac

  if ! ops_dependabot_rollup_ok "$pr"; then
    echo 'wait:checks'
    return 0
  fi

  if ! ops_dependabot_has_other_checks "$pr"; then
    local created age grace
    created="$(printf '%s' "$pr" | jq -r '.createdAt // empty')"
    grace="${GRACE_SECONDS:-300}"
    age="$(ops_dependabot_age_seconds "$created")"
    if [ -z "$age" ] || [ "$age" -lt "$grace" ]; then
      echo 'wait:grace'
      return 0
    fi
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
  gh api graphql \
    -f query='mutation($id:ID!,$m:PullRequestMergeMethod!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:$m}){pullRequest{autoMergeRequest{enabledAt mergeMethod}}}}' \
    -f id="$PR_NODE_ID" \
    -f m="$method"
}

ops_dependabot_merge_now() {
  local n=0 out args
  # No --delete-branch: that flag also deletes a *local* git ref and this
  # action does not checkout. Pass --repo; GH_REPO is not enough inside gh
  # when there is no .git.
  args=(pr merge --repo "$GITHUB_REPOSITORY" --"${MERGE_METHOD}")
  if [ -n "${HEAD_OID:-}" ]; then
    args+=(--match-head-commit "$HEAD_OID")
  fi
  args+=("$PR_NUMBER")
  while true; do
    if out="$(gh "${args[@]}" 2>&1)"; then
      printf '%s\n' "$out"
      return 0
    fi
    if printf '%s\n' "$out" | grep -Eqi 'already merged'; then
      echo '::notice::ops-dependabot: already merged'
      return 0
    fi
    if printf '%s\n' "$out" | grep -Eqi 'head commit.*(do not match|did not match|mismatch)|match-head-commit'; then
      echo '::notice::ops-dependabot: head moved; next sweep will retry'
      return 0
    fi
    if printf '%s\n' "$out" | grep -Fq 'Base branch was modified'; then
      n=$((n + 1))
      if [ "$n" -ge 5 ]; then
        printf '%s\n' "$out"
        return 1
      fi
      echo "::notice::ops-dependabot: retry ${n}/5, base branch modified"
      sleep $((n * 2))
      continue
    fi
    printf '%s\n' "$out"
    return 1
  done
}

ops_dependabot_arm() {
  local out
  if [ -z "${PR_NODE_ID:-}" ]; then
    echo '::notice::ops-dependabot: no pull request node id; skip arm'
    return 0
  fi
  if out="$(ops_dependabot_enable 2>&1)"; then
    printf '%s\n' "$out"
    return 0
  fi
  if printf '%s\n' "$out" | grep -Eqi 'already enabled'; then
    echo '::notice::ops-dependabot: auto-merge already enabled'
    return 0
  fi
  # Without required checks GitHub will not queue auto-merge (UNSTABLE while
  # any optional check is pending, including this job). Not an error. The
  # schedule sweep squash-merges when the rollup is actually green.
  if printf '%s\n' "$out" | grep -Eqi 'unstable status|required protected branch rules|cannot be enabled|auto-?merge is not allowed|not enabled on this repository'; then
    echo '::notice::ops-dependabot: cannot queue auto-merge; schedule sweep will merge when green'
    return 0
  fi
  printf '%s\n' "$out"
  return 1
}

ops_dependabot_commit_message() {
  local oid="$1"
  gh api "repos/${GITHUB_REPOSITORY}/git/commits/${oid}" --jq .message
}

ops_dependabot_pr_messages() {
  local pr="$1" oid msg text=""
  text="$(printf '%s' "$pr" | jq -r '[.commits[]?.messageBody // empty] | join("\n")')"
  if [ -n "$(ops_dependabot_parse_update_type "$text")" ]; then
    printf '%s' "$text"
    return 0
  fi
  text=""
  while IFS= read -r oid; do
    [ -z "$oid" ] && continue
    [ "$oid" = null ] && continue
    msg="$(ops_dependabot_commit_message "$oid")"
    text="${text}${msg}"$'\n'
  done < <(printf '%s' "$pr" | jq -r '.commits[]?.oid // empty')
  printf '%s' "$text"
}

ops_dependabot_sweep_one() {
  local pr="$1" text result
  PR_NUMBER="$(printf '%s' "$pr" | jq -r '.number // empty')"
  HEAD_OID="$(printf '%s' "$pr" | jq -r '.commits[-1].oid // empty')"
  if [ -z "$PR_NUMBER" ]; then
    echo '::notice::ops-dependabot: skip PR with empty number'
    return 0
  fi
  text="$(ops_dependabot_pr_messages "$pr")"
  result="$(ops_dependabot_evaluate "$pr" "$text")"
  case "$result" in
    merge)
      echo "::notice::ops-dependabot: merging #${PR_NUMBER}"
      ops_dependabot_merge_now
      ;;
    skip:* | wait:*)
      echo "::notice::ops-dependabot: #${PR_NUMBER} ${result}"
      return 0
      ;;
    *)
      echo "ops-dependabot: unexpected evaluate '${result}'" >&2
      return 2
      ;;
  esac
}

ops_dependabot_sweep() {
  local n json fail=0
  if [ -z "${GITHUB_REPOSITORY:-}" ]; then
    echo 'ops-dependabot: GITHUB_REPOSITORY is empty' >&2
    return 2
  fi
  # Do not list statusCheckRollup/commits in one GraphQL query: 50 PRs exceeds
  # GitHub's 500k node cap. Number-only list, then one view per PR.
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    json="$(gh pr view "$n" --repo "$GITHUB_REPOSITORY" --json number,author,labels,isDraft,mergeStateStatus,mergeable,createdAt,statusCheckRollup,commits)"
    if ! ops_dependabot_sweep_one "$json"; then
      fail=1
    fi
  done < <(gh pr list --repo "$GITHUB_REPOSITORY" --state open --app dependabot --limit 50 --json number --jq '.[].number')
  return "$fail"
}

ops_dependabot_main() {
  local decision
  case "${EVENT_NAME:-pull_request}" in
    schedule | workflow_dispatch)
      ops_dependabot_sweep
      return
      ;;
  esac
  decision="$(ops_dependabot_decide)"
  case "$decision" in
    merge)
      ops_dependabot_arm
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
