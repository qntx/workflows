#!/usr/bin/env bash
set -euo pipefail

publish_one() {
  local spec="$1"
  local attempt=0
  local max_attempts=12
  local log status wait_s retry_line when target now
  local -a args=(--locked)

  if [ -n "$spec" ]; then
    args=(-p "$spec" --locked)
  fi

  while [ "$attempt" -lt "$max_attempts" ]; do
    attempt=$((attempt + 1))
    log="$(mktemp)"
    echo "::group::Publishing ${spec:-.} (attempt ${attempt})"
    set +e
    cargo publish "${args[@]}" >"$log" 2>&1
    status=$?
    set -e
    cat "$log"
    echo "::endgroup::"

    if [ "$status" -eq 0 ]; then
      rm -f "$log"
      return 0
    fi

    if grep -Eqi 'already exists on crates\.io|already been uploaded|already uploaded' "$log"; then
      echo "${spec:-.} already on crates.io; skipping"
      rm -f "$log"
      return 0
    fi

    if grep -Fq 'Too Many Requests' "$log"; then
      wait_s=120
      retry_line="$(grep -oE 'try again after [^[:space:]].*GMT' "$log" | head -n1 || true)"
      if [ -n "$retry_line" ]; then
        when="${retry_line#try again after }"
        target="$(date -u -d "$when" +%s)"
        now="$(date -u +%s)"
        wait_s=$((target - now + 15))
      fi
      if [ "$wait_s" -lt 60 ]; then
        wait_s=60
      fi
      if [ "$wait_s" -gt 900 ]; then
        wait_s=900
      fi
      rm -f "$log"
      echo "crates.io 429 for ${spec:-.}; sleeping ${wait_s}s"
      sleep "$wait_s"
      continue
    fi

    rm -f "$log"
    echo "::error::cargo publish failed for ${spec:-.}"
    return 1
  done

  echo "::error::exhausted retries for ${spec:-.}"
  return 1
}

if [ -n "${PACKAGES:-}" ]; then
  if ! printf '%s' "$PACKAGES" | grep -Eq '^[A-Za-z0-9_[:space:]-]+$'; then
    echo '::error::packages charset'
    exit 1
  fi
  # shellcheck disable=SC2086
  for pkg in $PACKAGES; do
    publish_one "$pkg"
  done
else
  publish_one ""
fi
