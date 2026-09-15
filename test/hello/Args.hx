// Prints its arguments, and with "fail" among them lets an exception out, which the
//  host reports as neko does
class Args {
	static function main() {
		var args = Sys.args();
		Sys.println(args.length + " args: " + args.join(" "));
		if (args.indexOf("fail") >= 0)
			fail(args.length);
	}

	static function fail(n:Int) {
		throw 'failed with $n args';
	}
}
