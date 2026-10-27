class Point {
	public var x:Int;
	public var y:Int;

	public static var origin = new Point(0, 0);
	static var hidden = "hidden";

	public function new(x:Int, y:Int) {
		this.x = x;
		this.y = y;
	}

	public function len()
		return Math.sqrt(x * x + y * y);

	public static function make(n:Int)
		return new Point(n, n);

	public function toString()
		return 'Point($x, $y)';
}

class Point3 extends Point {
	public var z:Int = 9;

	public function sum()
		return x + y + z;
}

class CaseReflect {
	static function sorted(a:Array<String>) {
		a.sort(Reflect.compare);
		return a;
	}

	static function main() {
		var o:Dynamic = {name: "obj", count: 3, nested: {a: 1}, list: [1, 2]};
		// Field order is the runtime's own, which neko gives in hash order
		trace(Reflect.fields(o));
		trace(sorted(Reflect.fields(o)));
		trace(Reflect.field(o, "name") + " " + Reflect.field(o, "missing") + " " + Reflect.hasField(o, "count") + " " + Reflect.hasField(o, "nope"));
		Reflect.setField(o, "added", true);
		trace(Reflect.fields(o).length + " " + o.added);
		trace(Reflect.deleteField(o, "count") + " " + Reflect.deleteField(o, "count") + " " + Reflect.hasField(o, "count"));
		var copy = Reflect.copy(o);
		copy.name = "copy";
		trace(o.name + " " + copy.name + " " + Reflect.fields(copy).length);
		trace(Reflect.isObject(o) + " " + Reflect.isObject(1) + " " + Reflect.isObject("s") + " " + Reflect.isObject(Point) + " "
			+ Reflect.isObject(null));
		var f = function(a:Int, b:Int) return a * b;
		trace(Reflect.isFunction(f) + " " + Reflect.isFunction(o) + " " + Reflect.callMethod(null, f, [6, 7]));
		var p = new Point(3, 4);
		trace(Reflect.callMethod(p, Reflect.field(p, "len"), []));
		trace(Reflect.compareMethods(p.len, p.len) + " " + Reflect.compareMethods(p.len, new Point(1, 1).len));
		trace(Reflect.getProperty(p, "x") + " " + Reflect.field(p, "y"));
		Reflect.setProperty(p, "x", 30);
		trace(p);
		var va:Dynamic = Reflect.makeVarArgs(args -> args.length + ":" + args.join("|"));
		trace(va(1, 2, 3) + " " + va());
		trace(Reflect.compare(1, 2) + " " + Reflect.compare("b", "a") + " " + Reflect.compare(1.5, 1.5) + " " + Reflect.compare(null, null));

		trace(Type.getClassName(Point) + " " + Type.getClassName(Point3) + " " + Type.getClassName(Type.getSuperClass(Point3)));
		trace(sorted(Type.getInstanceFields(Point3)));
		trace(sorted(Type.getClassFields(Point)));
		trace(Type.resolveClass("Point") == Point);
		trace(Type.resolveClass("NoSuchClass"));
		trace(Type.resolveClass("haxe.ds.StringMap") != null);
		var e = Type.createEmptyInstance(Point);
		trace(e.x + " " + Std.isOfType(e, Point));
		var made:Point3 = Type.createInstance(Point3, [1, 2]);
		trace(made.sum() + " " + made);
		for (v in ([null, 1, 1.5, true, "s", [1], {a: 1}, p, Point, f, haxe.ds.Option.None, haxe.ds.Option] : Array<Dynamic>))
			trace(Std.string(Type.typeof(v)));
		trace(Std.string(Type.getClass(p)) + " " + Type.getClass("str") + " " + Type.getClass([1]) + " " + Type.getClass(o));
		trace(Type.getClass(p) == Point);
		var dyn:Dynamic = p;
		trace(dyn.len() + " " + dyn.x);
		var anon:Dynamic = {};
		anon.fn = function() return "anon method " + anon.v;
		anon.v = 5;
		trace(anon.fn());
		trace(Reflect.fields(Point.origin));
		trace(Std.isOfType(1, Int) + " " + Std.isOfType(1.5, Int) + " " + Std.isOfType(1, Float) + " " + Std.isOfType("s", String) + " "
			+ Std.isOfType(null, String) + " " + Std.isOfType([], Array) + " " + Std.isOfType(true, Bool) + " " + Std.isOfType(p, Dynamic));
	}
}
