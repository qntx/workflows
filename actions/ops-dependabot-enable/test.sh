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
}

expect_decision() {
  local label="$1" want="$2" got
  got="$(ops_dependabot_decide)"
  if [ "$got" = "$want" ]; then
    echo "ok ${label}"
  else
    echo "FAIL ${label}: got '${got}' want '${want}'"
    fail=1
  fi
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
expect_error 'non-dependabot-actor'

base_env
MERGE_METHOD='fast-forward'
expect_error 'bad-merge-method'

if [ "$fail" -ne 0 ]; then
  echo 'ops-dependabot-enable tests failed'
  exit 1
fi
echo 'ops-dependabot-enable tests passed'
