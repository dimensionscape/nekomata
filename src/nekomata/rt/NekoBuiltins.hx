package nekomata.rt;

import haxe.io.Bytes;
import nekomata.rt.Values;

// Neko's $ builtins (vm/builtins.c)
@:keep
class NekoBuiltins {
	static var table:haxe.ds.IntMap<NFunction>;

	public static function get(h:Int):Dynamic {
		if (table == null)
			init();
		var f = table.get(h);
		if (f == null)
			Rt.error("Builtin not found : " + Rt.fieldName(h));
		return f;
	}

	// The builtin, or null when there is none, for a module to look up once
	public static function find(h:Int):Dynamic {
		if (table == null)
			init();
		return table.get(h);
	}

	static function add(name:String, nargs:Int, fn:Dynamic)
		table.set(nekomata.neko.Hash.field(name), new NFunction(fn, nargs, Primitive, null, null, name));

	static inline function int(v:Dynamic, what:String):Int {
		if (!Rt.isInt(v))
			Rt.error(what);
		return v;
	}

	static inline function array(v:Dynamic, what:String):Array<Dynamic> {
		if (Rt.typeOf(v) != Rt.TARRAY)
			Rt.error(what);
		return v;
	}

	static inline function string(v:Dynamic, what:String):NString {
		if (!Std.isOfType(v, NString))
			Rt.error(what);
		return v;
	}

	static inline function object(v:Dynamic, what:String):NObject {
		if (!Std.isOfType(v, NObject))
			Rt.error(what);
		return v;
	}

	// Builtins that never run neko code, which translated code may call straight
	//  from where it uses them: without a frame of their own, which neko's stack
	//  traces would not show, as none of them calls back into neko code

	@:noDebug public static function amake(n:Dynamic):Dynamic {
		var size = int(n, "$amake");
		var a:Array<Dynamic> = [];
		if (size > 0)
			a[size - 1] = null;
		return a;
	}

	@:noDebug public static function asize(a:Dynamic):Dynamic {
		if (Rt.typeOf(a) != Rt.TARRAY)
			Rt.error("$asize");
		return untyped __cpp__("{0}->__length()", a);
	}

	@:noDebug public static function ssize(s:Dynamic):Dynamic
		return string(s, "$ssize").b.length;

	@:noDebug public static function sget(s:Dynamic, p:Dynamic):Dynamic {
		var b = string(s, "$sget").b, pos = int(p, "$sget");
		return pos < 0 || pos >= b.length ? null : b.get(pos);
	}

	@:noDebug public static function sset(s:Dynamic, p:Dynamic, c:Dynamic):Dynamic {
		var b = string(s, "$sset").b, pos = int(p, "$sset"), v = int(c, "$sset") & 0xFF;
		if (pos < 0 || pos >= b.length)
			return null;
		b.set(pos, v);
		return v;
	}

	@:noDebug public static function toInt(v:Dynamic):Dynamic {
		switch Rt.typeOf(v) {
			case Rt.TINT:
				return v;
			case Rt.TFLOAT:
				var f = Rt.num(v);
				if (Math.isNaN(f) || !Math.isFinite(f))
					return null;
				return Std.int(f);
			case Rt.TSTRING:
				return Std.parseInt(Rt.bytes(v).toString());
			default:
				return null;
		}
	}

	@:noDebug public static function toFloat(v:Dynamic):Dynamic {
		switch Rt.typeOf(v) {
			case Rt.TINT | Rt.TFLOAT:
				return new NFloat(Rt.num(v));
			case Rt.TSTRING:
				return new NFloat(Std.parseFloat(Rt.bytes(v).toString()));
			default:
				return null;
		}
	}

