#!/usr/bin/env bash
# Runs the test harness (test/Harness.hx) from the repository root. With no arguments it
# runs the cases suite: the programs in test/cases, test/hello's among them, built with
# nekoc or haxe and checked on neko and on each host the harness finds (bin/host/nekomata,
# and bin/cppia/Cppia, the stock cppia host with Nekomata in it, once haxe cppia.hxml has
# built it), interpreted and with the JIT: the same output, exit code and arguments after
# the module. Any arguments go to the harness instead. Needs haxe and neko. Usage:
# test/run.sh [options] [suite[:filter]...]   (test/run.sh --help lists the options)
set -u
cd "$(dirname "$0")/.."
if [ $# -eq 0 ]; then
   set -- cases
fi
exec haxe test/harness.hxml "$@"
