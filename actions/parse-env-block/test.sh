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
expect_ok 'simple' $'FOO=bar\n' $'FOO=bar'
expect_ok 'empty value' $'FOO=\n' $'FOO='
expect_ok 'skip blanks' $'FOO=1\n\nBAR=2\n' $'FOO=1\nBAR=2'
expect_ok 'underscore key' $'_FOO=1\n' $'_FOO=1'
expect_fail 'lowercase key' $'foo=bar\n'
expect_fail 'missing equals' $'FOO\n'
expect_fail 'GITHUB_ENV' $'GITHUB_ENV=x\n'
expect_fail 'GITHUB_PATH' $'GITHUB_PATH=x\n'
expect_fail 'GITHUB_OUTPUT' $'GITHUB_OUTPUT=x\n'
expect_fail 'GITHUB_ACTION_PATH' $'GITHUB_ACTION_PATH=x\n'
expect_fail 'heredoc delimiter' $'FOO<<EOF\n'
expect_fail 'heredoc in value' $'FOO=bar<<EOF\n'
expect_fail 'leading digit' $'1FOO=bar\n'
expect_fail 'comment' $'# FOO=bar\n'
expect_fail 'export' $'export FOO=bar\n'

if [ "$fail" -ne 0 ]; then
  echo "parse-env-block tests failed"
  exit 1
fi
echo "parse-env-block tests passed"
