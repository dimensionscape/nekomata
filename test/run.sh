#!/usr/bin/env bash
# Builds each program in test/hello with nekoc or haxe, runs it on neko and on the
# Nekomata host (interpreted and with the JIT), and checks the output matches.
# Needs haxe and neko, and the host built with haxe build.hxml. The stock cppia host
# with Nekomata in it is checked too once haxe cppia.hxml has built it. Usage:
# test/run.sh
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)
HOST="$ROOT/bin/host/nekomata"
[ -x "$HOST.exe" ] && HOST="$HOST.exe"
HOSTS=("$HOST")
CPPIA="$ROOT/bin/cppia/Cppia"
[ -x "$CPPIA.exe" ] && CPPIA="$CPPIA.exe"
[ -x "$CPPIA" ] && HOSTS+=("$CPPIA")
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# What a command prints, and its exit code
run() {
   "$@" 2>&1 | tr -d '\r'
   echo "exit ${PIPESTATUS[0]}"
}

failures=0
# check name module [args...]
check() {
   local name=$1 module=$2
   shift 2
   local expected
   expected=$(run neko "$module" "$@")
   for host in "${HOSTS[@]}"; do
      local label
      label=$(basename "$host" .exe)
      # The Nekomata host runs the JIT unless told not to, the stock host the interpreter
      local modes=("-interp" "-jit")
      [ "$label" = "Cppia" ] && modes=("" "-jit")
      for mode in "${modes[@]}"; do
         local got how=${mode:-interp}
         how=${how#-}
         got=$(run "$host" $mode "$module" "$@")
         if [ "$got" = "$expected" ]; then
            echo "ok   $name $label $how"
         else
            echo "FAIL $name $label $how"
            diff <(echo "$expected") <(echo "$got") | head -10 | sed 's/^/       /'
            failures=$((failures + 1))
         fi
      done
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

# What follows the module on the command line, and an exception nothing catches
check haxe_Args_given "$WORK/haxe_Args.n" one two
check haxe_Args_uncaught "$WORK/haxe_Args.n" one fail

exit $failures
