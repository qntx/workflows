#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
fixtures="$dir/fixtures"
fail=0

# Run check.sh against a recorded readelf fixture; captures combined output
# in $out and the exit code in $code.
run() {
  local fixture="$1" floor="$2"
  set +e
  out="$(READELF="$dir/readelf-stub.sh" bash "$dir/check.sh" "$fixtures/$fixture" "$floor" 2>&1)"
  code=$?
  set -e
}

expect_ok() {
  local label="$1" fixture="$2" floor="$3"
  run "$fixture" "$floor"
  if [ "$code" -eq 0 ]; then
    echo "ok ${label}"
  else
    echo "FAIL ${label} (expected ok, got exit ${code}: ${out})"
    fail=1
  fi
}

expect_fail() {
  local label="$1" fixture="$2" floor="$3"
  run "$fixture" "$floor"
  if [ "$code" -ne 0 ]; then
    echo "ok ${label}"
  else
    echo "FAIL ${label} (expected fail): ${out}"
    fail=1
  fi
}

expect_out() {
  local label="$1" needle="$2"
  if [[ "$out" == *"$needle"* ]]; then
    echo "ok ${label}"
  else
    echo "FAIL ${label} (expected '${needle}' in: ${out})"
    fail=1
  fi
}

# Real `readelf --version-info --wide` output of the qntx/nosfry v0.4.0
# release assets (built by release-rust via cargo-zigbuild). Newest need on
# both arches is GLIBC_2.30, so the 2.31 floor they shipped under passes.
expect_ok 'nosfry x86_64 @ 2.31' nosfry-0.4.0-x86_64-unknown-linux-gnu.txt 2.31
expect_out 'nosfry x86_64 newest is 2.30' 'needs GLIBC_2.30 <= floor 2.31'
expect_ok 'nosfry aarch64 @ 2.31' nosfry-0.4.0-aarch64-unknown-linux-gnu.txt 2.31
expect_out 'nosfry aarch64 newest is 2.30' 'needs GLIBC_2.30 <= floor 2.31'

# Floor equal to the newest need passes.
expect_ok 'nosfry x86_64 @ its newest 2.30' nosfry-0.4.0-x86_64-unknown-linux-gnu.txt 2.30
expect_out 'equality prints the ok line' 'needs GLIBC_2.30 <= floor 2.30'

# One minor below the newest need fails.
expect_fail 'nosfry x86_64 @ 2.29' nosfry-0.4.0-x86_64-unknown-linux-gnu.txt 2.29
expect_out 'fail names the newest' 'needs GLIBC_2.30, newer than the floor 2.29'

# Every glibc binary needs the GLIBC_2.2.5 base version, and the nosfry
# fixture lists it alongside 2.9/2.17/2.30: lexicographic order would rank
# 2.9 or 2.2.5 above 2.17/2.30. A fail at floor 2.17 proves sort -V ordering.
run nosfry-0.4.0-x86_64-unknown-linux-gnu.txt 2.17
if [ "$code" -ne 0 ]; then echo 'ok nosfry x86_64 @ 2.17 fails'; else
  echo 'FAIL nosfry x86_64 @ 2.17 (expected fail)'; fail=1
fi
expect_out 'requires list contains the 2.2.5 base' 'requires GLIBC versions: '
expect_out '2.2.5 is listed' '2.2.5'
expect_out 'newest is 2.30 not 2.2.5 or 2.9' 'needs GLIBC_2.30, newer than the floor 2.17'

# kobe 7.0.0 was built by release-rust on ubuntu-24.04 (glibc 2.39): both
# arches must exceed a 2.31 floor.
expect_fail 'kobe x86_64 @ 2.31' kobe-7.0.0-x86_64-unknown-linux-gnu.txt 2.31
expect_out 'kobe x86_64 names 2.39' 'needs GLIBC_2.39, newer than the floor 2.31'
expect_fail 'kobe aarch64 @ 2.31' kobe-7.0.0-aarch64-unknown-linux-gnu.txt 2.31
expect_out 'kobe aarch64 names 2.39' 'needs GLIBC_2.39, newer than the floor 2.31'

# A statically linked musl binary has no version info at all.
expect_fail 'static-musl has no version needs' static-musl.txt 2.31
expect_out 'static-musl message' 'has no GLIBC_ version needs'

# Synthetic fixture: a verneed block with GLIBC_2.17 + GLIBC_PRIVATE plus a
# version definition section naming GLIBC_9.99. Only version needs count and
# PRIVATE is ignored, so the newest is 2.17 and a 2.17 floor passes.
expect_ok 'synthetic verneed+verdef @ 2.17' synthetic-private-and-verdef.txt 2.17
expect_out 'synthetic newest is 2.17' 'needs GLIBC_2.17 <= floor 2.17'

# Usage / input validation exits 2.
for bad in 2 2.31.1 v2.31 ''; do
  set +e
  READELF="$dir/readelf-stub.sh" bash "$dir/check.sh" "$fixtures/static-musl.txt" "$bad" 2>/dev/null
  code=$?
  set -e
  if [ "$code" -eq 2 ]; then echo "ok invalid floor '${bad}' exits 2"; else
    echo "FAIL invalid floor '${bad}' (expected exit 2, got ${code})"; fail=1
  fi
done
set +e
bash "$dir/check.sh" 2>/dev/null
code=$?
set -e
if [ "$code" -eq 2 ]; then echo 'ok missing args exit 2'; else
  echo "FAIL missing args (expected exit 2, got ${code})"; fail=1
fi

# A failing readelf exits 1.
set +e
out="$(READELF=false bash "$dir/check.sh" "$fixtures/static-musl.txt" 2.31 2>&1)"
code=$?
set -e
if [ "$code" -eq 1 ] && [[ "$out" == *'readelf failed'* ]]; then
  echo 'ok READELF=false fails'
else
  echo "FAIL READELF=false (got ${code}: ${out})"
  fail=1
fi

# Step summary gets one markdown row in both outcomes.
summary="$(mktemp)"
trap 'rm -f "$summary"' EXIT
: >"$summary"
set +e
GITHUB_STEP_SUMMARY="$summary" READELF="$dir/readelf-stub.sh" \
  bash "$dir/check.sh" "$fixtures/nosfry-0.4.0-x86_64-unknown-linux-gnu.txt" 2.31 >/dev/null 2>&1
GITHUB_STEP_SUMMARY="$summary" READELF="$dir/readelf-stub.sh" \
  bash "$dir/check.sh" "$fixtures/kobe-7.0.0-x86_64-unknown-linux-gnu.txt" 2.31 >/dev/null 2>&1
set -e
if grep -q '| Binary | Newest GLIBC | Floor | Result |' "$summary" \
  && grep -q '| 2.30 | 2.31 | ok |' "$summary" \
  && grep -q '| 2.39 | 2.31 | exceeds floor |' "$summary"; then
  echo 'ok step summary rows'
else
  echo "FAIL step summary rows:"; cat "$summary"; fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "glibc-floor tests failed"
  exit 1
fi
echo "glibc-floor tests passed"