	public static function init() {
		if (table != null)
			return;
		table = new haxe.ds.IntMap();

		add("print", NFunction.VAR_ARGS, function(args:Array<Dynamic>) {
			for (a in args)
				Rt.print(a);
			return true;
		});

		// Arrays
		add("array", NFunction.VAR_ARGS, (args:Array<Dynamic>) -> args.copy());
		add("amake", 1, amake);
		add("acopy", 1, (a:Dynamic) -> array(a, "$acopy").copy());
		add("asize", 1, asize);
		add("asub", 3, function(a:Dynamic, p:Dynamic, l:Dynamic) {
			var arr = array(a, "$asub"), pos = int(p, "$asub"), len = int(l, "$asub");
			if (pos < 0 || len < 0 || pos + len > arr.length)
				Rt.error("$asub");
			return arr.slice(pos, pos + len);
		});
		add("ablit", 5, function(dst:Dynamic, dp:Dynamic, src:Dynamic, sp:Dynamic, l:Dynamic) {
			var d = array(dst, "$ablit"), s = array(src, "$ablit");
			var dpos = int(dp, "$ablit"), spos = int(sp, "$ablit"), len = int(l, "$ablit");
			if (dpos < 0 || spos < 0 || len < 0 || dpos + len > d.length || spos + len > s.length)
				Rt.error("$ablit");
			var tmp = s.slice(spos, spos + len);
			for (i in 0...len)
				d[dpos + i] = tmp[i];
			return null;
		});
		add("aconcat", 1, function(arrs:Dynamic) {
			var result:Array<Dynamic> = [];
			for (a in array(arrs, "$aconcat"))
				for (x in array(a, "$aconcat"))
					result.push(x);
			return result;
		});

		// Strings
		add("smake", 1, (n:Dynamic) -> new NString(Bytes.alloc(int(n, "$smake"))));
		add("ssize", 1, ssize);
		add("scopy", 1, function(s:Dynamic) {
			var b = string(s, "$scopy").b;
			var c = Bytes.alloc(b.length);
			c.blit(0, b, 0, b.length);
			return new NString(c);
		});
		add("ssub", 3, function(s:Dynamic, p:Dynamic, l:Dynamic) {
			var b = string(s, "$ssub").b, pos = int(p, "$ssub"), len = int(l, "$ssub");
			if (pos < 0 || len < 0 || pos + len > b.length)
				Rt.error("$ssub");
			return new NString(b.sub(pos, len));
		});
		add("sget", 2, sget);
		add("sset", 3, sset);
		add("sblit", 5, function(dst:Dynamic, dp:Dynamic, src:Dynamic, sp:Dynamic, l:Dynamic) {
			var d = string(dst, "$sblit").b, s = string(src, "$sblit").b;
			var dpos = int(dp, "$sblit"), spos = int(sp, "$sblit"), len = int(l, "$sblit");
			if (dpos < 0 || spos < 0 || len < 0 || dpos + len > d.length || spos + len > s.length)
				Rt.error("$sblit");
			d.blit(dpos, s, spos, len);
			return null;
		});
		add("sfind", 3, function(s:Dynamic, p:Dynamic, pat:Dynamic):Dynamic {
			var b = string(s, "$sfind").b, pos = int(p, "$sfind"), sub = string(pat, "$sfind").b;
			if (pos < 0 || pos > b.length)
				Rt.error("$sfind");
			var last = b.length - sub.length;
			var i = pos;
			while (i <= last) {
				var j = 0;
				while (j < sub.length && b.get(i + j) == sub.get(j))
					j++;
				if (j == sub.length)
					return i;
				i++;
			}
			return null;
		});

		// Objects
		add("new", 1, (o:Dynamic) -> Rt.newObject(o));
		add("objget", 2, function(o:Dynamic, f:Dynamic):Dynamic {
			if (!Std.isOfType(o, NObject))
				return null;
			return (o : NObject).find(int(f, "$objget"));
		});
		add("objset", 3, function(o:Dynamic, f:Dynamic, v:Dynamic):Dynamic {
			if (!Std.isOfType(o, NObject))
				return null;
			(o : NObject).fields.set(int(f, "$objset"), v);
			return v;
		});
		add("objcall", 3, function(o:Dynamic, f:Dynamic, args:Dynamic):Dynamic {
			if (!Std.isOfType(o, NObject))
				return null;
			return Rt.callArgs((o : NObject).find(int(f, "$objcall")), o, array(args, "$objcall"));
		});
		add("objfield", 2, function(o:Dynamic, f:Dynamic):Bool {
			if (!Std.isOfType(o, NObject))
				return false;
			return (o : NObject).has(int(f, "$objfield"));
		});
		add("objremove", 2, (o:Dynamic, f:Dynamic) -> object(o, "$objremove").fields.remove(int(f, "$objremove")));
		add("objfields", 1, function(o:Dynamic):Array<Dynamic> {
			var obj = object(o, "$objfields");
			return [for (k in obj.keys()) k];
		});
		add("hash", 1, (s:Dynamic) -> Rt.hash(s));
		add("fasthash", 1, (s:Dynamic) -> Rt.hash(s));
		add("field", 1, (f:Dynamic) -> Rt.str(Rt.fieldName(int(f, "$field"))));
		add("objsetproto", 2, function(o:Dynamic, p:Dynamic) {
			var obj = object(o, "$objsetproto");
			obj.proto = p == null ? null : object(p, "$objsetproto");
			return null;
		});
		add("objgetproto", 1, (o:Dynamic) -> object(o, "$objgetproto").proto);

		// Conversions and types
		add("int", 1, toInt);
		add("float", 1, toFloat);
		add("string", 1, (v:Dynamic) -> new NString(Rt.valueBytes(v)));
		add("typeof", 1, (v:Dynamic) -> Rt.typeOf(v));
		add("compare", 2, (a:Dynamic, b:Dynamic) -> Rt.compareOp(a, b));
		add("pcompare", 2, (a:Dynamic, b:Dynamic) -> Rt.physCompare(a, b));
		add("not", 1, (v:Dynamic) -> Rt.not(v));
		add("istrue", 1, (v:Dynamic) -> Rt.toBool(v));
		add("isnan", 1, (v:Dynamic) -> Std.isOfType(v, NFloat) && Math.isNaN((v : NFloat).v));
		add("isinfinite", 1, (v:Dynamic) -> Std.isOfType(v, NFloat) && !Math.isNaN((v : NFloat).v) && !Math.isFinite((v : NFloat).v));
		add("getkind", 1, function(v:Dynamic):Dynamic {
			if (!Std.isOfType(v, NAbstract))
				Rt.error("$getkind");
			return (v : NAbstract).kind;
		});
		add("iskind", 2, (v:Dynamic, k:Dynamic) -> Std.isOfType(v, NAbstract) && (v : NAbstract).kind == k);

		// Functions
		add("nargs", 1, function(f:Dynamic) {
			if (!Std.isOfType(f, NFunction))
				Rt.error("$nargs");
			return (f : NFunction).nargs;
		});
		add("call", 3, (f:Dynamic, th:Dynamic, args:Dynamic) -> Rt.callArgs(f, th, array(args, "$call")));
		add("closure", NFunction.VAR_ARGS, function(args:Array<Dynamic>):Dynamic {
			if (args.length < 2 || !Std.isOfType(args[0], NFunction))
				Rt.error("$closure");
			var fn:NFunction = args[0];
			var th = args[1];
			var bound = args.slice(2);
			if (fn.nargs != NFunction.VAR_ARGS && bound.length > fn.nargs)
				Rt.error("$closure");
			var left = fn.nargs == NFunction.VAR_ARGS ? NFunction.VAR_ARGS : fn.nargs - bound.length;
			return Rt.bind(fn, th, bound, left);
		});
		add("apply", NFunction.VAR_ARGS, function(args:Array<Dynamic>):Dynamic {
			if (args.length < 1)
				Rt.error("$apply");
			return Rt.apply(args[0], null, args.slice(1));
		});
		add("varargs", 1, function(f:Dynamic):Dynamic {
			if (!Std.isOfType(f, NFunction) || (f : NFunction).nargs != 1)
				Rt.error("$varargs");
			return new NFunction(function(args:Array<Dynamic>) return Rt.call1(f, null, args), NFunction.VAR_ARGS, Primitive);
		});

		// Exceptions
		add("throw", 1, (v:Dynamic) -> Rt.raise(v));
		add("rethrow", 1, (v:Dynamic) -> Rt.raise(v));
		add("excstack", 0, () -> NekoStack.excStack());
		add("callstack", 0, () -> NekoStack.callStack());

		// Hash tables
		add("hnew", 1, (n:Dynamic) -> new NHash(int(n, "$hnew")));
		add("hget", 3, (h:Dynamic, k:Dynamic, cmp:Dynamic) -> {
			var c = hash(h).find(k, comparer(cmp, "$hget"));
			c == null ? null : c.value;
		});
		add("hmem", 3, (h:Dynamic, k:Dynamic, cmp:Dynamic) -> hash(h).find(k, comparer(cmp, "$hmem")) != null);
		add("hset", 4, function(h:Dynamic, k:Dynamic, v:Dynamic, cmp:Dynamic) {
			var t = hash(h);
			var c = t.find(k, comparer(cmp, "$hset"));
			if (c != null) {
				c.value = v;
				return false;
			}
			t.add(k, v);
			return true;
		});
		add("hadd", 3, function(h:Dynamic, k:Dynamic, v:Dynamic) {
			hash(h).add(k, v);
			return null;
		});
		add("hremove", 3, (h:Dynamic, k:Dynamic, cmp:Dynamic) -> hash(h).remove(k, comparer(cmp, "$hremove")));
		add("hresize", 2, function(h:Dynamic, n:Dynamic) {
			hash(h).resize(int(n, "$hresize"));
			return null;
		});
		add("hkey", 1, (k:Dynamic) -> NHash.valHash(k));
		add("hcount", 1, (h:Dynamic) -> hash(h).nitems);
		add("hsize", 1, (h:Dynamic) -> hash(h).ncells);
		add("hiter", 2, function(h:Dynamic, f:Dynamic) {
			var t = hash(h);
			for (i in 0...t.ncells) {
				var c = t.cells[i];
				while (c != null) {
					Rt.call2(f, null, c.key, c.value);
					c = c.next;
				}
			}
			return null;
		});

		// 32-bit int arithmetic, which neko's ints already are here
		add("iadd", 2, (a:Dynamic, b:Dynamic) -> (int(a, "$iadd") + int(b, "$iadd")));
		add("isub", 2, (a:Dynamic, b:Dynamic) -> (int(a, "$isub") - int(b, "$isub")));
		add("imult", 2, (a:Dynamic, b:Dynamic) -> (int(a, "$imult") * int(b, "$imult")));
		add("idiv", 2, function(a:Dynamic, b:Dynamic) {
			var y = int(b, "$idiv");
			if (y == 0)
				Rt.error("$idiv");
			return Std.int(int(a, "$idiv") / y);
		});

		add("version", 0, () -> 241);
		add("neko_build_year", 0, () -> 2026);
		add("setresolver", 1, function(f:Dynamic) {
			if (f != null && (!Std.isOfType(f, NFunction) || (f : NFunction).nargs != 2))
				Rt.error("$setresolver");
			Rt.resolver.value = f;
			return null;
		});
		add("isbigendian", 0, () -> false);
	}

