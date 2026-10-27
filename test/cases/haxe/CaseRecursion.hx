// Deep recursion in Haxe code, and a long loop the Haxe compiler leaves as a loop
class CaseRecursion {
	static function sum(n:Int):Int
		return n == 0 ? 0 : n + sum(n - 1);

	static function depth(n:Int, acc:Array<Int>):Array<Int> {
		if (n == 0)
			return acc;
		acc.push(n);
		var r = depth(n - 1, acc);
		return r;
	}

	static function hanoi(n:Int, from:Int, to:Int, via:Int, moves:Array<Int>) {
		if (n == 0)
			return;
		hanoi(n - 1, from, via, to, moves);
		moves.push(from * 10 + to);
		hanoi(n - 1, via, to, from, moves);
	}

	static function main() {
		Sys.println("sum 10000 " + sum(10000));
		Sys.println("depth 10000 " + depth(10000, []).length);
		var moves = [];
		hanoi(16, 1, 3, 2, moves);
		Sys.println("hanoi " + moves.length + " " + moves.slice(0, 6));
		var obj = {f: null};
		obj.f = function(n:Int):Int return n <= 0 ? 0 : 1 + obj.f(n - 1);
		Sys.println("closure recursion " + obj.f(5000));
		var x = 0;
		for (i in 0...3000000)
			x = (x + i) % 1000003;
		Sys.println("loop " + x);
		try {
			infinite(0);
		} catch (e:Dynamic) {
			Sys.println("infinite recursion caught: " + e);
		}
	}

	static function infinite(n:Int):Int
		return infinite(n + 1) + 1;
}
