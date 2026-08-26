#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
fail=0
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

mkdir -p "$root/.git" "$root/.github/workflows" "$root/content/docs" "$root/foo"

run_guard() {
  local src="$1" dst="$2"
  ROOT="$root" SRC="$src" DST="$dst" GITHUB_OUTPUT="$(mktemp)" bash "$dir/protect.sh"
}

expect_ok() {
  local label="$1" src="$2" dst="$3"
  if run_guard "$src" "$dst" >/dev/null; then
    echo "ok ${label}"
  else
    echo "FAIL ${label} (expected ok)"
    fail=1
  fi
}

expect_fail() {
  local label="$1" src="$2" dst="$3"
  if run_guard "$src" "$dst" >/dev/null 2>&1; then
    echo "FAIL ${label} (expected fail)"
    fail=1
  else
    echo "ok ${label}"
  fi
}

expect_ok 'content to content/docs' 'content' 'content/docs'
expect_ok 'root dest' 'content' '.'
expect_ok 'dot source' '.' 'content'

expect_fail 'dest .github/workflows/x.yml' 'content' '.github/workflows/x.yml'
expect_fail 'dest ../../.git' 'content' '../../.git'
expect_fail 'dest /etc' 'content' '/etc'
expect_fail 'dest foo/../../.github' 'content' 'foo/../../.github'
expect_fail 'dest .github/dependabot.yml' 'content' '.github/dependabot.yml'
expect_fail 'dest .git/config' 'content' '.git/config'

expect_fail 'src ../../.git' '../../.git' 'content'
expect_fail 'src /etc' '/etc' 'content'
expect_fail 'src foo/../../.github' 'foo/../../.github' 'content'

if [ "$fail" -ne 0 ]; then
  echo "protect-sync-path tests failed"
  exit 1
fi
echo "protect-sync-path tests passed"
