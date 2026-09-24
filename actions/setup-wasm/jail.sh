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
if ! joined="$(realpath "$root/$rel")"; then
  die 'path realpath failed'
fi

# Prefix check, not a glob: a workspace named `foo` must not accept `foo-evil`.
if [ "$joined" != "$root" ] && [ "${joined#"$root"/}" = "$joined" ]; then
  die 'path escapes workspace'
fi

printf '%s\n' "$joined"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'path=%s\n' "$joined" >>"$GITHUB_OUTPUT"
fi
