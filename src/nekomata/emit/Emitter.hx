package nekomata.emit;

import nekomata.emit.CppiaWriter;
import nekomata.neko.Module;
import nekomata.neko.Opcode;
import nekomata.neko.StackCheck;

// Translates a neko module to cppia. Each neko function becomes a static function
//  (this, env, args...) whose stack slots are locals, run by a loop that switches on
//  the basic block to run next
class Emitter {
	static inline var RT = "nekomata.rt.Rt";
	static inline var BUILTINS = "nekomata.rt.NekoBuiltins";
	static inline var BOOT = "nekomata.rt.Boot";

	var m:Module;
	var cls:String;
	var w:CppiaWriter;
	var nextVar = 1;

	// Locals of the function being written
	var th:Local;
	var env:Local;
	var acc:Local;
	var pc:Local;
	var traps:Local;
	var slots:Array<Local>;
	var scope:Scope;
	var file = "";
	var line = 0;

	static final loaderHash = nekomata.neko.Hash.field("loader");
	static final exportsHash = nekomata.neko.Hash.field("exports");

	// name is the module's name, the position of code that has no debug info
	public static function emit(m:Module, cls:String, name = "module"):String
		return new Emitter(m, cls, name).run();

	var name:String;

	function new(m:Module, cls:String, name:String) {
		this.m = m;
		this.cls = cls;
		this.name = name;
		w = new CppiaWriter();
	}

	function local(name:String, type = CppiaWriter.DYNAMIC):Local
		return {name: name, id: nextVar++, type: type};

	// hxcpp passes stack frames as class::method::file::line, and Haxe's debug info names
	//  positions like Class::method, so the separator is escaped; NekoStack restores it
	public static inline var COLONS = "::";

	static function frameFile(file:String):String
		return StringTools.replace(file, "::", COLONS);

	static function functionName(s:Scope):String
		return s.global < 0 ? "body" : 'f${s.global}';

	function run():String {
		var scopes = StackCheck.run(m);
		w.beginClass(cls, scopes.length + 2);
		w.staticVar("G", CppiaWriter.ARRAY);
		w.staticVar("M", CppiaWriter.DYNAMIC);
		for (s in scopes)
			writeFunction(s);
		w.main(mainExpr());
		return w.toString();
	}

	inline function call(name:String, args:Array<E>):E
		return ECallStatic(RT, name, args);

	inline function v(l:Local):E
		return EVar(l.id);

	inline function set(l:Local, e:E):E
		return ESet(EVar(l.id), e);

	inline function globals():E
		return EStatic(cls, "G");

	inline function moduleRef():E
		return EStatic(cls, "M");

	function mainExpr():E {
		var items = [];
		for (g in m.globals)
			items.push(switch g {
				case GFunction(_, nargs):
					null; // filled below, knowing the global's index
				case GString(b):
					call("stringOf", [EString(b.toHex())]);
				case GFloat(text):
					call("floatOf", [EString(text)]);
				default:
					ENull;
			});
		for (i in 0...m.globals.length)
			switch m.globals[i] {
				case GFunction(_, nargs):
					items[i] = call("func", [EStatic(cls, 'f$i'), EInt(nargs), moduleRef(), EInt(i)]);
				default:
			}
		return EBlock([
			ESet(moduleRef(), ECallStatic(BOOT, "begin", [])),
			call("registerFields", [EArrayDef([for (f in m.fields) EString(f)])]),
			ESet(globals(), EArrayDef(items)),
			ECallStatic(BOOT, "run", [moduleRef(), globals(), EStatic(cls, "body")])
		]);
	}

