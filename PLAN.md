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
- **libhxcpp:** a script format hook, `__scriptable_cppia_register_format`. The
  Nekomata host is a cppia host of its own that checks the magic and hands generated
  cppia to `cpp.cppia.Module.fromString`. `nekomata.CppiaFormat` registers `NEKO` with
  the hook instead, so `Module.fromData` translates neko modules, and the stock
  `cpp.cppia.Host` built with it (`cppia.hxml`) runs `.n` files from its command line.
  Later, neko-specific expression nodes can replace runtime calls on hot paths once
  profiling says where.

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

Milestones 1 to 3 are done, with most of 4, 5 and 6:

- libhxcpp's `run.n` runs `hxcpp.n`, which builds a C program as on neko; lime's,
  openfl's and stock hxcpp's run scripts print what they print on neko.
- neko's own `nekoc`, run on the host, compiles to the same bytes as on neko.
- Haxe 4.3.7's unit tests all pass on the host, interpreted and with the JIT, and its sys
  and threads suites give the same results as on neko.
- 255 of the 296 primitives neko 2.4.1's std, regexp, zlib, ssl and sqlite libraries
  export are there, on libhxcpp's ports where they match neko and on the C libraries
  where they do not; regexp runs on PCRE2 itself, a byte a character unless asked for
  UTF-8, as neko's does. The rest (`unicode_*`, most `int32_*`, socket polling and
  epoll, `parse_xml`, `make_sha1` and a few of neko's internals) load and fail when
  called, which the Haxe std never does; a name neko does not have fails to load, as
  on neko.
- The host stands in for neko (`tools/install-neko.sh`): with it first on PATH, haxelib's
  `version`, `list`, `path`, `run` and `install` print what they print on neko, and
  haxelib's `info` reads lib.haxe.org over HTTPS. `nekomata boot` writes executables in
  `nekotools boot`'s format, and runs those nekotools writes.
- Ndlls built with hxcpp's CFFI load (`test/ndll/run.sh`): libhxcpp's test/cffi suite and
  a test library of Nekomata's own give the same results as on neko, and lime's `svg.n`
  renders an icon through lime.ndll's cairo to the same PNG bytes.

Left: `hxcpp.n` building libhxcpp itself and bigger projects (milestone 4), a `haxelib`
executable that needs no neko install (5), ndlls built against libneko (7) and speed (8).

## Test corpus

Neko is the oracle: every check runs the same module on neko and on the host.

