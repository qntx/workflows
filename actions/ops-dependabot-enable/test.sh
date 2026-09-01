#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
fail=0
OPS_DEPENDABOT_SOURCE=1
# shellcheck source=enable.sh
source "$dir/enable.sh"

base_env() {
  ACTOR='dependabot[bot]'
  MERGE_METHOD='squash'
  ALLOW_PATCH='true'
  ALLOW_MINOR='true'
  ALLOW_MAJOR='false'
  EXEMPT_LABELS='do-not-merge,work-in-progress'
  PR_LABELS='dependencies,javascript'
  UPDATE_TYPE='version-update:semver-minor'
  NOW_EPOCH='1700000000'
  GRACE_SECONDS='300'
}

expect_eq() {
  local label="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    echo "ok ${label}"
  else
    echo "FAIL ${label}: got '${got}' want '${want}'"
    fail=1
  fi
}

expect_decision() {
  local label="$1" want="$2" got
  got="$(ops_dependabot_decide)"
  expect_eq "$label" "$got" "$want"
}

expect_error() {
  local label="$1"
  if ops_dependabot_decide >/dev/null 2>&1; then
    echo "FAIL ${label}: expected error"
    fail=1
  else
    echo "ok ${label}"
  fi
}

base_env
expect_decision 'minor-allowed' 'merge'

UPDATE_TYPE='version-update:semver-patch'
expect_decision 'patch-allowed' 'merge'

UPDATE_TYPE='version-update:semver-major'
expect_decision 'major-disabled' 'skip:update-type-disabled version-update:semver-major'

ALLOW_MAJOR='true'
expect_decision 'major-allowed' 'merge'

base_env
PR_LABELS='dependencies,do-not-merge'
expect_decision 'exempt-label' 'skip:exempt-label do-not-merge'

base_env
UPDATE_TYPE='version-update:semver-minor'
PR_LABELS=' work-in-progress , javascript '
EXEMPT_LABELS='do-not-merge, work-in-progress'
expect_decision 'exempt-label-trimmed' 'skip:exempt-label work-in-progress'

base_env
UPDATE_TYPE='lockfile-only'
expect_decision 'unhandled-type' 'skip:unhandled-update-type lockfile-only'

base_env
UPDATE_TYPE='version-update:lockfile-only'
expect_decision 'lockfile-only-as-patch' 'merge'

base_env
UPDATE_TYPE='version-update:lockfile-only'
ALLOW_PATCH='false'
expect_decision 'lockfile-only-disabled' 'skip:update-type-disabled version-update:lockfile-only'

base_env
ACTOR='human'
expect_decision 'non-dependabot-actor' 'skip:actor human'

base_env
ACTOR='app/dependabot'
expect_decision 'app-dependabot-actor' 'merge'

base_env
MERGE_METHOD='fast-forward'
expect_error 'bad-merge-method'

expect_eq 'parse-empty' "$(ops_dependabot_parse_update_type '')" ''
expect_eq 'parse-patch' "$(ops_dependabot_parse_update_type 'update-type: version-update:semver-patch')" 'version-update:semver-patch'
expect_eq 'parse-highest' "$(ops_dependabot_parse_update_type $'update-type: version-update:semver-patch\nupdate-type: version-update:semver-major\nupdate-type: version-update:semver-minor')" 'version-update:semver-major'

footer=$'---\nupdated-dependencies:\n- dependency-name: blake2\n  update-type: version-update:semver-minor\n...\n'
expect_eq 'parse-footer' "$(ops_dependabot_parse_update_type "$footer")" 'version-update:semver-minor'

lockfile_footer=$'---\nupdated-dependencies:\n- dependency-name: foo\n  update-type: version-update:lockfile-only\n...\n'
expect_eq 'parse-lockfile' "$(ops_dependabot_parse_update_type "$lockfile_footer")" 'version-update:lockfile-only'

expect_rollup() {
  local label="$1" json="$2" rc=0
  set +e
  ops_dependabot_rollup_ok "$json"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "ok ${label}"
  else
    echo "FAIL ${label}"
    fail=1
  fi
}

expect_rollup_fail() {
  local label="$1" json="$2" rc=0
  set +e
  ops_dependabot_rollup_ok "$json"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "ok ${label}"
  else
    echo "FAIL ${label}: expected not green"
    fail=1
  fi
}

