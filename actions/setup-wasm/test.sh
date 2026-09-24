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

lock_file() {
  local dest
  dest="$(mktemp "$root/lock.XXXXXX")"
  cat >"$dest"
  printf '%s' "$dest"
}

pkg_variant() {
  local dest
  dest="$(mktemp "$root/pkg.XXXXXX")"
  jq "$1" "$dir/fixtures/pkg/package.json" >"$dest"
  printf '%s' "$dest"
}

copy_pkg() {
  local dest
  dest="$(mktemp -d "$root/tree.XXXXXX")"
  mkdir -p "$dest/dist"
  cp "$dir/fixtures/pkg/package.json" "$dest/package.json"
  cp "$dir/fixtures/pkg/dist/wasm.mjs" "$dest/dist/wasm.mjs"
  cp "$dir/fixtures/pkg/dist/fixture.wasm" "$dest/dist/fixture.wasm"
  printf '%s' "$dest"
}

run_cdylib() {
  bash "$dir/check-cdylib.sh" <<<"$1"
}

meta_one() {
  local publish="$1" types="$2" members="$3" kind="$4"
  if [ "$members" = omit ]; then
    jq -n \
      --argjson publish "$publish" \
      --argjson types "$types" \
      --argjson kind "$kind" \
      '{packages:[{id:"id:accel",name:"accel",publish:$publish,targets:[{kind:$kind,crate_types:$types,name:"accel"}]}]}'
  else
    jq -n \
      --argjson publish "$publish" \
      --argjson types "$types" \
      --argjson members "$members" \
      --argjson kind "$kind" \
      '{packages:[{id:"id:accel",name:"accel",publish:$publish,targets:[{kind:$kind,crate_types:$types,name:"accel"}]}],workspace_members:$members}'
  fi
}

lines="$(bash "$dir/lockver.sh" "$dir/fixtures/Cargo.lock" wasm-bindgen | wc -l | tr -d '[:space:]')"
if [ "$lines" = 1 ]; then
  echo 'ok lockver one line'
else
  echo "FAIL lockver one line: ${lines}"
  fail=1
fi
expect_out 'fixture wasm-bindgen' '0.2.122' bash "$dir/lockver.sh" "$dir/fixtures/Cargo.lock" wasm-bindgen
expect_out 'fixture macro exact name' '0.2.122' bash "$dir/lockver.sh" "$dir/fixtures/Cargo.lock" wasm-bindgen-macro

macro_only="$(lock_file <<'EOF'
version = 4

[[package]]
name = "wasm-bindgen-macro"
version = "0.2.122"
EOF
)"
expect_fail_silent 'macro only is not wasm-bindgen' bash "$dir/lockver.sh" "$macro_only" wasm-bindgen

differ="$(lock_file <<'EOF'
version = 4

[[package]]
name = "wasm-bindgen-macro"
version = "0.2.1"

[[package]]
name = "wasm-bindgen"
version = "0.2.122"

[[package]]
name = "wasm-bindgen-shared"
version = "0.2.1"
EOF
)"
expect_out 'macro version does not match bindgen' '0.2.122' bash "$dir/lockver.sh" "$differ" wasm-bindgen
expect_out 'shared exact name' '0.2.1' bash "$dir/lockver.sh" "$differ" wasm-bindgen-shared

two="$(lock_file <<'EOF'
version = 4

[[package]]
name = "wasm-bindgen"
version = "0.2.100"

[[package]]
name = "wasm-bindgen"
version = "0.2.122"
EOF
)"
expect_fail_silent 'two versions' bash "$dir/lockver.sh" "$two" wasm-bindgen

same="$(lock_file <<'EOF'
version = 4

[[package]]
name = "wasm-bindgen"
version = "0.2.122"

[[package]]
name = "wasm-bindgen"
version = "0.2.122"
EOF
)"
expect_out 'same version twice is one' '0.2.122' bash "$dir/lockver.sh" "$same" wasm-bindgen

