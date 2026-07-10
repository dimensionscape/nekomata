package nekomata.neko;

import nekomata.neko.Module;

class StackError extends haxe.Exception {}

// One code entry point (the module body or a function) and the stack depth
//  at each instruction it reaches
class Scope {
	public var entry:Int;
	// -1 for the module body
	public var global:Int;
	public var nargs:Int;
	// Code index to stack depth, for every instruction the scope reaches
	public var depth:Map<Int, Int> = new Map();
	public var maxDepth:Int = 0;

	public function new(entry, global, nargs) {
		this.entry = entry;
		this.global = global;
		this.nargs = nargs;
	}

	// The scope's instructions in code order
	public function pcs():Array<Int> {
		var result = [for (pc in depth.keys()) pc];
		result.sort((a, b) -> a - b);
		return result;
	}
}

// Repeats neko's neko_check_stack: every instruction has one stack depth, whatever
//  path reaches it, which lets each stack slot become a local variable
class StackCheck {
	// Neko's MAX_STACK_PER_FUNCTION, less the 4 slots a sub call needs
	static inline var MAX_STACK = 128 - 4;

	var m:Module;
	var scope:Scope;
	// Depth at each code index across all scopes, as neko shares one table
	var shared:Array<Int>;

	public static function run(m:Module):Array<Scope> {
		var check = new StackCheck(m);
		var scopes = [check.walk(new Scope(0, -1, 0))];
		var prev = 0;
		for (g in m.functions())
			switch m.globals[g] {
				case GFunction(addr, nargs):
					if (!m.isOp[addr] || addr < prev)
						throw new StackError('function global $g starts at $addr, out of code order');
					scopes.push(check.walk(new Scope(addr, g, nargs)));
					prev = addr;
				default:
			}
		return scopes;
	}

	function new(m:Module) {
		this.m = m;
		shared = [for (_ in 0...m.codeSize + 1) -1];
	}

	function walk(s:Scope):Scope {
		scope = s;
		var base = s.nargs < 0 ? 0 : s.nargs;
		if (!visit(s.entry, base, base))
			throw new StackError(s.global < 0 ? 'stack check failed for the module body' : 'stack check failed for function global ${s.global}');
		return s;
	}

	function mark(pc:Int, stack:Int):Int {
		scope.depth.set(pc, stack);
		if (stack > scope.maxDepth)
			scope.maxDepth = stack;
		var had = shared[pc];
		if (had == -1)
			shared[pc] = stack;
		return had;
	}

	function visit(pc:Int, stack:Int, istack:Int):Bool {
		while (true) {
			var atEnd = pc >= m.codeSize;
			var op:Opcode = atEnd ? Opcode.Last : m.op(pc);
			var had = scope.depth.exists(pc) ? scope.depth.get(pc) : -1;
			if (had != -1)
				return had == stack;
			var other = mark(pc, stack);
			if (other != -1 && other != stack)
				return false;
			if (atEnd)
				return stack == 0;

			var p = op.hasParam ? m.param(pc) : 0;
			var s = op.stackEffect;
			if (s == Opcode.P)
				stack += p;
			else if (s == -Opcode.P)
				stack -= p;
			else
				stack += s;
			if (stack < istack || stack >= MAX_STACK)
				return false;

			switch op {
				case Jump | JumpIf | JumpIfNot | Trap:
					var to = m.target(pc);
					// A trap's handler runs with the stack as it was before the trap
					var at = op == Trap ? stack - s : stack;
					if (!visit(to, at, istack))
						return false;
					if (op == Jump)
						return true;
				case JumpTable:
					for (k in 1...p + 1) {
						var entry = pc + 2 * k;
						if (m.op(entry) != Jump)
							return false;
						if (!visit(entry, stack, istack))
							return false;
					}
					// The default case runs on past the table
					pc += 2 * p;
				case AccStack | SetStack:
					if (m.slot(pc) >= stack)
						return false;
				case AccStack0:
					if (0 >= stack)
						return false;
				case AccStack1:
					if (1 >= stack)
						return false;
				case Ret:
					return p == stack;
				case ObjCall:
					stack--;
					if (stack < istack)
						return false;
				case TailCall:
					return stack - (p & 7) >= istack && (p >> 3) == stack;
				default:
			}
			pc = m.next(pc);
		}
	}
}
