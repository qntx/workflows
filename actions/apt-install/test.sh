#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
fail=0

expect_ok() {
  local label="$1"
  shift
  if "$@"; then
    echo "ok ${label}"
  else
    echo "FAIL ${label} (expected ok)"
    fail=1
  fi
}

expect_fail() {
  local label="$1"
  shift
  if "$@"; then
    echo "FAIL ${label} (expected fail)"
    fail=1
  else
    echo "ok ${label}"
  fi
}

run_charset() {
  CHARSET_ONLY=1 PACKAGES="$1" bash "$dir/install.sh" 2>/dev/null
}

expect_ok 'empty' env CHARSET_ONLY=1 PACKAGES='' bash "$dir/install.sh"
expect_ok 'libssl-dev:arm64' run_charset 'libssl-dev:arm64'
expect_ok 'g++ plus colon' run_charset 'gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libssl-dev:arm64'
expect_ok 'dotted package' run_charset 'libfoo1.0-dev'
expect_fail 'semicolon' run_charset 'pkg;id'
expect_fail 'ampersand' run_charset 'pkg&x'
expect_fail 'pipe' run_charset 'pkg|x'
expect_fail 'dollar' run_charset 'pkg$x'
expect_fail 'backtick' run_charset 'pkg`x`'
expect_fail 'paren' run_charset 'pkg(x)'
expect_fail 'dotdot' run_charset 'pkg..deb'
expect_fail 'underscore' run_charset 'libfoo_dev'

if [ "$fail" -ne 0 ]; then
  echo "apt-install tests failed"
  exit 1
fi
echo "apt-install tests passed"
