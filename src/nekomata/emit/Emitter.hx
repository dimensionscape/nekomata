package nekomata.emit;

import nekomata.emit.CppiaWriter;
import nekomata.neko.Module;
import nekomata.neko.Opcode;
import nekomata.neko.StackCheck;

// Translates a neko module to cppia. Each neko function becomes a static function
//  (this, env, args...) whose stack slots are locals, run by a loop that switches on
//  the basic block to run next.
//
// Within a run of code the accumulator and the stack slots are kept as expressions
//  until something needs them in a local, so most instructions become part of one
//  statement rather than a statement each. A block that only one other block reaches
//  is written where that block goes to it, inside the if of a conditional jump, so
//  only blocks reached from more than one place, such as loop heads, are cases of the
//  switch. Calls of the module's own functions, through a global that holds the
//  function whenever they run, call its static function directly.
@:build(nekomata.build.NoFrames.build())
class Emitter {
	static inline var RT = "nekomata.rt.Rt";
	static inline var BUILTINS = "nekomata.rt.NekoBuiltins";
	static inline var BOOT = "nekomata.rt.Boot";

	// Set by the host: whether the runtime has a builtin, so that the module can look
	//  it up once. Without it, every builtin is taken to be there
	public static var builtinExists:Null<Int->Bool>;

	var m:Module;
	var cls:String;
	var w:CppiaWriter;
	var nextVar = 1;
	var name:String;
	var jit:Bool;

	// Locals of the function being written
	var th:Local;
	var env:Local;
	var acc:Local;
	var pc:Local;
	var traps:Local;
	var slots:Array<Local>;
	var scope:Scope;
	var hasTraps:Bool;

	// Module analysis
	var scopes:Array<Scope>;
	// How many SetGlobal instructions write each global
	var writes:Array<Int>;
	// For a global that holds one of the module's functions whenever any function
	//  runs: that function's global, else -1
	var heldFunction:Array<Int>;
	// Functions that can return a TailCall for their caller to make
	var mayTail = new Map<Int, Bool>();
	// The module function every SetField of a field hash stores, as Haxe's statics and
	//  the methods on its prototypes are set: a call through such a field calls that
	//  function's static function while the field still holds it
	var fieldFunction = new Map<Int, Int>();
	// Instructions some jump goes to
	var targets:Array<Bool>;
	// Per function, indexed by code index: the blocks, and marks set to the scope's entry
	var blockAt:Array<Block> = [];
	var leadAt:Array<Int>;
	var inScope:Array<Int>;
	// The builtins the module names, by hash, as their index in its B array
	var builtinIndex = new Map<Int, Int>();
	var builtinHashes:Array<Int> = [];

	static final loaderHash = nekomata.neko.Hash.field("loader");
	static final exportsHash = nekomata.neko.Hash.field("exports");

	// The operations the runtime has a version of with an int on the right
	static final INT_OPS = [for (op in ["add", "sub", "lt", "lte", "gt", "gte", "eq", "neq"]) op => true];

	// Builtins that run no neko code, with the runtime function that does each
	static final LEAF_BUILTINS:Map<Int, {cls:String, fn:String, nargs:Int, isBool:Bool, canThrow:Bool}> = [
		for (b in [
			{name: "not", cls: RT, fn: "not", nargs: 1, isBool: true, canThrow: false},
			{name: "istrue", cls: RT, fn: "toBool", nargs: 1, isBool: true, canThrow: false},
			{name: "typeof", cls: RT, fn: "typeOf", nargs: 1, isBool: false, canThrow: false},
			{name: "asize", cls: BUILTINS, fn: "asize", nargs: 1, isBool: false, canThrow: true},
			{name: "ssize", cls: BUILTINS, fn: "ssize", nargs: 1, isBool: false, canThrow: true},
			{name: "sget", cls: BUILTINS, fn: "sget", nargs: 2, isBool: false, canThrow: true},
			{name: "sset", cls: BUILTINS, fn: "sset", nargs: 3, isBool: false, canThrow: true},
			{name: "amake", cls: BUILTINS, fn: "amake", nargs: 1, isBool: false, canThrow: true},
			{name: "int", cls: BUILTINS, fn: "toInt", nargs: 1, isBool: false, canThrow: false},
			{name: "float", cls: BUILTINS, fn: "toFloat", nargs: 1, isBool: false, canThrow: false}
		])
			nekomata.neko.Hash.field(b.name) => {cls: b.cls, fn: b.fn, nargs: b.nargs, isBool: b.isBool, canThrow: b.canThrow}
	];

	// Hash builtins that run no neko code when their compare function, the last argument,
	//  is null: called where they are used, without it
	static final NULL_COMPARE_BUILTINS:Map<Int, {fn:String, nargs:Int, isBool:Bool}> = [
		for (b in [
			{name: "hget", fn: "hgetNull", nargs: 3, isBool: false},
			{name: "hset", fn: "hsetNull", nargs: 4, isBool: true},
			{name: "hmem", fn: "hmemNull", nargs: 3, isBool: true},
			{name: "hremove", fn: "hremoveNull", nargs: 3, isBool: true}
		])
			nekomata.neko.Hash.field(b.name) => {fn: b.fn, nargs: b.nargs, isBool: b.isBool}
	];

	// How deep blocks written inline nest, at most, so the loader's recursion stays shallow
	static inline var MAX_NEST = 100;
	// The most cases one switch has under the JIT, which tests them one after another;
	//  more are split by comparing the code index
	static inline var JIT_SWITCH = 6;

	// name is the module's name, the position of code that has no debug info. jit says
	//  the module will run under cppia's JIT
	public static function emit(m:Module, cls:String, name = "module", jit = false):haxe.io.Bytes
		return translate(m, cls, name, jit).cppia;

	// The cppia, and where in it the class names are, so a copy can be renamed: each
	//  starts with cls
	public static function translate(m:Module, cls:String, name = "module", jit = false):{cppia:haxe.io.Bytes, classOffsets:Array<Int>} {
		var e = new Emitter(m, cls, name, jit);
		var cppia = e.run();
		return {cppia: cppia, classOffsets: e.w.classOffsets};
	}

	function new(m:Module, cls:String, name:String, jit:Bool) {
		this.m = m;
		this.cls = cls;
		this.name = name;
		this.jit = jit;
		w = new CppiaWriter();
	}

