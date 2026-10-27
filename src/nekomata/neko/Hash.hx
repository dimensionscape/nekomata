package nekomata.neko;

class Hash {
	// Neko's val_id: each step is kept to a 31-bit neko int, sign included
	public static function field(name:String):Int
		return bytes(haxe.io.Bytes.ofString(name));

	// The same over bytes, which need not be UTF-8
	public static function bytes(b:haxe.io.Bytes):Int {
		var h = 0;
		for (i in 0...b.length)
			h = ((223 * h + b.get(i)) << 1) >> 1;
		return h;
	}
}
