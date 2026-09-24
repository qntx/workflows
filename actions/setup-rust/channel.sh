#!/usr/bin/env bash
# Parse the rustup channel. A comment may contain a version; only a channel assignment counts.
set -euo pipefail

die() {
  echo "::error::setup-rust: $*" >&2
  exit 1
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

channel_re='^channel[[:space:]]*=[[:space:]]*"([^"]*)"[[:space:]]*$'

if [ -n "${RUST_VERSION:-}" ]; then
  die 'rust-version must be empty when toolchain-file is true'
fi

ws="${GITHUB_WORKSPACE:-}"
if [ -z "$ws" ]; then
  die 'GITHUB_WORKSPACE is unset'
fi

toml="${ws}/rust-toolchain.toml"
plain="${ws}/rust-toolchain"
mode=plain
file=
if [ -f "$toml" ]; then
  file="$toml"
  mode=toml
elif [ -f "$plain" ]; then
  file="$plain"
  mode=plain
else
  die 'rust-toolchain.toml or rust-toolchain not found'
fi

toml_count=0
content_count=0
toml_value=
content_value=
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  trimmed="$(trim "$line")"
  if [ -z "$trimmed" ]; then
    continue
  fi
  case "$trimmed" in
    \#*) continue ;;
  esac
  if [[ "$trimmed" =~ $channel_re ]]; then
    toml_count=$((toml_count + 1))
    toml_value="${BASH_REMATCH[1]}"
    continue
  fi
  case "$trimmed" in
    \[*\]) continue ;;
  esac
  content_count=$((content_count + 1))
  content_value="$trimmed"
done <"$file"

if [ "$mode" = toml ] || [ "$toml_count" -gt 0 ]; then
  if [ "$toml_count" -ne 1 ]; then
    die 'expected exactly one channel assignment'
  fi
  channel="$toml_value"
else
  if [ "$content_count" -ne 1 ]; then
    die 'expected exactly one channel line'
  fi
  channel="$content_value"
fi

case "$channel" in
  '' | *[!A-Za-z0-9._+-]*)
    die 'channel charset'
    ;;
esac

printf '%s\n' "$channel"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'channel=%s\n' "$channel" >>"$GITHUB_OUTPUT"
fi