	function local(name:String, type = CppiaWriter.DYNAMIC):Local
		return {name: name, id: nextVar++, type: type};

	// hxcpp passes stack frames as class::method::file::line, and Haxe's debug info names
	//  positions like Class::method, so the separator is escaped; NekoStack restores it.
	//  hxcpp also drops the file of a frame whose file starts with ?, which neko's own
	//  code without a position has, so such a file gets a marker in front
	public static inline var COLONS = "::";
	public static inline var UNKNOWN = "";

	static function frameFile(file:String):String {
		var escaped = StringTools.replace(file, "::", COLONS);
		return StringTools.startsWith(escaped, "?") ? UNKNOWN + escaped : escaped;
	}

	public static function unescapeFile(file:String):String {
		if (StringTools.startsWith(file, UNKNOWN))
			file = file.substr(UNKNOWN.length);
		return StringTools.replace(file, COLONS, "::");
	}

	static inline var CHUNK = 256;

	// The class of each module function, by global
	var classOf = new Map<Int, String>();

	function chunkClass(k:Int):String
		return k == 0 ? cls : cls + "_" + k;

	static function functionName(s:Scope):String
		return s.global < 0 ? "body" : 'f${s.global}';

	function run():haxe.io.Bytes {
		scopes = StackCheck.run(m);
		analyse();
		// cppia finds a static function by looking through its class's functions one
		//  by one, so the functions go in classes of CHUNK at most, the first with the
		//  module's statics
		for (k in 0...scopes.length)
			if (scopes[k].global >= 0)
				classOf.set(scopes[k].global, chunkClass(Std.int(k / CHUNK)));
		var k = 0;
		while (k < scopes.length) {
			var n = scopes.length - k < CHUNK ? scopes.length - k : CHUNK;
			if (k == 0) {
				w.beginClass(cls, n + 3);
				w.staticVar("G", CppiaWriter.ARRAY);
				w.staticVar("M", CppiaWriter.DYNAMIC);
				w.staticVar("B", CppiaWriter.ARRAY);
			} else
				w.beginClass(chunkClass(Std.int(k / CHUNK)), n);
			for (i in k...k + n)
				writeFunction(scopes[i]);
			k += n;
		}
		gLocal = null;
		w.main(mainExpr());
		return w.toBytes();
	}

	// -- Module analysis --

	function analyse() {
		var n = m.globals.length;
		targets = [for (_ in 0...m.codeSize + 1) false];
		leadAt = [for (_ in 0...m.codeSize + 1) -1];
		inScope = [for (_ in 0...m.codeSize + 1) -1];
		writes = [for (_ in 0...n) 0];
		heldFunction = [for (_ in 0...n) -1];
		for (s in scopes) {
			targets[s.entry] = true;
			for (p in s.pcs()) {
				if (p >= m.codeSize)
					continue;
				switch m.op(p) {
					case Jump | JumpIf | JumpIfNot | Trap:
						targets[m.target(p)] = true;
					case JumpTable:
						for (k in 0...m.param(p) + 1)
							targets[p + 2 + 2 * k] = true;
					case SetGlobal:
						writes[m.param(p)]++;
					default:
				}
			}
		}
		// A global the module body sets to one of the module's functions before it runs
		//  anything that could run a function, and that nothing sets to anything else,
		//  holds that function whenever a function runs
		var stored = [for (_ in 0...n) -2];
		for (s in scopes)
			for (p in s.pcs()) {
				if (p >= m.codeSize || m.op(p) != SetGlobal)
					continue;
				var g = m.param(p), f = storedFunction(p);
				stored[g] = stored[g] == -2 || stored[g] == f ? f : -1;
			}
		for (g in setBeforeCalls())
			if (stored[g] >= 0)
				heldFunction[g] = stored[g];
		for (i in 0...n)
			switch m.globals[i] {
				case GFunction(_, _) if (writes[i] == 0):
					heldFunction[i] = i;
				default:
			}
		for (s in scopes)
			if (s.global >= 0)
				for (p in s.pcs())
					if (p < m.codeSize && m.op(p) == TailCall && !((m.param(p) & 7) == s.nargs && accFunction(p) == s.global))
						mayTail.set(s.global, true);
		var stores = new Map<Int, Int>();
		for (s in scopes)
			for (p in s.pcs())
				if (p < m.codeSize && m.op(p) == SetField) {
					var h = m.param(p), f = accFunction(p);
					var had = stores.get(h);
					stores.set(h, had == null || had == f ? f : -1);
				}
		for (h => f in stores)
			if (f >= 0)
				fieldFunction.set(h, f);
	}

	// The function an AccGlobal just before p, with no jump to p, puts in the
	//  accumulator, when it is a function global nothing writes; else -1
	function storedFunction(p:Int):Int {
		if (targets[p] || p < 2 || !m.isOp[p - 2] || m.op(p - 2) != AccGlobal)
			return -1;
		var f = m.param(p - 2);
		return switch m.globals[f] {
			case GFunction(_, _) if (writes[f] == 0): f;
			default: -1;
		}
	}

	// The globals the module body sets before it runs anything that could run neko code
	function setBeforeCalls():Array<Int> {
		var result = [];
		var p = 0, seen = new Map<Int, Bool>();
		while (p < m.codeSize && !seen.exists(p)) {
			seen.set(p, true);
			switch m.op(p) {
				case Jump:
					p = m.target(p);
					continue;
				case SetGlobal:
					result.push(m.param(p));
				case AccNull | AccTrue | AccFalse | AccThis | AccInt | AccStack | AccStack0 | AccStack1 | AccGlobal | AccBuiltin | SetStack | Push |
					Pop | Loop | MakeArray:
				default:
					return result;
			}
			p = m.next(p);
		}
		return result;
	}

	// The function an AccGlobal just before p, with no jump to p, gives for a call
	function accFunction(p:Int):Int {
		if (targets[p] || p < 2 || !m.isOp[p - 2] || m.op(p - 2) != AccGlobal)
			return -1;
		return heldFunction[m.param(p - 2)];
	}

	// Whether a global's value can be read at any time in the code, rather than where
	//  the instruction reading it is
	function constantGlobal(g:Int, inBody:Bool):Bool
		return writes[g] == 0 || (!inBody && heldFunction[g] >= 0);

	function functionArgs(g:Int):Int
		return switch m.globals[g] {
			case GFunction(_, nargs): nargs;
			default: -2;
		}

