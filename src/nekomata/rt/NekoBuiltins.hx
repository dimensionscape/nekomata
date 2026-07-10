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

	static function init() {
		table = new haxe.ds.IntMap();

		add("print", NFunction.VAR_ARGS, function(args:Array<Dynamic>) {
			for (a in args)
				Rt.print(a);
			return true;
		});

		// Arrays
		add("array", NFunction.VAR_ARGS, (args:Array<Dynamic>) -> args.copy());
		add("amake", 1, function(n:Dynamic) {
			var size = int(n, "$amake");
			var a:Array<Dynamic> = [];
			if (size > 0)
				a[size - 1] = null;
			return a;
		});
		add("acopy", 1, (a:Dynamic) -> array(a, "$acopy").copy());
		add("asize", 1, (a:Dynamic) -> array(a, "$asize").length);
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
		add("ssize", 1, (s:Dynamic) -> string(s, "$ssize").b.length);
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
		add("sget", 2, function(s:Dynamic, p:Dynamic):Dynamic {
			var b = string(s, "$sget").b, pos = int(p, "$sget");
			return pos < 0 || pos >= b.length ? null : b.get(pos);
		});
		add("sset", 3, function(s:Dynamic, p:Dynamic, c:Dynamic):Dynamic {
			var b = string(s, "$sset").b, pos = int(p, "$sset"), v = int(c, "$sset") & 0xFF;
			if (pos < 0 || pos >= b.length)
				return null;
			b.set(pos, v);
			return v;
		});
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
		add("int", 1, function(v:Dynamic):Dynamic {
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
		});
		add("float", 1, function(v:Dynamic):Dynamic {
			switch Rt.typeOf(v) {
				case Rt.TINT | Rt.TFLOAT:
					return new NFloat(Rt.num(v));
				case Rt.TSTRING:
					return new NFloat(Std.parseFloat(Rt.bytes(v).toString()));
				default:
					return null;
			}
		});
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
			return new NFunction(function(rest:Array<Dynamic>) return Rt.callArgs(fn, th, bound.concat(rest)), left, Primitive);
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
		add("excstack", 0, function():Array<Dynamic> return []);
		add("callstack", 0, function():Array<Dynamic> return []);

		// Hash tables
		add("hnew", 1, (n:Dynamic) -> new NHash());
		add("hget", 3, (h:Dynamic, k:Dynamic, cmp:Dynamic) -> hash(h).get(k));
		add("hmem", 3, (h:Dynamic, k:Dynamic, cmp:Dynamic) -> hash(h).exists(k));
		add("hset", 4, function(h:Dynamic, k:Dynamic, v:Dynamic, cmp:Dynamic) {
			var t = hash(h);
			var had = t.exists(k);
			t.set(k, v);
			return !had;
		});
		add("hadd", 3, function(h:Dynamic, k:Dynamic, v:Dynamic) {
			hash(h).add(k, v);
			return null;
		});
		add("hremove", 3, (h:Dynamic, k:Dynamic, cmp:Dynamic) -> hash(h).remove(k));
		add("hresize", 2, (h:Dynamic, n:Dynamic) -> null);
		add("hkey", 1, (k:Dynamic) -> NHash.keyHash(k));
		add("hcount", 1, (h:Dynamic) -> hash(h).count());
		add("hsize", 1, (h:Dynamic) -> hash(h).count());
		add("hiter", 2, function(h:Dynamic, f:Dynamic) {
			for (e in hash(h).entries())
				Rt.call2(f, null, e.k, e.v);
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
		add("setresolver", 1, (f:Dynamic) -> null);
		add("isbigendian", 0, () -> false);
	}

	static function hash(h:Dynamic):NHash {
		if (!Std.isOfType(h, NHash))
			Rt.error("Invalid hashtable");
		return h;
	}
}

// Neko's $hnew tables, keyed by value the way val_hash and val_compare see keys
@:keep
class NHash {
	var map = new Map<String, Array<{k:Dynamic, v:Dynamic}>>();
	var size = 0;

	public function new() {}

	public static function keyHash(k:Dynamic):Int
		return nekomata.neko.Hash.field(key(k));

	static function key(k:Dynamic):String {
		return switch Rt.typeOf(k) {
			case Rt.TINT | Rt.TFLOAT | Rt.TSTRING | Rt.TBOOL | Rt.TNULL: Rt.typeOf(k) + ":" + Rt.valueBytes(k).toHex();
			default: "#";
		}
	}

	function bucket(k:Dynamic):Array<{k:Dynamic, v:Dynamic}> {
		var name = key(k);
		var b = map.get(name);
		if (b == null) {
			b = [];
			map.set(name, b);
		}
		return b;
	}

	function find(k:Dynamic):Null<{k:Dynamic, v:Dynamic}> {
		var b = map.get(key(k));
		if (b != null)
			for (e in b)
				if (Rt.compare(e.k, k) == 0)
					return e;
		return null;
	}

	public function get(k:Dynamic):Dynamic {
		var e = find(k);
		return e == null ? null : e.v;
	}

	public function exists(k:Dynamic):Bool
		return find(k) != null;

	public function set(k:Dynamic, v:Dynamic) {
		var e = find(k);
		if (e != null)
			e.v = v;
		else
			add(k, v);
	}

	public function add(k:Dynamic, v:Dynamic) {
		bucket(k).unshift({k: k, v: v});
		size++;
	}

	public function remove(k:Dynamic):Bool {
		var b = map.get(key(k));
		if (b != null)
			for (e in b)
				if (Rt.compare(e.k, k) == 0) {
					b.remove(e);
					size--;
					return true;
				}
		return false;
	}

	public function count():Int
		return size;

	public function entries():Array<{k:Dynamic, v:Dynamic}> {
		var result = [];
		for (b in map)
			for (e in b)
				result.push(e);
		return result;
	}
}
