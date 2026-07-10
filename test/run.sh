#!/usr/bin/env bash
# Builds each program in test/hello with nekoc or haxe, runs it on neko and on the
# Nekomata host (interpreted and with the JIT), and checks the output matches.
# Needs haxe and neko, and the host built with haxe build.hxml. Usage: test/run.sh
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)
HOST="$ROOT/bin/host/nekomata"
[ -x "$HOST.exe" ] && HOST="$HOST.exe"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

failures=0
check() {
   local name=$1 module=$2
   local expected
   expected=$(neko "$module" 2>&1 | tr -d '\r')
   for mode in "" "-jit"; do
      local got
      got=$("$HOST" $mode "$module" 2>&1 | tr -d '\r')
      if [ "$got" = "$expected" ]; then
         echo "ok   $name ${mode:-interp}"
      else
         echo "FAIL $name ${mode:-interp}"
         diff <(echo "$expected") <(echo "$got") | head -10 | sed 's/^/       /'
         failures=$((failures + 1))
      fi
   done
}

for src in test/hello/*.neko; do
   name=$(basename "$src" .neko)
   cp "$src" "$WORK/$name.neko"
   (cd "$WORK" && nekoc "$name.neko" > /dev/null)
   check "$name" "$WORK/$name.n"
done

for src in test/hello/*.hx; do
   main=$(basename "$src" .hx)
   # Prefixed, since Windows file names ignore case and Hello.n would clash with hello.n
   haxe -cp test/hello -main "$main" -neko "$WORK/haxe_$main.n"
   check "haxe_$main" "$WORK/haxe_$main.n"
done

exit $failures