	// -- Module main --

	inline function call(name:String, args:Array<E>):E
		return ECallStatic(RT, name, args);

	inline function v(l:Local):E
		return EVar(l.id);

	inline function set(l:Local, e:E):E
		return ESet(EVar(l.id), e);

	// The module's globals: in a function, a local the function reads them through,
	//  so the code names the static once rather than at each use, which the garbage
	//  collector marks every time
	function globals():E {
		if (gLocal == null)
			return EStatic(cls, "G");
		usesG = true;
		return v(gLocal);
	}

	var gLocal:Local;
	var bLocal:Local;
	var usesG:Bool;
	var usesB:Bool;

	inline function moduleRef():E
		return EStatic(cls, "M");

	function builtin(h:Int):E {
		var k = builtinIndex.get(h);
		if (k == null) {
			k = builtinHashes.length;
			builtinHashes.push(h);
			builtinIndex.set(h, k);
		}
		usesB = true;
		return EArrayI(v(bLocal), EInt(k));
	}

	function mainExpr():E {
		var items = [];
		for (i in 0...m.globals.length)
			items.push(switch m.globals[i] {
				case GFunction(_, nargs):
					call("func", [EStatic(classOf.get(i), 'f$i'), EInt(nargs), moduleRef(), EInt(i)]);
				case GString(b):
					call("stringOf", [EString(b.toHex())]);
				case GFloat(text):
					call("floatOf", [EString(text)]);
				default:
					ENull;
			});
		var bs = [
			for (h in builtinHashes)
				if (h == loaderHash)
					ECallStatic(BOOT, "loader", [moduleRef()])
				else if (h == exportsHash)
					ECallStatic(BOOT, "exports", [moduleRef()])
				else
					ECallStatic(BUILTINS, "find", [EInt(h)])
		];
		return EBlock([
			ESet(moduleRef(), ECallStatic(BOOT, "begin", [])),
			call("registerFields", [EArrayDef([for (f in m.fields) EString(f)])]),
			ESet(EStatic(cls, "B"), EArrayDef(bs)),
			ESet(globals(), EArrayDef(items)),
			ECallStatic(BOOT, "run", [moduleRef(), globals(), EStatic(cls, "body")])
		]);
	}

	// -- Functions --

	var stamp = 0;
	var order:Array<Block>;

	function writeFunction(s:Scope) {
		scope = s;
		th = local("this");
		env = local("env", CppiaWriter.ARRAY);
		var nargs = s.nargs < 0 ? 0 : s.nargs;
		slots = [for (i in 0...s.maxDepth + 1) local('s$i')];
		acc = local("acc");
		pc = local("pc", CppiaWriter.INT);
		var pcs = s.pcs();
		hasTraps = false;
		for (p in pcs)
			if (p < m.codeSize && m.op(p) == Trap)
				hasTraps = true;
		traps = hasTraps ? local("traps", CppiaWriter.ARRAY) : null;
		gLocal = local("g", CppiaWriter.ARRAY);
		bLocal = local("b", CppiaWriter.ARRAY);
		usesG = usesB = false;

		buildBlocks(pcs);

		// Blocks written inline that end up nested too deep become cases as well
		var cases = [];
		var done = new Map<Int, Bool>();
		var more = true;
		while (more) {
			more = false;
			for (b in order)
				if (b.reached && !b.inlined && !done.exists(b.start)) {
					done.set(b.start, true);
					more = true;
					// A block that goes back to itself, a loop's head, runs in a loop of
					//  its own, so going round is a continue rather than a trip through
					//  the switch; it is written again once that is known
					caseHead = b.start;
					wrapped = false;
					selfJump = false;
					var out = [];
					chain(b, new State(slots.length), out, 0);
					if (selfJump) {
						wrapped = true;
						out = [];
						chain(b, new State(slots.length), out, 0);
					}
					wrapped = false;
					caseHead = -1;
					cases.push({value: b.start, body: selfJump ? EWhile(EBool(true), EBlock(out)) : EBlock(out)});
				}
		}
		cases.sort((a, b) -> a.value - b.value);

		var dispatch = EWhile(EBool(true), cases.length == 1 ? cases[0].body : switchOn(cases));
		if (hasTraps) {
			var ex = local("e");
			var handler = EBlock([
				EIf(call("trapEmpty", [v(traps)]), EThrow(EVar(ex.id))),
				set(th, call("trapThis", [v(traps)])),
				set(pc, call("trapPc", [v(traps)])),
				call("trapPop", [v(traps)]),
				set(acc, call("trapped", [EVar(ex.id)]))
			]);
			dispatch = EWhile(EBool(true), ETry(EWhile(EBool(true), switchOn(cases)), ex, handler));
		}
		// Only the locals the code uses are declared: one with no value to start with
		//  starts as null, as the slots and the accumulator do
		markUsed(dispatch);
		var decls:Array<{v:Local, init:Null<E>}> = [];
		inline function declare(l:Local, init:Null<E>)
			if (usedAt[l.id] == stamp)
				decls.push({v: l, init: init});
		declare(acc, null);
		if (usesG)
			decls.push({v: gLocal, init: EStatic(cls, "G")});
		if (usesB)
			decls.push({v: bLocal, init: EStatic(cls, "B")});
		for (i in nargs...slots.length)
			declare(slots[i], null);
		declare(pc, EInt(s.entry));
		if (hasTraps)
			decls.push({v: traps, init: EArrayDef([])});
		var body:Array<E> = decls.length > 0 ? [EVars(decls)] : [];
		body.push(dispatch);
		body.push(EReturn(ENull));

		var args = [th, env].concat(slots.slice(0, nargs));
		var pos = m.positions != null && s.entry < m.positions.length ? m.positions[s.entry] : null;
		w.staticFunction(functionName(s), args, CppiaWriter.DYNAMIC, EBlock(body), fileId(pos), pos == null ? s.entry : pos.line);
	}

	// The function each local was last seen used in, by id
	var usedAt:Array<Int> = [];

