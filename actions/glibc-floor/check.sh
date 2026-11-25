#!/usr/bin/env bash
# glibc-floor: fail when an ELF binary requires a GLIBC_x.y symbol version
# newer than the floor. Usage: check.sh <elf> <floor>
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <elf> <floor: MAJOR.MINOR>" >&2
  exit 2
fi

elf="$1"
floor="$2"

if [[ ! "$floor" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "glibc-floor: invalid floor '${floor}' (expected MAJOR.MINOR, e.g. 2.31)" >&2
  exit 2
fi

READELF="${READELF:-readelf}"
if ! info="$("$READELF" --version-info --wide "$elf" 2>/dev/null)"; then
  echo "::error::glibc-floor: readelf failed on ${elf}"
  exit 1
fi

# Only 'Version needs section' blocks count what the binary requires: the
# version symbols section repeats them per symbol, and a version definition
# section names versions the binary provides. GLIBC_PRIVATE carries no
# digits and is ignored by the pattern.
versions="$(printf '%s\n' "$info" | awk '
  /Version needs section/ { in_needs = 1; next }
  /Version symbols section|Version definition section/ { in_needs = 0 }
  in_needs { print }
' | grep -oE 'GLIBC_[0-9]+(\.[0-9]+)+' | sed 's/^GLIBC_//' | sort -uV)" || true

if [ -z "$versions" ]; then
  echo "::error::glibc-floor: ${elf} has no GLIBC_ version needs (not a dynamically linked glibc binary)"
  exit 1
fi

echo "glibc-floor: ${elf} requires GLIBC versions: $(printf '%s\n' "$versions" | tr '\n' ' ' | sed 's/ $//')"

newest="$(printf '%s\n' "$versions" | tail -n 1)"
# versions is already sorted with sort -V, so tail is the max. The check
# stays numeric: sort -V makes 2.17 newer than 2.9 and 2.2.5.
if [ "$(printf '%s\n%s\n' "$newest" "$floor" | sort -V | tail -n 1)" = "$floor" ]; then
  result='ok'
  echo "glibc-floor: ${elf} needs GLIBC_${newest} <= floor ${floor}"
else
  result='exceeds floor'
  echo "::error::glibc-floor: ${elf} needs GLIBC_${newest}, newer than the floor ${floor}"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo ''
    echo '| Binary | Newest GLIBC | Floor | Result |'
    echo '| --- | --- | --- | --- |'
    echo "| \`${elf}\` | ${newest} | ${floor} | ${result} |"
  } >>"$GITHUB_STEP_SUMMARY"
fi

[ "$result" = 'ok' ]