expect_rollup 'no-checks' '{"statusCheckRollup":[]}'
expect_rollup 'self-only' '{"statusCheckRollup":[{"name":"merge / merge","status":"COMPLETED","conclusion":"FAILURE","workflowName":"Dependabot"}]}'
expect_rollup 'app-green' '{"statusCheckRollup":[{"name":"merge / merge","status":"COMPLETED","conclusion":"FAILURE","workflowName":"Dependabot"},{"name":"Lint","status":"COMPLETED","conclusion":"SUCCESS","workflowName":"CI"},{"name":"Test","status":"COMPLETED","conclusion":"SKIPPED","workflowName":"CI"}]}'
expect_rollup_fail 'lint-pending' '{"statusCheckRollup":[{"name":"Lint","status":"IN_PROGRESS","conclusion":null,"workflowName":"CI"}]}'
expect_rollup_fail 'lint-red' '{"statusCheckRollup":[{"name":"Lint","status":"COMPLETED","conclusion":"FAILURE","workflowName":"CI"}]}'
expect_rollup_fail 'lint-cancelled' '{"statusCheckRollup":[{"name":"Lint","status":"COMPLETED","conclusion":"CANCELLED","workflowName":"CI"}]}'
expect_rollup 'status-success' '{"statusCheckRollup":[{"__typename":"StatusContext","context":"coverage","state":"SUCCESS"}]}'
expect_rollup_fail 'status-pending' '{"statusCheckRollup":[{"__typename":"StatusContext","context":"coverage","state":"PENDING"}]}'

pr_base() {
  python3 -c 'import json,sys
print(json.dumps({
  "number": 1,
  "isDraft": False,
  "mergeable": "MERGEABLE",
  "mergeStateStatus": "CLEAN",
  "createdAt": "2023-11-14T22:13:20Z",
  "author": {"login": "app/dependabot"},
  "labels": [{"name": "dependencies"}],
  "body": "",
  "statusCheckRollup": json.loads(sys.argv[1]),
  "commits": [{"oid": "abc"}],
}))
' "$1"
}

expect_eval() {
  local label="$1" want="$2" pr="$3" text="$4" got now
  now="${NOW_EPOCH:-1700000000}"
  base_env
  NOW_EPOCH="$now"
  got="$(ops_dependabot_evaluate "$pr" "$text")"
  expect_eq "$label" "$got" "$want"
}

# Locks ${GRACE_SECONDS:-900}: base_env then unset.
expect_eval_default_grace() {
  local label="$1" want="$2" pr="$3" text="$4" got now
  now="${NOW_EPOCH:-1700000000}"
  base_env
  unset GRACE_SECONDS
  NOW_EPOCH="$now"
  got="$(ops_dependabot_evaluate "$pr" "$text")"
  expect_eq "$label" "$got" "$want"
}

TEXT='update-type: version-update:semver-minor'
PATCH='update-type: version-update:semver-patch'
GREEN='[{"name":"Lint","status":"COMPLETED","conclusion":"SUCCESS","workflowName":"CI"}]'

expect_eval 'eval-green' 'merge' "$(pr_base "$GREEN")" "$TEXT"
expect_eval 'eval-pending' 'wait:checks' "$(pr_base '[{"name":"Lint","status":"IN_PROGRESS","conclusion":null,"workflowName":"CI"}]')" "$TEXT"
expect_eval 'eval-red' 'wait:checks' "$(pr_base '[{"name":"Lint","status":"COMPLETED","conclusion":"FAILURE","workflowName":"CI"}]')" "$TEXT"
expect_eval 'eval-major' 'skip:update-type-disabled version-update:semver-major' "$(pr_base '[]')" 'update-type: version-update:semver-major'
expect_eval 'eval-self-only-young' 'wait:grace' "$(pr_base '[{"name":"merge / merge","status":"COMPLETED","conclusion":"FAILURE","workflowName":"Dependabot"}]')" "$TEXT"

# createdAt 2023-11-14T22:13:20Z == epoch 1700000000. Age 0 with NOW_EPOCH. No other checks → grace.
expect_eval 'eval-no-checks-young' 'wait:grace' "$(pr_base '[]')" "$TEXT"

NOW_EPOCH=1700000400
expect_eval 'eval-no-checks-old' 'merge' "$(pr_base '[]')" "$TEXT"
expect_eval 'eval-self-only-old' 'merge' "$(pr_base '[{"name":"merge / merge","status":"COMPLETED","conclusion":"FAILURE","workflowName":"Dependabot"}]')" "$TEXT"

NOW_EPOCH=1700000400
expect_eval_default_grace 'eval-default-grace-young' 'wait:grace' "$(pr_base '[]')" "$PATCH"

NOW_EPOCH=1700000900
expect_eval_default_grace 'eval-default-grace-old' 'merge' "$(pr_base '[]')" "$PATCH"

draft="$(printf '%s' "$(pr_base '[]')" | jq '.isDraft=true')"
expect_eval 'eval-draft' 'skip:draft' "$draft" "$TEXT"

conflict="$(printf '%s' "$(pr_base '[]')" | jq '.mergeable="CONFLICTING"')"
expect_eval 'eval-conflicts' 'skip:conflicts' "$conflict" "$TEXT"