	function writeFunction(s:Scope) {
		scope = s;
		th = local("this");
		env = local("env", CppiaWriter.ARRAY);
		var nargs = s.nargs < 0 ? 0 : s.nargs;
		slots = [for (i in 0...s.maxDepth + 1) local('s$i')];
		acc = local("acc");
		pc = local("pc", CppiaWriter.INT);
		var pcs = s.pcs();
		var hasTraps = false;
		for (p in pcs)
			if (p < m.codeSize && m.op(p) == Trap)
				hasTraps = true;
		traps = hasTraps ? local("traps", CppiaWriter.ARRAY) : null;

		var body:Array<E> = [EDecl(acc, ENull)];
		for (i in nargs...slots.length)
			body.push(EDecl(slots[i], ENull));
		body.push(EDecl(pc, EInt(s.entry)));
		if (hasTraps)
			body.push(EDecl(traps, EArrayDef([])));

		var dispatch = EWhile(EBool(true), ESwitch(v(pc), blocks(pcs)));
		if (hasTraps) {
			var ex = local("e");
			var handler = EBlock([
				EIf(call("trapEmpty", [v(traps)]), EThrow(EVar(ex.id))),
				set(th, call("trapThis", [v(traps)])),
				set(pc, call("trapPc", [v(traps)])),
				call("trapPop", [v(traps)]),
				set(acc, call("caught", [EVar(ex.id)]))
			]);
			dispatch = ETry(dispatch, ex, handler);
		}
		body.push(EWhile(EBool(true), dispatch));
		body.push(EReturn(ENull));

		var args = [th, env].concat(slots.slice(0, nargs));
		var pos = m.positions != null && s.entry < m.positions.length ? m.positions[s.entry] : null;
		w.staticFunction(functionName(s), args, CppiaWriter.DYNAMIC, EBlock(body), pos == null ? '$name@' : frameFile(pos.file), pos == null ? s.entry : pos.line);
	}

	// The instructions that start a basic block
	function leaders(pcs:Array<Int>):Map<Int, Bool> {
		var result = new Map<Int, Bool>();
		result.set(scope.entry, true);
		for (p in pcs) {
			if (p >= m.codeSize) {
				result.set(p, true);
				continue;
			}
			switch m.op(p) {
				case Jump:
					result.set(m.target(p), true);
					result.set(m.next(p), true);
				case JumpIf | JumpIfNot | Trap:
					result.set(m.target(p), true);
					result.set(m.next(p), true);
				case JumpTable:
					var n = m.param(p);
					for (k in 0...n + 1)
						result.set(p + 2 + 2 * k, true);
				case Ret | TailCall:
					result.set(m.next(p), true);
				default:
			}
		}
		return result;
	}

	function blocks(pcs:Array<Int>):Array<{value:Int, body:E}> {
		var lead = leaders(pcs);
		var reached = new Map<Int, Bool>();
		for (p in pcs)
			reached.set(p, true);
		var cases = [];
		var i = 0;
		while (i < pcs.length) {
			var start = pcs[i];
			var stmts:Array<E> = [];
			var p = start;
			while (true) {
				if (p >= m.codeSize) {
					// The module body ends with neko's Last, returning the accumulator
					stmts.push(EReturn(v(acc)));
					break;
				}
				var ended = instruction(p, stmts);
				var next = m.next(p);
				if (m.op(p) == JumpTable)
					next = p + 2 + 2 * m.param(p);
				if (ended)
					break;
				if (lead.exists(next) || !reached.exists(next)) {
					stmts.push(set(pc, EInt(next)));
					stmts.push(EContinue);
					break;
				}
				p = next;
			}
			cases.push({value: start, body: EBlock(stmts)});
			// The next block starts at the next leader among the scope's instructions
			i++;
			while (i < pcs.length && !lead.exists(pcs[i]))
				i++;
		}
		return cases;
	}

	inline function slot(index:Int):E
		return v(slots[index]);

	// The values of the n slots below the top, deepest first
	function top(depth:Int, n:Int):Array<E>
		return [for (k in depth - n...depth) slot(k)];

