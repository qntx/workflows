#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
fail=0
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

expect_ok() {
  local label="$1"
  shift
  if "$@"; then
    echo "ok ${label}"
  else
    echo "FAIL ${label} (expected ok)"
    fail=1
  fi
}

expect_out() {
  local label="$1" want="$2"
  shift 2
  local got
  if got="$("$@")"; then
    if [ "$got" = "$want" ]; then
      echo "ok ${label}"
    else
      echo "FAIL ${label}: got '${got}' want '${want}'"
      fail=1
    fi
  else
    echo "FAIL ${label} (expected ok)"
    fail=1
  fi
}

expect_fail_msg() {
  local label="$1" needle="$2"
  shift 2
  local err rc
  set +e
  err="$("$@" 2>&1 >/dev/null)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL ${label} (expected fail)"
    fail=1
    return
  fi
  case "$err" in
    *"$needle"*) echo "ok ${label}" ;;
    *)
      echo "FAIL ${label}: stderr missing '${needle}': ${err}"
      fail=1
      ;;
  esac
}

expect_fail_silent() {
  local label="$1"
  shift
  local out rc
  set +e
  out="$("$@" 2>/dev/null)"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL ${label} (expected fail)"
    fail=1
    return
  fi
  if [ -n "$out" ]; then
    echo "FAIL ${label}: stdout not empty: ${out}"
    fail=1
    return
  fi
  echo "ok ${label}"
}

new_ws() {
  ws="$(mktemp -d "$root/ws.XXXXXX")"
  other="$(mktemp -d "$root/cwd.XXXXXX")"
}

run_channel() {
  (
    cd "$other"
    if [ "${RUST_VERSION+x}" = x ]; then
      env -u GITHUB_OUTPUT GITHUB_WORKSPACE="$ws" RUST_VERSION="$RUST_VERSION" bash "$dir/channel.sh"
    else
      env -u GITHUB_OUTPUT -u RUST_VERSION GITHUB_WORKSPACE="$ws" bash "$dir/channel.sh"
    fi
  )
}

# The comment's version must not win. 1.94 in the comment, channel is 1.93.
new_ws
cat >"$ws/rust-toolchain.toml" <<'EOF'
# Pin to the workspace MSRV (1.94, edition 2024).
[toolchain]
channel = "1.93"
components = ["rustfmt", "clippy"]
targets = ["wasm32-unknown-unknown"]
profile = "minimal"
EOF
unset RUST_VERSION
expect_out 'comment version does not win' '1.93' run_channel

# The nostr.js comment shape, channel equal to the number in the comment.
new_ws
cat >"$ws/rust-toolchain.toml" <<'EOF'
# Pin to the workspace MSRV (1.94, edition 2024).
# channel = "nightly"
[toolchain]
channel = "1.94"
components = ["rustfmt", "clippy"]
targets = ["wasm32-unknown-unknown"]
profile = "minimal"
EOF
expect_out 'nostr comment above channel' '1.94' run_channel

new_ws
printf '%s\n' '1.94' >"$ws/rust-toolchain"
expect_out 'one-line file' '1.94' run_channel

new_ws
printf '%s\n' '  1.94  ' >"$ws/rust-toolchain"
expect_out 'one-line trimmed' '1.94' run_channel

new_ws
cat >"$ws/rust-toolchain" <<'EOF'

# comment with 1.94
[toolchain]
1.94

EOF
expect_out 'one-line ignores comment and section' '1.94' run_channel

new_ws
printf '%s\n' 'channel = "nightly"' >"$ws/rust-toolchain"
expect_out 'plain file toml form' 'nightly' run_channel

new_ws
printf '%s\n' '1.94' >"$ws/rust-toolchain"
cat >"$ws/rust-toolchain.toml" <<'EOF'
# Pin to the workspace MSRV (1.94, edition 2024).
channel = "nightly"
EOF
expect_out 'toml wins over plain file' 'nightly' run_channel

new_ws
printf '%s\n' '1.94' >"$ws/rust-toolchain"
printf '\n' >"$ws/rust-toolchain.toml"
expect_fail_silent 'empty toml does not fall through' run_channel

new_ws
mkdir "$ws/rust-toolchain.toml"
printf '%s\n' 'stable' >"$ws/rust-toolchain"
expect_out 'toml directory is not the file' 'stable' run_channel

new_ws
cat >"$ws/rust-toolchain.toml" <<'EOF'
channel = "nightly-2024-01-01"
EOF
expect_out 'dated nightly' 'nightly-2024-01-01' run_channel

new_ws
cat >"$ws/rust-toolchain.toml" <<'EOF'
  channel="1.94.0"
EOF
expect_out 'tight quotes and patch' '1.94.0' run_channel

new_ws
printf '%s\n' 'channel = "beta"' >"$ws/rust-toolchain.toml"
RUST_VERSION=''
expect_out 'empty rust-version is allowed' 'beta' run_channel
unset RUST_VERSION

