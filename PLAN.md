# Nekomata plan

Nekomata makes the libhxcpp cppia host a neko-compatible VM. The host already runs
`.cppia` scripts; Nekomata teaches it to run neko `.n` bytecode too, so one binary
serves both formats, and haxelib (and every `run.n` it launches) runs without neko.

## How it works

```
app.n ──► reader ──► stack analysis ──► cppia emitter ──► in-memory CPPIA ──► cppia loader
                                                                               (interpreter, JIT, GC)
                    neko runtime (values, builtins, primitives) ◄── calls from the generated code
```

1. **Reader.** Parses the `.n` format exactly as neko's `vm/module.c` does: the `NEKO`
   magic, globals (vars, functions, strings, floats, debug info, version), the field
   name table and the packed opcode stream.
2. **Stack analysis.** Neko verifies that every instruction has one fixed stack depth
   (`neko_check_stack`), at most 128 slots per function. Nekomata repeats that walk, so
   each stack slot becomes an ordinary local variable and the stack disappears.
3. **Emitter.** Each neko function becomes a static cppia function taking
   `(this, env, args...)`. Its body is a `while (true) switch (pc)` loop over basic
   blocks, because cppia has no jumps. Traps become `try`/`catch` around the loop with a
   handler stack. The output is cppia text (`CPPIA` magic), which the existing loader
   reads; nothing in it depends on the Haxe compiler.
4. **Runtime.** The generated code calls host classes compiled into the Nekomata host:
   - value types neko has and hxcpp lacks: mutable strings, objects keyed by field hash
     with prototypes, function values that carry `nargs`, env and `this` binding,
     abstracts with a kind, 31-bit ints that overflow into int32;
   - the 80 `$` builtins (`$array`, `$objget`, `$hnew`, `$sblit`, ...);
   - `$loader` with `loadprim` and `loadmodule`, `$exports`;
   - a primitive table mapping `lib@name` and an argument count onto host functions.
     Haxe's neko std uses 232 primitives (172 from `std`, 34 `ssl`, 10 `sqlite`, 8
     `zlib`, 4 `regexp`, 4 `ui`). Most wrap libhxcpp's `_hx_std_*` ports of the same
     neko libraries, converting neko strings and abstracts at the boundary.

Ints, floats, bools, null and arrays use hxcpp's own representation (Int, Float, Bool,
null, `Array<Dynamic>`), so they cost nothing to pass to primitives.

## Repository split

- **Nekomata (this repo):** reader, analysis, emitter, runtime, primitive table, the
  `nekomata` host and the `neko`/`haxelib` launchers, tests.
- **libhxcpp:** nothing at first. The Nekomata host is a cppia host of its own that
  checks the magic and hands generated cppia to `cpp.cppia.Module.fromData`. Later,
  a small hook lets the stock `Cppia` host run `.n` files, and neko-specific
  expression nodes can replace runtime calls on hot paths once profiling says where.

## Milestones

| # | Goal | Done when |
|---|------|-----------|
| 1 | Reader, stack analysis, disassembler | Every `.n` in the corpus parses, and every function passes the stack walk |
| 2 | Emitter and minimal runtime, native host | A hello-world `.n` prints through `$print` on the host |
| 3 | Haxe neko std basics | libhxcpp's `run.n` runs: strings, `EReg`, file IO, `Sys` |
| 4 | Processes, threads, sockets, zlib, ssl | `hxcpp.n` builds libhxcpp; haxelib's `run.n` installs a library over HTTPS |
| 5 | Launchers | `neko` and `haxelib` executables; `haxelib run` works because it calls `neko <run.n>` |
| 6 | Conformance | Haxe's unit tests compiled with `-neko` pass on Nekomata |
| 7 | Native extensions | ndlls rebuilt against hxcpp CFFI load; then a libneko shim for prebuilt neko ndlls |
| 8 | Speed | Profile, then add native expression nodes through a libhxcpp hook where calls cost most |

Milestones 1 and 2 are done. libhxcpp's `run.n` and haxelib's `run.n` translate, load and
start, then stop at `std@thread_current`, the first primitive milestone 3 adds.

## Test corpus

- libhxcpp `run.n` and `hxcpp.n` (Haxe 4 output)
- haxelib's `run.n`
- `run.n` from popular libraries (lime, openfl, hxcpp releases from several Haxe versions)
- Haxe unit tests compiled with `-neko`
- hand-written neko from neko's own tests, for code the Haxe compiler never emits

## Semantics to match exactly

- Field hash: `h = 223 * h + byte`, kept to 31 signed bits after each step.
- `AccInt` params that do not fit 31 bits become int32 values (`AccInt32`).
- Modules with version >= 2 build arrays with `MakeArray2` ordering.
- `JumpTable n` is followed by `n` `Jump` instructions.
- `Call`, `ObjCall` and `TailCall` take at most 5 arguments; more go through `Apply`.
- Wrong argument counts raise "Invalid call", as neko does.
- `$print`, `$string` and string conversion of every value match neko's output.

## Notes from milestone 2

- hxcpp boxes a Float with a small integral value (-1 to 255) as an Int, so neko floats
  are boxed in `NFloat` to keep `$typeof` and float arithmetic right.
- The host must compile the runtime package explicitly (`--macro include`), since only
  generated scripts name its classes.
- Startup: translating and loading costs about 0.4 s for haxelib's `run.n` and 1.8 s for
  lime's `tools.n`, where neko starts haxelib in under 0.1 s. The text form is about 70
  times the bytecode's size. Writing binary cppia (`CPPIB`), a smaller encoding of the
  dispatch loop and a cache of translated modules keyed by content hash all belong to
  milestone 8, and the cache may need to come earlier for haxelib.

## Open questions

- Performance of the switch-dispatch form against neko's interpreter; structured
  control flow recovery is the next step if dispatch dominates.
- Deep `TailCall` recursion: neko reuses the frame, cppia does not.
- License: to be chosen before the first public push.
