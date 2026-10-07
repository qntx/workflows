#!/usr/bin/env bash
set -euo pipefail

if [ -z "${HERMES:-}" ] || [ ! -x "$HERMES" ]; then
  echo 'HERMES is not set to an executable' >&2
  exit 1
fi

"$HERMES" -version
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
printf '%s\n' 'print(6 * 7);' >"$dir/smoke.js"
out="$("$HERMES" "$dir/smoke.js")"
if [ "$out" != 42 ]; then
  echo "unexpected hermes output: ${out}" >&2
  exit 1
fi