only4="$(lock_file <<'EOF'
version = 4
EOF
)"
expect_fail_silent 'top-level version = 4' bash "$dir/lockver.sh" "$only4" wasm-bindgen

quoted4="$(lock_file <<'EOF'
version = "4"

[[package]]
name = "wasm-bindgen"
version = "0.2.122"
EOF
)"
expect_out 'quoted top-level 4 is not the crate' '0.2.122' bash "$dir/lockver.sh" "$quoted4" wasm-bindgen

first="$(lock_file <<'EOF'
[[package]]
name = "wasm-bindgen"
version = "0.2.122"
version = "9.9.9"
EOF
)"
expect_out 'first version in the table' '0.2.122' bash "$dir/lockver.sh" "$first" wasm-bindgen

ordered="$(lock_file <<'EOF'
[[package]]
version = "0.2.122"
name = "wasm-bindgen"
EOF
)"
expect_out 'version before name' '0.2.122' bash "$dir/lockver.sh" "$ordered" wasm-bindgen

deps="$(lock_file <<'EOF'
version = 4

[[package]]
name = "app"
version = "0.1.0"
dependencies = [
 "wasm-bindgen 0.2.122",
]
EOF
)"
expect_fail_silent 'dependency string is not a package' bash "$dir/lockver.sh" "$deps" wasm-bindgen

meta="$(lock_file <<'EOF'
version = 4

[[package]]
name = "other"
version = "1.0.0"

[metadata]
name = "wasm-bindgen"
version = "9.9.9"
EOF
)"
expect_fail_silent 'metadata is not a package table' bash "$dir/lockver.sh" "$meta" wasm-bindgen

cli="$(lock_file <<'EOF'
[[package]]
name = "wasm-bindgen-cli"
version = "0.2.122"
EOF
)"
expect_fail_silent 'cli name is not wasm-bindgen' bash "$dir/lockver.sh" "$cli" wasm-bindgen

alpha="$(lock_file <<'EOF'
[[package]]
name = "wasm-bindgen"
version = "1.2.3-alpha"
EOF
)"
expect_out 'lockver does not charset-filter' '1.2.3-alpha' bash "$dir/lockver.sh" "$alpha" wasm-bindgen

shortv="$(lock_file <<'EOF'
[[package]]
name = "wasm-bindgen"
version = "0.2"
EOF
)"
expect_out 'lockver prints short version' '0.2' bash "$dir/lockver.sh" "$shortv" wasm-bindgen

crlf="$(mktemp "$root/crlf.XXXXXX")"
printf 'version = 4\r\n\r\n[[package]]\r\nname = "wasm-bindgen"\r\nversion = "0.2.122"\r\n' >"$crlf"
expect_out 'crlf lock' '0.2.122' bash "$dir/lockver.sh" "$crlf" wasm-bindgen

nospace="$(lock_file <<'EOF'
[[package]]
name="wasm-bindgen"
version="0.2.122"
EOF
)"
expect_out 'no space around equals' '0.2.122' bash "$dir/lockver.sh" "$nospace" wasm-bindgen

expect_fail_msg 'lockver usage' 'usage' bash "$dir/lockver.sh"
expect_fail_msg 'lockver missing file' 'not found' bash "$dir/lockver.sh" "$root/no-such-lock" wasm-bindgen
expect_fail_msg 'lockver empty name' 'usage' bash "$dir/lockver.sh" "$dir/fixtures/Cargo.lock" ''

ws="$(mktemp -d "$root/jail.XXXXXX")"
outside="$(mktemp -d "$root/outside.XXXXXX")"
mkdir -p "$ws/packages/foo" "$ws/a/b" "$ws/b" "$ws/a_b" "$ws/foo.bar"
ln -s "$outside" "$ws/outlink"
ln -s "packages/foo" "$ws/alias"
echo x >"$ws/canary"
echo x >"$ws/not-a-dir"

jail() {
  GITHUB_WORKSPACE="$ws" REL="$1" bash "$dir/jail.sh"
}

