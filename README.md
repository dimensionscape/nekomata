# Nekomata

Nekomata turns the [libhxcpp](https://github.com/openfl/libhxcpp) cppia host into a
neko-compatible VM. The same binary that runs `.cppia` scripts runs neko `.n` bytecode,
on cppia's interpreter and JIT, so haxelib and the `run.n` scripts it launches work
without neko installed.

It translates neko bytecode to cppia in memory when a module loads. Neko's builtins and
primitives come from a runtime compiled into the host, mostly on top of libhxcpp's
ports of neko's own `std`, `regexp`, `zlib` and `ssl` libraries. [PLAN.md](PLAN.md)
describes the design and the milestones.

## Status

Milestones 1 and 2 of [PLAN.md](PLAN.md) are done. The host runs neko modules: a
hand-written neko program and a Haxe program built with `-neko` print exactly what neko
prints, interpreted and with cppia's JIT. Most primitives are not there yet, so larger
programs such as haxelib's `run.n` load and start, then stop at the first primitive the
runtime lacks.

The reader decodes every instruction exactly as `nekoc -d` does on haxelib's, lime's and
libhxcpp's run scripts, and every one of those modules passes neko's stack check and
translates.

## Building the host

The host builds against libhxcpp. A haxelib repository local to this checkout points
`hxcpp` at a libhxcpp checkout, leaving the global haxelib setup alone:

```bash
haxelib newrepo
```

```bash
haxelib dev hxcpp path/to/libhxcpp
```

```bash
haxe build.hxml
```

Then `bin/host/nekomata path/to/module.n` runs a module, `-jit` turns on cppia's JIT,
and `--emit out.cppia` saves the generated cppia.

The host keeps each module it translates in a cache, so the next run loads the cppia
without translating again. Entries are keyed by a hash of the bytecode, the module's
name, the JIT setting and the host's own sources. The cache is `nekomata/cache` in
`%LOCALAPPDATA%` on Windows and `nekomata` in `$XDG_CACHE_HOME` or `~/.cache`
elsewhere; `NEKOMATA_CACHE` names another directory, or turns it off when set to
`off`. `NEKOMATA_TIME=1` reports how long each module takes to translate and load.

```bash
haxe cppia.hxml
```

builds libhxcpp's stock cppia host, `cpp.cppia.Host`, with Nekomata compiled in. It
registers neko bytecode with libhxcpp's script format hook, so
`bin/cppia/Cppia [-jit] path/to/module.n [args...]` runs a module as the same command
runs a `.cppia` script, and `cpp.cppia.Module.fromData` loads one. It needs a libhxcpp
with the hook.

## Trying it

These run under Haxe's interpreter, with no native build:

```bash
haxe -cp src --run nekomata.tools.Dump path/to/run.n --summary
```

Without `--summary` it prints every function's instructions with the stack depth,
source positions and the names of globals, fields and builtins.

## Tests

```bash
test/run.sh
```

builds the programs in `test/hello` and checks that the host, and the stock cppia host
once `cppia.hxml` has built it, print what neko prints;

```bash
haxe test.hxml path/to/dir-or-file.n
```

reads, stack-checks and translates every `.n` file under the paths given;

```bash
test/nekoc-compare.sh path/to/file.n
```

compares the decoded instructions against `nekoc -d` (needs neko installed); and

```bash
test/ndll/run.sh
```

builds a CFFI ndll with hxcpp and checks that programs loading it, libhxcpp's own CFFI
tests and, with lime installed, calls into lime.ndll print on the host what they print
on neko.