	function markUsed(e:E) {
		switch e {
			case EVar(id):
				usedAt[id] = stamp;
			case EBlock(es) | ECallStatic(_, _, es) | EArrayDef(es):
				for (x in es)
					markUsed(x);
			case ESet(a, b) | EArrayI(a, b) | EIf(a, b) | EWhile(a, b) | ELess(a, b):
				markUsed(a);
				markUsed(b);
			case EIfElse(a, b, c):
				markUsed(a);
				markUsed(b);
				markUsed(c);
			case ESwitch(c, cases):
				markUsed(c);
				for (x in cases)
					markUsed(x.body);
			case ETry(body, _, handler):
				markUsed(body);
				markUsed(handler);
			case EReturn(x) | EThrow(x) | ENot(x) | EIsNull(x) | ENotNull(x) | EPos(_, _, x) | EDecl(_, x):
				markUsed(x);
			case EVars(vars):
				for (d in vars)
					if (d.init != null)
						markUsed(d.init);
			case EInt(_) | EString(_) | EBool(_) | ENull | EStatic(_, _) | EContinue | EBreak:
		}
	}

	// The switch over the blocks; under the JIT, which tests cases one by one, a large
	//  one becomes a tree of comparisons with small switches at its leaves
	function switchOn(cases:Array<{value:Int, body:E}>):E {
		if (!jit || cases.length <= JIT_SWITCH)
			return ESwitch(v(pc), cases);
		var half = cases.length >> 1;
		return EIfElse(ELess(v(pc), EInt(cases[half].value)), switchOn(cases.slice(0, half)), switchOn(cases.slice(half)));
	}

	var lastFile:String = null;
	var lastFileId = 0;

	function fileId(pos:Null<Position>):Int {
		var f = pos == null ? '$name@' : pos.file;
		if (f != lastFile) {
			lastFile = f;
			lastFileId = w.stringId(pos == null ? f : frameFile(f));
		}
		return lastFileId;
	}

	function position(p:Int):Pos {
		var pos = m.positions != null && p < m.positions.length ? m.positions[p] : null;
		// Without debug info the code index stands in for the line
		return new Pos(fileId(pos), pos == null ? p : pos.line);
	}

	// -- Blocks --

	function buildBlocks(pcs:Array<Int>) {
		var mark = ++stamp;
		leadAt[scope.entry] = mark;
		for (p in pcs) {
			if (p >= m.codeSize) {
				leadAt[p] = mark;
				continue;
			}
			switch m.op(p) {
				case Jump | JumpIf | JumpIfNot | Trap:
					leadAt[m.target(p)] = mark;
					leadAt[m.next(p)] = mark;
				case JumpTable:
					for (k in 0...m.param(p) + 1)
						leadAt[p + 2 + 2 * k] = mark;
				case Ret | TailCall:
					leadAt[m.next(p)] = mark;
				default:
			}
		}

		for (p in pcs)
			inScope[p] = mark;


		order = [];
		var i = 0;
		while (i < pcs.length) {
			var b = new Block(pcs[i]);
			var p = b.start;
			while (true) {
				b.code.push(p);
				if (p >= m.codeSize)
					break;
				var op = m.op(p);
				var next = op == JumpTable ? p + 2 + 2 * m.param(p) : m.next(p);
				b.next = next;
				if (op == Jump || op == Ret || op == TailCall || op == JumpTable || op == JumpIf || op == JumpIfNot || op == Trap)
					break;
				if (leadAt[next] == mark || inScope[next] != mark)
					break;
				p = next;
			}
			blockAt[b.start] = b;
			order.push(b);
			i++;
			while (i < pcs.length && leadAt[pcs[i]] != mark)
				i++;
		}

		// The edges between blocks; the entry, trap handlers and jump table cases are
		//  reached through the switch
		blockAt[scope.entry].forced = true;
		for (b in order) {
			var p = b.code[b.code.length - 1];
			b.succ = [];
			if (p < m.codeSize)
				switch m.op(p) {
					case Jump:
						b.succ.push(m.target(p));
					case JumpIf | JumpIfNot:
						b.succ.push(m.target(p));
						b.succ.push(m.next(p));
					case Trap:
						blockAt[m.target(p)].forced = true;
						b.succ.push(m.next(p));
					case JumpTable:
						for (k in 0...m.param(p) + 1) {
							var t = p + 2 + 2 * k;
							blockAt[t].forced = true;
							b.succ.push(t);
						}
					case Ret | TailCall:
					default:
						b.succ.push(b.next);
				}
		}
		// Predecessors among the blocks that run
		var work = [for (b in order) if (b.forced) b];
		for (b in work)
			b.reached = true;
		while (work.length > 0) {
			var b = work.pop();
			for (t in b.succ) {
				var c = blockAt[t];
				c.preds++;
				if (!c.reached) {
					c.reached = true;
					work.push(c);
				}
			}
		}
		for (b in order)
			b.inlined = b.reached && !b.forced && b.preds == 1;

		// Where the accumulator is read before it is written
		for (b in order) {
			for (p in b.code) {
				if (readsAcc(p)) {
					b.accIn = true;
					break;
				}
				if (writesAcc(p)) {
					b.writesAcc = true;
					break;
				}
			}
		}
		var changed = true;
		while (changed) {
			changed = false;
			for (b in order) {
				if (b.accIn || b.writesAcc)
					continue;
				for (t in b.succ)
					if (blockAt[t].accIn) {
						b.accIn = true;
						changed = true;
						break;
					}
			}
		}
	}

	// Whether the accumulator is read after each instruction of a block, before it is
	//  written, by the block or one after it
	function accLiveAfter(b:Block):Array<Bool> {
		var out = false;
		for (t in b.succ)
			if (blockAt[t].accIn)
				out = true;
		var live = [for (_ in b.code) false];
		var k = b.code.length;
		while (k-- > 0) {
			live[k] = out;
			var p = b.code[k];
			if (writesAcc(p))
				out = false;
			if (readsAcc(p))
				out = true;
		}
		return live;
	}

	function readsAcc(p:Int):Bool {
		if (p >= m.codeSize)
			return true;
		return switch m.op(p) {
			case AccNull | AccTrue | AccFalse | AccThis | AccInt | AccStack | AccStack0 | AccStack1 | AccGlobal | AccEnv | AccBuiltin | Pop | Loop |
				Jump | Trap | EndTrap:
				false;
			default:
				true;
		}
	}

	function writesAcc(p:Int):Bool {
		if (p >= m.codeSize)
			return false;
		return switch m.op(p) {
			case SetStack | SetGlobal | SetEnv | SetField | SetThis | Push | Pop | Loop | Jump | JumpIf | JumpIfNot | Trap | EndTrap | Ret | TailCall |
				JumpTable | SetArray | SetIndex:
				false;
			default:
				true;
		}
	}

