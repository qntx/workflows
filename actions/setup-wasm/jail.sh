#!/usr/bin/env bash
# Strip one leading ./ only. `././x` stays dotted and is rejected.
set -euo pipefail

die() {
  echo "::error::setup-wasm: $*" >&2
  exit 1
}

if ! command -v realpath >/dev/null 2>&1; then
  die 'realpath is required'
fi

ws="${GITHUB_WORKSPACE:-}"
if [ -z "$ws" ] || [ ! -d "$ws" ]; then
  die 'GITHUB_WORKSPACE is missing'
fi

orig="${REL-}"
rel="$orig"
if [ "$orig" != "." ]; then
  case "$rel" in
    ./*) rel="${rel#./}" ;;
  esac
  if [ -z "$rel" ]; then
    die 'path is empty'
  fi
  case "$rel" in
    /*) die 'path must be relative' ;;
    .*) die 'path must not start with .' ;;
  esac
  case "$rel" in
    *' '* | *$'\n'* | *$'\r'*) die 'path charset' ;;
  esac
  case "$rel" in
    *[!A-Za-z0-9._/-]*) die 'path charset' ;;
  esac
  # Word-splitting drops a trailing empty field, so reject it before the walk.
  case "$rel" in
    */) die 'path has an empty or .. segment' ;;
  esac
  rest="$rel"
  while [ -n "$rest" ]; do
    case "$rest" in
      */*)
        seg="${rest%%/*}"
        rest="${rest#*/}"
        ;;
      *)
        seg="$rest"
        rest=
        ;;
    esac
    if [ -z "$seg" ] || [ "$seg" = .. ]; then
      die 'path has an empty or .. segment'
    fi
  done
fi

if ! root="$(realpath "$ws")"; then
  die 'GITHUB_WORKSPACE realpath failed'
fi
if [ ! -e "$root/$rel" ]; then
  die 'path does not exist'
fi
if [ ! -d "$root/$rel" ]; then
  die 'path is not a directory'
fi
# REL can pass the charset while a symlink target contains CR, LF, or NUL.
# Those bytes split stdout and GITHUB_OUTPUT into extra workflow commands.
raw_file="$(mktemp)"
if ! realpath "$root/$rel" >"$raw_file"; then
  rm -f "$raw_file"
  die 'path realpath failed'
fi
if ! joined="$(awk '
  NR > 1 { bad = 1; exit 1 }
  index($0, "\r") > 0 { bad = 1; exit 1 }
  { line = $0 }
  END {
    if (bad || NR != 1) exit 1
    printf "%s", line
  }
' "$raw_file")"; then
  rm -f "$raw_file"
  die 'resolved path contains CR, LF, or NUL'
fi
if [ -z "$joined" ] || ! printf '%s\n' "$joined" | cmp -s - "$raw_file"; then
  rm -f "$raw_file"
  die 'resolved path contains CR, LF, or NUL'
fi
rm -f "$raw_file"

# Prefix check, not a glob: a workspace named `foo` must not accept `foo-evil`.
if [ "$joined" != "$root" ] && [ "${joined#"$root"/}" = "$joined" ]; then
  die 'path escapes workspace'
fi

printf '%s\n' "$joined"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'path=%s\n' "$joined" >>"$GITHUB_OUTPUT"
fi
