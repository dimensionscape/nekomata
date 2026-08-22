// Loads test/ndll's CFFI library (ndlltest.ndll, in the current directory) from a Haxe
//  program built for neko, and prints what each primitive gives, for test/ndll/run.sh to
//  compare between neko and Nekomata. Left out are the cases where hxcpp's API has to
//  differ from neko's glue: floats with small integral values, which hxcpp boxes as
//  ints, ints and bools read as each other, and lengths of strings that are not ASCII
class Point {
	public var x:Int;
	public var y:Int;

	public function new(x, y) {
		this.x = x;
		this.y = y;
	}

	public function scale(k:Int):Int {
		x *= k;
		y *= k;
		return x + y;
	}
}

class NdllTest {
	static function load(name:String, nargs:Int):Dynamic {
		var f:Dynamic = neko.Lib.load("ndlltest", name, nargs);
		return f;
	}

	static function show(label:String, f:Void->Dynamic) {
		var text = try Std.string(f()) catch (e:Dynamic) "throws " + Std.string(e);
		Sys.println(label + ": " + text);
	}

	static function main() {
		Sys.println("neko_init: " + cpp.Prime.nekoInit("ndlltest"));

		var type:Dynamic = load("nt_type", 1);
		var counter:Dynamic = load("nt_counter", 1);
		var values:Array<Dynamic> = [null, true, 3, 2.5, "text", [1, 2], {x: 1}, function(a) return a, counter(1)];
		Sys.println("types: " + [for (v in values) type(v)].join(","));

		var add:Dynamic = load("nt_add", 2);
		show("add ints", () -> add(2, 3));
		show("add floats", () -> add(2.5, 1));
		show("not", () -> [load("nt_bool", 1)(false), load("nt_bool", 1)(true)]);
		show("concat", () -> load("nt_concat", 2)("abc", "défi"));
		show("concat is a String", () -> Std.isOfType(load("nt_concat", 2)("a", "b"), String));
		show("strlen", () -> load("nt_strlen", 1)("hello"));
		show("string_len", () -> load("nt_string_len", 2)("hello world", 5));

		// Objects the ndll makes, and neko objects it reads and writes
		var o:Dynamic = load("nt_object", 0)();
		show("object", () -> o);
		show("object fields", () -> [o.count, o.ratio, o.name, o.ok, o.inner.depth, o.list]);
		show("object kinds", () -> ([Std.isOfType(o.name, String), Std.isOfType(o.list, Array), Reflect.fields(o).length] : Array<Dynamic>));
		var mine:Dynamic = {a: 1, b: "bee", c: {d: 4}};
		var get:Dynamic = load("nt_get_field", 2), set:Dynamic = load("nt_set_field", 3);
		show("get", () -> [get(mine, "a"), get(mine, "b"), get(mine, "c").d, get(mine, "c") == mine.c, get(mine, "zz")]);
		set(mine, "e", 5);
		set(mine, "b", "new");
		set(mine, "f", [7, 8]);
		show("set", () -> [mine.e, mine.b, Std.isOfType(mine.b, String), mine.f.length]);
		show("numeric field", () -> load("nt_field_number", 2)(mine, "a"));
		show("fields", () -> load("nt_fields", 1)({one: 1, two: "2", three: {}}));
		var p = new Point(3, 4);
		show("instance field", () -> get(p, "x"));
		show("method", () -> [load("nt_ocall", 3)(p, "scale", 2), p.x, p.y]);

		// Arrays, read and written in place
		show("array sum", () -> load("nt_array_sum", 1)([1, 2.5, 3]));
		var arr = [1, 2, 3];
		load("nt_array_double", 1)(arr);
		show("array doubled", () -> arr);
		var made:Dynamic = load("nt_array_make", 1)(4);
		show("array made", () -> [made, Std.isOfType(made, Array), made.length]);

		// Functions: called back now, kept and called later, varargs
		var call:Dynamic = load("nt_call", 2), call2:Dynamic = load("nt_call2", 3);
		show("call", () -> call(function(x) return x * 10, 4));
		show("call2", () -> call2(function(a, b) return a + "/" + b, "left", 7));
		show("callback string", () -> call(function(s) return Std.isOfType(s, String) + ":" + s, "hi"));
		show("callback object", () -> call(function(v) return v.d, mine.c));
		show("nargs", () -> [load("nt_nargs", 1)(function(a, b) return 0), load("nt_nargs", 1)(Reflect.makeVarArgs(a -> a))]);
		var total = 0;
		load("nt_keep", 1)(function(n) {
			total += n;
			return total;
		});
		neko.vm.Gc.run(true);
		var fire:Dynamic = load("nt_fire", 1);
		show("kept callback", () -> [fire(5), fire(6), total]);
		var sum:Dynamic = load("nt_sum", -1);
		show("varargs", () -> [sum(), sum(1, 2, 3), sum(1, 2, 3, 4, 5, 6, 7)]);

		// Exceptions, raised in the ndll and through it
		var throwIt:Dynamic = load("nt_throw", 1);
		show("throw string", () -> try throwIt("boom") catch (e:String) "caught String " + e);
		show("throw object", () -> try throwIt(mine.c) catch (e:Dynamic) e == mine.c);
		show("throw made string", () -> try load("nt_throw_string", 1)("bad") catch (e:String) "caught String " + e);
		show("throw in callback", () -> try call(function(x) throw "from neko " + x, 1) catch (e:String) "caught " + e);

		// Abstracts
		var c = counter(10);
		var next:Dynamic = load("nt_counter_next", 1);
		show("abstract", () -> [next(c), next(c), next({}), next(null), Type.typeof(c)]);

		// Haxe Bytes, read and written in place, and values as a buffer prints them
		var b = haxe.io.Bytes.ofString("abc");
		show("bytes sum", () -> load("nt_bytes_sum", 1)(b));
		load("nt_bytes_fill", 2)(b, 65);
		show("bytes filled", () -> b.toString());
		var buf:Dynamic = load("nt_buffer", 3);
		show("buffer", () -> [buf(42, "str", [1, 2]), buf(null, true, 2.5), buf(mine.c, p, -7)]);

		// What the loader does with what it cannot find
		show("missing primitive", () -> neko.Lib.load("ndlltest", "nt_missing", 1));
		show("wrong count", () -> neko.Lib.load("ndlltest", "nt_add", 3));
		show("missing library", () -> neko.Lib.load("nosuchndll", "x", 0));
		var add1:Dynamic = add;
		show("bad call", () -> add1(1));
	}
}
