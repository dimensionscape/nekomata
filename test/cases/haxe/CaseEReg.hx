class CaseEReg {
	static function show(r:EReg, s:String) {
		if (!r.match(s)) {
			Sys.println('no match in [$s]');
			return;
		}
		var groups = [];
		var i = 0;
		while (true) {
			var g = try r.matched(i) catch (e:Dynamic) break;
			groups.push(g);
			i++;
		}
		var p = r.matchedPos();
		Sys.println('[$s] groups $groups pos ${p.pos} len ${p.len} left [${r.matchedLeft()}] right [${r.matchedRight()}]');
	}

	static function main() {
		show(~/(\d+)-(\d+)/, "range 10-20 and 30-40");
		show(~/^(\w+)\s+(\w+)$/, "hello world");
		show(~/(a)|(b)/, "b");
		show(~/x*/, "aaa");
		show(~/[A-Z]+/i, "lower UPPER");
		show(~/^b/m, "a\nb\nc");
		show(~/é(.)/, "café au lait, émile");
		show(~/(日本)(語)/, "これは日本語です");
		show(~/😀+/, "smile 😀😀 twice");
		show(~/(.)$/, "naïve");
		show(~/\bfox\b/, "the quick brown fox");
		show(~/(\w+)@(\w+)\.com/, "mail bob@example.com now");
		show(~/nothing/, "here");
		show(~/(?:non)(capturing)/, "noncapturing");
		show(~/(a(b(c)))/, "xabcx");
		show(~/./u, "é");
		show(~/.{2}/u, "日本語");
		show(~/^.{3}$/u, "日本語");
		show(~/^.{3}$/, "日本語");

		var r = ~/(\d+)/g;
		Sys.println(r.replace("a1b22c333", "<$1>") + " " + ~/o/.replace("foo", "0") + " " + ~/o/g.replace("foo", "0") + " " + ~/(o)/g.replace("foo", "$1$1"));
		Sys.println(~/\s*,\s*/g.split("a , b,c ,  d") + " " + ~/x/.split("axbxc") + " " + ~/x/g.split("axbxc") + " " + ~/,/g.split(""));
		Sys.println(~/[aeiou]/g.map("hello world", r -> r.matched(0).toUpperCase()));
		Sys.println(~/é/g.map("éléphant été", r -> "[" + r.matchedPos().pos + "]"));
		Sys.println(~/(\w)(\w)/g.map("abcdef", r -> r.matched(2) + r.matched(1)));
		var all = [];
		var re = ~/\d+/;
		var s = "1 22 333 4444";
		var pos = 0;
		while (re.matchSub(s, pos)) {
			var p = re.matchedPos();
			all.push(re.matched(0) + "@" + p.pos);
			pos = p.pos + p.len;
		}
		Sys.println(all);
		var u = ~/ö/;
		var t = "größe öl";
		Sys.println(u.matchSub(t, 4) + " " + u.matchedPos().pos + " " + u.matchSub(t, 7, 3));
		Sys.println(EReg.escape("a.b*c(d)[e]{f}|g+h?i^j$k\\l"));
		Sys.println(new EReg("^[a-z]+$", "").match("abc") + " " + new EReg("^[a-z]+$", "i").match("ABC") + " " + new EReg("a.c", "s").match("a\nc"));
		try {
			new EReg("(unclosed", "").match("x");
			Sys.println("no error");
		} catch (e:Dynamic) {
			Sys.println("bad pattern: " + Std.string(e));
		}
		var tpl = new haxe.Template("Hello ::name::! ::foreach items::[::__current__::]::end:: ::if (count > 1)::many::else::few::end::");
		Sys.println(tpl.execute({name: "World", items: [1, 2, 3], count: 3}));
		var long = [for (i in 0...2000) "word" + i].join(" ");
		Sys.println(~/word(\d+)/g.replace(long, "$1").length + " " + ~/\s/g.split(long).length);
	}
}
