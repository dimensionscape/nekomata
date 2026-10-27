enum E {
	A;
	B(x:Int, s:String);
	C(e:E);
}

class WithToString {
	public function new() {}

	public function toString()
		return "custom toString";
}

class Plain {
	public var a = 1;
	public var b = "two";

	public function new() {}
}

class CaseStdString {
	static function main() {
		var values:Array<Dynamic> = [
			null, 0, -1, 1073741823, 1073741824, 2147483647, -2147483648, 0.0, -0.0, 1.0, 1.5, -1.5, 0.1, 1 / 3, 1e21, 1e-7, 123456789.123,
			Math.NaN, Math.POSITIVE_INFINITY, Math.NEGATIVE_INFINITY, true, false, "", "str", "with\nnewline", [], [1, 2, 3], [[1], [2, [3]]],
			[null, "a", 1.5], {}, {a: 1}, {b: {c: [1, 2]}}, A, B(1, "s"), C(C(A)), new WithToString(), new Plain(), CaseStdString, E,
			Plain, function() {}, Math.max, new haxe.ds.StringMap<Int>(), [1 => "a"], ["k" => 1], haxe.io.Bytes.ofString("bytes"),
			new List<Int>(), Date.fromTime(0).getTime(), String, Int, Float, Bool, Dynamic, haxe.ds.Option.Some(1), [A, B(2, "t")]
		];
		for (v in values)
			Sys.println(Std.string(v));
		var l = new List<Int>();
		l.add(1);
		l.add(2);
		Sys.println(Std.string(l));
		var m = new Map<String, Array<Int>>();
		m.set("x", [1]);
		Sys.println(Std.string(m));
		var im = new Map<Int, String>();
		im.set(3, "three");
		Sys.println(Std.string(im));
		Sys.println("concat " + null + 1 + 1.5 + true + [1] + {x: 1} + A + B(3, "b"));
		Sys.println('interp ${null} ${1 + 1} ${[1, 2]} ${A}');
		Sys.println(Std.string(Std.int(3.99)) + " " + Std.int(-3.99) + " " + Std.parseInt("42") + " " + Std.parseInt("0x10") + " "
			+ Std.parseInt("  7x") + " " + Std.parseInt("x") + " " + Std.parseFloat("2.5e3") + " " + Std.parseFloat("x"));
		trace("trace output", [1, 2]);
		haxe.Log.trace("custom pos", {fileName: "F.hx", lineNumber: 3, className: "C", methodName: "m"});
		Sys.print("print without newline;");
		Sys.println("");
		Sys.stderr().writeString("to stderr\n");
	}
}
