using Lambda;

class CaseLambda {
	static function main() {
		var a = [5, 3, 8, 1, 9, 2, 7];
		trace(a.map(x -> x * 2) + " " + a.filter(x -> x % 2 == 1) + " " + a.fold((x, acc) -> acc + x, 0));
		trace(a.count(x -> x > 4) + " " + a.has(8) + " " + a.has(4) + " " + a.exists(x -> x > 8) + " " + a.foreach(x -> x > 0));
		trace(a.find(x -> x > 5) + " " + a.findIndex(x -> x > 5) + " " + a.indexOf(9) + " " + a.empty() + " " + [].empty());
		var it = 0;
		a.iter(x -> it += x);
		trace(it + " " + Lambda.array(a.list()) + " " + a.concat([100]).length + " " + a.mapi((i, x) -> i * x));
		trace(Lambda.flatten([[1, 2], [], [3]]) + " " + Lambda.flatMap([1, 2], x -> [x, x * 10]));

		var b = a.copy();
		b.sort((x, y) -> x - y);
		trace(b + " " + a);
		b.reverse();
		trace(b + " " + b.join("-") + " " + b.indexOf(3) + " " + b.lastIndexOf(3) + " " + b.contains(7));
		var people = [{n: "c", age: 30}, {n: "a", age: 25}, {n: "b", age: 30}, {n: "d", age: 25}, {n: "e", age: 30}];
		haxe.ds.ArraySort.sort(people, (x, y) -> x.age - y.age);
		trace([for (p in people) p.n].join(""));
		people.sort((x, y) -> Reflect.compare(x.n, y.n));
		trace([for (p in people) p.n].join(""));
		var s = [1, 2, 3, 4, 5, 6, 7, 8];
		trace(s.splice(2, 3) + " " + s + " " + s.slice(1, 3) + " " + s.slice(-2) + " " + s.splice(-1, 5) + " " + s);
		s.insert(0, 99);
		s.insert(100, 98);
		s.insert(-1, 97);
		trace(s + " " + s.remove(99) + " " + s.remove(12345) + " " + s);
		trace(s.shift() + " " + s.pop() + " " + s);
		s.unshift(0);
		trace(s);
		var e:Array<Int> = [];
		trace(e.pop() + " " + e.shift() + " " + e.length);
		var g = [1, 2, 3];
		g[5] = 6;
		trace(g + " " + g.length + " " + g[4]);
		g.resize(2);
		trace(g + " " + g.length);
		g.resize(4);
		trace(g);
		var it2 = [10, 20, 30].iterator();
		var out = [];
		while (it2.hasNext())
			out.push(it2.next());
		trace(out + " " + [for (k => v in ["x", "y"]) '$k=$v']);
		var words = "pear Apple fig banana apple Fig".split(" ");
		words.sort(Reflect.compare);
		trace(words);
		words.sort((x, y) -> Reflect.compare(x.toLowerCase(), y.toLowerCase()));
		trace(words);
		var nums = [3.5, -1, 2, 1e10, -0.5, 0];
		nums.sort(Reflect.compare);
		trace(nums + " " + Lambda.fold(nums, Math.max, Math.NEGATIVE_INFINITY));
		var l = new List<String>();
		l.add("b");
		l.push("a");
		l.add("c");
		trace(l + " " + l.length + " " + l.first() + " " + l.last() + " " + l.pop() + " " + l + " " + l.remove("c") + " " + l.join("+"));
		var big = [for (i in 0...10000) (i * 7919) % 10007];
		big.sort((x, y) -> x - y);
		trace(big[0] + " " + big[5000] + " " + big[9999] + " " + big.length);
		var dd = [for (i in 0...20) i % 7];
		trace(dd.filter(x -> x == 3).length + " " + [for (x in dd) if (x > 4) x]);
		var copy = [[1], [2]];
		var shallow = copy.copy();
		shallow[0].push(9);
		trace(copy + " " + shallow);
		trace([1, 2, 3].toString() + " " + Std.string([[]]) + " " + [null, null]);
	}
}
