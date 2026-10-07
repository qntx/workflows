#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
fail=0
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

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

new_ws() {
  ws="$(mktemp -d "$root/ws.XXXXXX")"
  wd="$(mktemp -d "$root/wd.XXXXXX")"
}

plan() {
  env -u GITHUB_OUTPUT WORK_DIR="$wd" GITHUB_WORKSPACE="${GW:-$wd}" RUST_VERSION="${RUST_VERSION-}" bash "$dir/plan.sh"
}

plan_rv() {
  RUST_VERSION="$1" plan
}

new_ws
expect_out 'explicit wins without file' 'explicit' plan_rv stable

new_ws
printf '%s\n' '[toolchain]' 'channel = "1.94"' >"$wd/rust-toolchain.toml"
expect_out 'explicit wins over toml' 'explicit' plan_rv beta

new_ws
printf '%s\n' '[toolchain]' 'channel = "1.94"' >"$wd/rust-toolchain.toml"
expect_out 'toml gives file' 'file' plan

new_ws
printf '%s\n' '1.94' >"$wd/rust-toolchain"
expect_out 'plain file gives file' 'file' plan

new_ws
mkdir "$wd/rust-toolchain.toml"
expect_out 'toml directory is not the file' 'stable' plan

new_ws
expect_out 'no file gives stable' 'stable' plan

new_ws
printf '%s\n' 'channel = "beta"' >"$wd/rust-toolchain.toml"
out="$(mktemp "$root/out.XXXXXX")"
WORK_DIR="$wd" RUST_VERSION='' GITHUB_OUTPUT="$out" bash "$dir/plan.sh" >/dev/null
if [ "$(cat "$out")" = 'mode=file' ]; then
  echo 'ok github output mode'
else
  echo "FAIL github output mode: $(cat "$out")"
  fail=1
fi

new_ws
expect_fail_msg 'rust-version charset' 'charset' plan_rv '1.94;rm'

new_ws
expect_fail_msg 'missing work dir' 'not found' env -u GITHUB_OUTPUT WORK_DIR="$root/no-such-dir" RUST_VERSION='' bash "$dir/plan.sh"

# rustup walks up from the working directory; the walk must stop at
# GITHUB_WORKSPACE (inclusive) like the caller jail does.
ws_anc="$(mktemp -d "$root/ancws.XXXXXX")"
mkdir -p "$ws_anc/sub/deep"
printf '%s\n' '[toolchain]' 'channel = "1.94"' >"$ws_anc/rust-toolchain.toml"
wd="$ws_anc/sub/deep"
expect_out 'ancestor file inside workspace' 'file' env -u GITHUB_OUTPUT WORK_DIR="$wd" GITHUB_WORKSPACE="$ws_anc" RUST_VERSION='' bash "$dir/plan.sh"

ws_above="$(mktemp -d "$root/abovews.XXXXXX")"
mkdir -p "$ws_above/sub"
printf '%s\n' '[toolchain]' 'channel = "1.94"' >"$root/rust-toolchain.toml"
wd="$ws_above/sub"
expect_out 'file above workspace ignored' 'stable' env -u GITHUB_OUTPUT WORK_DIR="$wd" GITHUB_WORKSPACE="$ws_above" RUST_VERSION='' bash "$dir/plan.sh"
rm -f "$root/rust-toolchain.toml"
new_ws

# install.sh charset gates reject metacharacters before rustup runs.
expect_fail_msg 'components charset ;' 'components charset' env -u GITHUB_OUTPUT WORK_DIR="$wd" COMPONENTS='rustfmt;rm' bash "$dir/install.sh"
expect_fail_msg 'components charset @' 'components charset' env -u GITHUB_OUTPUT WORK_DIR="$wd" COMPONENTS='rustfmt@x' bash "$dir/install.sh"
expect_fail_msg 'components charset [' 'components charset' env -u GITHUB_OUTPUT WORK_DIR="$wd" COMPONENTS='rust[fmt' bash "$dir/install.sh"
expect_fail_msg 'targets charset ;' 'targets charset' env -u GITHUB_OUTPUT WORK_DIR="$wd" TARGETS='wasm32;rm' bash "$dir/install.sh"
expect_fail_msg 'targets charset @' 'targets charset' env -u GITHUB_OUTPUT WORK_DIR="$wd" TARGETS='wasm32@x' bash "$dir/install.sh"
expect_fail_msg 'targets charset [' 'targets charset' env -u GITHUB_OUTPUT WORK_DIR="$wd" TARGETS='wasm32[x' bash "$dir/install.sh"