expect_out 'jail dot' "$(realpath "$ws")" jail '.'
expect_out 'jail packages/foo' "$(realpath "$ws/packages/foo")" jail 'packages/foo'
expect_out 'jail ./packages/foo' "$(realpath "$ws/packages/foo")" jail './packages/foo'
expect_out 'jail underscore' "$(realpath "$ws/a_b")" jail 'a_b'
expect_out 'jail dotted name' "$(realpath "$ws/foo.bar")" jail 'foo.bar'
expect_out 'jail inner symlink' "$(realpath "$ws/packages/foo")" jail 'alias'

jout="$(mktemp "$root/jout.XXXXXX")"
jgot="$(GITHUB_WORKSPACE="$ws" GITHUB_OUTPUT="$jout" REL='packages/foo' bash "$dir/jail.sh")"
if [ "$jgot" = "$(realpath "$ws/packages/foo")" ] && [ "$(cat "$jout")" = "path=${jgot}" ] && [ "$(wc -l <"$jout" | tr -d '[:space:]')" -eq 1 ]; then
  echo 'ok jail github output'
else
  echo "FAIL jail github output got=${jgot} file=$(cat "$jout")"
  fail=1
fi

expect_fail_msg 'foo;rm' 'charset' jail 'foo;rm'
expect_fail_msg 'foo;rm payload' 'charset' jail "foo;rm $ws/canary"
if [ -f "$ws/canary" ]; then
  echo 'ok jail did not run payload'
else
  echo 'FAIL jail ran payload'
  fail=1
fi
expect_fail_msg 'dotdot stays inside' 'empty or ..' jail 'a/../b'
expect_fail_msg 'double slash exists' 'empty or ..' jail 'a//b'
expect_fail_msg 'trailing slash' 'empty or ..' jail 'packages/foo/'
expect_fail_msg 'absolute' 'relative' jail '/etc'
expect_fail_msg 'leading dotdot' 'start with .' jail '../b'
expect_fail_msg 'double ./' 'start with .' jail '././packages/foo'
expect_fail_msg './.' 'start with .' jail './.'
expect_fail_msg 'bare ./' 'empty' jail './'
expect_fail_msg 'empty rel' 'empty' jail ''
expect_fail_msg 'unset rel' 'empty' env -u REL GITHUB_WORKSPACE="$ws" bash "$dir/jail.sh"
expect_fail_msg 'space' 'charset' jail 'packages/foo bar'
expect_fail_msg 'newline' 'charset' jail $'foo\nbar'
expect_fail_msg 'pipe' 'charset' jail 'foo|bar'
expect_fail_msg 'ampersand' 'charset' jail 'foo&bar'
expect_fail_msg 'dollar' 'charset' jail 'foo$bar'
expect_fail_msg 'backtick' 'charset' jail 'foo`bar'
expect_fail_msg 'paren' 'charset' jail 'foo(bar)'
expect_fail_msg 'quote' 'charset' jail 'foo"bar'
expect_fail_msg 'backslash' 'charset' jail 'foo\bar'
expect_fail_msg 'missing dir' 'does not exist' jail 'missing-dir'
expect_fail_msg 'file path' 'not a directory' jail 'not-a-dir'
expect_fail_msg 'symlink escape' 'escapes workspace' jail 'outlink'
expect_fail_msg 'workspace unset' 'GITHUB_WORKSPACE' env -u GITHUB_WORKSPACE REL='.' bash "$dir/jail.sh"