- libhxcpp `run.n` and `hxcpp.n` (Haxe 4 output)
- haxelib's `run.n`
- `run.n` from popular libraries (lime, openfl, hxcpp releases from several Haxe versions)
- Haxe 4.3.7's unit, sys and threads suites, as Haxe's CI runs them for neko
  (`test/upstream/fetch.sh` pins them, with utest at the commit Haxe's CI uses)
- neko 2.4.1's benchmarks, and its bootstrap compilers (`boot/nekoc.n`, `boot/nekoml.n`):
  run on the host, they must build neko's compilers and programs to the same bytes as
  on neko. nekoml's code is nothing like the Haxe compiler's

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

## Notes from milestone 3

- Tail calls: neko's `TailCall` pops the caller's frame before calling. nekoml compiles
  its loops that way, so a call in tail position to the function itself becomes a jump
  back to its start, and any other returns a `TailCall` for the caller's call helper to
  make. Stack traces then leave the frame out, as neko's do.
- Hash tables are laid out cell for cell as neko's, with `val_hash`, since programs
  print or generate code in `$hiter` order, and nekoml's compare keys with a function.
- Neko recurses as deep as 256K stack values; libhxcpp gives cppia scripts a fixed 128K
  stack per thread. The host swaps in a 16M one on each thread before running neko code,
  and links a 256M native stack on Windows, until libhxcpp makes the size configurable.
- cppia's JIT cannot carry a thrown null (its pending exception slot uses null for none)
  and turns it into an empty string; the runtime throws a marker instead. libhxcpp's JIT
  should be fixed too.
- `$excstack` is recorded when a value is raised and cut at the catching function, as
  neko's is; hxcpp's own record of an unwind holds no frame of the function that caught.

## Notes from milestone 7

Third-party ndlls come in two kinds. Those built with hxcpp's CFFI (`hx/CFFI.h`) find
their API at run time from the host that loaded them, so one binary runs on neko and on
hxcpp. Those built against libneko link to neko.dll or libneko.so and read neko's value
layout through its macros. Of the installed haxelibs, only lime ships ndlls (`lime.ndll`
for Windows, Windows64, Linux64, Mac64 and MacArm64), which its `tools.n` and `svg.n`
load. They are of the first kind, built with neko's glue (`NEKO_COMPATIBLE`): they export
`hx_set_loader` and `neko_init__5`, import nothing from neko.dll, and look for it with
`GetModuleHandle` when neko loads them. The only ndlls of the second kind here are neko's
own: std, regexp, zlib, ssl, sqlite, ui, mysql, mysql5 and mod_neko2.

- `prims/Ndll.hx` serves CFFI ndlls: a primitive no built-in library has comes from
  `lib.ndll` found along the loader's path, loaded by libhxcpp, which hands it hxcpp's
  API. A library that does not load or lacks the primitive fails as `loadprim` returns,
  as on neko, which lime's search for its ndll relies on; neko's own libraries keep
  failing only when a missing primitive is called. A library without `hx_set_loader` is
  refused, as it needs libneko.
- Values convert at the boundary the way Haxe's neko values map onto its hxcpp ones: a
  Haxe String object becomes a String, a neko string the byte array a BytesData is on
  hxcpp (and so a CFFI buffer, ending in a NUL for `val_string`), a float a Float.
  Objects, arrays and functions go over as proxies that read, write and call the neko
  value itself, so an ndll that keeps a callback or fills in an object later reaches
  neko code. Results are built as neko's glue builds them, with the String and Array
  constructors the program gave `neko_init`, which is recorded and not called, since
  the glue it sets up needs neko.dll.
- What hxcpp's API cannot give as neko's glue does: a float with a small integral value
  comes back an int, as hxcpp boxes it; a primitive returning a C NULL, which neko
  raises as an error, gives null, as `alloc_null()` is NULL too; a neko string is an
  array to `val_type`, and `val_strlen` measures its printed form; `val_array_push` on a
  Haxe Array does nothing, and `val_array_int` and the like give NULL, as on neko; an
  object the ndll makes is copied into an NObject, so writes it makes to it later are
  lost; an abstract freed with `free_abstract` reads as null to `$typeof`; a function
  read from an object field is called with that object as `this`. The loader finds only
  files on disk, where neko's `dlopen` also searches the system's path, and keeps one
  list of libraries for the process, where neko keeps one per loader.
- libhxcpp: `__hxcpp_get_proc_address` asked to fail quietly calls the primitive's query
  function even when the symbol is missing, a null pointer (src/hx/Lib.cpp), so Ndll
  asks for the query function and calls it itself. hxcpp's neko glue
  (include/hx/NekoFunc.h) reads value tags with neko 1.8's 3 bits where neko 2 has 4, so
  on neko 2 plain neko strings and arrays come out twice their length (an ndll summing a
  neko array reads past it). Haxe programs pass Strings and Arrays as objects with a
  `length` field and never see it. Without `neko_init`, the glue's `alloc_bool` and
  `alloc_null` return C NULLs, which neko crashes printing.

## The libneko shim

Ndlls of the second kind need a library that is libneko to them and Nekomata's runtime
behind it. Nekomata serves neko's own std, regexp, zlib, ssl and sqlite in Haxe, so the
shim is for third-party ndlls (none are installed here) and neko's ui, mysql and
mod_neko.

What it exports. An ndll imports `neko.dll`, `libneko.so.2` or `libneko.2.dylib` by name,
so the shim is a library of that name next to the host, which loads it by full path
before the first such ndll: on Windows an import whose module name is already loaded
binds to it, elsewhere the soname or install name does, so an installed neko's libneko
is never the one used. neko.dll exports 88 names; neko's 9 libraries import 75 of them
(std 65, mod_neko2 40, mysql and mysql5 24, sqlite 20, regexp 19, ssl 17, zlib 15, ui
6). Three are data, not functions: `val_null`, `val_true` and `val_false`, which every
library imports, as `alloc_bool` and `val_is_null` are macros comparing against them.
The core, used by 5 or more of them: `val_id`, `alloc_string`, `alloc_empty_string`,
`alloc_buffer`, `buffer_append`, `buffer_to_string`, `val_buffer`, `alloc_object`,
`alloc_field`, `val_field`, `alloc_abstract`, `val_gc`, `val_throw`, `_neko_failure`,
`alloc_array`, `alloc_int32`, `alloc` and `val_call1`, with `alloc_float`,
`alloc_private`, `copy_string` and `buffer_append_sub` in 4. Most of the rest only std
and mod_neko use:
`vm_*`, locks, threads and thread locals, `gc_*`, `read_module`, `vm_execute`,
`default_loader`, `select_file`, `exc_stack`, `call_stack`, `val_print`,
`val_compare`, `val_iter_fields`, `kind_share`, `kind_lookup`, `k_hash`,
`kind_module`. `val_this` is a function, so no macro reads the VM's struct.

What neko's macros fix. Most of the API is macros that read value memory directly, so a
value an ndll sees must be laid out as neko 2 lays it out (vm/neko.h):

- `value` is a pointer. An int is the odd word `(i << 1) | 1`, 31 bits; wider ints are
  boxed `{VAL_INT32 = 8, int}`.
- Every other value points at a 32-bit tag: the type in the low `NEKO_TAG_BITS` = 4
  bits, the length of a string or array above them (at most 2^28 - 1). hxcpp's glue has
  3 bits, neko 1.8's layout, hence its doubled lengths on neko 2.
- A float is `{tag, double}` packed to 4 bytes; a string's bytes follow its tag and end
  in a NUL, and `val_string` points into the value, which ndlls write through (an
  `alloc_empty_string` then filled); an array's slots follow its tag, read and written
  through `val_array_ptr`; an abstract is `{tag, kind, data}` with `val_kind` and
  `val_data` assignable; a function is `{tag, nargs, addr, env, module}`, read by
  `val_fun_nargs`, its short tag 6 shared by `VAL_PRIMITIVE` (6 | 16) and `VAL_JITFUN`
  (6 | 32). Objects are reached only through functions (`val_field`, `alloc_field`,
  `val_iter_fields`, `val_ocall*`), so their insides are the shim's to choose.
- `neko_error()` is `return NULL`: a primitive returning NULL raises its own name. An
  exception is a `longjmp` out of the ndll's C frames, which have nothing to unwind.

How it fits. Nekomata's values are hxcpp objects, a vtable first, so none can be handed
to an ndll as it is. The shim keeps neko values of its own and Nekomata converts at the
call, as Ndll does for CFFI:

- The heap is neko's: Boehm's collector, which neko links, and neko's own vm/alloc.c,
  objtable.c, hash.c, callback.c, threads.c and the parts of others.c with buffers,
  failures, `val_print` and `val_compare` (MIT), with interp.c and load.c replaced by
  calls into Nekomata. Ndlls keep values in blocks from `alloc()`, in their static data
  and in roots, and rely on the collector finding them, which Boehm does for the data
  of every loaded library. hxcpp's collector accepts pointers up to 8 words into an
  object (`RegisterVTableOffset` raises that), so neko values could live in hxcpp
  objects, but it scans only thread stacks, roots and what objects mark, never an
  ndll's data or blocks. A thread registers with Boehm (`GC_register_my_thread`)
  before its first call into such an ndll, as its stack then holds neko values.
- Ints, floats, bools, null and int32 go by value. Strings are copied in, and back out
  when the ndll wrote to them; arrays are copied in and their slots copied back after
  the call.
- An NObject passed in gets a neko object standing for it, whose fields `val_field`,
  `alloc_field` and `val_iter_fields` read and write on the NObject itself, so writes
  made later reach neko code, as with Ndll's proxies. Objects the ndll makes come back
  as NObjects, their field names taken from `val_id` so they print.
- An NFunction gets a neko function whose `addr` is a trampoline into Nekomata, with its
  `nargs`; functions the ndll makes (`alloc_function`) come back as NFunctions calling
  the C address through the same conversion, with `this` for `val_this`.
- Abstracts stay in the neko heap. Nekomata holds an NAbstract whose data is the neko
  pointer, rooted until the NAbstract's hxcpp finalizer drops the root and lets Boehm
  run the ndll's `val_gc` finalizer; one NAbstract per pointer keeps `==` physical.
- Each NObject, array and NFunction keeps one stand-in while the ndll may hold it, in a
  map rooted on the neko side and weak on Nekomata's, so a value the ndll keeps and
  hands back is the same value.
- The call boundary `setjmp`s; `val_throw` and `_neko_failure` `longjmp` to it, and
  Nekomata raises the converted value. A Nekomata exception in a callback is caught in
  the trampoline and raised into the ndll by `longjmp`, as a C++ exception must not
  cross C frames built without unwind tables; `val_callEx` with an `exc` pointer gets it
  there instead.
- Ndll.find already finds the file and tells the kinds apart. For the second it would
  load the shim, `dlopen` the ndll, call `__neko_entry_point` and look up `name__N` as
  neko does, without libhxcpp.

Order of work: the core and buffers first, which cover libraries like regexp, zlib and
sqlite; the VM functions with a library that needs them (mod_neko, ui).

## Notes from milestone 8

- Where the time went: each neko operation is a call into the runtime, and a call of a
  host function from cppia pushes its arguments on the script stack for a generated
  wrapper. The runtime's functions also pushed host stack frames of their own and
  checked classes with `Std.isOfType`, a neko call went through `Rt.call` and a Dynamic
  closure call, and every basic block went back through the dispatch switch.
- The emitter keeps the accumulator and stack slots as expressions until something
  needs them in a local, so a run of instructions is one statement. cppia records a
  frame's line per statement, so an effect only goes into the next instruction's
  statement when both are at the same line or one of them cannot throw. A block with
  one predecessor is written where that predecessor goes to it; a loop's head runs in a
  while of its own. Calls through a global that always holds one of the module's
  functions call its static function directly, and builtins that run no neko code are
  called where they are used.
- cppia looks up a static function by walking its class's functions, so a module's
  functions go in classes of 256, and Rt declares the functions translated code calls
  most first. The JIT compiles a switch as a chain of tests, so a large one becomes a
  tree of comparisons under the JIT.
- Binary cppia (`CPPIB`) carries no file or line for expressions, which neko's stack
  traces need, so the host writes text. A cache of translated modules, keyed by a hash of
  the bytecode and of the host's sources, takes care of startup instead.
- The JIT compiles a whole module when it loads it, which costs more than it gains for
  short runs of big programs: Haxe's unit tests load in 0.45 s interpreted and 0.9 s
  under the JIT. Code that is mostly calls into the runtime gains least from it.
- Measured on Windows, CPU time: fib(30) 391 ms interpreted and 94 ms with the JIT, from
  1109 and 438 (neko 94); haxelib's `run.n version` 47 ms with the cache and 172 ms
  without, from 547; Haxe's unit tests 1.5 s with the cache, from 7.5 s (neko 0.34 s).
## Notes from milestone 9

- Objects keep their fields as neko's objtable does: the field hashes in order with
  their values beside them, scanned when there are few and searched by halves past
  eight. Keys come out in order without sorting, and copying an object copies two arrays.
- A pushed value stays in its stack slot until it is popped, and neko's fixed depths
  make the code it lives through a region: the slot at each instruction, joined across
  each step and jump that keeps it. A region whose every value is an int is an `int`
  local, found by supposing every region holds ints and taking that back for any region
  given a value that may not be one. Arithmetic, bit operations and comparisons on two
  ints are cppia's own, and an int on one side of a runtime operation or array access
  goes in unboxed.
- A module function that code calls directly gets an int version, which takes ints and
  gives an int when each of its returns does, found over the whole module the same way.
  Calls with int arguments go to it, and a function whose int version gives an int or
  calls itself with ints checks its arguments on entry and runs as that version.
- libhxcpp's JIT compiles each script function when it is first called, so the JIT is
  the host's default: haxelib's `run.n` loads in 74 ms under it, where compiling all of
  it took 139 ms, and `-interp` or `NEKOMATA_JIT=0` gives the interpreter. Compiling
  what runs costs short programs a little: `run.n version` runs for 37 ms under the JIT
  and 11 ms interpreted, not counting the `haxe` it starts.
- Measured on Windows against neko, wall clock with the cache: fib 45 ms (neko 101),
  nsieve 18 (16), nbodies 45 (50), recursive 402 (259), binary-trees 69 (32), Haxe's fib
  1003 (699). Loops on locals run 6 to 25 times faster than neko's, and Haxe code still
  runs 1.5 to 6 times slower, as its values pass through fields and methods as Dynamic.
- Next: compiling a function after a few calls rather than its first, so short programs
  pay nothing for the JIT; floats in locals of their own, boxed as an `NFloat` only
  where one is needed, since hxcpp boxes an integral Float as an Int; typed module
  globals; and fewer runtime calls for field reads and method calls.

## Open questions

- Performance of the switch-dispatch form against neko's interpreter; structured
  control flow recovery is the next step if dispatch dominates. First timings on neko's
  benchmarks range from 2.5 times faster to 13 times slower than neko.
