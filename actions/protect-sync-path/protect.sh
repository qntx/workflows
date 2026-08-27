#!/usr/bin/env bash
set -euo pipefail

root="${ROOT:-${GITHUB_WORKSPACE:-}}"
src="${SRC-}"
dst="${DST-}"

if [ -z "$root" ]; then
  echo '::error::protect-sync-path: ROOT/GITHUB_WORKSPACE required'
  exit 1
fi
if [ -z "$src" ]; then
  echo '::error::protect-sync-path: source is empty'
  exit 1
fi
if [ -z "$dst" ]; then
  echo '::error::protect-sync-path: destination is empty'
  exit 1
fi
if [ ! -d "$root" ]; then
  echo '::error::protect-sync-path: root is not a directory'
  exit 1
fi

# Reject absolute paths and any `..` segment before rsync / realpath.
illegal_rel() {
  local p="$1"
  if [[ "$p" == /* ]]; then
    return 0
  fi
  local IFS=/
  local seg
  set -f
  # shellcheck disable=SC2086
  for seg in $p; do
    if [ "$seg" = .. ]; then
      set +f
      return 0
    fi
  done
  set +f
  return 1
}

if illegal_rel "$src"; then
  echo "::error::protect-sync-path: illegal source path"
  exit 1
fi
if illegal_rel "$dst"; then
  echo "::error::protect-sync-path: illegal destination path"
  exit 1
fi

canon() {
  python3 -c 'import os, sys; print(os.path.realpath(os.path.join(sys.argv[1], sys.argv[2])))' "$1" "$2"
}

root_abs="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$root")"
src_abs="$(canon "$root_abs" "$src")"
dst_abs="$(canon "$root_abs" "$dst")"

under_root() {
  local p="$1"
  [[ "$p" == "$root_abs" || "$p" == "$root_abs/"* ]]
}

if ! under_root "$src_abs"; then
  echo '::error::protect-sync-path: source escapes root'
  exit 1
fi
if ! under_root "$dst_abs"; then
  echo '::error::protect-sync-path: destination escapes root'
  exit 1
fi

jailed() {
  local p="$1"
  [[ "$p" == "$root_abs/.git" || "$p" == "$root_abs/.git/"* ||
    "$p" == "$root_abs/.github" || "$p" == "$root_abs/.github/"* ]]
}

if jailed "$src_abs" || jailed "$dst_abs"; then
  echo '::error::protect-sync-path: source or destination is .git or .github'
  exit 1
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "source-abs=${src_abs}"
    echo "destination-abs=${dst_abs}"
  } >>"$GITHUB_OUTPUT"
fi