expect_ok 'cdylib publish []' run_cdylib "$(meta_one '[]' '["cdylib","rlib"]' '["id:accel"]' '["cdylib","rlib"]')"
expect_ok 'crate_types cdylib beats kind rlib' run_cdylib "$(meta_one '[]' '["cdylib"]' '["id:accel"]' '["rlib"]')"
expect_fail_msg 'kind cdylib is not crate_types' 'no cdylib' run_cdylib "$(meta_one '[]' '["rlib"]' '["id:accel"]' '["cdylib"]')"
expect_fail_msg 'publish null' 'publish must be []' run_cdylib "$(meta_one 'null' '["cdylib"]' '["id:accel"]' '["cdylib"]')"
expect_fail_msg 'publish registry' 'publish must be []' run_cdylib "$(meta_one '["crates-io"]' '["cdylib"]' '["id:accel"]' '["cdylib"]')"
expect_fail_msg 'rlib only' 'no cdylib' run_cdylib "$(meta_one '[]' '["rlib"]' '["id:accel"]' '["rlib"]')"
expect_fail_msg 'no packages' 'no cdylib' run_cdylib '{"packages":[],"workspace_members":[]}'
expect_ok 'members omitted' run_cdylib "$(meta_one '[]' '["cdylib"]' omit '["cdylib"]')"
expect_fail_msg 'members omitted publish null' 'publish must be []' run_cdylib "$(meta_one 'null' '["cdylib"]' omit '["cdylib"]')"
run_empty() {
  bash "$dir/check-cdylib.sh" </dev/null
}
expect_fail_msg 'empty metadata' 'empty' run_empty
expect_fail_msg 'invalid metadata' 'not valid JSON' run_cdylib '{'

two_good="$(jq -n '{
  packages: [
    {id:"id:a",name:"a",publish:[],targets:[{kind:["cdylib"],crate_types:["cdylib"],name:"a"}]},
    {id:"id:b",name:"b",publish:[],targets:[{kind:["cdylib"],crate_types:["cdylib"],name:"b"}]}
  ],
  workspace_members: ["id:a","id:b"]
}')"
expect_ok 'two cdylibs unpublished' run_cdylib "$two_good"

mixed="$(jq -n '{
  packages: [
    {id:"id:good",name:"good",publish:[],targets:[{kind:["cdylib"],crate_types:["cdylib"],name:"good"}]},
    {id:"id:bad",name:"bad",publish:["crates-io"],targets:[{kind:["cdylib"],crate_types:["cdylib"],name:"bad"}]}
  ],
  workspace_members: ["id:good","id:bad"]
}')"
expect_fail_msg 'one publishable cdylib' 'bad' run_cdylib "$mixed"

nonmember="$(jq -n '{
  packages: [
    {id:"id:good",name:"good",publish:[],targets:[{kind:["cdylib"],crate_types:["cdylib"],name:"good"}]},
    {id:"id:dep",name:"dep",publish:null,targets:[{kind:["cdylib"],crate_types:["cdylib"],name:"dep"}]}
  ],
  workspace_members: ["id:good"]
}')"
expect_ok 'non-member cdylib ignored' run_cdylib "$nonmember"

only_dep="$(jq -n '{
  packages: [
    {id:"id:host",name:"host",publish:[],targets:[{kind:["rlib"],crate_types:["rlib"],name:"host"}]},
    {id:"id:dep",name:"dep",publish:null,targets:[{kind:["cdylib"],crate_types:["cdylib"],name:"dep"}]}
  ],
  workspace_members: ["id:host"]
}')"
expect_fail_msg 'only non-member cdylib' 'no cdylib' run_cdylib "$only_dep"

fixture_pkg="$dir/fixtures/pkg/package.json"
expect_ok 'pkg fixture' env PM=bun bash "$dir/check-pkg.sh" "$fixture_pkg"
expect_ok 'pkg no devEngines' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant 'del(.devEngines)')"
expect_ok 'pkg no pack:local or release' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant 'del(.scripts["pack:local"], .scripts.release)')"
expect_ok 'pkg no publishConfig' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant 'del(.publishConfig)')"
expect_ok 'pkg sideEffects plus extra' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.sideEffects = ["**/*.wasm", "**/*.mjs"]')"
expect_ok 'pkg Wasm case' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.exports["."].import = "./dist/Wasm.mjs"')"
expect_ok 'pkg npm' env PM=npm bash "$dir/check-pkg.sh" "$(pkg_variant '.scripts.prepublishOnly = "npm run build:wasm" | .devEngines.packageManager.name = "npm"')"