	// -- Writing code --

	// Writes block b and the blocks written inline after it, starting from state st
	function chain(b:Block, st:State, out:Array<E>, nest:Int) {
		var live = accLiveAfter(b);
		for (k in 0...b.code.length) {
			var p = b.code[k];
			if (p >= m.codeSize) {
				// The module body ends with neko's Last, returning the accumulator
				var pos = position(p);
				var e = consumeAcc(st, out, pos, false);
				out.push(EPos(pos.file, pos.line, EReturn(e)));
				return;
			}
			var op = m.op(p);
			switch op {
				case Jump:
					goTo(m.target(p), st, out, nest);
					return;
				case JumpIf | JumpIfNot:
					var pos = position(p);
					var cond = condition(st, out, pos, op == JumpIf, live[k]);
					var taken = [];
					goTo(m.target(p), st.copy(), taken, nest + 1);
					out.push(EPos(pos.file, pos.line, EIf(cond, EBlock(taken))));
					goTo(m.next(p), st, out, nest);
					return;
				default:
					if (instruction(p, st, out, live[k]))
						return;
			}
		}
		goTo(b.next, st, out, nest);
	}

	// Goes on to the block at t: inline when nothing else reaches it, else through
	//  the switch with the state in locals
	function goTo(t:Int, st:State, out:Array<E>, nest:Int) {
		var b = blockAt[t];
		if (b.inlined && nest < MAX_NEST) {
			chain(b, st, out, nest);
			return;
		}
		b.inlined = false;
		flush(st, out, scope.depth.get(t), b.accIn);
		jumpTo(t, out);
	}

	// The switch's case being written, whether it loops on its own, and whether it
	//  goes back to itself
	var caseHead = -1;
	var wrapped = false;
	var selfJump = false;

	// Goes to the case at t, with the state in locals: round the case's own loop when
	//  t is its head, else out of it to the switch
	function jumpTo(t:Int, out:Array<E>) {
		if (t == caseHead) {
			selfJump = true;
			if (wrapped) {
				out.push(EContinue);
				return;
			}
		}
		out.push(set(pc, EInt(t)));
		out.push(wrapped ? EBreak : EContinue);
	}

	// Puts the state in locals: the slots below depth, and the accumulator when it is read
	function flush(st:State, out:Array<E>, depth:Int, accLive:Bool) {
		for (k in 0...depth)
			if (st.slots[k] != null)
				materializeSlot(st, k, out);
		if (accLive)
			materializeAcc(st, out);
		else
			dropAcc(st, out);
	}

	// The condition of a conditional jump on the accumulator, which the jump leaves as it is
	function condition(st:State, out:Array<E>, pos:Pos, ifTrue:Bool, live:Bool):E {
		var a = st.acc;
		var isBool = a != null && a.isBool;
		var e = readAcc(st, out, pos, false, live);
		if (isBool)
			return ifTrue ? e : ENot(e);
		return call(ifTrue ? "isTrue" : "isNotTrue", [e]);
	}

	// -- The state --
	//
	// A slot or the accumulator is pending when its value is an expression rather than
	//  its local. While it is, nothing pending reads its local, so a pending value can
	//  go into its local at any time without upsetting another. Effects stay in order:
	//  only the accumulator holds one, which the next instruction takes or puts in a local

	// Before local id changes or stops holding its slot's value: whatever pending reads it
	//  goes into its own local
	function release(st:State, id:Int, out:Array<E>, keepAcc = false) {
		for (k in 0...st.slots.length) {
			var s = st.slots[k];
			if (s != null && s.kind == LOCAL && s.local == id)
				materializeSlot(st, k, out);
		}
		var a = st.acc;
		if (!keepAcc && a != null && (a.kind == LOCAL && a.local == id || a.kind == EFFECT && reads(a.e, id)))
			materializeAcc(st, out);
	}

	static function reads(e:E, id:Int):Bool {
		return switch e {
			case EVar(i): i == id;
			case ECallStatic(_, _, args) | EArrayDef(args) | EBlock(args):
				for (a in args)
					if (reads(a, id))
						return true;
				false;
			case EArrayI(a, i): reads(a, id) || reads(i, id);
			case ENot(x) | EIsNull(x) | ENotNull(x) | EPos(_, _, x): reads(x, id);
			case ESet(l, r): reads(l, id) || reads(r, id);
			case EIfElse(c, a, b): reads(c, id) || reads(a, id) || reads(b, id);
			case ELess(a, b): reads(a, id) || reads(b, id);
			default: false;
		}
	}

	function materializeSlot(st:State, k:Int, out:Array<E>) {
		var s = st.slots[k];
		st.slots[k] = null;
		out.push(ESet(v(slots[k]), s.e));
	}

	function materializeAcc(st:State, out:Array<E>) {
		var a = st.acc;
		if (a == null)
			return;
		st.acc = null;
		if (a.kind == LOCAL && a.local == acc.id)
			return;
		out.push(EPos(a.file, a.line, set(acc, a.e)));
	}

	// The accumulator is about to be replaced: a pending effect still happens
	function dropAcc(st:State, out:Array<E>) {
		var a = st.acc;
		st.acc = null;
		if (a != null && a.kind == EFFECT && !a.droppable)
			out.push(EPos(a.file, a.line, a.e));
	}

	// The accumulator's value for an instruction that reads it and then replaces it.
	//  An effect pending in it goes into the instruction's own expression when they are
	//  at the same line, or one of them cannot throw, so the statement's line is right
	//  for whatever throws in it
	function consumeAcc(st:State, out:Array<E>, pos:Pos, canThrow:Bool):E {
		var a = st.acc;
		if (a == null)
			return v(acc);
		if (a.kind == EFFECT) {
			if (a.canThrow && canThrow && a.line != pos.line) {
				materializeAcc(st, out);
				return v(acc);
			}
			st.acc = null;
			if (a.canThrow)
				pos.takes(a);
		}
		return a.e;
	}

	// The accumulator's value for an instruction that reads it and leaves it: a pending
	//  effect goes into the local when it is read again later
	function readAcc(st:State, out:Array<E>, pos:Pos, canThrow:Bool, liveAfter:Bool):E {
		var a = st.acc;
		if (a == null)
			return v(acc);
		if (a.kind != EFFECT)
			return a.e;
		if (liveAfter) {
			materializeAcc(st, out);
			return v(acc);
		}
		return consumeAcc(st, out, pos, canThrow);
	}

