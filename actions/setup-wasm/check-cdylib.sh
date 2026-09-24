#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "::error::setup-wasm: $*" >&2
  exit 1
}

if ! command -v jq >/dev/null 2>&1; then
  die 'jq is required'
fi

json="$(cat)"
if [ -z "$json" ]; then
  die 'cargo metadata is empty'
fi

if ! out="$(jq -r '
  . as $root
  | [
      $root.packages[]
      | select(. as $pkg | ($root.workspace_members | index($pkg.id)) != null)
      | select(any(.targets[]; any(.crate_types[]; . == "cdylib")))
    ] as $pkgs
  | if ($pkgs | length) == 0 then
      "none"
    elif ($pkgs | map(select(.publish != [])) | length) > 0 then
      "bad " + ($pkgs | map(select(.publish != []) | .name) | join(","))
    else
      "ok"
    end
' <<<"$json" 2>/dev/null)"; then
  die 'cargo metadata is not valid JSON'
fi

case "$out" in
  ok) exit 0 ;;
  none) die 'no cdylib in the workspace' ;;
  bad\ *) die "cdylib publish must be [] (${out#bad })" ;;
  *) die 'cdylib check failed' ;;
esac