bare="$(mktemp -d "$root/barepkg.XXXXXX")"
cp "$fixture_pkg" "$bare/package.json"
expect_ok 'pkg does not need dist files' env PM=bun bash "$dir/check-pkg.sh" "$bare/package.json"

expect_fail_msg 'files extra' 'files must be ["dist"]' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.files = ["dist", "src"]')"
expect_fail_msg 'files case' 'files must be ["dist"]' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.files = ["Dist"]')"
expect_fail_msg 'files empty' 'files must be ["dist"]' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.files = []')"
expect_fail_msg 'sideEffects false' 'sideEffects must be an array' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.sideEffects = false')"
expect_fail_msg 'sideEffects true' 'sideEffects must be an array' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.sideEffects = true')"
expect_fail_msg 'sideEffects missing glob' 'sideEffects must contain' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.sideEffects = ["**/*.js"]')"
expect_fail_msg 'sideEffects missing' 'sideEffects must be an array' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant 'del(.sideEffects)')"
expect_fail_msg 'sideEffects string' 'sideEffects must be an array' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.sideEffects = "**/*.wasm"')"
expect_fail_msg 'root import wasm' 'must not contain wasm' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.exports["."].import = "./dist/wasm.mjs"')"
expect_fail_msg 'root import missing' 'exports["."].import is missing' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant 'del(.exports["."].import)')"
expect_fail_msg 'wasm import missing' 'exports["./wasm"].import is missing' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.exports["./wasm"] = "./dist/wasm.mjs"')"
expect_fail_msg 'wasm export absent' 'exports["./wasm"].import is missing' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant 'del(.exports["./wasm"])')"
expect_fail_msg 'build missing' 'scripts.build is missing' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant 'del(.scripts.build)')"
expect_fail_msg 'build empty' 'scripts.build is missing' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.scripts.build = ""')"
expect_fail_msg 'build calls build:wasm' 'must not run the wasm build' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.scripts.build = "bun run build:wasm"')"
expect_fail_msg 'build sets WASM_PACK' 'must not run the wasm build' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.scripts.build = "WASM_PACK=1 vp pack"')"
expect_fail_msg 'build:wasm missing' 'scripts.build:wasm is missing' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant 'del(.scripts["build:wasm"])')"
expect_fail_msg 'test:wasm missing' 'scripts.test:wasm is missing' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant 'del(.scripts["test:wasm"])')"
expect_fail_msg 'prepublishOnly extra' 'prepublishOnly' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.scripts.prepublishOnly = "bun run build:wasm && true"')"
expect_fail_msg 'prepublishOnly space' 'prepublishOnly' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.scripts.prepublishOnly = "bun run build:wasm "')"
expect_fail_msg 'npm pm bun script' 'prepublishOnly' env PM=npm bash "$dir/check-pkg.sh" "$fixture_pkg"
expect_fail_msg 'devEngines name' 'name must equal' env PM=npm bash "$dir/check-pkg.sh" "$(pkg_variant '.scripts.prepublishOnly = "npm run build:wasm"')"
expect_fail_msg 'onFail download' 'onFail must be ignore' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.devEngines.packageManager.onFail = "download"')"
expect_fail_msg 'onFail missing' 'onFail must be ignore' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant 'del(.devEngines.packageManager.onFail)')"
expect_fail_msg 'install forbidden' 'scripts.install is forbidden' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.scripts.install = "echo hi"')"
expect_fail_msg 'postinstall forbidden' 'scripts.postinstall is forbidden' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.scripts.postinstall = "echo hi"')"
expect_fail_msg 'prepublish forbidden' 'scripts.prepublish is forbidden' env PM=bun bash "$dir/check-pkg.sh" "$(pkg_variant '.scripts.prepublish = "echo hi"')"
expect_fail_msg 'pm pnpm' 'package-manager' env PM=pnpm bash "$dir/check-pkg.sh" "$fixture_pkg"
expect_fail_msg 'pm unset' 'package-manager' env -u PM bash "$dir/check-pkg.sh" "$fixture_pkg"
expect_fail_msg 'pkg missing' 'not found' env PM=bun bash "$dir/check-pkg.sh" "$root/no-package.json"
badjson="$(mktemp "$root/badjson.XXXXXX")"
printf '{\n' >"$badjson"
expect_fail_msg 'pkg invalid json' 'not valid JSON' env PM=bun bash "$dir/check-pkg.sh" "$badjson"