	// A hash table comparison: cmp must return the int 0 for equal keys
	static function comparer(cmp:Dynamic, prim:String):Null<(Dynamic, Dynamic) -> Bool> {
		if (cmp == null)
			return null;
		if (!Std.isOfType(cmp, NFunction) || (cmp : NFunction).nargs != 2)
			Rt.error(prim);
		return function(a, b) {
			var r = Rt.call2(cmp, null, a, b);
			return Rt.isInt(r) && (r : Int) == 0;
		};
	}

	static function hash(h:Dynamic):NHash {
		if (!Std.isOfType(h, NHash))
			Rt.error("Invalid hashtable");
		return h;
	}
}

// One binding in a neko hash table
class HCell {
	public var hkey:Int;
	public var key:Dynamic;
	public var value:Dynamic;
	public var next:Null<HCell>;

	public function new(hkey:Int, key:Dynamic, value:Dynamic, next:Null<HCell>) {
		this.hkey = hkey;
		this.key = key;
		this.value = value;
		this.next = next;
	}
}

// Neko's $hnew tables (vm/builtins.c), cell for cell: $hiter visits bindings in the
//  order neko does, which programs that print or generate code from a table rely on
@:keep
class NHash {
	static inline var DEF_SIZE = 7;

	public var cells:Array<Null<HCell>>;
	public var ncells:Int;
	public var nitems = 0;

