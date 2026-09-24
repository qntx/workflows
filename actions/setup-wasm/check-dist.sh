#!/usr/bin/env bash
# `./dist/wasm.mjs` strips once to `dist/wasm.mjs`. `././dist/...` must not pass.
set -euo pipefail

die() {
  echo "::error::setup-wasm: $*" >&2
  exit 1
}

if ! command -v jq >/dev/null 2>&1; then
  die 'jq is required'
fi

dir="${PACKAGE_DIR:-}"
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  die 'package directory not found'
fi
pkg="${dir}/package.json"
if [ ! -f "$pkg" ]; then
  die 'package.json not found'
fi
if ! jq -e . "$pkg" >/dev/null 2>&1; then
  die 'package.json is not valid JSON'
fi

# `.import` on a string export is a jq error, not null, so branch on type first.
rel="$(jq -r '
  .exports["./wasm"] as $w
  | if $w == null then ""
    elif ($w | type) == "string" then $w
    elif ($w | type) == "object" and ($w.import | type) == "string" then $w.import
    else ""
    end
' "$pkg")"
if [ -z "$rel" ]; then
  die 'exports["./wasm"] is missing'
fi

case "$rel" in
  ./*) rel="${rel#./}" ;;
esac

case "$rel" in
  dist/*) ;;
  *) die 'exports["./wasm"] must point at dist/' ;;
esac

old_ifs="$IFS"
IFS=/
set -f
for seg in $rel; do
  if [ -z "$seg" ] || [ "$seg" = .. ]; then
    set +f
    IFS="$old_ifs"
    die 'exports["./wasm"] path is not safe'
  fi
done
set +f
IFS="$old_ifs"

summary="${GITHUB_STEP_SUMMARY:-}"
cd "$dir"

if [ ! -f "$rel" ]; then
  die "missing ${rel}"
fi

shopt -s nullglob
wasm_files=(dist/*.wasm)
if [ "${#wasm_files[@]}" -eq 0 ]; then
  die 'no dist/*.wasm'
fi

if [ -n "$summary" ]; then
  {
    echo '### wasm dist'
    for f in "${wasm_files[@]}"; do
      bytes="$(wc -c <"$f" | tr -d '[:space:]')"
      printf '%s %s\n' "$bytes" "$f"
    done
  } >>"$summary"
fi