if grep -q '"./dist/wasm.mjs"' "$fixture_pkg"; then
  echo 'ok fixture export prefix'
else
  echo 'FAIL fixture export prefix'
  fail=1
fi

summary="$(mktemp "$root/summary.XXXXXX")"
expect_ok 'dist fixture' env PACKAGE_DIR="$dir/fixtures/pkg" GITHUB_STEP_SUMMARY="$summary" bash "$dir/check-dist.sh"
wasm_bytes="$(wc -c <"$dir/fixtures/pkg/dist/fixture.wasm" | tr -d '[:space:]')"
if grep -q "${wasm_bytes} dist/fixture.wasm" "$summary" && grep -q '### wasm dist' "$summary"; then
  echo 'ok dist summary bytes'
else
  echo "FAIL dist summary bytes want ${wasm_bytes} got $(cat "$summary")"
  fail=1
fi
expect_ok 'dist summary optional' env -u GITHUB_STEP_SUMMARY PACKAGE_DIR="$dir/fixtures/pkg" bash "$dir/check-dist.sh"

raw="$(copy_pkg)"
jq '.exports["./wasm"].import = "dist/wasm.mjs"' "$raw/package.json" >"$raw/package.json.tmp"
mv "$raw/package.json.tmp" "$raw/package.json"
expect_ok 'dist without ./' env PACKAGE_DIR="$raw" bash "$dir/check-dist.sh"

string_export="$(copy_pkg)"
jq '.exports["./wasm"] = "./dist/wasm.mjs"' "$string_export/package.json" >"$string_export/package.json.tmp"
mv "$string_export/package.json.tmp" "$string_export/package.json"
expect_ok 'dist string export' env PACKAGE_DIR="$string_export" bash "$dir/check-dist.sh"

minimal="$(copy_pkg)"
jq -n '{exports:{"./wasm":{import:"./dist/wasm.mjs"}}}' >"$minimal/package.json"
expect_ok 'dist ignores package contract' env PACKAGE_DIR="$minimal" bash "$dir/check-dist.sh"

double="$(copy_pkg)"
jq '.exports["./wasm"].import = "././dist/wasm.mjs"' "$double/package.json" >"$double/package.json.tmp"
mv "$double/package.json.tmp" "$double/package.json"
expect_fail_msg 'double ./ prefix' 'must point at dist/' env PACKAGE_DIR="$double" bash "$dir/check-dist.sh"

escape="$(copy_pkg)"
jq '.exports["./wasm"].import = "./dist/../package.json"' "$escape/package.json" >"$escape/package.json.tmp"
mv "$escape/package.json.tmp" "$escape/package.json"
expect_fail_msg 'dist dotdot' 'not safe' env PACKAGE_DIR="$escape" bash "$dir/check-dist.sh"

missing_file="$(copy_pkg)"
rm "$missing_file/dist/wasm.mjs"
expect_fail_msg 'missing export target' 'missing dist/wasm.mjs' env PACKAGE_DIR="$missing_file" bash "$dir/check-dist.sh"

no_wasm="$(copy_pkg)"
rm "$no_wasm/dist/fixture.wasm"
expect_fail_msg 'no wasm blob' 'no dist/*.wasm' env PACKAGE_DIR="$no_wasm" bash "$dir/check-dist.sh"