	// Replaces the accumulator with p
	function setAcc(st:State, out:Array<E>, p:Pending) {
		dropAcc(st, out);
		release(st, acc.id, out, true);
		st.acc = p;
	}

	// The value of stack slot k
	function slotValue(st:State, k:Int):E {
		var s = st.slots[k];
		return s == null ? v(slots[k]) : s.e;
	}

	function slotPending(st:State, k:Int):Pending {
		var s = st.slots[k];
		return s != null ? s : Pending.ofLocal(slots[k].id, v(slots[k]));
	}

	// The n slots below the top, deepest first
	function top(st:State, depth:Int, n:Int):Array<E>
		return [for (k in depth - n...depth) slotValue(st, k)];

	function pop(st:State, from:Int, to:Int)
		for (k in from...to)
			st.slots[k] = null;

	inline function effect(e:E, pos:Pos, canThrow = true, isBool = false):Pending
		return Pending.ofEffect(e, pos.file, pos.line, canThrow || pos.throws, isBool);

	// Puts the accumulator's value in slot k: kept pending when it is a constant or a
	//  local, else written to the slot's local, which the accumulator then reads
	function setSlot(st:State, k:Int, out:Array<E>, pos:Pos) {
		var a = st.acc;
		var id = slots[k].id;
		if (a == null && !hasTraps)
			a = Pending.ofLocal(acc.id, v(acc));
		if (a != null && a.kind == LOCAL && a.local == id) {
			st.slots[k] = null;
			return;
		}
		if (a != null && a.kind != EFFECT && !hasTraps) {
			release(st, id, out);
			st.slots[k] = a;
			return;
		}
		var e = consumeAcc(st, out, pos, false);
		var wasEffect = st.acc == null && a != null && a.kind == EFFECT;
		release(st, id, out, true);
		st.slots[k] = null;
		out.push(EPos(pos.file, pos.line, ESet(v(slots[k]), e)));
		if (wasEffect)
			st.acc = Pending.ofLocal(id, v(slots[k]));
	}

	// Writes local l, which is not a slot, with what pending reads it put in locals first
	function writeLocal(st:State, l:Local, e:E, out:Array<E>, pos:Pos) {
		release(st, l.id, out, true);
		out.push(EPos(pos.file, pos.line, set(l, e)));
	}

