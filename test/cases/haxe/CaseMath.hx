class CaseMath {
	static function main() {
		var xs = [0.0, -0.0, 0.5, -0.5, 1.5, -1.5, 2.5, -2.5, 1e10, -1e10, 0.49999999999999994, 3.7, -3.7, 1073741823.5, 2147483647.5,
			Math.NaN, Math.POSITIVE_INFINITY];
		for (x in xs)
			Sys.println('$x: floor ${Math.floor(x)} ceil ${Math.ceil(x)} round ${Math.round(x)} ffloor ${Math.ffloor(x)} fceil ${Math.fceil(x)} fround ${Math.fround(x)} abs ${Math.abs(x)} int ${Std.int(x)}');
		Sys.println(Math.sqrt(2) + " " + Math.sqrt(-1) + " " + Math.pow(2, 0.5) + " " + Math.pow(2, 31) + " " + Math.pow(-2, 3) + " " + Math.pow(0, 0));
		Sys.println(Math.sin(1) + " " + Math.cos(1) + " " + Math.tan(1) + " " + Math.asin(0.5) + " " + Math.acos(0.5) + " " + Math.atan(1));
		Sys.println(Math.atan2(1, -1) + " " + Math.exp(1) + " " + Math.log(10) + " " + Math.log(0) + " " + Math.log(-1));
		Sys.println(Math.min(1, 2) + " " + Math.max(1, 2) + " " + Math.min(Math.NaN, 1) + " " + Math.max(-0.0, 0.0) + " " + Math.min(-0.0, 0.0));
		Sys.println(Math.isNaN(Math.NaN) + " " + Math.isNaN(1) + " " + Math.isFinite(Math.POSITIVE_INFINITY) + " " + Math.isFinite(1e308) + " " + Math.PI);
		Sys.println((1 / 0) + " " + (-1 / 0) + " " + (0 / 0) + " " + (5 % 3) + " " + (-5 % 3) + " " + (5.5 % 2) + " " + (-5.5 % -2));
		var i:Int = 2147483647;
		i++;
		var j:Int = 1073741823;
		j += 1;
		var k:Int = 65536;
		Sys.println(i + " " + j + " " + (k * k) + " " + (k * 32768) + " " + (0x7FFFFFFF + 1) + " " + (-2147483648 - 1));
		Sys.println((1 << 31) + " " + (1 << 32) + " " + (-1 >> 1) + " " + (-1 >>> 1) + " " + (-8 >> 1) + " " + (-8 >>> 28) + " " + (0x80000000 >> 31));
		Sys.println((5 & 3) + " " + (5 | 3) + " " + (5 ^ 3) + " " + (~5) + " " + (~0x7FFFFFFF) + " " + (0xFFFFFFFF & 0xFF00));
		Sys.println(Std.int(7 / 2) + " " + (7 / 2) + " " + Std.int(-7 / 2) + " " + (7 % -2) + " " + (10 / 3) + " " + (1e20 + 1) + " " + (0.1 + 0.2));
		Sys.println(Std.parseInt("123") + " " + Std.parseInt("-0x1A") + " " + Std.parseInt(" 42 ") + " " + Std.parseInt("4.9") + " " + Std.parseInt("")
			+ " " + Std.parseInt("2147483648") + " " + Std.parseInt("0x80000000"));
		Sys.println(Std.parseFloat("3.25") + " " + Std.parseFloat("-1e-3") + " " + Std.parseFloat(".5") + " " + Std.parseFloat("1e400") + " "
			+ Std.parseFloat("abc") + " " + Std.parseFloat("12abc"));
		var seeded = new Array<Int>();
		for (n in 0...5)
			seeded.push(Std.random(1));
		var r = Std.random(100);
		var f = Math.random();
		Sys.println(seeded + " " + (r >= 0 && r < 100) + " " + (f >= 0 && f < 1));
		var sum = 0.0;
		for (n in 1...100001)
			sum += 1 / n;
		Sys.println("harmonic " + sum);
		var acc = 1;
		for (n in 0...40)
			acc = acc * 31 + n;
		Sys.println("wrapping hash " + acc);
		var fl:Float = 1;
		for (n in 0...30)
			fl *= 3.3;
		Sys.println("powers " + fl + " " + Std.string(fl / 1e15));
		var big:haxe.Int32 = 0x7FFFFFFF;
		var half:haxe.Int32 = 65536;
		Sys.println((big + 1) + " " + (half * 65536) + " " + haxe.Int32.ucompare(-1, 1));
		Sys.println(Std.string(1e15) + " " + 1e16 + " " + 123456789012345678.0 + " " + 0.000001 + " " + 1.0 + " " + 100.0 + " " + -0.0);
	}
}
