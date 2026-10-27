import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;

class CaseBytes {
	static function main() {
		var b = Bytes.alloc(16);
		Sys.println(b.length + " " + b.toHex());
		b.fill(0, 16, 0xAB);
		b.set(0, 1);
		b.set(1, 256 + 2);
		b.set(2, -1);
		Sys.println(b.toHex() + " " + b.get(1) + " " + b.get(2));
		b.setInt32(4, 0x12345678);
		b.setUInt16(8, 0xBEEF);
		b.setInt32(12, -2);
		Sys.println(b.toHex() + " " + b.getInt32(4) + " " + b.getUInt16(8) + " " + b.getInt32(12) + " " + b.getUInt16(12));
		b.setFloat(0, 1.5);
		b.setDouble(8, Math.PI);
		Sys.println(b.toHex() + " " + b.getFloat(0) + " " + b.getDouble(8));
		b.setInt64(0, haxe.Int64.make(1, 2));
		Sys.println(b.getInt64(0) + " " + b.sub(0, 8).toHex());
		var s = Bytes.ofString("héllo 日本 😀");
		Sys.println(s.length + " " + s.toHex() + " " + s.toString() + " " + s.getString(1, 2) + " " + s.sub(7, 6).toString());
		Sys.println(Bytes.ofHex("48656c6c6f").toString() + " " + Bytes.ofString("abc").compare(Bytes.ofString("abd")) + " "
			+ Bytes.ofString("abc").compare(Bytes.ofString("ab")) + " " + Bytes.ofString("x").compare(Bytes.ofString("x")));
		var t = Bytes.ofString("0123456789");
		t.blit(2, Bytes.ofString("abc"), 0, 3);
		t.blit(0, t, 5, 5);
		Sys.println(t.toString());
		try {
			t.blit(8, Bytes.ofString("abc"), 0, 3);
		} catch (e:Dynamic) {
			Sys.println("blit out of bounds: " + e);
		}
		try {
			t.sub(5, 10);
		} catch (e:Dynamic) {
			Sys.println("sub out of bounds: " + e);
		}
		try {
			t.get(100);
			Sys.println("get past end " + t.get(100));
		} catch (e:Dynamic) {
			Sys.println("get out of bounds: " + e);
		}

		var bb = new BytesBuffer();
		bb.addByte(1);
		bb.addString("two");
		bb.addInt32(3);
		bb.addFloat(4.5);
		bb.addDouble(5.25);
		bb.addInt64(haxe.Int64.ofInt(-6));
		bb.add(Bytes.ofString("seven"));
		bb.addBytes(Bytes.ofString("xeighty"), 1, 5);
		Sys.println(bb.length);
		var all = bb.getBytes();
		Sys.println(all.length + " " + all.toHex());

		var out = new BytesOutput();
		out.bigEndian = true;
		out.writeInt16(-2);
		out.writeUInt16(65535);
		out.writeInt32(0x01020304);
		out.writeFloat(1.25);
		out.writeDouble(-2.5);
		out.writeString("str");
		out.writeByte(0);
		out.bigEndian = false;
		out.writeInt24(0x123456);
		out.writeInt32(-1);
		var ob = out.getBytes();
		Sys.println(ob.toHex());
		var inp = new BytesInput(ob);
		inp.bigEndian = true;
		Sys.println(inp.readInt16() + " " + inp.readUInt16() + " " + inp.readInt32() + " " + inp.readFloat() + " " + inp.readDouble() + " "
			+ inp.readString(3) + " " + inp.readByte());
		inp.bigEndian = false;
		Sys.println(inp.readInt24() + " " + inp.readInt32() + " " + inp.position + " " + inp.length);
		try {
			inp.readByte();
		} catch (e:haxe.io.Eof) {
			Sys.println("eof " + e);
		}
		var lines = new BytesInput(Bytes.ofString("line one\nline two\r\nlast"));
		var got = [];
		try {
			while (true)
				got.push(lines.readLine());
		} catch (e:haxe.io.Eof) {}
		Sys.println(got);
		var until = new BytesInput(Bytes.ofString("a,b,c"));
		Sys.println(until.readUntil(",".code) + " " + until.readAll().toString());
		Sys.println(haxe.crypto.Base64.encode(Bytes.ofString("any carnal pleas")) + " " + haxe.crypto.Base64.decode("aGVsbG8=").toString());
		Sys.println(haxe.crypto.Md5.encode("hello") + " " + haxe.crypto.Sha1.encode("hello") + " " + haxe.crypto.Sha256.encode("hello"));
		Sys.println(haxe.crypto.Crc32.make(Bytes.ofString("hello")) + " " + haxe.crypto.Adler32.make(Bytes.ofString("hello")));
		Sys.println(haxe.crypto.Md5.make(Bytes.ofString("é")).toHex() + " " + haxe.io.Bytes.ofString("ab").getData() != null);
		var big = Bytes.alloc(100000);
		for (i in 0...big.length)
			big.set(i, i * 31);
		Sys.println(haxe.crypto.Md5.make(big).toHex() + " " + haxe.crypto.Crc32.make(big));
	}
}