	public function new(size:Int) {
		ncells = size <= 0 ? DEF_SIZE : size;
		cells = [for (_ in 0...ncells) null];
	}

	// Finds the binding for k, comparing keys with cmp, or with $compare when null
	public function find(k:Dynamic, cmp:Null<(Dynamic, Dynamic) -> Bool>):Null<HCell> {
		var c = cells[valHash(k) % ncells];
		while (c != null) {
			if (cmp == null ? Rt.compare(k, c.key) == 0 : cmp(k, c.key))
				return c;
			c = c.next;
		}
		return null;
	}

	// Adds a binding in front of any for the same key, as $hadd and $hset do
	public function add(k:Dynamic, v:Dynamic) {
		var hkey = valHash(k);
		if (nitems >= (ncells << 1))
			resize(ncells << 1);
		var i = hkey % ncells;
		cells[i] = new HCell(hkey, k, v, cells[i]);
		nitems++;
	}

	public function remove(k:Dynamic, cmp:Null<(Dynamic, Dynamic) -> Bool>):Bool {
		var i = valHash(k) % ncells;
		var c = cells[i], prev:HCell = null;
		while (c != null) {
			if (cmp == null ? Rt.compare(k, c.key) == 0 : cmp(k, c.key)) {
				if (prev == null)
					cells[i] = c.next;
				else
					prev.next = c.next;
				nitems--;
				return true;
			}
			prev = c;
			c = c.next;
		}
		return false;
	}

