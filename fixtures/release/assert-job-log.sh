#!/usr/bin/env bash
# Assert that a job in a workflow run logged a line containing each given
# fixed substring. Used by the self-CI glibc-floor e2e to prove the gnu
# smoke ran inside the pinned smoke-image container.
#
# usage: assert-job-log.sh '<job name>' '<fixed substring>'...
# env:   GH_TOKEN, REPO, RUN_ID, RUN_ATTEMPT
set -euo pipefail

usage() {
  echo "usage: $0 '<job name>' '<fixed substring>'..." >&2
  exit 2
}

die() {
  echo "::error::$1" >&2
  exit 1
}

(($# >= 2)) || usage
job_name="$1"
shift

: "${GH_TOKEN:?assert-job-log.sh requires GH_TOKEN}"
: "${REPO:?assert-job-log.sh requires REPO}"
: "${RUN_ID:?assert-job-log.sh requires RUN_ID}"
: "${RUN_ATTEMPT:?assert-job-log.sh requires RUN_ATTEMPT}"
export GH_TOKEN

pages="$(gh api "repos/$REPO/actions/runs/$RUN_ID/attempts/$RUN_ATTEMPT/jobs" --paginate)"
match="$(jq -sc --arg name "$job_name" 'map(.jobs[]) | map(select(.name == $name))' <<<"$pages")"
count="$(jq 'length' <<<"$match")"
[[ "$count" == 1 ]] || die "expected exactly one job named '$job_name' in run $RUN_ID attempt $RUN_ATTEMPT, found $count"
job_id="$(jq -r '.[0].id' <<<"$match")"
echo "job '$job_name' (id $job_id)"

# Job logs can lag right after the job completes: retry while the fetch
# fails or the body is still empty. curl, not `gh api`: gh refuses to print
# a response that contains terminal escape sequences (job logs are full of
# ANSI colours). curl follows the redirect to blob storage without
# forwarding the Authorization header to the other host.
logs=''
err=''
for _ in 1 2 3 4 5 6; do
  if logs="$(curl -fsSL --max-time 60 \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H 'Accept: application/vnd.github+json' \
    "${GITHUB_API_URL:-https://api.github.com}/repos/$REPO/actions/jobs/$job_id/logs" 2>&1)" \
    && [[ -n "$logs" ]]; then
    break
  fi
  err="$logs"
  logs=''
  sleep 10
done
[[ -n "$logs" ]] || die "job '$job_name' log is still empty after 6 fetches: ${err}"

status=0
for sub in "$@"; do
  if line="$(grep -F -m 1 -- "$sub" <<<"$logs")"; then
    echo "  $line"
  else
    echo "::error::job '$job_name' log has no line containing '$sub'" >&2
    status=1
  fi
done

((status == 0)) || exit 1
echo "assert-job-log: all substrings found in '$job_name' log"