	// Writes one instruction; true when it ends the block
	function instruction(p:Int, st:State, out:Array<E>, liveAfter:Bool):Bool {
		var op = m.op(p);
		var param = op.hasParam ? m.param(p) : 0;
		var d = scope.depth.get(p);
		var pos = position(p);
		var inBody = scope.global < 0;
		function binary(name:String, isBool = false, canThrow = true) {
			var a = slotValue(st, d - 1);
			var b = consumeAcc(st, out, pos, canThrow);
			pop(st, d - 1, d);
			// With an int constant on the right, the runtime takes the int as it is
			var e = switch b {
				case EInt(_) if (INT_OPS.exists(name)): call(name + "I", [a, b]);
				default: call(name, [a, b]);
			}
			setAcc(st, out, effect(e, pos, canThrow, isBool));
		}
		function unary(make:E->E, canThrow:Bool, isBool = false) {
			var a = consumeAcc(st, out, pos, canThrow);
			setAcc(st, out, effect(make(a), pos, canThrow, isBool));
		}

		switch op {
			case AccNull:
				setAcc(st, out, Pending.ofConst(ENull));
			case AccTrue:
				setAcc(st, out, Pending.ofConst(EBool(true), true));
			case AccFalse:
				setAcc(st, out, Pending.ofConst(EBool(false), true));
			case AccThis:
				setAcc(st, out, Pending.ofLocal(th.id, v(th)));
			case AccInt:
				setAcc(st, out, Pending.ofConst(EInt(param)));
			case AccStack | AccStack0 | AccStack1:
				var s = slotPending(st, d - 1 - m.slot(p));
				if (s.kind == LOCAL && s.local == acc.id) {
					// The value is in the accumulator's local already
					dropAcc(st, out);
				} else
					setAcc(st, out, s);
			case AccGlobal:
				var e = EArrayI(globals(), EInt(param));
				if (constantGlobal(param, inBody)) {
					var c = Pending.ofConst(e);
					c.fn = heldFunction[param];
					setAcc(st, out, c);
				} else {
					var r = effect(e, pos, false);
					r.droppable = true;
					setAcc(st, out, r);
				}
			case AccEnv:
				setAcc(st, out, effect(EArrayI(v(env), EInt(param)), pos));
			case AccField:
				unary(a -> call("field", [a, EInt(param)]), true);
			case AccArray:
				binary("aget");
			case AccIndex | AccIndex0 | AccIndex1:
				unary(a -> call("aget", [a, EInt(m.slot(p))]), true);
			case AccBuiltin:
				if (param == loaderHash || param == exportsHash || builtinExists == null || builtinExists(param))
				{
					var c = Pending.ofConst(builtin(param));
					c.builtin = param;
					setAcc(st, out, c);
				}
				else
					setAcc(st, out, effect(ECallStatic(BUILTINS, "get", [EInt(param)]), pos));
			case SetStack:
				setSlot(st, d - 1 - param, out, pos);
			case Push:
				setSlot(st, d, out, pos);
			case SetGlobal:
				var e = readAcc(st, out, pos, false, liveAfter);
				out.push(EPos(pos.file, pos.line, ESet(EArrayI(globals(), EInt(param)), e)));
			case SetEnv:
				var e = readAcc(st, out, pos, false, liveAfter);
				out.push(EPos(pos.file, pos.line, ESet(EArrayI(v(env), EInt(param)), e)));
			case SetField:
				var o = slotValue(st, d - 1);
				var e = readAcc(st, out, pos, true, liveAfter);
				out.push(EPos(pos.file, pos.line, call("setField", [o, EInt(param), e])));
			case SetArray:
				var a = slotValue(st, d - 1), i = slotValue(st, d - 2);
				var e = readAcc(st, out, pos, true, liveAfter);
				out.push(EPos(pos.file, pos.line, call("aset", [a, i, e])));
			case SetIndex:
				var a = slotValue(st, d - 1);
				var e = readAcc(st, out, pos, true, liveAfter);
				out.push(EPos(pos.file, pos.line, call("aset", [a, EInt(param), e])));
			case SetThis:
				var a = st.acc;
				if (a != null && a.kind == LOCAL && a.local == th.id)
					return false;
				var wasEffect = a != null && a.kind == EFFECT;
				var e = readAcc(st, out, pos, false, false);
				writeLocal(st, th, e, out, pos);
				if (wasEffect)
					st.acc = Pending.ofLocal(th.id, v(th));
			case Pop:
				pop(st, d - param, d);
			case Loop:
			case Call:
				var args = top(st, d, param);
				var f = st.acc;
				var e:E;
				var leaf = f != null && f.kind == CONST && f.builtin != 0 ? LEAF_BUILTINS.get(f.builtin) : null;
				var isBool = false, canThrow = true;
				var noCompare = f != null && f.kind == CONST && f.builtin != 0 ? NULL_COMPARE_BUILTINS.get(f.builtin) : null;
				if (noCompare != null && noCompare.nargs == param && args[param - 1].match(ENull)) {
					st.acc = null;
					e = ECallStatic(BUILTINS, noCompare.fn, args.slice(0, param - 1));
					isBool = noCompare.isBool;
				} else if (leaf != null && leaf.nargs == param) {
					// A builtin that runs no neko code, called where it is used
					st.acc = null;
					e = ECallStatic(leaf.cls, leaf.fn, args);
					isBool = leaf.isBool;
					canThrow = leaf.canThrow;
				} else if (f != null && f.kind == CONST && f.fn >= 0 && functionArgs(f.fn) == param) {
					st.acc = null;
					e = directCall(f.fn, args);
				} else
					e = call('call$param', [consumeAcc(st, out, pos, true), v(th)].concat(args));
				pop(st, d - param, d);
				setAcc(st, out, effect(e, pos, canThrow, isBool));
			case ObjCall:
				var o = slotValue(st, d - 1);
				var args = top(st, d - 1, param);
				var a = st.acc;
				var h = a != null && a.kind == EFFECT && !(a.canThrow && a.line != pos.line) ? fieldOf(a.e, o) : null;
				var e:E;
				var known = h == null ? null : fieldFunction.get(h);
				if (known != null && functionArgs(known) == param) {
					// The field read into the accumulator's local, then a direct call of
					//  the function the module stores there while it still holds it. The
					//  arguments and o are constants or locals, so they read the same after
					st.acc = null;
					pos.takes(a);
					writeLocal(st, acc, a.e, out, pos);
					o = slotValue(st, d - 1);
					args = top(st, d - 1, param);
					var direct = ECallStatic(classOf.get(known), 'f$known', [o, ENull].concat(args));
					if (mayTail.exists(known))
						direct = call("finish", [direct]);
					var cond = call("isValue", [v(acc), EArrayI(globals(), EInt(known))]);
					e = EIfElse(cond, direct, call('call$param', [v(acc), o].concat(args)));
				} else if (h != null) {
					// o.f(args) in one call: the field read, then the call, as before
					st.acc = null;
					pos.takes(a);
					e = call('method$param', [o, EInt(h)].concat(args));
				} else
					e = call('call$param', [consumeAcc(st, out, pos, true), o].concat(args));
				pop(st, d - 1 - param, d);
				setAcc(st, out, effect(e, pos));
			case TailCall:
				tailCall(param & 7, d, st, out, pos);
				return true;
			case Ret:
				var e = consumeAcc(st, out, pos, false);
				out.push(EPos(pos.file, pos.line, EReturn(e)));
				return true;
			case Trap:
				// An effect pending happens before the trap is set
				if (liveAfter)
					materializeAcc(st, out);
				else
					dropAcc(st, out);
				out.push(EPos(pos.file, pos.line, call("trapPush", [v(traps), EInt(m.target(p)), v(th)])));
			case EndTrap:
				if (liveAfter)
					materializeAcc(st, out);
				else
					dropAcc(st, out);
				out.push(EPos(pos.file, pos.line, call("trapPop", [v(traps)])));
			case MakeEnv:
				var items = top(st, d, param);
				var f = consumeAcc(st, out, pos, true);
				pop(st, d - param, d);
				setAcc(st, out, effect(call("makeEnv", [f, EArrayDef(items)]), pos));
			case MakeArray:
				var items = top(st, d, param);
				var a = consumeAcc(st, out, pos, false);
				if (m.version >= 2)
					items.push(a);
				else
					items.unshift(a);
				pop(st, d - param, d);
				var r = effect(EArrayDef(items), pos, false);
				r.droppable = !r.canThrow;
				setAcc(st, out, r);
			case Bool:
				unary(a -> call("toBool", [a]), false, true);
			case Not:
				unary(a -> call("not", [a]), false, true);
			case IsNull:
				unary(a -> EIsNull(a), false, true);
			case IsNotNull:
				unary(a -> ENotNull(a), false, true);
			case Add:
				binary("add");
			case Sub:
				binary("sub");
			case Mult:
				binary("mult");
			case Div:
				binary("div");
			case Mod:
				binary("mod");
			case Shl:
				binary("shl");
			case Shr:
				binary("shr");
			case UShr:
				binary("ushr");
			case Or:
				binary("or");
			case And:
				binary("and");
			case Xor:
				binary("xor");
			case Eq:
				binary("eq", true);
			case Neq:
				binary("neq", true);
			case Gt:
				binary("gt", true);
			case Gte:
				binary("gte", true);
			case Lt:
				binary("lt", true);
			case Lte:
				binary("lte", true);
			case TypeOf:
				unary(a -> call("typeOf", [a]), false);
			case Compare:
				binary("compareOp");
			case PhysCompare:
				binary("physCompare", false, false);
			case Hash:
				unary(a -> call("hash", [a]), true);
			case New:
				unary(a -> call("newObject", [a]), true);
			case JumpTable:
				// Each case is a Jump of its own in the switch, as is the default
				for (k in 0...st.slots.length)
					if (st.slots[k] != null)
						materializeSlot(st, k, out);
				materializeAcc(st, out);
				out.push(EPos(pos.file, pos.line, set(pc, call("tableTarget", [v(acc), EInt(param), EInt(p)]))));
				out.push(wrapped ? EBreak : EContinue);
				return true;
			case Apply:
				var args = top(st, d, param);
				var f = consumeAcc(st, out, pos, true);
				pop(st, d - param, d);
				setAcc(st, out, effect(call("apply", [f, v(th), EArrayDef(args)]), pos));
			case Jump | JumpIf | JumpIfNot:
				throw 'unexpected ${op.name} at $p';
			case MakeArray2 | AccInt32 | Last:
				throw 'unexpected ${op.name} at $p';
		}
		return false;
	}

