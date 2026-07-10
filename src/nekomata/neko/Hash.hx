package nekomata.neko;

class Hash {
	// Neko's val_id: each step is kept to a 31-bit neko int, sign included
	public static function field(name:String):Int {
		var h = 0;
		var bytes = haxe.io.Bytes.ofString(name);
		for (i in 0...bytes.length)
			h = ((223 * h + bytes.get(i)) << 1) >> 1;
		return h;
	}
}