new_ws
printf '%s\n' 'channel = "beta"' >"$ws/rust-toolchain.toml"
out="$(mktemp "$root/out.XXXXXX")"
(
  cd "$other"
  GITHUB_WORKSPACE="$ws" GITHUB_OUTPUT="$out" bash "$dir/channel.sh" >"$root/stdout.txt"
)
if [ "$(cat "$root/stdout.txt")" = beta ] && [ "$(wc -l <"$out" | tr -d '[:space:]')" -eq 1 ] && [ "$(cat "$out")" = 'channel=beta' ]; then
  echo 'ok github output line'
else
  echo "FAIL github output line stdout=$(cat "$root/stdout.txt") file=$(cat "$out")"
  fail=1
fi

new_ws
printf '%s\n' '1.94' 'nightly' >"$ws/rust-toolchain"
expect_fail_silent 'two bare lines' run_channel

new_ws
cat >"$ws/rust-toolchain.toml" <<'EOF'
channel = "1.94"
channel = "1.94"
EOF
expect_fail_silent 'two identical assignments' run_channel

new_ws
cat >"$ws/rust-toolchain.toml" <<'EOF'
# only a comment 1.94
[toolchain]
profile = "minimal"
EOF
expect_fail_msg 'no channel assignment' 'exactly one channel' run_channel

new_ws
expect_fail_msg 'missing files' 'not found' run_channel

new_ws
printf '%s\n' 'channel = "1.94"' >"$ws/rust-toolchain.toml"
RUST_VERSION='stable'
expect_fail_msg 'rust-version stable' 'rust-version must be empty' run_channel
RUST_VERSION=' '
expect_fail_msg 'rust-version whitespace' 'rust-version must be empty' run_channel
unset RUST_VERSION

new_ws
printf '%s\n' 'channel = "1.94;rm"' >"$ws/rust-toolchain.toml"
expect_fail_msg 'charset semicolon' 'charset' run_channel

new_ws
printf '%s\n' 'channel = "has space"' >"$ws/rust-toolchain.toml"
expect_fail_msg 'charset space' 'charset' run_channel

new_ws
printf '%s\n' 'channel = ""' >"$ws/rust-toolchain.toml"
expect_fail_msg 'empty channel' 'charset' run_channel

new_ws
printf '%s\n' 'channel = "1.94.0-x86_64-unknown-linux-gnu"' >"$ws/rust-toolchain.toml"
expect_out 'underscore is in the charset' '1.94.0-x86_64-unknown-linux-gnu' run_channel

new_ws
printf '%s\n' 'channel = "beta@nightly"' >"$ws/rust-toolchain.toml"
expect_fail_msg 'charset at' 'charset' run_channel

new_ws
printf '%s\n' 'channel = "stable/gnu"' >"$ws/rust-toolchain.toml"
expect_fail_msg 'charset slash' 'charset' run_channel

new_ws
printf '%s\n' "channel = 'beta'" >"$ws/rust-toolchain.toml"
expect_fail_silent 'single quotes are not toml channel' run_channel

new_ws
printf '%s\n' 'channel = "beta" # trailing' >"$ws/rust-toolchain.toml"
expect_fail_silent 'trailing comment is not an assignment' run_channel

new_ws
printf '%s\n' '# only' >"$ws/rust-toolchain"
expect_fail_silent 'comment-only plain file' run_channel

(
  cd "$other"
  env -u GITHUB_WORKSPACE bash "$dir/channel.sh" >/dev/null 2>&1
) && {
  echo 'FAIL unset workspace (expected fail)'
  fail=1
} || echo 'ok unset workspace'

# Wiring: both dtolnay steps pass toolchain. The pin does not read the file.
action="$dir/action.yml"
if [ "$(grep -c 'dtolnay/rust-toolchain@6c977a6ca4077a0ceb28ffbe03f59d46e9ac8772' "$action")" -eq 2 ] &&
  [ "$(grep -c 'Swatinem/rust-cache@6323deb102c322ba6fcbdcafc7e3dddab59af2b6' "$action")" -eq 1 ] &&
  grep -q 'toolchain: ${{ inputs.rust-version }}' "$action" &&
  grep -q 'toolchain: ${{ steps.channel.outputs.channel }}' "$action" &&
  grep -q "if: inputs.toolchain-file == 'true'" "$action" &&
  grep -q "if: inputs.toolchain-file != 'true'" "$action" &&
  grep -q 'default: '"'"'stable'"'"'' "$action" &&
  grep -q 'default: '"'"'false'"'"'' "$action" &&
  grep -q 'steps.channel.outputs.channel || inputs.rust-version' "$action" &&
  grep -q 'bash "$GITHUB_ACTION_PATH/channel.sh"' "$action"; then
  echo 'ok action wiring'
else
  echo 'FAIL action wiring'
  fail=1
fi

if grep -nE '0\.2\.122|1\.94' "$action" "$dir/channel.sh"; then
  echo 'FAIL hardcoded channel or bindgen version'
  fail=1
else
  echo 'ok no hardcoded version'
fi

if grep -n 'set -x' "$action" "$dir/channel.sh"; then
  echo 'FAIL set -x'
  fail=1
else
  echo 'ok no set -x'
fi

if [ "$fail" -ne 0 ]; then
  echo 'setup-rust tests failed'
  exit 1
fi
echo 'setup-rust tests passed'
