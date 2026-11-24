#!/usr/bin/env bash
# Assert that a job in a workflow run reached the expected step conclusions
# and emitted the expected check-run annotations. Used by the self-CI
# independent-gates proof (fixtures/rust-gates, fixtures/bun-gates).
#
# usage: assert-gates.sh '<job name>' '<Step Name>=<conclusion>'... [--annotation '<substring>']...
# env:   GH_TOKEN, REPO, RUN_ID, RUN_ATTEMPT
set -euo pipefail

usage() {
  echo "usage: $0 '<job name>' '<Step Name>=<conclusion>'... [--annotation '<substring>']..." >&2
  exit 2
}

die() {
  echo "::error::$1" >&2
  exit 1
}

(($# >= 1)) || usage
job_name="$1"
shift

expected=()
annotations=()
mode=steps
while (($#)); do
  case "$1" in
    --annotation)
      mode=annotations
      shift
      (($#)) || usage
      annotations+=("$1")
      shift
      ;;
    --annotation=*)
      mode=annotations
      annotations+=("${1#--annotation=}")
      shift
      ;;
    *=*)
      [[ "$mode" == steps ]] || usage
      expected+=("$1")
      shift
      ;;
    *)
      usage
      ;;
  esac
done

: "${GH_TOKEN:?assert-gates.sh requires GH_TOKEN}"
: "${REPO:?assert-gates.sh requires REPO}"
: "${RUN_ID:?assert-gates.sh requires RUN_ID}"
: "${RUN_ATTEMPT:?assert-gates.sh requires RUN_ATTEMPT}"
export GH_TOKEN

pages="$(gh api "repos/$REPO/actions/runs/$RUN_ID/attempts/$RUN_ATTEMPT/jobs" --paginate)"
match="$(jq -sc --arg name "$job_name" 'map(.jobs[]) | map(select(.name == $name))' <<<"$pages")"
count="$(jq 'length' <<<"$match")"
[[ "$count" == 1 ]] || die "expected exactly one job named '$job_name' in run $RUN_ID attempt $RUN_ATTEMPT, found $count"
job_id="$(jq -r '.[0].id' <<<"$match")"
echo "job '$job_name' (id $job_id)"

status=0
if ((${#expected[@]})); then
  for spec in "${expected[@]}"; do
    step_name="${spec%%=*}"
    want="${spec#*=}"
    got="$(jq -r --arg n "$step_name" 'first(.[0].steps[]? | select(.name == $n) | .conclusion) // ""' <<<"$match")"
    if [[ "$got" == "$want" ]]; then
      echo "  step '$step_name': $got"
    else
      echo "::error::job '$job_name' step '$step_name': expected conclusion '$want', got '${got:-missing}'" >&2
      status=1
    fi
  done
fi

if ((${#annotations[@]})); then
  messages="$(gh api "repos/$REPO/check-runs/$job_id/annotations" --paginate | jq -sc '[.[][] | .message // ""]')"
  for sub in "${annotations[@]}"; do
    if jq -e --arg s "$sub" '[.[] | contains($s)] | any' <<<"$messages" >/dev/null; then
      echo "  annotation containing '$sub': found"
    else
      echo "::error::job '$job_name' has no annotation containing '$sub'" >&2
      status=1
    fi
  done
fi

((status == 0)) || exit 1
echo "assert-gates: all checks passed for '$job_name'"