	// The field hash when e reads a field of o, Rt.field(o, h)
	static function fieldOf(e:E, o:E):Null<Int> {
		return switch e {
			case ECallStatic(RT, "field", [obj, EInt(h)]) if (sameValue(obj, o)): h;
			default: null;
		}
	}

	// Whether two pending values are the same constant or local
	static function sameValue(a:E, b:E):Bool {
		return switch [a, b] {
			case [EVar(x), EVar(y)]: x == y;
			case [EInt(x), EInt(y)]: x == y;
			case [ENull, ENull]: true;
			case [EArrayI(EStatic(c1, f1), EInt(i)), EArrayI(EStatic(c2, f2), EInt(j))]: c1 == c2 && f1 == f2 && i == j;
			case [EArrayI(EVar(x), EInt(i)), EArrayI(EVar(y), EInt(j))]: x == y && i == j;
			default: false;
		}
	}

	// A call of the module's function in global f, straight to its static function. It
	//  is the function value with no environment, as AccGlobal gives it
	function directCall(f:Int, args:Array<E>):E {
		var e = ECallStatic(classOf.get(f), 'f$f', [v(th), ENull].concat(args));
		return mayTail.exists(f) ? call("finish", [e]) : e;
	}

	function tailCall(n:Int, d:Int, st:State, out:Array<E>, pos:Pos) {
		var self = scope.global >= 0 && n == scope.nargs;
		var f = st.acc;
		var known = self && f != null && f.kind == CONST && f.fn == scope.global;
		if (self && !known && f != null && f.kind == EFFECT)
			materializeAcc(st, out);
		f = st.acc;
		var fe = f == null ? v(acc) : f.e;
		if (self) {
			// Calling itself, the function loops with the new arguments, as neko reuses
			//  the frame; the arguments sit above the slots they replace
			var loop = [];
			var ls = st.copy();
			writeLocal(ls, env, known ? ENull : call("envOf", [fe]), loop, pos);
			for (i in 0...n) {
				var id = slots[i].id;
				release(ls, id, loop);
				var value = slotPending(ls, d - n + i);
				ls.slots[i] = null;
				if (!(value.kind == LOCAL && value.local == id))
					loop.push(ESet(v(slots[i]), value.e));
			}
			flush(ls, loop, n, blockAt[scope.entry].accIn);
			jumpTo(scope.entry, loop);
			if (known) {
				out.push(EPos(pos.file, pos.line, EBlock(loop)));
				return;
			}
			out.push(EPos(pos.file, pos.line, EIf(call("isSelf", [fe, moduleRef(), EInt(scope.global)]), EBlock(loop))));
		}
		var args = top(st, d, n);
		var e = consumeAcc(st, out, pos, true);
		if (n <= 3)
			out.push(EPos(pos.file, pos.line, EReturn(call('tail$n', [e, v(th)].concat(args)))));
		else
			out.push(EPos(pos.file, pos.line, EReturn(call("tailCall", [e, v(th), EArrayDef(args)]))));
	}
}

// Where an instruction is, and whether an effect it takes in can throw there
@:build(nekomata.build.NoFrames.build())
class Pos {
	public var file:Int;
	public var line:Int;
	public var throws = false;

	public function new(file:Int, line:Int) {
		this.file = file;
		this.line = line;
	}

	// The instruction's expression takes in pending p, which can throw: the statement
	//  it ends up in is at p's line
	public function takes(p:Pending) {
		file = p.file;
		line = p.line;
		throws = true;
	}
}

// A run of instructions with one way in, and the blocks it goes on to
@:build(nekomata.build.NoFrames.build())
class Block {
	public var start:Int;
	public var code:Array<Int> = [];
	// Where the block runs on to when it does not end in a jump or return
	public var next:Int = -1;
	public var succ:Array<Int>;
	public var preds = 0;
	public var reached = false;
	// Reached through the switch: the entry, trap handlers and jump table cases
	public var forced = false;
	// Written where its one predecessor goes to it
	public var inlined = false;
	public var accIn = false;
	public var writesAcc = false;

	public function new(start:Int)
		this.start = start;
}

// A value not yet in a local: a constant, a local's value, or the result of an
//  instruction, worked out where it is used
@:build(nekomata.build.NoFrames.build())
class Pending {
	public var kind:Int;
	public var e:E;
	public var local:Int = -1;
	public var file:Int = 0;
	public var line:Int = 0;
	public var canThrow = false;
	// A value the runtime gives as a Bool, which a conditional jump tests directly
	public var isBool = false;
	// An effect that can be left out when nothing reads its value
	public var droppable = false;
	// For a constant: the builtin it is, by hash, or 0
	public var builtin = 0;
	// For a constant: the module function it is, when it is a function global's value
	public var fn = -1;

	function new(kind:Int, e:E) {
		this.kind = kind;
		this.e = e;
	}

	public static function ofConst(e:E, isBool = false):Pending {
		var p = new Pending(CONST, e);
		p.isBool = isBool;
		return p;
	}

	public static function ofLocal(id:Int, e:E):Pending {
		var p = new Pending(LOCAL, e);
		p.local = id;
		return p;
	}

	public static function ofEffect(e:E, file:Int, line:Int, canThrow:Bool, isBool:Bool):Pending {
		var p = new Pending(EFFECT, e);
		p.file = file;
		p.line = line;
		p.canThrow = canThrow;
		p.isBool = isBool;
		return p;
	}
}

// What the slots and the accumulator hold where their locals do not
@:build(nekomata.build.NoFrames.build())
class State {
	public var slots:Array<Pending>;
	public var acc:Pending = null;

	public function new(n:Int)
		slots = [for (_ in 0...n) null];

	public function copy():State {
		var s = new State(0);
		s.slots = slots.copy();
		s.acc = acc;
		return s;
	}
}

inline var CONST = 0;
inline var LOCAL = 1;
inline var EFFECT = 2;
