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

Milestone 1 of [PLAN.md](PLAN.md): the `.n` reader, the stack analysis and a
disassembler. Running modules is not there yet.

The reader decodes every instruction exactly as `nekoc -d` does on haxelib's, lime's and
libhxcpp's run scripts, and every module tried passes the same stack check neko makes
before it runs code.

## Trying it

These run under Haxe's interpreter, with no native build:

```bash
haxe -cp src --run nekomata.tools.Dump path/to/run.n --summary
```

Without `--summary` it prints every function's instructions with the stack depth,
source positions and the names of globals, fields and builtins.

## Tests

```bash
haxe test.hxml path/to/dir-or-file.n
```

reads and stack-checks every `.n` file under the paths given, and

```bash
test/nekoc-compare.sh path/to/file.n
```

compares the decoded instructions against `nekoc -d` (needs neko installed).
