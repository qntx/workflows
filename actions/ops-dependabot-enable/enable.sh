#!/usr/bin/env bash
# Policy + GitHub merge. Sourced by test.sh (skip sweep).
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

# Highest version-update:semver-* or version-update:lockfile-only in text, else empty.
ops_dependabot_parse_update_type() {
  local text="$1" t best= rank=0 r
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    r=0
    case "$t" in
      version-update:semver-major) r=3 ;;
      version-update:semver-minor) r=2 ;;
      version-update:semver-patch) r=1 ;;
      version-update:lockfile-only) r=1 ;;
      *) continue ;;
    esac
    if [ "$r" -gt "$rank" ]; then
      rank="$r"
      best="$t"
    fi
  done < <(printf '%s\n' "$text" | grep -oE 'version-update:(semver-(patch|minor|major)|lockfile-only)' || true)
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
    version-update:semver-patch | version-update:lockfile-only)
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

  case "$state" in
    BEHIND)
      echo 'wait:behind'
      return 0
      ;;
    UNKNOWN)
      echo 'wait:unknown'
      return 0
      ;;
  esac

  if ! ops_dependabot_rollup_ok "$pr"; then
    echo 'wait:checks'
    return 0
  fi

  if ! ops_dependabot_has_other_checks "$pr"; then
    local created age grace
    created="$(printf '%s' "$pr" | jq -r '.createdAt // empty')"
    grace="${GRACE_SECONDS:-900}"
    age="$(ops_dependabot_age_seconds "$created")"
    if [ -z "$age" ] || [ "$age" -lt "$grace" ]; then
      echo 'wait:grace'
      return 0
    fi
  fi

  printf 'merge\n'
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
  OPS_DEPENDABOT_OUTCOME=fail
  PR_NUMBER="$(printf '%s' "$pr" | jq -r '.number // empty')"
  HEAD_OID="$(printf '%s' "$pr" | jq -r '.commits[-1].oid // empty')"
  if [ -z "$PR_NUMBER" ]; then
    echo '::notice::ops-dependabot: skip PR with empty number'
    OPS_DEPENDABOT_OUTCOME=skip
    return 0
  fi
  text="$(ops_dependabot_pr_messages "$pr")"
  result="$(ops_dependabot_evaluate "$pr" "$text")"
  case "$result" in
    merge)
      echo "::notice::ops-dependabot: merging #${PR_NUMBER}"
      if ops_dependabot_merge_now; then
        OPS_DEPENDABOT_OUTCOME=merge
        return 0
      fi
      OPS_DEPENDABOT_OUTCOME=fail
      return 1
      ;;
    skip:*)
      echo "::notice::ops-dependabot: #${PR_NUMBER} ${result}"
      OPS_DEPENDABOT_OUTCOME=skip
      return 0
      ;;
    wait:checks | wait:grace | wait:behind | wait:unknown)
      echo "::notice::ops-dependabot: #${PR_NUMBER} ${result}"
      OPS_DEPENDABOT_OUTCOME=$result
      return 0
      ;;
    *)
      echo "ops-dependabot: unexpected evaluate '${result}'" >&2
      OPS_DEPENDABOT_OUTCOME=fail
      return 2
      ;;
  esac
}

ops_dependabot_is_rollup_forbidden() {
  printf '%s' "$1" | grep -Fq 'Resource not accessible by integration' \
    && printf '%s' "$1" | grep -Fq 'statusCheckRollup'
}

ops_dependabot_forbidden_scope() {
  case "$1" in
    *StatusContext* | *statusContext*) printf 'statuses\n' ;;
    *workflowRun*) printf 'actions\n' ;;
    *) printf 'checks\n' ;;
  esac
}

ops_dependabot_sweep() {
  local n json errfile err scope
  local c_merge=0 c_wait_checks=0 c_wait_grace=0 c_wait_behind=0 c_wait_unknown=0 c_skip=0 c_fail=0
  if [ -z "${GITHUB_REPOSITORY:-}" ]; then
    echo 'ops-dependabot: GITHUB_REPOSITORY is empty' >&2
    return 2
  fi
  errfile="$(mktemp)"
  trap "rm -f '$errfile'" EXIT
  # Do not list statusCheckRollup/commits in one GraphQL query: 50 PRs exceeds
  # GitHub's 500k node cap. Number-only list, then one view per PR.
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    if json="$(gh pr view "$n" --repo "$GITHUB_REPOSITORY" \
        --json number,author,labels,isDraft,mergeStateStatus,mergeable,createdAt,statusCheckRollup,commits \
        2>"$errfile")"; then
      OPS_DEPENDABOT_OUTCOME=fail
      ops_dependabot_sweep_one "$json" || true
      case "${OPS_DEPENDABOT_OUTCOME}" in
        merge) c_merge=$((c_merge + 1)) ;;
        wait:checks) c_wait_checks=$((c_wait_checks + 1)) ;;
        wait:grace) c_wait_grace=$((c_wait_grace + 1)) ;;
        wait:behind) c_wait_behind=$((c_wait_behind + 1)) ;;
        wait:unknown) c_wait_unknown=$((c_wait_unknown + 1)) ;;
        skip) c_skip=$((c_skip + 1)) ;;
        *) c_fail=$((c_fail + 1)) ;;
      esac
    else
      err="$(cat "$errfile")"
      if ops_dependabot_is_rollup_forbidden "$err"; then
        scope="$(ops_dependabot_forbidden_scope "$err")"
        echo "ops-dependabot: #${n} GraphQL 403 on statusCheckRollup (need ${scope}: read); grant checks: read, actions: read (and statuses: read iff the path names StatusContext) on the caller job and the callee (workflow_call token is the intersection)" >&2
        echo "ops-dependabot: #${n} ${err}" >&2
      else
        echo "ops-dependabot: #${n} gh pr view failed: ${err}" >&2
      fi
      c_fail=$((c_fail + 1))
      continue
    fi
  done < <(gh pr list --repo "$GITHUB_REPOSITORY" --state open --app dependabot --limit 50 --json number --jq '.[].number')

  rm -f "$errfile"

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo '## ops-dependabot sweep'
      echo
      echo '| result | count |'
      echo '| --- | --- |'
      echo "| merge | ${c_merge} |"
      echo "| wait:checks | ${c_wait_checks} |"
      echo "| wait:grace | ${c_wait_grace} |"
      echo "| wait:behind | ${c_wait_behind} |"
      echo "| wait:unknown | ${c_wait_unknown} |"
      echo "| skip | ${c_skip} |"
      echo "| fail | ${c_fail} |"
    } >>"$GITHUB_STEP_SUMMARY"
  fi

  if [ "$c_fail" -gt 0 ]; then
    return 1
  fi
  return 0
}

if [ "${OPS_DEPENDABOT_SOURCE:-}" != 1 ]; then
  ops_dependabot_sweep
fi
