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

Then `bin/host/nekomata path/to/module.n` runs a module under cppia's JIT, which
compiles each function when it is first called. `-interp` (or `NEKOMATA_JIT=0`, for
when the host stands in for neko and takes no options) runs it in cppia's interpreter
instead, and `--emit out.cppia` saves the generated cppia.

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

The test harness runs under Haxe's interpreter, from the root of this checkout:

```bash
haxe test/harness.hxml [options] [suite[:filter]...]
```

Neko is the oracle. Every program runs on neko and on the host, interpreted and with
`-jit`, each in a work directory of its own, and the host passes when it prints the same
stdout and stderr and exits with the same code; the expected output always comes from
neko at test time. The host under test is `bin/host/nekomata`, and also `bin/cppia/Cppia`
once `haxe cppia.hxml` has built it, or the hosts given with `--host`. The harness runs
a copy of each, so a rebuild can go on meanwhile, and puts a copy named `neko` first on
`PATH`, so the programs the host runs that start `neko` start the host too. The suites:

- `cases`: the programs in `test/cases`, `neko/*.neko` built with nekoc next to the
  modules in `neko/lib`, and `haxe/*.hx` built with `haxe -neko`. A case's first comment
  lines can give haxe flags (`// flags:`), arguments (`// args:`), more runs with other
  arguments (`// run:`) and builds with other flags (`// variant:`).
- `neko`: neko's benchmarks, and neko's own compilers from `test/upstream/neko` run on
  the host: `boot/nekoc.n` compiling each of neko's `.neko` sources, `nekoml.n`
  compiling one module, then neko's bootstrap, `nekoml.n` compiling nekoc and nekoml,
  `nekoc.n -link` linking them and the linked nekoc compiling the benchmarks, with every
  `.n` compared byte for byte. A bootstrap step that fails on the host leaves the next
  ones to start from what neko's run wrote.
- `haxe-unit`, `haxe-sys` and `haxe-threads`: Haxe's unit, sys and threads tests, built
  and run as Haxe's CI runs them for neko. The host passes when every test that passes
  on neko passes on it too.
- `libhxcpp`: libhxcpp's `run.n` started as haxelib starts it, and a one-file C program
  built with it.
- `decode`: the reader decodes every `.n` in the corpus as `nekoc -d` does. The corpus is
  the `.n` files haxelib has installed, libhxcpp's, neko's compilers, what the other
  suites built in the same run and `--corpus` paths.
- `translate`: every module in the corpus reads, passes the stack check and translates.

With no suite named it runs them all, in that order, then prints a summary and every
failure, and exits non-zero when anything failed. `cases:hash` runs the cases whose
names contain `hash`, `--list` lists the suites or the tests of those named, `--no-jit`
skips the JIT runs, `-j <n>` runs that many tests at once (8 by default), `--timeout <s>`
sets how long a run may take before it is killed, `--keep` keeps the work directories,
and `--reuse` keeps the builds of Haxe's tests in `bin/harness` for the next run.
`test/run.sh` runs the `cases` suite, or passes its arguments on to the harness, and

```bash
test/ndll/run.sh
```

builds a CFFI ndll with hxcpp and checks that programs loading it, libhxcpp's own CFFI
tests and, with lime installed, calls into lime.ndll print on the host what they print
on neko.
