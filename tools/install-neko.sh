#!/bin/sh
# Installs the Nekomata host as a stand-in for neko in a directory of your choice:
#  nekomata, a hard link to it (or a copy) named neko, and with --haxelib a haxelib
#  executable, haxelib's run.n with the host attached. Put the directory first on PATH
#  and `haxelib run`, which starts `neko <lib>/run.n`, runs on Nekomata.
#
#  tools/install-neko.sh [--host path/to/nekomata] [--haxelib path/to/run.n] <dir>
#
# Nothing outside <dir> changes: not PATH, not a neko or Haxe install.
set -e

root=$(cd "$(dirname "$0")/.." && pwd)
host=
haxelib=
dir=
while [ $# -gt 0 ]; do
	case "$1" in
		--host) host=$2; shift 2 ;;
		--haxelib) haxelib=$2; shift 2 ;;
		-h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
		*) dir=$1; shift ;;
	esac
done
if [ -z "$dir" ]; then
	echo "usage: $0 [--host path/to/nekomata] [--haxelib path/to/run.n] <dir>" >&2
	exit 1
fi

if [ -z "$host" ]; then
	for h in "$root/bin/host/nekomata.exe" "$root/bin/host/nekomata"; do
		[ -f "$h" ] && host=$h && break
	done
fi
if [ -z "$host" ] || [ ! -f "$host" ]; then
	echo "no Nekomata host found; build it with 'haxe build.hxml' or pass --host" >&2
	exit 1
fi
case "$host" in
	*.exe) ext=.exe ;;
	*) ext= ;;
esac

mkdir -p "$dir"
hostabs=$(cd "$(dirname "$host")" && pwd)/$(basename "$host")
dirabs=$(cd "$dir" && pwd)
# The host finds nothing next to itself it needs, so a copy runs anywhere
rm -f "$dir/neko$ext"
if [ "$hostabs" != "$dirabs/nekomata$ext" ]; then
	rm -f "$dir/nekomata$ext"
	cp "$host" "$dir/nekomata$ext"
fi
# Named neko it takes neko's command line. A symbolic link would not do: on Linux the
#  host sees the path it links to
ln "$dir/nekomata$ext" "$dir/neko$ext" 2>/dev/null || cp "$dir/nekomata$ext" "$dir/neko$ext"
echo "installed $dir/nekomata$ext and $dir/neko$ext"

if [ -n "$haxelib" ]; then
	rm -f "$dir/haxelib$ext"
	"$dir/nekomata$ext" boot "$haxelib" -o "$dir/haxelib$ext"
	echo "installed $dir/haxelib$ext from $haxelib"
fi

echo "to use it in a shell: export PATH=\"$dirabs:\$PATH\""
