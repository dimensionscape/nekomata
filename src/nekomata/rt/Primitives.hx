package nekomata.rt;

import nekomata.rt.Values;

// The primitives neko loads from ndlls with $loader.loadprim("lib@name", nargs)
@:keep
class Primitives {
	static var table:Map<String, NFunction>;

	public static function find(name:String, nargs:Int):Null<NFunction> {
		if (table == null)
			init();
		return table.get(name + "/" + nargs);
	}

	public static function add(name:String, nargs:Int, fn:Dynamic)
		table.set(name + "/" + nargs, new NFunction(fn, nargs, Primitive, null, null, name));

	// A primitive that returns NULL makes neko throw the primitive's name
	public static function fail(name:String):Dynamic
		return Rt.error(name);

	public static function init() {
		if (table != null)
			return;
		table = new Map();
		StdPrims.register();
		nekomata.rt.prims.StdSys.register();
		nekomata.rt.prims.StdThread.register();
		nekomata.rt.prims.StdDate.register();
		nekomata.rt.prims.StdString.register();
		nekomata.rt.prims.Regexp.register();
		nekomata.rt.prims.StdSocket.register();
		nekomata.rt.prims.Zlib.register();
		nekomata.rt.prims.Ssl.register();
		nekomata.rt.prims.StdModule.register();
		nekomata.rt.prims.Sqlite.register();
		nekomata.rt.prims.StdSerialize.register();
	}
}

// libs/std
@:keep
class StdPrims {
	static function number(v:Dynamic, name:String):Float {
		var t = Rt.typeOf(v);
		if (t != Rt.TINT && t != Rt.TFLOAT)
			Primitives.fail(name);
		return Rt.num(v);
	}

	// alloc_best_int((int)f): a C cast, which gives what the processor gives for a float
	//  out of range, as neko's math_floor and the like do on the same system
	static function bestInt(f:Float):Int
		return untyped __cpp__("(int)({0})", f);

	static function math(name:String, f:Float->Float)
		Primitives.add('std@math_$name', 1, (v:Dynamic) -> new NFloat(f(number(v, 'std@math_$name'))));

	// math_ceil and the like keep ints, round floats to ints
	static function rounding(name:String, f:Float->Float, toFloat:Bool) {
		var prim = 'std@math_$name';
		Primitives.add(prim, 1, function(v:Dynamic):Dynamic {
			if (Rt.isInt(v))
				return v;
			if (Rt.typeOf(v) != Rt.TFLOAT)
				return Primitives.fail(prim);
			var r = f(Rt.num(v));
			return toFloat ? new NFloat(r) : bestInt(r);
		});
	}

	public static function register() {
		Primitives.add("std@sys_exit", 1, function(code:Dynamic):Dynamic {
			Sys.exit(code);
			return null;
		});
		Primitives.add("std@print_redirect", 1, (f:Dynamic) -> null);
		Primitives.add("std@set_trace_callback", 1, (f:Dynamic) -> null);

		// math.c
		Primitives.add("std@math_pi", 0, () -> new NFloat(Math.PI));
		math("sqrt", Math.sqrt);
		math("atan", Math.atan);
		math("cos", Math.cos);
		math("sin", Math.sin);
		math("tan", Math.tan);
		math("log", Math.log);
		math("exp", Math.exp);
		math("acos", Math.acos);
		math("asin", Math.asin);
		Primitives.add("std@math_atan2", 2, (a:Dynamic, b:Dynamic) -> new NFloat(Math.atan2(number(a, "std@math_atan2"), number(b, "std@math_atan2"))));
		Primitives.add("std@math_pow", 2, function(a:Dynamic, b:Dynamic):Dynamic {
			var r = Math.pow(number(a, "std@math_pow"), number(b, "std@math_pow"));
			if (Std.int(r) == r && Math.abs(r) < 2147483648.0)
				return Std.int(r);
			return new NFloat(r);
		});
		Primitives.add("std@math_abs", 1, function(v:Dynamic):Dynamic {
			if (Rt.isInt(v))
				return (v : Int) < 0 ? -(v : Int) : v;
			return new NFloat(Math.abs(number(v, "std@math_abs")));
		});
		rounding("ceil", Math.fceil, false);
		rounding("floor", Math.ffloor, false);
		rounding("round", f -> Math.ffloor(f + 0.5), false);
		rounding("fceil", Math.fceil, true);
		rounding("ffloor", Math.ffloor, true);
		rounding("fround", f -> Math.ffloor(f + 0.5), true);
		rounding("int", f -> f < 0 ? Math.fceil(f) : Math.ffloor(f), false);

		// buffer.c
		var bufferKind = new NObject();
		function buffer(b:Dynamic, prim:String):haxe.io.BytesBuffer {
			if (!Rt.isAbstract(b) || (b : NAbstract).kind != bufferKind)
				Primitives.fail(prim);
			return (b : NAbstract).data;
		}
		Primitives.add("std@buffer_new", 0, () -> new NAbstract(bufferKind, new haxe.io.BytesBuffer()));
		Primitives.add("std@buffer_add", 2, function(b:Dynamic, v:Dynamic) {
			Rt.appendValue(buffer(b, "std@buffer_add"), v);
			return true;
		});
		Primitives.add("std@buffer_add_char", 2, function(b:Dynamic, c:Dynamic) {
			var buf = buffer(b, "std@buffer_add_char");
			if (!Rt.isInt(c) || (c : Int) < 0 || (c : Int) > 255)
				Primitives.fail("std@buffer_add_char");
			buf.addByte(c);
			return true;
		});
		Primitives.add("std@buffer_add_sub", 4, function(b:Dynamic, v:Dynamic, p:Dynamic, l:Dynamic) {
			var buf = buffer(b, "std@buffer_add_sub");
			if (!Rt.isNString(v) || !Rt.isInt(p) || !Rt.isInt(l))
				Primitives.fail("std@buffer_add_sub");
			var s = (v : NString).b, pos:Int = p, len:Int = l;
			if (pos < 0 || len < 0 || pos + len > s.length)
				Primitives.fail("std@buffer_add_sub");
			buf.addBytes(s, pos, len);
			return true;
		});
		// BytesBuffer.getBytes ends the buffer, so the string comes from a copy
		Primitives.add("std@buffer_string", 1, function(b:Dynamic) {
			var buf = buffer(b, "std@buffer_string");
			var bytes = buf.getBytes();
			var again = new haxe.io.BytesBuffer();
			again.add(bytes);
			(b : NAbstract).data = again;
			return new NString(bytes.sub(0, bytes.length));
		});
		Primitives.add("std@buffer_reset", 1, function(b:Dynamic) {
			buffer(b, "std@buffer_reset");
			(b : NAbstract).data = new haxe.io.BytesBuffer();
			return null;
		});
		Primitives.add("std@buffer_get_length", 1, (b:Dynamic) -> buffer(b, "std@buffer_get_length").length);

		// random.c
		var kind = new NObject();
		Primitives.add("std@random_new", 0, () -> new NAbstract(kind, null));
		Primitives.add("std@random_set_seed", 2, (r:Dynamic, seed:Dynamic) -> null);
		Primitives.add("std@random_int", 2, function(r:Dynamic, max:Dynamic):Dynamic {
			if (!Rt.isInt(max))
				return Primitives.fail("std@random_int");
			var m:Int = max;
			return m <= 0 ? 0 : Std.random(m);
		});
		Primitives.add("std@random_float", 1, (r:Dynamic) -> new NFloat(Math.random()));
	}
}
