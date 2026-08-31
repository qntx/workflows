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

TEXT='update-type: version-update:semver-minor'

expect_eval 'eval-green' 'merge' "$(pr_base '[{"name":"Lint","status":"COMPLETED","conclusion":"SUCCESS","workflowName":"CI"}]')" "$TEXT"
expect_eval 'eval-pending' 'wait:checks' "$(pr_base '[{"name":"Lint","status":"IN_PROGRESS","conclusion":null,"workflowName":"CI"}]')" "$TEXT"
expect_eval 'eval-red' 'wait:checks' "$(pr_base '[{"name":"Lint","status":"COMPLETED","conclusion":"FAILURE","workflowName":"CI"}]')" "$TEXT"
expect_eval 'eval-major' 'skip:update-type-disabled version-update:semver-major' "$(pr_base '[]')" 'update-type: version-update:semver-major'
expect_eval 'eval-self-only-young' 'wait:grace' "$(pr_base '[{"name":"merge / merge","status":"COMPLETED","conclusion":"FAILURE","workflowName":"Dependabot"}]')" "$TEXT"

# createdAt 2023-11-14T22:08:20Z == epoch 1700000000. Age 0 with NOW_EPOCH. No other checks → grace.
expect_eval 'eval-no-checks-young' 'wait:grace' "$(pr_base '[]')" "$TEXT"

NOW_EPOCH=1700000400
expect_eval 'eval-no-checks-old' 'merge' "$(pr_base '[]')" "$TEXT"
expect_eval 'eval-self-only-old' 'merge' "$(pr_base '[{"name":"merge / merge","status":"COMPLETED","conclusion":"FAILURE","workflowName":"Dependabot"}]')" "$TEXT"

draft="$(printf '%s' "$(pr_base '[]')" | jq '.isDraft=true')"
expect_eval 'eval-draft' 'skip:draft' "$draft" "$TEXT"

conflict="$(printf '%s' "$(pr_base '[]')" | jq '.mergeable="CONFLICTING"')"
expect_eval 'eval-conflicts' 'skip:conflicts' "$conflict" "$TEXT"

human="$(printf '%s' "$(pr_base '[{"name":"Lint","status":"COMPLETED","conclusion":"SUCCESS","workflowName":"CI"}]')" | jq '.author.login="octocat"')"
expect_eval 'eval-human' 'skip:actor octocat' "$human" "$TEXT"

if [ "$fail" -ne 0 ]; then
  echo 'ops-dependabot-enable tests failed'
  exit 1
fi
echo 'ops-dependabot-enable tests passed'
