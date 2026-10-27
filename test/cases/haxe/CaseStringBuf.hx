class CaseStringBuf {
	static function main() {
		var b = new StringBuf();
		Sys.println("empty [" + b.toString() + "] " + b.length);
		b.add("text");
		b.add(1);
		b.add(2.5);
		b.add(null);
		b.add(true);
		b.add([1, 2]);
		b.add({a: 1});
		b.addChar(65);
		b.addChar(255);
		// Neko's buffers take bytes, not code points
		for (c in [0xE9 + 256, 0x65E5, 0x1F600, -1])
			try {
				b.addChar(c);
			} catch (e:Dynamic) {
				Sys.println('addChar $c fails: $e');
			}
		b.addSub("0123456789", 3, 4);
		b.addSub("héllo", 1, 2);
		b.addSub("abc", 1);
		Sys.println(b.toString() + " " + b.length);
		var big = new StringBuf();
		for (i in 0...20000)
			big.add(i % 10);
		var s = big.toString();
		Sys.println(s.length + " " + s.substr(19990) + " " + big.length);
		var again = new StringBuf();
		again.add(s);
		again.add(s);
		Sys.println(again.length + " " + haxe.crypto.Md5.encode(again.toString()));
		var lines = new StringBuf();
		for (i in 0...5)
			lines.add('line $i\n');
		Sys.print(lines.toString());
	}
}
