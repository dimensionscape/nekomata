#!/usr/bin/env bash
# Builds test/ndll's CFFI library with the hxcpp this checkout's haxelib repository
# points at, runs the programs that load it on neko and on the Nekomata host
# (interpreted and with the JIT), and checks the output matches: NdllTest.hx built for
# neko and raw.neko. When hxcpp is a libhxcpp checkout and utest is installed, its own
# test/cffi suite runs the same way, and with lime installed LimeTest.hx calls lime.ndll.
# Needs haxe, haxelib, neko and nekoc, and the host built with haxe build.hxml. The
# libraries are built 64-bit, as neko is on 64-bit systems. Usage: test/ndll/run.sh
set -u
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
HOST="$ROOT/bin/host/nekomata"
[ -x "$HOST.exe" ] && HOST="$HOST.exe"
HXCPP=$(haxelib libpath hxcpp | tr -d '\r')
UTEST=$(haxelib --global libpath utest 2> /dev/null | tr -d '\r') || UTEST=""
LIME=$(haxelib --global libpath lime 2> /dev/null | tr -d '\r') || LIME=""
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A haxelib repository of the work directory's own: this checkout's hxcpp, and the
#  global utest
(
   cd "$WORK" && haxelib newrepo > /dev/null && haxelib dev hxcpp "$HXCPP" > /dev/null
   [ -z "$UTEST" ] || haxelib dev utest "$UTEST" > /dev/null
)

case "$(uname -s)" in
   MINGW* | MSYS* | CYGWIN*) BIN=Windows64 ;;
   Darwin) [ "$(uname -m)" = arm64 ] && BIN=MacArm64 || BIN=Mac64 ;;
   *) BIN=Linux64 ;;
esac

failures=0

# check name dir filter module [args...]: runs the module in dir on neko and on the host,
#  and compares what they print once filter (a sed script) has dropped what may differ
check() {
   local name=$1 dir=$2 filter=$3
   shift 3
   local expected got
   expected=$(cd "$dir" && neko "$@" 2>&1 | tr -d '\r' | sed -e "$filter")
   for mode in "" "-jit"; do
      got=$(cd "$dir" && "$HOST" $mode "$@" 2>&1 | tr -d '\r' | sed -e "$filter")
      if [ "$got" = "$expected" ]; then
         echo "ok   $name ${mode:-interp}"
      else
         echo "FAIL $name ${mode:-interp}"
         diff <(echo "$expected") <(echo "$got") | head -10 | sed 's/^/       /'
         failures=$((failures + 1))
      fi
   done
}

# ndll project buildfile name dest: builds the library a copy of project describes and
#  puts it in dest as name.ndll
ndll() {
   local project=$1 buildfile=$2 name=$3 dest=$4
   cp -r "$project" "$WORK/build-$name"
   if ! (cd "$WORK/build-$name" && haxelib run hxcpp "$buildfile" -DHXCPP_M64 > build.log 2>&1); then
      echo "FAIL build $name.ndll"
      tail -20 "$WORK/build-$name/build.log" | sed 's/^/       /'
      failures=$((failures + 1))
      return 1
   fi
   local out
   out=$(find "$WORK/build-$name/ndll" -type f -name "*$name.*" ! -name "*.hash" | head -1)
   cp "$out" "$dest/$name.ndll"
}

mkdir -p "$WORK/ndll"
if ndll test/ndll/project Build.xml ndlltest "$WORK/ndll"; then
   haxe -cp test/ndll -main NdllTest -neko "$WORK/ndll/NdllTest.n"
   check NdllTest "$WORK/ndll" "" NdllTest.n
   cp test/ndll/raw.neko "$WORK/ndll"
   (cd "$WORK/ndll" && nekoc raw.neko > /dev/null)
   check raw "$WORK/ndll" "" raw.n
fi

if [ -d "$HXCPP/test/cffi/project" ] && [ -n "$UTEST" ]; then
   cp -r "$HXCPP/test/cffi" "$WORK/cffi"
   mkdir -p "$WORK/cffi/bin"
   if ndll "$WORK/cffi/project" build.xml prime "$WORK/cffi/bin"; then
      (cd "$WORK/cffi" && haxe -cp src -main TestMain -lib utest -neko bin/TestMain.n 2> /dev/null)
      check "libhxcpp test/cffi" "$WORK/cffi/bin" "/^execution time/d" TestMain.n
   fi
else
   echo "skip libhxcpp test/cffi (needs hxcpp to be a libhxcpp checkout, and utest)"
fi

if [ -n "$LIME" ] && [ -f "$LIME/ndll/$BIN/lime.ndll" ]; then
   mkdir -p "$WORK/lime"
   haxe -cp test/ndll -main LimeTest -neko "$WORK/lime/LimeTest.n"
   check "LimeTest ($LIME)" "$WORK/lime" "" LimeTest.n "$LIME/ndll/$BIN/lime" "$LIME/templates/default/icon.svg"
else
   echo "skip LimeTest (lime is not installed)"
fi

exit $failures
