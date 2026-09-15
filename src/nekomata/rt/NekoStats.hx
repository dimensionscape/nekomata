package nekomata.rt;

import nekomata.rt.Values;

// neko -stats (vm/stats.c): time spent reading and running each module and in each
//  primitive loaded while it is on, printed when the program ends
private class Measure {
	public var kind:String;
	public var calls = 0;
	public var errors = 0;
	public var total = 0;
	public var sub = 0;
	public var start = 0;
	public var running = false;
	public var below:Null<Measure>;

	public function new(kind:String)
		this.kind = kind;
}

@:keep
class NekoStats {
	public static var enabled = false;

	static var list:Array<Measure> = [];
	static var stack:Null<Measure>;
	static var base = Sys.time();

	static function now():Int
		return Std.int((Sys.time() - base) * 1000000);

	public static function measure(kind:String, start:Bool):Void {
		if (!enabled)
			return;
		if (start) {
			var s = null;
			for (m in list)
				if (m.kind == kind && !m.running) {
					s = m;
					break;
				}
			if (s == null) {
				s = new Measure(kind);
				list.unshift(s);
			}
			s.calls++;
			s.below = stack;
			stack = s;
			s.running = true;
			s.start = now();
			return;
		}
		// Measures above this one stopped by an exception count as errors
		var s = stack;
		while (s != null && s.kind != kind) {
			s.errors++;
			s.running = false;
			s = s.below;
		}
		if (s == null) {
			stack = null;
			return;
		}
		var delta = now() - s.start;
		s.total += delta;
		stack = s.below;
		if (stack != null)
			stack.sub += delta;
		s.running = false;
	}

	// A primitive that measures each call under its name
	public static function wrap(f:NFunction):NFunction {
		var name = f.name;
		function timed(args:Array<Dynamic>):Dynamic {
			measure(name, true);
			var r = f.nargs == NFunction.VAR_ARGS ? f.fn(args) : Reflect.callMethod(null, f.fn, args);
			measure(name, false);
			return r;
		}
		return new NFunction(f.nargs == NFunction.VAR_ARGS ? timed : Reflect.makeVarArgs(timed), f.nargs, Primitive, null, null, name);
	}

	// The table neko prints, longest total first
	public static function report():String {
		var merged:Array<Measure> = [];
		for (m in list) {
			var same = Lambda.find(merged, x -> x.kind == m.kind);
			if (same == null)
				merged.push(m);
			else {
				same.errors += m.errors;
				same.calls += m.calls;
				same.total += m.total;
				same.sub += m.sub;
			}
		}
		merged.sort((a, b) -> a.total != b.total ? b.total - a.total : a.calls - b.calls);
		var b = new StringBuf();
		b.add("TOT\tTIME\tCOUNT\tNAME\n");
		for (m in merged) {
			b.add('${m.total}\t${m.total - m.sub}\t${m.calls}\t${m.kind}');
			b.add(m.errors > 0 ? ' ERRORS=${m.errors}\n' : "\n");
		}
		return b.toString();
	}
}
