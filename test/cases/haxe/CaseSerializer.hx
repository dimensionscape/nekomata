import haxe.Serializer;
import haxe.Unserializer;

enum Shape {
	Circle(r:Float);
	Rect(w:Int, h:Int);
	Empty;
}

class Person {
	public var name:String;
	public var age:Int;
	public var friends:Array<Person>;

	public function new(n, a) {
		name = n;
		age = a;
		friends = [];
	}
}

class Custom {
	public var data:String;

	public function new(d)
		data = d;

	@:keep function hxSerialize(s:Serializer) {
		s.serialize(data.toUpperCase());
	}

	@:keep function hxUnserialize(u:Unserializer) {
		data = "back:" + u.unserialize();
	}
}

class CaseSerializer {
	static function main() {
		var values:Array<Dynamic> = [
			null, true, false, 0, -7, 123456789, 1.5, -0.25, 1e100, Math.NaN, Math.POSITIVE_INFINITY, Math.NEGATIVE_INFINITY, "", "hello",
			"spaces and : colons", "unicode é 日本 😀", [1, 2, 3], [null, null, 1], {a: 1, b: "two"}, Circle(2.5), Rect(3, 4), Empty,
			[Empty, Circle(1)], ["k" => 1, "j" => 2], [1 => "a", 2 => "b"], haxe.io.Bytes.ofString("bytes\x00here"), Date.fromTime(1234567890000.0),
			new Custom("custom"), new List<Int>(), Person, Shape
		];
		for (v in values) {
			var s = Serializer.run(v);
			var back:Dynamic = try Unserializer.run(s) catch (e:Dynamic) "unserialize fails: " + e;
			Sys.println(s + "  =>  " + Std.string(back));
		}
		var p = new Person("ann", 30);
		var q = new Person("bob", 40);
		p.friends.push(q);
		q.friends.push(p);
		var s = new Serializer();
		s.useCache = true;
		s.serialize(p);
		s.serialize("hello");
		s.serialize("hello");
		var text = s.toString();
		Sys.println(text);
		var u = new Unserializer(text);
		var p2:Person = u.unserialize();
		Sys.println(p2.name + " " + p2.friends[0].name + " " + (p2.friends[0].friends[0] == p2) + " " + u.unserialize() + u.unserialize());
		var s2 = new Serializer();
		s2.useEnumIndex = true;
		s2.serialize([Circle(1), Rect(1, 2), Empty]);
		Sys.println(s2.toString() + " => " + Unserializer.run(s2.toString()));
		var s3 = new Serializer();
		s3.serialize("repeat");
		s3.serialize("repeat");
		Sys.println("no cache " + s3);
		for (bad in ["", "x", "i", "y5:abc", "oy1:a", "wy5:Shape"]) {
			try {
				Sys.println('[$bad] => ' + Std.string(Unserializer.run(bad)));
			} catch (e:Dynamic) {
				Sys.println('[$bad] fails: ' + Std.string(e));
			}
		}
		var big = [for (i in 0...300) {i: i, s: "v" + i, f: i / 4}];
		var bs = Serializer.run(big);
		var bb:Array<Dynamic> = Unserializer.run(bs);
		Sys.println(bs.length + " " + bb.length + " " + bb[299].s + " " + bb[3].f);
	}
}