human="$(printf '%s' "$(pr_base "$GREEN")" | jq '.author.login="octocat"')"
expect_eval 'eval-human' 'skip:actor octocat' "$human" "$TEXT"

behind="$(printf '%s' "$(pr_base "$GREEN")" | jq '.mergeStateStatus="BEHIND"')"
expect_eval 'eval-behind' 'wait:behind' "$behind" "$PATCH"

unknown="$(printf '%s' "$(pr_base "$GREEN")" | jq '.mergeStateStatus="UNKNOWN"')"
expect_eval 'eval-unknown' 'wait:unknown' "$unknown" "$PATCH"

blocked="$(printf '%s' "$(pr_base "$GREEN")" | jq '.mergeStateStatus="BLOCKED"')"
expect_eval 'eval-blocked' 'skip:BLOCKED' "$blocked" "$PATCH"

behind_major="$(printf '%s' "$(pr_base "$GREEN")" | jq '.mergeStateStatus="BEHIND"')"
expect_eval 'eval-behind-major-disabled' 'skip:update-type-disabled version-update:semver-major' "$behind_major" 'update-type: version-update:semver-major'

err_rollup='GraphQL: Resource not accessible by integration (repository.pullRequest.statusCheckRollup.nodes.0.commit.statusCheckRollup)'
err_workflow='GraphQL: Resource not accessible by integration (repository.pullRequest.statusCheckRollup.nodes.0.commit.statusCheckRollup.contexts.nodes.0.checkSuite.workflowRun)'
err_status='GraphQL: Resource not accessible by integration (repository.pullRequest.statusCheckRollup.nodes.0.commit.statusCheckRollup.contexts.nodes.0.StatusContext)'
err_merged='Pull request is already merged'
err_generic='GraphQL: Resource not accessible by integration (repository.issues)'

expect_forbidden() {
  local label="$1" err="$2"
  if ops_dependabot_is_rollup_forbidden "$err"; then
    echo "ok ${label}"
  else
    echo "FAIL ${label}: expected true"
    fail=1
  fi
}

expect_not_forbidden() {
  local label="$1" err="$2"
  if ops_dependabot_is_rollup_forbidden "$err"; then
    echo "FAIL ${label}: expected false"
    fail=1
  else
    echo "ok ${label}"
  fi
}

expect_forbidden 'forbidden-rollup' "$err_rollup"
expect_forbidden 'forbidden-workflow' "$err_workflow"
expect_forbidden 'forbidden-status' "$err_status"
expect_not_forbidden 'forbidden-merged' "$err_merged"
expect_not_forbidden 'forbidden-empty' ''
expect_not_forbidden 'forbidden-generic' "$err_generic"

expect_eq 'scope-rollup' "$(ops_dependabot_forbidden_scope "$err_rollup")" 'checks'
expect_eq 'scope-workflow' "$(ops_dependabot_forbidden_scope "$err_workflow")" 'actions'
expect_eq 'scope-status' "$(ops_dependabot_forbidden_scope "$err_status")" 'statuses'

viewed="$(mktemp)"
merged="$(mktemp)"
pr12="$(printf '%s' "$(pr_base "$GREEN")" | jq --arg t "$PATCH" '.number=12 | .body=$t | .commits[0].messageBody=$t')"
base_env
GITHUB_REPOSITORY='owner/repo'
unset GITHUB_STEP_SUMMARY
gh() {
  local n
  case "${1:-} ${2:-}" in
    'pr list')
      printf '16\n12\n'
      return 0
      ;;
    'pr view')
      n="${3:-}"
      printf '%s\n' "$n" >>"$viewed"
      if [ "$n" = 16 ]; then
        echo "$err_rollup" >&2
        return 1
      fi
      if [ "$n" = 12 ]; then
        printf '%s\n' "$pr12"
        return 0
      fi
      echo "ops-dependabot-test: unexpected pr view ${n}" >&2
      return 1
      ;;
    'pr merge')
      printf '%s\n' "$*" >>"$merged"
      return 0
      ;;
    *)
      echo "ops-dependabot-test: unexpected gh $*" >&2
      return 1
      ;;
  esac
}

set +e
ops_dependabot_sweep
sweep_rc=$?
set -e
expect_eq 'sweep-403-rc' "$sweep_rc" '1'
expect_eq 'sweep-viewed' "$(xargs echo <"$viewed")" '16 12'
if awk '{print $NF}' "$merged" | grep -qx 12; then
  echo 'ok sweep-merged-12'
else
  echo 'FAIL sweep-merged-12: expected merge of #12'
  fail=1
fi
rm -f "$viewed" "$merged"

if [ "$fail" -ne 0 ]; then
  echo 'ops-dependabot-enable tests failed'
  exit 1
fi
echo 'ops-dependabot-enable tests passed'
