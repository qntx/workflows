#!/usr/bin/env bash
# Install the toolchain named by WORK_DIR's rust-toolchain file. rustup >=1.28
# reads the file itself, including its components and targets; COMPONENTS and
# TARGETS are added on top.
set -euo pipefail

die() {
  echo "::error::setup-rust: $*" >&2
  exit 1
}

if ! command -v rustup >/dev/null 2>&1; then
  die 'rustup is required to install from a rust-toolchain file'
fi

rustup_ver="$(rustup --version | awk 'NR == 1 {print $2}')"
case "$rustup_ver" in
  '' | *[!0-9.]*) die "unexpected rustup version '${rustup_ver}'" ;;
esac
major="${rustup_ver%%.*}"
minor="${rustup_ver#*.}"
minor="${minor%%.*}"
if [ "$major" -lt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -lt 28 ]; }; then
  die "rustup ${rustup_ver} cannot install from a toolchain file; needs >= 1.28"
fi

dir="${WORK_DIR:-}"
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  die 'working directory not found'
fi

case "${COMPONENTS:-}" in
  *[!A-Za-z0-9_,.+\ -]*) die 'components charset' ;;
esac
case "${TARGETS:-}" in
  *[!A-Za-z0-9_,.+\ -]*) die 'targets charset' ;;
esac

cd "$dir"
rustup toolchain install
if [ -n "${COMPONENTS:-}" ]; then
  # word-split is intentional: comma-separated list
  # shellcheck disable=SC2086
  rustup component add ${COMPONENTS//,/ }
fi
if [ -n "${TARGETS:-}" ]; then
  # shellcheck disable=SC2086
  rustup target add ${TARGETS//,/ }
fi
