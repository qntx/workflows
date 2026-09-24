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
  bun) pre='bun run build:wasm' ;;
  npm) pre='npm run build:wasm' ;;
  *) die 'package-manager must be bun or npm' ;;
esac

if ! jq -e . "$pkg" >/dev/null 2>&1; then
  die 'package.json is not valid JSON'
fi

if [ "$(jq -r '.files == ["dist"]' "$pkg")" != true ]; then
  die 'files must be ["dist"]'
fi

if [ "$(jq -r '.sideEffects | type' "$pkg")" != array ]; then
  die 'sideEffects must be an array containing **/*.wasm'
fi
if [ "$(jq -r 'any(.sideEffects[]; . == "**/*.wasm")' "$pkg")" != true ]; then
  die 'sideEffects must contain **/*.wasm'
fi

if [ "$(jq -r '.exports["."].import | type' "$pkg")" != string ]; then
  die 'exports["."].import is missing'
fi
root_import="$(jq -r '.exports["."].import' "$pkg")"
case "$root_import" in
  *wasm*) die 'exports["."].import must not contain wasm' ;;
esac

if [ "$(jq -r '.exports["./wasm"].import | type' "$pkg")" != string ]; then
  die 'exports["./wasm"].import is missing'
fi
if [ -z "$(jq -r '.exports["./wasm"].import' "$pkg")" ]; then
  die 'exports["./wasm"].import is missing'
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

need_script build
build="$(jq -r '.scripts.build' "$pkg")"
case "$build" in
  *build:wasm* | *WASM_PACK*) die 'scripts.build must not run the wasm build' ;;
esac

need_script 'build:wasm'
need_script 'test:wasm'

got_pre="$(jq -r '.scripts.prepublishOnly' "$pkg")"
if [ "$(jq -r '.scripts.prepublishOnly | type' "$pkg")" != string ] || [ "$got_pre" != "$pre" ]; then
  die "scripts.prepublishOnly must be exactly ${pre}"
fi

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