two_wasm="$(copy_pkg)"
printf 'ab' >"$two_wasm/dist/second.wasm"
sum2="$(mktemp "$root/summary2.XXXXXX")"
expect_ok 'two wasm blobs' env PACKAGE_DIR="$two_wasm" GITHUB_STEP_SUMMARY="$sum2" bash "$dir/check-dist.sh"
if grep -q 'dist/fixture.wasm' "$sum2" && grep -q '2 dist/second.wasm' "$sum2"; then
  echo 'ok two wasm sizes'
else
  echo "FAIL two wasm sizes: $(cat "$sum2")"
  fail=1
fi

no_export="$(copy_pkg)"
jq 'del(.exports["./wasm"])' "$no_export/package.json" >"$no_export/package.json.tmp"
mv "$no_export/package.json.tmp" "$no_export/package.json"
expect_fail_msg 'dist export deleted' 'exports["./wasm"] is missing' env PACKAGE_DIR="$no_export" bash "$dir/check-dist.sh"
expect_fail_msg 'dist dir missing' 'package directory' env PACKAGE_DIR="$root/no-such-pkg" bash "$dir/check-dist.sh"

# Keep the rustc match identical to action.yml: "$WANT" | "$WANT".*
channel_match() {
  local WANT="$1" got="$2"
  case "$got" in
    "$WANT" | "$WANT".*) return 0 ;;
    *) return 1 ;;
  esac
}
expect_ok 'rustc exact' channel_match '1.94' '1.94'
expect_ok 'rustc patch' channel_match '1.94' '1.94.0'
if channel_match '1.94' '1.940'; then
  echo 'FAIL rustc 1.940 matched'
  fail=1
else
  echo 'ok rustc 1.940'
fi
if channel_match '1.94' '1.95'; then
  echo 'FAIL rustc 1.95 matched'
  fail=1
else
  echo 'ok rustc 1.95'
fi
expect_ok 'rustc stable' channel_match stable stable
if channel_match stable 'stable-gnu'; then
  echo 'FAIL stable-gnu matched'
  fail=1
else
  echo 'ok stable-gnu'
fi
if channel_match '1.8' '1.80'; then
  echo 'FAIL 1.8 matched 1.80'
  fail=1
else
  echo 'ok 1.8 does not match 1.80'
fi
expect_ok 'rustc 1.8.0' channel_match '1.8' '1.8.0'
if channel_match '' '1.94.0'; then
  echo 'FAIL empty channel matched'
  fail=1
else
  echo 'ok empty channel'
fi

action="$dir/action.yml"
if grep -F '"$WANT" | "$WANT".*' "$action" >/dev/null; then
  echo 'ok action rustc match'
else
  echo 'FAIL action rustc match'
  fail=1
fi

re='^[0-9]+\.[0-9]+\.[0-9]+$'
sem_ok() {
  printf '%s' "$1" | grep -Eq "$re"
}
expect_ok 'semver release' sem_ok '0.2.122'
if sem_ok '0.2.122-alpha' || sem_ok '4' || sem_ok '0.2' || sem_ok 'v0.2.122' || sem_ok '0.2.122 '; then
  echo 'FAIL semver rejects'
  fail=1
else
  echo 'ok semver rejects'
fi
if grep -F "grep -Eq '^[0-9]+\\.[0-9]+\\.[0-9]+$'" "$action" >/dev/null && grep -F '*$'"'"'\n'"'"'*' "$action" >/dev/null; then
  echo 'ok action version charset'
else
  echo 'FAIL action version charset'
  fail=1
fi

uses="$(grep -E '^[[:space:]]*uses:' "$action" | sed 's/^[[:space:]]*//')"
want_uses="$(printf '%s\n' 'uses: $/actions/apt-install' 'uses: $/actions/setup-rust')"
if [ "$uses" = "$want_uses" ]; then
  echo 'ok action uses'
else
  echo "FAIL action uses: ${uses}"
  fail=1
fi

if grep -q 'wasm-bindgen-version' "$action" || grep -q 'parse-env-block' "$action"; then
  echo 'FAIL forbidden input or parse-env-block'
  fail=1