	// Writes one instruction; true when it ends the block
	function instruction(p:Int, out:Array<E>):Bool {
		var op = m.op(p);
		var param = op.hasParam ? m.param(p) : 0;
		var d = scope.depth.get(p);
		var pos = m.positions != null && p < m.positions.length ? m.positions[p] : null;
		// Without debug info the code index stands in for the line
		var file = pos == null ? '$name@' : frameFile(pos.file);
		var line = pos == null ? p : pos.line;
		inline function emit(e:E)
			out.push(EPos(file, line, e));
		inline function toAcc(e:E)
			emit(set(acc, e));
		inline function binary(name:String)
			toAcc(call(name, [slot(d - 1), v(acc)]));

		switch op {
			case AccNull:
				toAcc(ENull);
			case AccTrue:
				toAcc(EBool(true));
			case AccFalse:
				toAcc(EBool(false));
			case AccThis:
				toAcc(v(th));
			case AccInt:
				toAcc(EInt(param));
			case AccStack | AccStack0 | AccStack1:
				toAcc(slot(d - 1 - m.slot(p)));
			case AccGlobal:
				toAcc(EArrayI(globals(), EInt(param)));
			case AccEnv:
				toAcc(EArrayI(v(env), EInt(param)));
			case AccField:
				toAcc(call("field", [v(acc), EInt(param)]));
			case AccArray:
				binary("aget");
			case AccIndex | AccIndex0 | AccIndex1:
				toAcc(call("aget", [v(acc), EInt(m.slot(p))]));
			case AccBuiltin:
				if (param == loaderHash)
					toAcc(ECallStatic(BOOT, "loader", [moduleRef()]));
				else if (param == exportsHash)
					toAcc(ECallStatic(BOOT, "exports", [moduleRef()]));
				else
					toAcc(ECallStatic(BUILTINS, "get", [EInt(param)]));
			case SetStack:
				emit(ESet(slot(d - 1 - param), v(acc)));
			case SetGlobal:
				emit(ESet(EArrayI(globals(), EInt(param)), v(acc)));
			case SetEnv:
				emit(ESet(EArrayI(v(env), EInt(param)), v(acc)));
			case SetField:
				emit(call("setField", [slot(d - 1), EInt(param), v(acc)]));
			case SetArray:
				toAcc(call("aset", [slot(d - 1), slot(d - 2), v(acc)]));
			case SetIndex:
				toAcc(call("aset", [slot(d - 1), EInt(param), v(acc)]));
			case SetThis:
				emit(set(th, v(acc)));
			case Push:
				emit(ESet(slot(d), v(acc)));
			case Pop | Loop:
			case Call:
				toAcc(call('call$param', [v(acc), v(th)].concat(top(d, param))));
			case ObjCall:
				toAcc(call('call$param', [v(acc), slot(d - 1)].concat(top(d - 1, param))));
			case TailCall:
				var n = param & 7;
				// Calling itself, the function loops with the new arguments, as neko
				//  reuses the frame; the arguments sit above the slots they replace
				if (scope.global >= 0 && n == scope.nargs) {
					var rebind = [set(env, call("envOf", [v(acc)]))];
					for (i in 0...n)
						rebind.push(ESet(slot(i), slot(d - n + i)));
					rebind.push(set(pc, EInt(scope.entry)));
					rebind.push(EContinue);
					emit(EIf(call("isSelf", [v(acc), moduleRef(), EInt(scope.global)]), EBlock(rebind)));
				}
				emit(EReturn(call("tailCall", [v(acc), v(th), EArrayDef(top(d, n))])));
				return true;
			case Ret:
				emit(EReturn(v(acc)));
				return true;
			case Jump:
				emit(set(pc, EInt(m.target(p))));
				emit(EContinue);
				return true;
			case JumpIf:
				emit(EIf(call("isTrue", [v(acc)]), EBlock([set(pc, EInt(m.target(p))), EContinue])));
			case JumpIfNot:
				emit(EIf(call("isNotTrue", [v(acc)]), EBlock([set(pc, EInt(m.target(p))), EContinue])));
			case Trap:
				emit(call("trapPush", [v(traps), EInt(m.target(p)), v(th)]));
			case EndTrap:
				emit(call("trapPop", [v(traps)]));
			case MakeEnv:
				toAcc(call("makeEnv", [v(acc), EArrayDef(top(d, param))]));
			case MakeArray:
				var items = top(d, param);
				if (m.version >= 2)
					items.push(v(acc));
				else
					items.unshift(v(acc));
				toAcc(EArrayDef(items));
			case Bool:
				toAcc(call("toBool", [v(acc)]));
			case Not:
				toAcc(call("not", [v(acc)]));
			case IsNull:
				toAcc(call("isNull", [v(acc)]));
			case IsNotNull:
				toAcc(call("isNotNull", [v(acc)]));
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
				binary("eq");
			case Neq:
				binary("neq");
			case Gt:
				binary("gt");
			case Gte:
				binary("gte");
			case Lt:
				binary("lt");
			case Lte:
				binary("lte");
			case TypeOf:
				toAcc(call("typeOf", [v(acc)]));
			case Compare:
				binary("compareOp");
			case PhysCompare:
				binary("physCompare");
			case Hash:
				toAcc(call("hash", [v(acc)]));
			case New:
				toAcc(call("newObject", [v(acc)]));
			case JumpTable:
				emit(set(pc, call("tableTarget", [v(acc), EInt(param), EInt(p)])));
				emit(EContinue);
				return true;
			case Apply:
				toAcc(call("apply", [v(acc), v(th), EArrayDef(top(d, param))]));
			case MakeArray2 | AccInt32 | Last:
				throw 'unexpected ${op.name} at $p';
		}
		return false;
	}
}
