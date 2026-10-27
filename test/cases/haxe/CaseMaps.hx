import haxe.ds.*;

enum Key {
	K1;
	K2(n:Int);
}

class Obj {
	public var id:Int;

	public function new(id)
		this.id = id;

	public function toString()
		return 'Obj$id';
}

class CaseMaps {
	static function keys<K, V>(m:Map<K, V>):String
		return [for (k in m.keys()) Std.string(k)].join(",");

	static function sortedKeys<K, V>(m:Map<K, V>):String {
		var a = [for (k in m.keys()) Std.string(k)];
		a.sort(Reflect.compare);
		return a.join(",");
	}

	static function main() {
		var sm = new Map<String, Int>();
		for (w in "the quick brown fox jumps over the lazy dog the end".split(" "))
			sm.set(w, sm.exists(w) ? sm.get(w) + 1 : 1);
		// Iteration order is the runtime's own; neko's comes from its hash tables
		trace(keys(sm));
		trace(sortedKeys(sm) + " the=" + sm.get("the") + " missing=" + sm.get("missing"));
		trace(sm.remove("the") + " " + sm.remove("the") + " " + sm.exists("the") + " " + sm.toString().length);
		trace([for (k => v in sm) '$k:$v'].join(" "));
		var copy = sm.copy();
		copy.set("new", 0);
		trace(Lambda.count(sm) + " " + Lambda.count(copy));
		sm.clear();
		trace("cleared " + Lambda.count(sm) + " " + sm);
		var special = new Map<String, String>();
		for (k in ["", "__proto__", "hasOwnProperty", "é", "日本", "a\nb", "constructor", "toString", "length"])
			special.set(k, "[" + k + "]");
		trace(sortedKeys(special) + " " + special.get("__proto__") + special.get("") + special.get("toString"));

		var im = new Map<Int, String>();
		for (i in [5, -3, 1000000, 0, 1073741823, -1073741824, 42, 7])
			im.set(i, "v" + i);
		trace(keys(im));
		trace(sortedKeys(im) + " " + im.get(-3) + " " + im.get(8) + " " + im.exists(0));
		var big = new IntMap<Int>();
		for (i in 0...10000)
			big.set(i * 7919 % 10007, i);
		var total = 0;
		for (v in big)
			total += v;
		trace("big " + Lambda.count(big) + " " + total + " " + big.get(7919));

		var om = new Map<Obj, String>();
		var objs = [for (i in 0...5) new Obj(i)];
		for (o in objs)
			om.set(o, "obj" + o.id);
		trace(sortedKeys(om) + " " + om.get(objs[3]) + " " + om.get(new Obj(3)) + " " + om.exists(objs[0]));
		om.remove(objs[1]);
		trace(sortedKeys(om));

		var em = new Map<Key, Int>();
		em.set(K1, 1);
		em.set(K2(5), 5);
		em.set(K2(5), 55);
		em.set(K2(6), 6);
		trace(sortedKeys(em) + " " + em.get(K2(5)) + " " + em.get(K2(7)) + " " + em.exists(K1));

		var lit = ["b" => 2, "a" => 1, "c" => 3];
		trace(sortedKeys(lit) + " " + lit["b"]);
		lit["d"] = 4;
		trace(lit.get("d"));
		var nested = [1 => ["x" => [1, 2]], 2 => ["y" => []]];
		trace(nested[1]["x"] + " " + nested.get(2).get("y"));
		var bt = new BalancedTree<String, Int>();
		for (w in ["m", "c", "x", "a", "e", "z", "b"])
			bt.set(w, w.charCodeAt(0));
		trace([for (k in bt.keys()) k].join(",") + " " + bt.get("e") + " " + bt.remove("c") + " " + [for (k in bt.keys()) k].join(","));
		trace(bt.toString());
	}
}
