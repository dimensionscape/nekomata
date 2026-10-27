// variant: -D neko-v1
// The order Haxe's neko output evaluates arguments, array literals, object literals,
//  operands and assignments. Haxe writes version 2 modules, whose arrays are built with
//  MakeArray2; with neko-v1 they are version 1, built with MakeArray
class CaseEvalOrder {
	static var log:Array<String> = [];

	static function t<T>(name:String, v:T):T {
		log.push(name);
		return v;
	}

	static function take(a:Int, b:Int, c:Int)
		return a + b + c;

	static function six(a:Int, b:Int, c:Int, d:Int, e:Int, f:Int)
		return [a, b, c, d, e, f];

	static function report(what:String, v:Dynamic) {
		Sys.println(what + " " + Std.string(v) + " " + log.join(""));
		log = [];
	}

	static function main() {
		report("call", take(t("a", 1), t("b", 2), t("c", 3)));
		report("six", six(t("1", 1), t("2", 2), t("3", 3), t("4", 4), t("5", 5), t("6", 6)));
		report("array", [t("a", 1), t("b", 2), t("c", 3), t("d", 4)]);
		report("long array", [for (i in 0...3) t("x" + i, i)].concat([t("p", 9), t("q", 8)]));
		report("object", {x: t("x", 1), y: t("y", 2), z: t("z", 3)});
		report("binop", t("l", 10) - t("r", 3));
		report("string concat", t("a", "A") + t("b", "B") + t("c", "C"));
		var arr = [0, 0, 0];
		t("arr", arr)[t("i", 1)] = t("v", 5);
		report("index set", arr);
		var o = {f: 0};
		t("o", o).f = t("v", 7);
		report("field set", o);
		var obj = new Target();
		report("method", t("target", obj).m(t("x", 2), t("y", 3)));
		report("and", t("a", false) && t("b", true));
		report("or", t("a", true) || t("b", true));
		report("ternary", t("c", true) ? t("yes", 1) : t("no", 2));
		var n = 1;
		n += t("rhs", 2);
		report("compound", n);
		var a2 = [1, 2];
		a2[t("i", 0)] += t("v", 10);
		report("compound index", a2);
		report("nested calls", take(take(t("a", 1), t("b", 2), t("c", 3)), t("d", 4), take(t("e", 5), t("f", 6), t("g", 7))));
		report("map literal", [t("k1", "a") => t("v1", 1), t("k2", "b") => t("v2", 2)].get("b"));
		report("new", new Target2(t("a", 1), t("b", 2)).sum);
		var i = 0;
		var arr3 = [i++, i++, i++];
		report("increments", arr3);
		var f = (x:Int) -> x * 2;
		report("closure arg", f(t("x", 21)));
		report("string interpolation", '${t("a", 1)}-${t("b", 2)}');
	}
}

class Target {
	public function new() {}

	public function m(x:Int, y:Int)
		return x * y;
}

class Target2 {
	public var sum:Int;

	public function new(a:Int, b:Int)
		sum = a + b;
}
