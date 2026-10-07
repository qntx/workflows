#!/usr/bin/env bash
# Print the install mode: explicit | file | stable.
# RUST_VERSION non-empty -> explicit (dtolnay plus RUSTUP_TOOLCHAIN export)
# else walk WORK_DIR up to GITHUB_WORKSPACE for rust-toolchain(.toml) -> file
# else -> stable. The upward walk mirrors rustup's own discovery.
set -euo pipefail

die() {
  echo "::error::setup-rust: $*" >&2
  exit 1
}

rv="${RUST_VERSION:-}"
dir="${WORK_DIR:-}"
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  die 'working directory not found'
fi

if [ -n "$rv" ]; then
  case "$rv" in
    *[!A-Za-z0-9._+-]*) die 'rust-version charset' ;;
  esac
  mode=explicit
else
  mode=stable
  stop="${GITHUB_WORKSPACE:-/}"
  search="$dir"
  if command -v realpath >/dev/null 2>&1; then
    stop="$(realpath "$stop" 2>/dev/null || printf '%s' "$stop")"
    search="$(realpath "$search")"
  fi
  while :; do
    if [ -f "$search/rust-toolchain.toml" ] || [ -f "$search/rust-toolchain" ]; then
      mode=file
      break
    fi
    if [ "$search" = "$stop" ] || [ "$search" = / ]; then
      break
    fi
    search="$(dirname "$search")"
  done
fi

printf '%s\n' "$mode"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'mode=%s\n' "$mode" >>"$GITHUB_OUTPUT"
fi
