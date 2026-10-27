enum Color {
	Red;
	Green;
	Blue;
	Rgb(r:Int, g:Int, b:Int);
	Named(name:String, ?alpha:Float);
}

enum Tree<T> {
	Leaf;
	Node(left:Tree<T>, value:T, right:Tree<T>);
}

enum Expr {
	Num(v:Float);
	Add(a:Expr, b:Expr);
	Mul(a:Expr, b:Expr);
	Neg(e:Expr);
	Var(name:String);
}

enum abstract Level(Int) to Int {
	var Low = 1;
	var Mid = 5;
	var High = 10;
}

class CaseEnums {
	static function insert<T>(t:Tree<T>, v:T, cmp:T->T->Int):Tree<T> {
		return switch t {
			case Leaf: Node(Leaf, v, Leaf);
			case Node(l, x, r):
				var c = cmp(v, x);
				if (c < 0) Node(insert(l, v, cmp), x, r) else if (c > 0) Node(l, x, insert(r, v, cmp)) else t;
		}
	}

	static function toList<T>(t:Tree<T>, out:Array<T>):Array<T> {
		switch t {
			case Leaf:
			case Node(l, v, r):
				toList(l, out);
				out.push(v);
				toList(r, out);
		}
		return out;
	}

	static function depth<T>(t:Tree<T>):Int
		return switch t {
			case Leaf: 0;
			case Node(l, _, r): 1 + Std.int(Math.max(depth(l), depth(r)));
		}

	static function eval(e:Expr, env:Map<String, Float>):Float
		return switch e {
			case Num(v): v;
			case Add(a, b): eval(a, env) + eval(b, env);
			case Mul(Num(0), _) | Mul(_, Num(0)): 0;
			case Mul(a, b): eval(a, env) * eval(b, env);
			case Neg(Neg(x)): eval(x, env);
			case Neg(x): -eval(x, env);
			case Var(n) if (env.exists(n)): env.get(n);
			case Var(n): throw 'unbound $n';
		}

	static function show(e:Expr):String
		return switch e {
			case Num(v): Std.string(v);
			case Add(a, b): '(${show(a)} + ${show(b)})';
			case Mul(a, b): '${show(a)} * ${show(b)}';
			case Neg(x): '-${show(x)}';
			case Var(n): n;
		}

	static function describe(c:Color):String
		return switch c {
			case Red | Green: "warm or green";
			case Blue: "blue";
			case Rgb(255, 0, 0): "pure red";
			case Rgb(r, g, b) if (r == g && g == b): 'grey $r';
			case Rgb(r, _, _) if (r > 128): 'reddish $r';
			case Rgb(_, _, _): "some rgb";
			case Named(n, null): 'named $n';
			case Named(n, a): 'named $n at $a';
		}

	static function matchInt(v:Int):String
		return switch v {
			case 0: "zero";
			case 1 | 2 | 3: "small";
			case n if (n < 0): "negative";
			case _: "other";
		}

	static function matchArray(a:Array<Int>):String
		return switch a {
			case []: "empty";
			case [a, b]: 'pair $a $b';
			case [_, _, _]: "triple";
			case [1, _, _, rest] if (rest > 3): "starts with 1, long";
			case _: "long";
		}

	static function matchPoint(p:{x:Int, y:Int}):String
		return switch p {
			case {x: 0, y: 0}: "origin";
			case {x: 0, y: y}: 'on y axis at $y';
			case {x: x, y: y}: 'point $x,$y';
		}

	static function matchString(s:String):String
		return switch s {
			case "hello": "greeting";
			case "": "empty";
			case "é": "e acute";
			case x if (x.length > 3): 'long string of ${x.length}';
			case _: "short";
		}

	static function main() {
		var colors = [Red, Green, Blue, Rgb(255, 0, 0), Rgb(9, 9, 9), Rgb(200, 1, 2), Rgb(1, 2, 3), Named("teal"), Named("sky", 0.5)];
		for (c in colors)
			trace(Std.string(c) + " => " + describe(c) + " index " + Type.enumIndex(c) + " ctor " + Type.enumConstructor(c) + " params "
				+ Type.enumParameters(c));
		trace(Type.getEnumConstructs(Color));
		trace(Type.allEnums(Color));
		trace(Type.createEnum(Color, "Rgb", [1, 2, 3]));
		trace(Type.createEnumIndex(Color, 1));
		trace(Type.enumEq(Rgb(1, 2, 3), Rgb(1, 2, 3)) + " " + Type.enumEq(Rgb(1, 2, 3), Rgb(1, 2, 4)) + " " + (Red == Red));
		trace(Type.getEnumName(Type.getEnum(Blue)));
		try {
			Type.createEnum(Color, "Purple");
		} catch (e) {
			trace("createEnum fails: " + e.message);
		}

		var t:Tree<Int> = Leaf;
		for (v in [50, 30, 70, 20, 40, 60, 80, 35, 45, 65])
			t = insert(t, v, (a, b) -> a - b);
		trace(toList(t, []) + " depth " + depth(t));
		var words:Tree<String> = Leaf;
		for (w in "the quick brown fox jumps over the lazy dog".split(" "))
			words = insert(words, w, Reflect.compare);
		trace(toList(words, []));
		trace(Std.string(insert(insert(Leaf, 2, (a, b) -> a - b), 1, (a, b) -> a - b)));

		var e = Add(Mul(Num(2), Var("x")), Neg(Neg(Add(Num(1), Mul(Var("y"), Num(0))))));
		var env = ["x" => 10.0, "y" => 3.0];
		trace(show(e) + " = " + eval(e, env));
		try {
			eval(Var("z"), env);
		} catch (msg:String) {
			trace("caught " + msg);
		}
		trace([for (i in [0, 2, -4, 99]) matchInt(i)]);
		trace([for (a in [[], [1, 2], [1, 2, 3], [1, 2, 3, 4], [2, 2, 3, 4]]) matchArray(a)]);
		trace([for (p in [{x: 0, y: 0}, {x: 0, y: 5}, {x: 1, y: 2}]) matchPoint(p)]);
		trace([for (s in ["hello", "", "é", "abcd", "ab"]) matchString(s)]);

		var levels = [Low, Mid, High];
		var sum = 0;
		for (l in levels)
			sum += l;
		trace("levels " + levels + " sum " + sum);
		var opt:haxe.ds.Option<Int> = Some(4);
		trace(switch opt {
			case Some(v) if (v > 3): "big some " + v;
			case Some(v): "some " + v;
			case None: "none";
		});
		var ev:EnumValue = Rgb(4, 5, 6);
		trace(ev.getIndex() + " " + ev.getParameters() + " " + ev.getName());
		trace(Rgb(4, 5, 6).match(Rgb(4, _, _)) + " " + Red.match(Blue));
	}
}