else
  echo 'ok no bindgen input'
fi

if [ "$(grep -c 'jail.sh' "$action")" -eq 3 ] &&
  [ "$(grep -c 'check-dist.sh' "$action")" -eq 1 ] &&
  [ "$(grep -c 'check-pkg.sh' "$action")" -eq 1 ] &&
  [ "$(grep -c 'check-cdylib.sh' "$action")" -eq 1 ] &&
  [ "$(grep -c 'lockver.sh' "$action")" -eq 1 ] &&
  [ "$(grep -c "if: inputs.toolchain == 'true'" "$action")" -eq 8 ] &&
  [ "$(grep -c "if: inputs.dist-check == 'true'" "$action")" -eq 1 ] &&
  grep -F 'toolchain-file: true' "$action" >/dev/null &&
  grep -F "rust-version: ''" "$action" >/dev/null &&
  grep -F 'cargo install wasm-bindgen-cli --version "$VER" --locked --root "$install_root" --force' "$action" >/dev/null &&
  grep -F 'wasm-bindgen ${VER} cache hit' "$action" >/dev/null &&
  grep -F 'echo "${install_root}/bin" >>"$GITHUB_PATH"' "$action" >/dev/null &&
  grep -F 'CC_wasm32_unknown_unknown=clang' "$action" >/dev/null &&
  grep -F 'AR_wasm32_unknown_unknown=llvm-ar' "$action" >/dev/null &&
  grep -F 'CFLAGS_wasm32_unknown_unknown=--target=wasm32-unknown-unknown -Wno-implicit-function-declaration' "$action" >/dev/null &&
  grep -F 'if [ "$TOOLCHAIN" != true ] && [ "$DIST_CHECK" != true ]; then' "$action" >/dev/null &&
  grep -F 'if [ "${RUNNER_OS}" != Linux ]; then' "$action" >/dev/null &&
  grep -F 'bun | npm' "$action" >/dev/null &&
  grep -F "default: 'clang lld llvm'" "$action" >/dev/null &&
  grep -F "default: 'wasm32'" "$action" >/dev/null &&
  grep -F "default: 'rustfmt, clippy'" "$action" >/dev/null &&
  grep -F "default: 'wasm32-unknown-unknown'" "$action" >/dev/null &&
  grep -F "default: 'bun'" "$action" >/dev/null &&
  grep -F "default: 'true'" "$action" >/dev/null &&
  grep -F "default: 'false'" "$action" >/dev/null &&
  grep -F 'lockver.sh" "$cargo_dir/Cargo.lock" wasm-bindgen' "$action" >/dev/null; then
  echo 'ok action contract'
else
  echo 'FAIL action contract'
  fail=1
fi

expr_bad=0
while IFS= read -r line; do
  case "$line" in
    *'${{'*)
      case "$line" in
        *': ${{'*) ;;
        *)
          echo "FAIL expression outside a mapping: ${line}"
          expr_bad=1
          ;;
      esac
      ;;
  esac
done <"$action"
if [ "$expr_bad" -eq 0 ]; then
  echo 'ok no run interpolation'
else
  fail=1
fi

if grep -nE '0\.2\.122|1\.94' \
  "$action" \
  "$dir/lockver.sh" \
  "$dir/check-pkg.sh" \
  "$dir/check-cdylib.sh" \
  "$dir/check-dist.sh" \
  "$dir/jail.sh"; then
  echo 'FAIL hardcoded version'
  fail=1
else
  echo 'ok no hardcoded version'
fi

if grep -n 'set -x' "$action" "$dir/jail.sh" "$dir/lockver.sh" "$dir/check-pkg.sh" "$dir/check-cdylib.sh" "$dir/check-dist.sh"; then
  echo 'FAIL set -x'
  fail=1
else
  echo 'ok no set -x'
fi

if [ "$fail" -ne 0 ]; then
  echo 'setup-wasm tests failed'
  exit 1
fi
echo 'setup-wasm tests passed'
