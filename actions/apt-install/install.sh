#!/usr/bin/env bash
set -euo pipefail

[ -z "${PACKAGES:-}" ] && exit 0

if printf '%s' "$PACKAGES" | grep -Eq '[;&|$`()\\]|\.\.'; then
  echo '::error::apt-install: illegal characters in packages'
  exit 1
fi
if ! printf '%s' "$PACKAGES" | grep -Eq '^[A-Za-z0-9+.:[:space:]-]+$'; then
  echo '::error::apt-install: charset'
  exit 1
fi

if [ "${CHARSET_ONLY:-}" = 1 ]; then
  exit 0
fi

sudo apt-get update
# word-split is intentional; -- stops option injection
# shellcheck disable=SC2086
sudo apt-get install -y -- $PACKAGES
