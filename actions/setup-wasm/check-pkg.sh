#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "::error::setup-wasm: $*" >&2
  exit 1
}

if ! command -v jq >/dev/null 2>&1; then
  die 'jq is required'
fi

pkg="${1:-}"
if [ -z "$pkg" ] || [ ! -f "$pkg" ]; then
  die 'package.json not found'
fi

pm="${PM:-}"
case "$pm" in
  bun | npm) ;;
  *) die 'package-manager must be bun or npm' ;;
esac

if ! jq -e . "$pkg" >/dev/null 2>&1; then
  die 'package.json is not valid JSON'
fi

if [ "$(jq -r '.files | type' "$pkg")" != array ]; then
  die 'files must be an array'
fi
if [ "$(jq -r 'any(.files[]; . == "dist")' "$pkg")" != true ]; then
  die 'files must contain "dist"'
fi
while IFS= read -r entry; do
  case "$entry" in
    dist) ;;
    dist/*)
      case "$entry" in
        *..* | *[\*\?\[]*) die "files entry \"${entry}\" is not allowed" ;;
      esac
      ;;
    *)
      printf '%s\n' "$entry" | grep -qiE '^(LICEN[CS]E|COPYING|NOTICE|README|CHANGELOG)([-.][A-Za-z0-9.-]+)?$' ||
        die "files entry \"${entry}\" is not allowed"
      ;;
  esac
done < <(jq -r '.files[]' "$pkg")

if [ "$(jq -r '.sideEffects | type' "$pkg")" != array ]; then
  die 'sideEffects must be an array containing **/*.wasm'
fi
if [ "$(jq -r 'any(.sideEffects[]; . == "**/*.wasm")' "$pkg")" != true ]; then
  die 'sideEffects must contain **/*.wasm'
fi

dist_export="${DIST_EXPORT:-./wasm}"
case "$dist_export" in
  .) ;;
  ./) die 'dist-export is empty' ;;
  ./*[!A-Za-z0-9._/-]* | ./*/) die 'dist-export charset' ;;
  ./*) ;;
  *) die 'dist-export must be . or start with ./' ;;
esac

# `.import` on a string export is a jq error, not null, so branch on type first.
wasm_import="$(jq -r --arg e "$dist_export" '
  .exports[$e] as $w
  | if $w == null then ""
    elif ($w | type) == "string" then $w
    elif ($w | type) == "object" and ($w.import | type) == "string" then $w.import
    else ""
    end
' "$pkg")"
if [ -z "$wasm_import" ]; then
  die "exports[\"${dist_export}\"].import is missing"
fi

need_script() {
  local key="$1"
  if [ "$(jq -r --arg k "$key" '.scripts[$k] | type' "$pkg")" != string ]; then
    die "scripts.${key} is missing"
  fi
  if [ -z "$(jq -r --arg k "$key" '.scripts[$k]' "$pkg")" ]; then
    die "scripts.${key} is missing"
  fi
}

need_script 'build:wasm'
need_script 'test:wasm'

for key in install postinstall prepublish; do
  if [ "$(jq -r --arg k "$key" '.scripts | has($k)' "$pkg")" = true ]; then
    die "scripts.${key} is forbidden"
  fi
done

if [ "$(jq -r '.devEngines.packageManager | type' "$pkg")" != null ]; then
  if [ "$(jq -r '.devEngines.packageManager | type' "$pkg")" != object ]; then
    die 'devEngines.packageManager must be an object'
  fi
  name="$(jq -r '.devEngines.packageManager.name // empty' "$pkg")"
  onfail="$(jq -r '.devEngines.packageManager.onFail // empty' "$pkg")"
  if [ "$name" != "$pm" ]; then
    die 'devEngines.packageManager.name must equal package-manager'
  fi
  if [ "$onfail" != ignore ]; then
    die 'devEngines.packageManager.onFail must be ignore'
  fi
fi
