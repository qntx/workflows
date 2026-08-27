#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
fail=0

run_parse() {
  local tmp rc
  tmp="$(mktemp)"
  set +e
  GITHUB_ENV="$tmp" BLOCK="$1" bash "$dir/parse.sh"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    cat "$tmp"
  fi
  rm -f "$tmp"
  return "$rc"
}

expect_ok() {
  local label="$1"
  local block="$2"
  local got
  if got="$(run_parse "$block")"; then
    echo "ok ${label}"
    if [ "${3+x}" = x ] && [ "$got" != "$3" ]; then
      echo "FAIL ${label} output mismatch:"
      printf 'got:\n%s\nwant:\n%s\n' "$got" "$3"
      fail=1
    fi
  else
    echo "FAIL ${label} (expected ok)"
    fail=1
  fi
}

expect_fail() {
  local label="$1"
  local block="$2"
  if run_parse "$block" >/dev/null 2>&1; then
    echo "FAIL ${label} (expected fail)"
    fail=1
  else
    echo "ok ${label}"
  fi
}

expect_ok 'empty' '' ''
expect_ok 'CARGO_TARGET_LINKER' $'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc\n' $'CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc'
expect_ok 'CC' $'CC=aarch64-linux-gnu-gcc\n' $'CC=aarch64-linux-gnu-gcc'
expect_ok 'RUSTFLAGS' $'RUSTFLAGS=-C target-feature=+crt-static\n' $'RUSTFLAGS=-C target-feature=+crt-static'
expect_ok 'skip blanks' $'CC=gcc\n\nCXX=g++\n' $'CC=gcc\nCXX=g++'
expect_fail 'unknown FOO' $'FOO=bar\n'
expect_fail 'lowercase key' $'foo=bar\n'
expect_fail 'missing equals' $'CC\n'
expect_fail 'PATH' $'PATH=/tmp\n'
expect_fail 'CARGO_HOME' $'CARGO_HOME=/tmp\n'
expect_fail 'HTTP_PROXY' $'HTTP_PROXY=http://evil\n'
expect_fail 'GITHUB_ENV' $'GITHUB_ENV=x\n'
expect_fail 'GITHUB_PATH' $'GITHUB_PATH=x\n'
expect_fail 'GITHUB_OUTPUT' $'GITHUB_OUTPUT=x\n'
expect_fail 'GITHUB_ACTION_PATH' $'GITHUB_ACTION_PATH=x\n'
expect_fail 'heredoc delimiter' $'CC<<EOF\n'
expect_fail 'heredoc in value' $'CC=bar<<EOF\n'
expect_fail 'leading digit' $'1FOO=bar\n'
expect_fail 'comment' $'# CC=gcc\n'
expect_fail 'export' $'export CC=gcc\n'

if [ "$fail" -ne 0 ]; then
  echo "parse-env-block tests failed"
  exit 1
fi
echo "parse-env-block tests passed"
