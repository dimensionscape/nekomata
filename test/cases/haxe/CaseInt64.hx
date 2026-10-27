import haxe.Int64;

using haxe.Int64;

// Each check in a function of its own: one long main has more stack than neko's
//  verifier allows a function
class CaseInt64 {
	static var a = Int64.make(0x12345678, 0x9ABCDEF0);
	static var b = Int64.ofInt(-5);
	static var c = Int64.parseString("9223372036854775807");
	static var d = Int64.parseString("-9223372036854775808");

	static function basics() {
		trace(a + " " + b + " " + c + " " + d);
		trace(a.high + " " + a.low + " " + Int64.toStr(b) + " " + b.high + " " + b.low);
	}

	static function arithmetic() {
		trace(a + b);
		trace(a - b);
		trace(a * b);
		trace(a / b);
		trace(a % b);
		trace(c + 1);
		trace(d - 1);
		trace(c * 2);
		trace(-d);
	}

	static function bits() {
		trace(a << 4);
		trace(a >> 4);
		trace(a >>> 4);
		trace(b >> 1);
		trace(b >>> 1);
		trace(Int64.ofInt(1) << 63);
		trace(a & b);
		trace(a | b);
		trace(a ^ b);
		trace(~a);
	}

	static function comparisons() {
		trace(Int64.compare(a, b) + " " + Int64.ucompare(a, b));
		trace((a > b) + " " + (b < 0));
		trace(a == Int64.make(0x12345678, 0x9ABCDEF0));
		trace(Int64.isZero(Int64.ofInt(0)) + " " + Int64.isNeg(b) + " " + Int64.isInt64(a) + " " + Int64.toInt(Int64.ofInt(123456)));
	}

	static function failures() {
		try {
			Int64.toInt(a);
		} catch (e:Dynamic) {
			trace("toInt overflow: " + e);
		}
		try {
			Int64.parseString("12x");
		} catch (e:Dynamic) {
			trace("parse fails: " + e);
		}
		try {
			a / Int64.ofInt(0);
		} catch (e:Dynamic) {
			trace("divide by zero: " + e);
		}
	}

	static function conversions() {
		trace(Int64.fromFloat(1e15));
		trace(Int64.fromFloat(-123456789012.0));
		trace(Int64.toStr(Int64.fromFloat(4294967296.5)));
		var dm = Int64.divMod(Int64.parseString("1000000000000"), Int64.ofInt(7));
		trace(dm.quotient + " " + dm.modulus);
	}

	// Int64's inlined multiply keeps many values on neko's stack at once
	static function times(x:Int64, y:Int64):Int64
		return x * y;

	static function loops() {
		var f = Int64.ofInt(1);
		for (i in 1...21)
			f = times(f, i);
		trace("20! = " + f);
		var fib = [Int64.ofInt(0), Int64.ofInt(1)];
		for (i in 2...93)
			fib.push(fib[i - 1] + fib[i - 2]);
		trace("fib 92 = " + fib[92]);
		var h = Int64.ofInt(0);
		var prime = Int64.parseString("1099511628211");
		for (ch in "the quick brown fox".split(""))
			h = times(h, prime) + ch.charCodeAt(0);
		trace("hash " + h);
	}

	static function int32() {
		var i32:haxe.Int32 = 0x7FFFFFFF;
		i32 += 1;
		var minus:haxe.Int32 = -1;
		trace("int32 " + i32 + " " + (i32 * 2) + " " + (minus >>> 1));
	}

	static function main() {
		basics();
		arithmetic();
		bits();
		comparisons();
		failures();
		conversions();
		loops();
		int32();
	}
}
