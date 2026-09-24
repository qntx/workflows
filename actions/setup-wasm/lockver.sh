#!/usr/bin/env bash
# Flush each [[package]] table. Top-level `version = 4` is not a crate version.
set -euo pipefail

if [ "$#" -ne 2 ] || [ -z "$2" ]; then
  echo '::error::setup-wasm: lockver usage' >&2
  exit 1
fi
if [ ! -f "$1" ]; then
  echo '::error::setup-wasm: Cargo.lock not found' >&2
  exit 1
fi

if ! awk -v want="$2" '
function qval(s, i, r) {
  i = index(s, "\"")
  if (i == 0) return ""
  r = substr(s, i + 1)
  i = index(r, "\"")
  if (i == 0) return ""
  return substr(r, 1, i - 1)
}

function flush() {
  if (inpkg && pname == want && pver != "") vers[pver] = 1
  pname = ""
  pver = ""
  have_name = 0
  have_ver = 0
  inpkg = 0
}

BEGIN {
  inpkg = 0
  have_name = 0
  have_ver = 0
  pname = ""
  pver = ""
}

{
  sub(/\r$/, "")
}

/^\[\[package\]\][[:space:]]*$/ {
  flush()
  inpkg = 1
  next
}

/^\[/ {
  flush()
  next
}

inpkg && have_name == 0 && /^name[[:space:]]*=[[:space:]]*"/ {
  pname = qval($0)
  have_name = 1
  next
}

inpkg && have_ver == 0 && /^version[[:space:]]*=[[:space:]]*"/ {
  pver = qval($0)
  have_ver = 1
  next
}

END {
  flush()
  n = 0
  only = ""
  for (v in vers) {
    n++
    only = v
  }
  if (n != 1) exit 1
  printf "%s\n", only
}
' "$1"; then
  echo "::error::setup-wasm: lockver: ${2} missing or not a single version" >&2
  exit 1
fi