	public function resize(size:Int) {
		var n = size <= 0 ? DEF_SIZE : size;
		var cc:Array<Null<HCell>> = [for (_ in 0...n) null];
		// Neko re-adds each chain from its end, which keeps the chain's order
		function addRec(c:Null<HCell>) {
			if (c == null)
				return;
			addRec(c.next);
			var k = c.hkey % n;
			c.next = cc[k];
			cc[k] = c;
		}
		for (i in 0...ncells)
			addRec(cells[i]);
		cells = cc;
		ncells = n;
	}

	// Neko's val_hash (vm/hash.c), stable across runs: it reads the contents of
	//  strings, floats, arrays and objects, and ignores functions and abstracts
	public static function valHash(v:Dynamic):Int {
		var h = new HashState();
		hashRec(v, h, null);
		return h.h & 0x3FFFFFFF;
	}

	static inline function big(h:HashState, x:Int)
		h.h = h.h * 65599 + x;

	static inline function small(h:HashState, x:Int)
		h.h = h.h * 19 + x;

	// Bytes hash as C chars, signed on the compilers neko is built with
	static inline function signed(b:Int):Int
		return b >= 128 ? b - 256 : b;

	static function hashRec(v:Dynamic, h:HashState, seen:Null<Array<Dynamic>>) {
		switch Rt.typeOf(v) {
			case Rt.TINT:
				big(h, (v : Int));
			case Rt.TNULL:
				small(h, 0);
			case Rt.TFLOAT:
				// val_string of a float on 64 bits starts 4 bytes into the vfloat: the
				//  padding before the double, then its low half, read from the end
				var b = haxe.io.Bytes.alloc(8);
				b.setDouble(0, Rt.num(v));
				for (k in [3, 2, 1, 0])
					small(h, signed(b.get(k)));
				for (_ in 0...4)
					small(h, 0);
			case Rt.TBOOL:
				small(h, (v : Bool) ? 1 : 0);
			case Rt.TSTRING:
				var b = Rt.bytes(v);
				var k = b.length;
				while (k > 0)
					small(h, signed(b.get(--k)));
			case t = Rt.TOBJECT | Rt.TARRAY:
				if (seen != null) {
					var k = 0;
					var i = seen.length;
					while (i-- > 0) {
						if (seen[i] == v) {
							small(h, k);
							return;
						}
						k++;
					}
				}
				var inner = seen == null ? [v] : seen.concat([v]);
				if (t == Rt.TOBJECT) {
					var o:NObject = v;
					for (f in o.keys()) {
						big(h, f);
						hashRec(o.fields.get(f), h, inner);
					}
					if (o.proto != null)
						hashRec(o.proto, h, inner);
				} else {
					var a:Array<Dynamic> = v;
					var k = a.length;
					while (k > 0)
						hashRec(a[--k], h, inner);
				}
			default:
		}
	}
}

class HashState {
	public var h = 0;

	public function new() {}
}
