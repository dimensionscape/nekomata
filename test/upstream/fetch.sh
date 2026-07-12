#!/usr/bin/env bash
# Fetches the upstream sources the test suites borrow, at pinned revisions, into
# test/upstream (ignored by git). Needs git. Usage: test/upstream/fetch.sh
#
#   haxe   the unit, sys and threads suites Haxe's own CI runs for its neko target
#   utest  the test library those suites use, at the commit Haxe's CI pins
#   neko   neko's tests, benchmarks and bootstrap compilers (boot/nekoc.n, nekoml.n)
set -eu
cd "$(dirname "$0")"

HAXE_REV=e0b355c6be312c1b17382603f018cf52522ec651    # 4.3.7
UTEST_REV=a94f8812e8786f2b5fec52ce9f26927591d26327   # Haxe 4.3.7 tests/RunCi.hx
NEKO_REV=e2fa58bde7e9ab4be0214f3e23b331da4d348c56    # v2-4-1

fetch() {
   local dir=$1 url=$2 rev=$3
   shift 3
   if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD)" = "$rev" ]; then
      echo "$dir is at $rev"
      return
   fi
   rm -rf "$dir"
   git init -q "$dir"
   git -C "$dir" remote add origin "$url"
   if [ $# -gt 0 ]; then
      git -C "$dir" sparse-checkout set "$@"
   fi
   git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$rev"
   git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
   echo "$dir fetched at $rev"
}

fetch haxe https://github.com/HaxeFoundation/haxe.git $HAXE_REV tests/unit tests/sys tests/threads
fetch utest https://github.com/haxe-utest/utest.git $UTEST_REV
fetch neko https://github.com/HaxeFoundation/neko.git $NEKO_REV tests src boot
