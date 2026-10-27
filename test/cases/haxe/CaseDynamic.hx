typedef Named = {
	var name:String;
	@:optional var nick:String;
}

abstract Meters(Float) from Float to Float {
	public inline function new(v:Float)
		this = v;

	@:op(A + B) static function add(a:Meters, b:Meters):Meters
		return new Meters((a : Float) + (b : Float));

	public function toString()
		return this + "m";
}

class Box<T> {
	public var value:T;

	public function new(v:T)
		value = v;
}

class CaseDynamic {
	static function optional(a:Int, ?b:Int, c = "default")
		return '$a $b $c';

	static function rest(first:String, ...others:Int)
		return first + ":" + others.toArray().join(",");

	static function main() {
		var d:Dynamic = {a: 1};
		d.b = "added";
		d.c = function(x) return x + d.a;
		Sys.println(d.a + " " + d.b + " " + d.c(10) + " " + d.missing);
		var arr:Dynamic = [1, "two", 3.5, null, [4]];
		Sys.println(arr[1] + " " + arr.length + " " + arr[4][0]);
		var n:Named = {name: "x"};
		Sys.println(n.name + " " + n.nick);
		var m = new Meters(1.5) + new Meters(2);
		Sys.println(m + " " + Std.string(m));
		var b = new Box<Array<Int>>([1, 2]);
		b.value.push(3);
		Sys.println(b.value);
		Sys.println(optional(1) + "|" + optional(1, 2) + "|" + optional(1, null, "given"));
		Sys.println(rest("r") + " " + rest("r", 1, 2, 3));
		var adders = [for (i in 0...3) (x:Int) -> x + i];
		Sys.println([for (f in adders) f(10)]);
		var counter = 0;
		var inc = () -> ++counter;
		inc();
		inc();
		Sys.println(counter + " " + inc());
		function fib(n:Int):Int
			return n < 2 ? n : fib(n - 1) + fib(n - 2);
		Sys.println(fib(20));
		var s:Dynamic = "str";
		var i:Dynamic = 5;
		var f:Dynamic = 2.5;
		Sys.println(s + i + " " + (i + f) + " " + (i * f) + " " + (i / 2) + " " + (s + null) + " " + (i == 5.0) + " " + (s == "str"));
		var any:Any = 42;
		Sys.println(Std.string(any) + " " + Std.isOfType(any, Int));
		var obj = {z: 1, y: 2, x: 3};
		var names = [for (f in Reflect.fields(obj)) f];
		names.sort(Reflect.compare);
		Sys.println(names);
		var nested:Dynamic = {list: [{v: 1}, {v: 2}]};
		var total = 0;
		for (e in (nested.list : Array<Dynamic>))
			total += e.v;
		Sys.println(total);
		var it = new IntIterator(3, 7);
		Sys.println([for (x in it) x]);
		var kv = [for (k => v in ["a" => 1]) k + v];
		Sys.println(kv);
		var bound = "hello".charAt;
		Sys.println(bound(1));
		var cast1:Int = cast 3.9;
		var cast2 = Std.int(3.9);
		Sys.println(cast1 + " " + cast2);
		inline function sq(x:Int)
			return x * x;
		Sys.println(sq(12));
		var u:Null<Int> = null;
		Sys.println((u == null) + " " + (u != 0));
		var en:haxe.ds.Either<Int, String> = Right("r");
		Sys.println(en);
	}
}
