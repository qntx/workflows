#!/usr/bin/env bash
set -euo pipefail

if [ -z "${GITHUB_ENV:-}" ]; then
  echo '::error::parse-env-block: GITHUB_ENV is unset'
  exit 1
fi

block="${BLOCK-}"
if [ -z "$block" ]; then
  exit 0
fi

allowed_key() {
  case "$1" in
    CARGO_TARGET_*) return 0 ;;
    CC | CXX | AR | RANLIB | CFLAGS | CXXFLAGS | CPPFLAGS | LDFLAGS) return 0 ;;
    RUSTFLAGS | RUSTC_WRAPPER | RUSTC_WORKSPACE_WRAPPER) return 0 ;;
    BINDGEN_EXTRA_CLANG_ARGS | BINDGEN_EXTRA_CLANG_ARGS_*) return 0 ;;
    *) return 1 ;;
  esac
}

n=0
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  line="${line%$'\r'}"
  [ -z "$line" ] && continue

  if [[ "$line" == *'<<'* ]]; then
    echo "::error::parse-env-block: heredoc delimiter on line ${n}"
    exit 1
  fi

  if ! [[ "$line" =~ ^[A-Z_][A-Z0-9_]*=.*$ ]]; then
    echo "::error::parse-env-block: invalid line ${n}"
    exit 1
  fi

  key="${line%%=*}"
  if ! allowed_key "$key"; then
    echo "::error::parse-env-block: unknown key ${key}"
    exit 1
  fi

  printf '%s\n' "$line" >>"$GITHUB_ENV"
done <<<"$block"
