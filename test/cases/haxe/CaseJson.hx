import haxe.Json;

class Item {
	public var name:String;
	public var tags:Array<String>;

	public function new(n, t) {
		name = n;
		tags = t;
	}
}

class CaseJson {
	static function main() {
		var values:Array<Dynamic> = [
			null, true, false, 0, -1, 1.5, 1e21, 1e-7, 0.1, 2147483647, -2147483648, Math.NaN, Math.POSITIVE_INFINITY, "", "plain",
			"quote \" backslash \\ slash / tab \t newline \n cr \r", "control \x01\x1f", "unicode é 日本 😀", [], [1, [2, [3]]], {},
			{b: 1, a: [true, null], c: {d: "e"}}, new Item("thing", ["x", "y"]), [{x: 1}, {y: 2}]
		];
		for (v in values)
			Sys.println(Json.stringify(v));
		Sys.println(Json.stringify({list: [1, 2], obj: {k: "v"}, s: "x"}, null, "  "));
		Sys.println(Json.stringify([1, {a: 2}], null, "\t"));
		Sys.println(Json.stringify({a: 1, b: "two", c: 3}, (key, value) -> key == "b" ? "replaced" : value));
		var texts = [
			'{"a":1,"b":[true,false,null],"c":{"d":"e\\u00e9\\n"},"e":-1.5e3,"f":""}', '[1,2,3]', '"just a string"', '42', 'null',
			'{"unicode":"\\ud83d\\ude00 \\u65e5","esc":"\\"\\\\\\/\\b\\f\\n\\r\\t"}', ' { "spaced" : [ 1 , 2 ] } ', '[1e2, 1E-2, 0.5, -0, 123456789012]',
			'{"dup":1,"dup":2}'
		];
		for (t in texts) {
			var v:Dynamic = Json.parse(t);
			Sys.println(Std.string(v) + " => " + Json.stringify(v));
		}
		for (bad in ['{', '[1,]', '{"a" 1}', 'tru', '"unterminated', '{"a":1}x', '']) {
			try {
				Json.parse(bad);
				Sys.println('parsed [$bad]');
			} catch (e:Dynamic) {
				Sys.println('[$bad] fails: ' + Std.string(e));
			}
		}
		var round:Dynamic = Json.parse(Json.stringify({n: 1.25, arr: ["a", "b"], nested: {deep: {deeper: [1, 2, 3]}}}));
		Sys.println(round.n + " " + round.arr[1] + " " + round.nested.deep.deeper.length + " " + Reflect.fields(round));
		var big = [for (i in 0...500) {id: i, name: "item" + i, ok: i % 2 == 0}];
		var s = Json.stringify(big);
		var back:Array<Dynamic> = Json.parse(s);
		Sys.println(s.length + " " + back.length + " " + back[499].name + " " + haxe.crypto.Md5.encode(s));
	}
}