# Jail: reuse the setup-wasm contract at a smaller surface.
ws_root="$(mktemp -d "$root/wsroot.XXXXXX")"
mkdir -p "$ws_root/packages/foo" "$ws_root/outside-parent"
outside="$(mktemp -d "$root/outside.XXXXXX")"
ln -s "$outside" "$ws_root/outlink"

jail() {
  GITHUB_WORKSPACE="$ws_root" REL="$1" bash "$dir/jail.sh"
}

expect_out 'jail dot' "$(realpath "$ws_root")" jail '.'
expect_out 'jail subdir' "$(realpath "$ws_root/packages/foo")" jail 'packages/foo'
expect_fail_msg 'dotdot stays inside' 'empty or ..' jail 'packages/../outside-parent'
expect_fail_msg 'leading dotdot' 'start with .' jail '../b'
expect_fail_msg 'absolute' 'relative' jail '/etc'
expect_fail_msg 'charset' 'charset' jail 'foo;rm'
expect_fail_msg 'missing dir' 'does not exist' jail 'missing-dir'
expect_fail_msg 'symlink escape' 'escapes workspace' jail 'outlink'

out="$(mktemp "$root/out.XXXXXX")"
GITHUB_WORKSPACE="$ws_root" REL='packages/foo' GITHUB_OUTPUT="$out" bash "$dir/jail.sh" >/dev/null
if grep -q '^rel=packages/foo$' "$out" && grep -q "^path=$(realpath "$ws_root/packages/foo")$" "$out"; then
  echo 'ok jail outputs path and rel'
else
  echo "FAIL jail outputs: $(cat "$out")"
  fail=1
fi
out="$(mktemp "$root/out.XXXXXX")"
GITHUB_WORKSPACE="$ws_root" REL='.' GITHUB_OUTPUT="$out" bash "$dir/jail.sh" >/dev/null
if grep -q '^rel=\.$' "$out"; then
  echo 'ok jail rel dot'
else
  echo "FAIL jail rel dot: $(cat "$out")"
  fail=1
fi

action="$dir/action.yml"
if [ "$(grep -c 'dtolnay/rust-toolchain@6c977a6ca4077a0ceb28ffbe03f59d46e9ac8772' "$action")" -eq 2 ] &&
  [ "$(grep -c 'Swatinem/rust-cache@6323deb102c322ba6fcbdcafc7e3dddab59af2b6' "$action")" -eq 1 ] &&
  grep -F 'toolchain: ${{ inputs.rust-version }}' "$action" >/dev/null &&
  grep -F 'toolchain: stable' "$action" >/dev/null &&
  grep -F "if: steps.plan.outputs.mode == 'explicit'" "$action" >/dev/null &&
  grep -F "if: steps.plan.outputs.mode == 'file'" "$action" >/dev/null &&
  grep -F "if: steps.plan.outputs.mode == 'stable'" "$action" >/dev/null &&
  grep -F 'RUSTUP_TOOLCHAIN' "$action" >/dev/null &&
  grep -F 'rustup show active-toolchain' "$action" >/dev/null &&
  grep -F 'bash "$GITHUB_ACTION_PATH/plan.sh"' "$action" >/dev/null &&
  grep -F 'bash "$GITHUB_ACTION_PATH/install.sh"' "$action" >/dev/null &&
  grep -F 'bash "$GITHUB_ACTION_PATH/jail.sh"' "$action" >/dev/null &&
  grep -F "default: ''" "$action" >/dev/null &&
  grep -F 'steps.resolve.outputs.toolchain' "$action" >/dev/null &&
  grep -F 'steps.resolve.outputs.rustc' "$action" >/dev/null &&
  grep -F 'workspaces: ${{ steps.workdir.outputs.rel }}' "$action" >/dev/null; then
  echo 'ok action wiring'
else
  echo 'FAIL action wiring'
  fail=1
fi

if [ -e "$dir/channel.sh" ] || grep -q 'channel\.sh' "$action"; then
  echo 'FAIL channel.sh remains or is referenced'
  fail=1
else
  echo 'ok no channel.sh'
fi

if grep -qE '^  (toolchain-file|channel):' "$action"; then
  echo 'FAIL obsolete toolchain-file input or channel output remains'
  fail=1
else
  echo 'ok no obsolete toolchain-file or channel'
fi

if grep -nE '0\.2\.122|1\.94' "$action" "$dir/plan.sh" "$dir/jail.sh" "$dir/install.sh"; then
  echo 'FAIL hardcoded version'
  fail=1
else
  echo 'ok no hardcoded version'
fi

if grep -n 'set -x' "$action" "$dir/plan.sh" "$dir/jail.sh" "$dir/install.sh"; then
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
