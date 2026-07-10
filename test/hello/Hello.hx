class Hello {
	static function main() {
		var parts = ["hello", "from", "haxe"];
		var total = 0;
		for (p in parts)
			total += p.length;
		try {
			throw "oops";
		} catch (e:String) {
			total += e.length;
		}
		var m = new Map<String, Int>();
		m.set("x", 40);
		Sys.println(parts.join(" ") + ' ${total + m.get("x")} ${1.5 * 2} ${Std.int(7 / 2)}');
	}
}
