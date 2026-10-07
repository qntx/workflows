#!/usr/bin/env bash
set -euo pipefail

if [ -z "${HERMES:-}" ] || [ ! -x "$HERMES" ]; then
  echo 'HERMES is not set to an executable' >&2
  exit 1
fi

"$HERMES" -version
out="$("$HERMES" -e 'print(6*7)')"
if [ "$out" != 42 ]; then
  echo "unexpected hermes output: ${out}" >&2
  exit 1
fi
