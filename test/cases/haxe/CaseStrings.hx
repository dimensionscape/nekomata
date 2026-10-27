using StringTools;

class CaseStrings {
	static function codes(s:String):String
		return [for (i in 0...s.length) s.charCodeAt(i)].join(",");

	static function main() {
		var texts = ["hello world", "", "a", "héllo wörld", "日本語のテキスト", "emoji 😀 and 🎉", "mixed é日😀x", "\x00nul\x00", "tab\tand\nnewline"];
		for (t in texts) {
			Sys.println('[$t] length ${t.length} upper [${t.toUpperCase()}] lower [${t.toLowerCase()}]');
			Sys.println('  codes ${codes(t)}');
			Sys.println('  charAt(1) [${t.charAt(1)}] charCodeAt(1) ${t.charCodeAt(1)} charCodeAt(99) ${t.charCodeAt(99)} charAt(99) [${t.charAt(99)}]');
			Sys.println('  indexOf o ${t.indexOf("o")} lastIndexOf o ${t.lastIndexOf("o")} indexOf ö ${t.indexOf("ö")} indexOf 😀 ${t.indexOf("😀")}');
			Sys.println('  substr(2, 3) [${t.substr(2, 3)}] substr(-3) [${t.substr(-3)}] substring(1, 4) [${t.substring(1, 4)}] substring(4, 1) [${t.substring(4, 1)}]');
			Sys.println('  split " " ${t.split(" ")} split "" ${t.split("").length}');
			var uni = [];
			for (c in new haxe.iterators.StringIteratorUnicode(t))
				uni.push(c);
			Sys.println('  unicode code points ${uni}');
			Sys.println('  urlEncode ${t.urlEncode()} htmlEscape ${t.htmlEscape(true)}');
		}
		Sys.println(String.fromCharCode(65) + String.fromCharCode(0xE9) + String.fromCharCode(0x65E5) + String.fromCharCode(0x1F600));
		Sys.println(codes(String.fromCharCode(0xE9)) + " " + codes(String.fromCharCode(0x1F600)));
		Sys.println("  padded ".trim() + "|" + "  left".ltrim() + "|" + "right  ".rtrim() + "|" + "x".lpad("-", 5) + "|" + "x".rpad("-", 5) + "|"
			+ "abc".lpad("12", 6));
		Sys.println("a.b.c".replace(".", "::") + " " + "aaa".replace("a", "bb") + " " + "abc".replace("", "-") + " " + "héé".replace("é", "e"));
		Sys.println("hello".startsWith("he") + " " + "hello".endsWith("lo") + " " + "hello".startsWith("") + " " + "hé".endsWith("é") + " "
			+ "hello".contains("ll"));
		Sys.println(StringTools.hex(255) + " " + StringTools.hex(255, 4) + " " + StringTools.hex(-1) + " " + StringTools.hex(0x7FFFFFFF));
		Sys.println(StringTools.isSpace(" \t", 1) + " " + StringTools.isSpace("x", 0) + " " + StringTools.fastCodeAt("abc", 1) + " "
			+ StringTools.isEof(StringTools.fastCodeAt("abc", 5)));
		Sys.println("%41%20b%C3%A9".urlDecode() + " " + "&lt;tag&gt; &amp; &quot;q&quot; &#039;".htmlUnescape() + " " + "<a href=\"x\">".htmlEscape());
		Sys.println("one,two,,three,".split(",") + " " + "abc".split("abc") + " " + "".split(",") + " " + "a--b--c".split("--"));
		Sys.println("Hello".charCodeAt(0) + " " + "z" < "a" + " " + ("abc" < "abd") + " " + ("é" > "z") + " " + ("B" < "a"));
		Sys.println(["b", "é", "a", "Z", "日", "aa", ""].join("|"));
		var sorted = ["b", "é", "a", "Z", "日", "aa", ""];
		sorted.sort(Reflect.compare);
		Sys.println(sorted.join("|"));
		Sys.println(StringTools.quoteUnixArg("it's") + " " + StringTools.quoteWinArg("a b\"c", true));
		Sys.println(haxe.Utf8.length("héllo") + " " + haxe.Utf8.sub("héllo", 1, 2) + " " + haxe.Utf8.charCodeAt("héllo", 1));
		var buf = new StringBuf();
		haxe.Utf8.iter("aé日", c -> buf.add(c + ";"));
		Sys.println(buf.toString() + " " + haxe.Utf8.encode("é") + " " + haxe.Utf8.decode(haxe.Utf8.encode("é")).length + " "
			+ haxe.Utf8.validate("ok é") + " " + haxe.Utf8.validate(haxe.io.Bytes.ofHex("ff41").toString()));
		var big = "";
		for (i in 0...1000)
			big += String.fromCharCode(97 + i % 26);
		Sys.println(big.length + " " + big.substr(990) + " " + big.indexOf("xyz", 500) + " " + big.lastIndexOf("abc", 100));
	}
}
