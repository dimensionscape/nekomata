#!/usr/bin/env bash
# Checks that the reader decodes each module's instructions exactly as neko does,
# by comparing against nekoc -d. Needs haxe and neko. Usage: test/nekoc-compare.sh <file.n>...
set -u
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
for f in "$@"; do
   cp "$f" "$WORK/t.n"
   rm -f "$WORK/t.dump"
   (cd "$WORK" && nekoc -d t.n > /dev/null)
   # Windows builds of both tools end lines with CR LF
   awk '/^CODE =/{c=1;next} c && NF>=3 && $1!="END" {sub(/\(.*/,"",$3); print $1" "$3}' "$WORK/t.dump" | tr -d '\r' > "$WORK/nekoc.txt"
   haxe -cp src --run nekomata.tools.Dump "$WORK/t.n" --linear | tr -d '\r' > "$WORK/ours.txt"
   if cmp -s "$WORK/ours.txt" "$WORK/nekoc.txt"; then
      echo "ok   $f ($(wc -l < "$WORK/ours.txt") instructions)"
   else
      echo "FAIL $f"
      diff "$WORK/ours.txt" "$WORK/nekoc.txt" | head -5 | sed 's/^/       /'
      failures=$((failures + 1))
   fi
done
exit $failures
