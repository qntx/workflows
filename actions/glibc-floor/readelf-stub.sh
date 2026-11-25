#!/usr/bin/env bash
# readelf stub for test.sh: validates the exact argument shape check.sh uses
# and cats the recorded `readelf --version-info --wide` output from <file>.
set -euo pipefail

if [ "$#" -ne 3 ] || [ "$1" != '--version-info' ] || [ "$2" != '--wide' ]; then
  echo "readelf-stub: unexpected args: $*" >&2
  exit 64
fi

cat "$3"
