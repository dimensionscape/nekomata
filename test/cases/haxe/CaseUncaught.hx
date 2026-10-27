// An exception nothing catches, from a few calls down: neko prints the stack and the
//  value, and exits 1
class Failing {
	public function new() {}

	public function run(depth:Int):Int {
		if (depth == 0)
			throw new haxe.Exception("gave up at the bottom");
		return run(depth - 1) + 1;
	}
}

class CaseUncaught {
	static function main() {
		Sys.println("starting");
		var f = new Failing();
		var v = [1, 2, 3].map(x -> x == 3 ? f.run(2) : x);
		Sys.println("never " + v);
	}
}
