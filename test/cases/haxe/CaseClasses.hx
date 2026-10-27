interface IShape {
	function area():Float;
	function name():String;
}

interface INamed {
	var label(get, never):String;
}

class Shape implements IShape {
	public static var created = 0;

	public var id:Int;

	public function new() {
		id = ++created;
	}

	public function area():Float
		return 0;

	public function name():String
		return "shape";

	public function describe():String
		return '${name()} #$id area ${area()}';

	public function toString():String
		return 'Shape(${name()})';
}

class Rect extends Shape implements INamed {
	public var w:Float;
	public var h:Float;
	public var label(get, never):String;

	public function new(w:Float, h:Float) {
		super();
		this.w = w;
		this.h = h;
	}

	function get_label()
		return 'rect ${w}x$h';

	override public function area():Float
		return w * h;

	override public function name():String
		return "rect";
}

class Square extends Rect {
	public function new(s:Float) {
		super(s, s);
	}

	override public function name():String
		return "square:" + super.name();

	override public function describe():String
		return "[" + super.describe() + "]";
}

class Circle extends Shape {
	public var r:Float;

	public function new(r:Float) {
		super();
		this.r = r;
	}

	override public function area():Float
		return Math.round(Math.PI * r * r * 1000) / 1000;

	override public function name():String
		return "circle";
}

class Counter {
	public var count(default, null):Int = 0;
	public var doubled(get, set):Int;
	public var log:Array<String> = [];

	public function new() {}

	function get_doubled() {
		log.push("get");
		return count * 2;
	}

	function set_doubled(v:Int) {
		log.push("set " + v);
		count = Std.int(v / 2);
		return v;
	}

	public function inc()
		count++;
}

class Base {
	public function new() {
		trace("Base constructor sees " + kind());
	}

	public function kind()
		return "base";

	public dynamic function hook()
		return "default hook";
}

class Derived extends Base {
	var extra = "initialized";

	public function new() {
		super();
		trace("Derived constructor, extra " + extra);
	}

	override public function kind()
		return "derived, extra " + extra;
}

abstract class Animal {
	public function new() {}

	public abstract function sound():String;

	public function speak()
		return Type.getClassName(Type.getClass(this)) + " says " + sound();
}

class Dog extends Animal {
	public function sound()
		return "woof";
}

class Generic<T> {
	public var items:Array<T> = [];

	public function new() {}

	public function add(x:T):Generic<T> {
		items.push(x);
		return this;
	}

	public function map<U>(f:T->U):Generic<U> {
		var g = new Generic<U>();
		for (i in items)
			g.add(f(i));
		return g;
	}
}

class CaseClasses {
	static var staticInit = computeStatic();

	static function computeStatic() {
		return "static initialized";
	}

	static function main() {
		trace(staticInit);
		var shapes:Array<Shape> = [new Rect(2, 3), new Square(4), new Circle(1.5), new Shape()];
		for (s in shapes)
			trace(s.describe() + " / " + s + " / " + Std.string(s));
		trace("created " + Shape.created);
		var named:INamed = new Rect(1, 2);
		trace(named.label);
		for (s in shapes) {
			var tags = [];
			if (Std.isOfType(s, Rect))
				tags.push("Rect");
			if (Std.isOfType(s, Square))
				tags.push("Square");
			if (Std.isOfType(s, IShape))
				tags.push("IShape");
			if (Std.isOfType(s, INamed))
				tags.push("INamed");
			if (Std.isOfType(s, Circle))
				tags.push("Circle");
			trace(s.name() + ": " + tags.join(","));
		}
		var r:Shape = new Square(2);
		var sq = Std.downcast(r, Square);
		var ci = Std.downcast(r, Circle);
		trace("downcast " + (sq != null) + " " + (ci == null));
		trace(Type.getClassName(Type.getClass(r)) + " super " + Type.getClassName(Type.getSuperClass(Type.getClass(r))));

		var c = new Counter();
		c.inc();
		c.inc();
		trace(c.count + " " + c.doubled);
		c.doubled = 10;
		trace(c.count + " " + c.log.join(","));

		var d = new Derived();
		trace(d.kind() + " / " + d.hook());
		d.hook = () -> "replaced hook";
		trace(d.hook());
		trace(new Dog().speak());

		var g = new Generic<Int>().add(1).add(2).add(3);
		trace(g.map(x -> "n" + x).items);
		var fn = new Rect(5, 5).area;
		trace("bound method " + fn());
		var cls:Class<Dynamic> = Square;
		var made = Type.createInstance(cls, [3.0]);
		trace("createInstance " + made.describe());
	}
}
