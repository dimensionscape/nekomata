import haxe.io.Bytes;
import haxe.zip.Compress;
import haxe.zip.Uncompress;

class CaseZip {
	static function main() {
		var text = [for (i in 0...200) "line " + i + " of some repetitive text"].join("\n");
		var raw = Bytes.ofString(text);
		for (level in [0, 1, 6, 9]) {
			var z = Compress.run(raw, level);
			var back = Uncompress.run(z);
			Sys.println('level $level: ${raw.length} -> ${z.length}, round trip ${back.compare(raw) == 0}, adler ${haxe.crypto.Adler32.make(back)}');
		}
		// Bytes neko's zlib wrote, so the result does not depend on the encoder
		var fixed = Bytes.ofHex("78dacb48cdc9c95728cf2fca49e102001e720467");
		Sys.println("fixed: [" + Uncompress.run(fixed).toString() + "]");
		var c = new Compress(9);
		var src = Bytes.ofString("streamed in two parts, streamed in two parts");
		var dst = Bytes.alloc(200);
		var r1 = c.execute(src, 0, dst, 0);
		c.setFlushMode(FINISH);
		var r2 = c.execute(src, r1.read, dst, r1.write);
		c.close();
		var out = dst.sub(0, r1.write + r2.write);
		Sys.println("stream: done " + r2.done + ", read " + (r1.read + r2.read) + ", back [" + Uncompress.run(out).toString() + "]");
		try {
			Uncompress.run(Bytes.ofString("not compressed at all"));
			Sys.println("uncompressed garbage");
		} catch (e:Dynamic) {
			Sys.println("garbage fails: " + e);
		}
		var empty = Compress.run(Bytes.alloc(0), 6);
		Sys.println("empty: " + Uncompress.run(empty).length);
		var big = Bytes.alloc(300000);
		for (i in 0...big.length)
			big.set(i, (i * i) & 0xFF);
		var bz = Compress.run(big, 6);
		Sys.println("big round trip " + (Uncompress.run(bz).compare(big) == 0) + " " + haxe.crypto.Crc32.make(Uncompress.run(bz)));
	}
}
