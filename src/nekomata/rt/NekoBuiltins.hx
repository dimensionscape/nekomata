package nekomata.rt;

import haxe.io.Bytes;
import nekomata.rt.Values;

// Neko's $ builtins (vm/builtins.c)
@:keep
@:cppFileCode('
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>
#include <string>

// $int of a float, as neko converts it on each system
static int nk_float_to_int(double f)
{
   #ifdef HX_WINDOWS
   return (int)f;
   #else
   return (int)(unsigned int)fmod(f, 4294967296.0);
   #endif
}

// $int of a string (builtin_int): hex after an optional sign, else strtol, which
//  stops at the first NUL as in neko
static int nk_string_to_int(Array<unsigned char> inBytes, int inLen, bool &outOk)
{
   std::string text(inLen ? (const char *)&inBytes[0] : "", inLen);
   const char *c = text.c_str();
   char *end;
   while (isspace((unsigned char)*c))
      ++c;
   char sign = c[0];
   bool isSigned = sign == 0x2d || sign == 0x2b;
   bool hex = isSigned ? (inLen >= 3 && c[1] == 0x30 && (c[2] == 0x78 || c[2] == 0x58))
                       : (inLen >= 2 && c[0] == 0x30 && (c[1] == 0x78 || c[1] == 0x58));
   outOk = true;
   if (hex)
   {
      int h = 0;
      c += isSigned ? 3 : 2;
      while (*c)
      {
         char k = *c++;
         if (k >= 0x30 && k <= 0x39) h = (h << 4) | (k - 0x30);
         else if (k >= 0x41 && k <= 0x46) h = (h << 4) | ((k - 0x41) + 10);
         else if (k >= 0x61 && k <= 0x66) h = (h << 4) | ((k - 0x61) + 10);
         else break;
      }
      return sign == 0x2d ? -h : h;
   }
   long h = strtol(c, &end, 10);
   if (c == end)
      outOk = false;
   return (int)h;
}

static double nk_string_to_float(Array<unsigned char> inBytes, int inLen, bool &outOk)
{
   std::string text(inLen ? (const char *)&inBytes[0] : "", inLen);
   char *end;
   double f = strtod(text.c_str(), &end);
   outOk = end != text.c_str();
   return f;
}
')
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
		if (!Rt.isNString(v))
			Rt.error(what);
		return v;
	}

	static inline function object(v:Dynamic, what:String):NObject {
		if (!Rt.isObject(v))
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

	// $hget, $hset, $hmem and $hremove with no compare function, which run no neko code,
	//  as the code calls them where they are used
	@:noDebug public static function hgetNull(h:Dynamic, k:Dynamic):Dynamic {
		var c = hash(h).find(k, null);
		return c == null ? null : c.value;
	}

	@:noDebug public static function hsetNull(h:Dynamic, k:Dynamic, v:Dynamic):Bool {
		var t = hash(h);
		var c = t.find(k, null);
		if (c != null) {
			c.value = v;
			return false;
		}
		t.add(k, v);
		return true;
	}

	@:noDebug public static function hmemNull(h:Dynamic, k:Dynamic):Bool
		return hash(h).find(k, null) != null;

	@:noDebug public static function hremoveNull(h:Dynamic, k:Dynamic):Bool
		return hash(h).remove(k, null);

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
				return untyped __cpp__("nk_float_to_int({0})", Rt.num(v));
			case Rt.TSTRING:
				var b = Rt.bytes(v);
				var ok = false;
				var r:Int = untyped __cpp__("nk_string_to_int({0}, {1}, {2})", b.getData(), b.length, ok);
				return ok ? r : null;
			default:
				return null;
		}
	}

	@:noDebug public static function toFloat(v:Dynamic):Dynamic {
		switch Rt.typeOf(v) {
			case Rt.TINT | Rt.TFLOAT:
				return new NFloat(Rt.num(v));
			case Rt.TSTRING:
				var b = Rt.bytes(v);
				var ok = false;
				var r:Float = untyped __cpp__("nk_string_to_float({0}, {1}, {2})", b.getData(), b.length, ok);
				return ok ? new NFloat(r) : null;
			default:
				return null;
		}
	}

	public static function init() {
		if (table != null)
			return;
		table = new haxe.ds.IntMap();

		// One write for all the arguments, as neko builds them into one string
		add("print", NFunction.VAR_ARGS, function(args:Array<Dynamic>) {
			if (args.length == 1)
				Rt.print(args[0]);
			else {
				var buf = new haxe.io.BytesBuffer();
				for (a in args)
					Rt.appendValue(buf, a);
				Rt.print(new NString(buf.getBytes()));
			}
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
			if (!Rt.isObject(o))
				return null;
			return (o : NObject).find(int(f, "$objget"));
		});
		add("objset", 3, function(o:Dynamic, f:Dynamic, v:Dynamic):Dynamic {
			if (!Rt.isObject(o))
				return null;
			(o : NObject).fields.set(int(f, "$objset"), v);
			return v;
		});
		add("objcall", 3, function(o:Dynamic, f:Dynamic, args:Dynamic):Dynamic {
			if (!Rt.isObject(o))
				return null;
			return Rt.callArgs((o : NObject).find(int(f, "$objcall")), o, array(args, "$objcall"));
		});
		add("objfield", 2, function(o:Dynamic, f:Dynamic):Bool {
			if (!Rt.isObject(o))
				return false;
			return (o : NObject).has(int(f, "$objfield"));
		});
		add("objremove", 2, (o:Dynamic, f:Dynamic) -> object(o, "$objremove").fields.remove(int(f, "$objremove")));
		add("objfields", 1, function(o:Dynamic):Array<Dynamic> {
			var obj = object(o, "$objfields");
			return [for (k in obj.keys()) k];
		});
		add("hash", 1, (s:Dynamic) -> Rt.hash(s));
		// $fasthash hashes without recording the name, unlike $hash
		add("fasthash", 1, (s:Dynamic) -> nekomata.neko.Hash.field(string(s, "$fasthash").b.toString()));
		add("field", 1, function(f:Dynamic):Dynamic {
			var n = Rt.knownFieldName(int(f, "$field"));
			return n == null ? null : Rt.str(n);
		});
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
		add("isnan", 1, (v:Dynamic) -> Rt.isNFloat(v) && Math.isNaN((v : NFloat).v));
		add("isinfinite", 1, (v:Dynamic) -> Rt.isNFloat(v) && !Math.isNaN((v : NFloat).v) && !Math.isFinite((v : NFloat).v));
		add("getkind", 1, function(v:Dynamic):Dynamic {
			if (!Rt.isAbstract(v))
				Rt.error("$getkind");
			return (v : NAbstract).kind;
		});
		add("iskind", 2, (v:Dynamic, k:Dynamic) -> Rt.isAbstract(v) && (v : NAbstract).kind == k);

		// Functions
		add("nargs", 1, function(f:Dynamic) {
			if (!Rt.isFunction(f))
				Rt.error("$nargs");
			return (f : NFunction).nargs;
		});
		add("call", 3, (f:Dynamic, th:Dynamic, args:Dynamic) -> Rt.callArgs(f, th, array(args, "$call")));
		add("closure", NFunction.VAR_ARGS, function(args:Array<Dynamic>):Dynamic {
			if (args.length < 2 || !Rt.isFunction(args[0]))
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
			if (!Rt.isFunction(f) || (f : NFunction).nargs != 1)
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
			if (f != null && (!Rt.isFunction(f) || (f : NFunction).nargs != 2))
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
		if (!Rt.isFunction(cmp) || (cmp : NFunction).nargs != 2)
			Rt.error(prim);
		return function(a, b) {
			var r:Dynamic = Rt.call2(cmp, null, a, b);
			return Rt.isInt(r) && (r : Int) == 0;
		};
	}

	static function hash(h:Dynamic):NHash {
		if (!Rt.isNHash(h))
			Rt.error("Invalid hashtable");
		return Rt.asNHash(h);
	}
}

// One binding in a neko hash table
@:build(nekomata.build.NoFrames.build())
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
@:build(nekomata.build.NoFrames.build())
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
		if (cmp == null && Rt.isInt(k)) {
			// An int key equals only an int of the same value
			var i:Int = k;
			while (c != null) {
				if (Rt.isInt(c.key) && (c.key : Int) == i)
					return c;
				c = c.next;
			}
			return null;
		}
		if (cmp == null && Rt.isNString(k)) {
			// A neko string key equals another with the same bytes, and other keys as
			//  $compare says
			var b = (k : NString).b;
			while (c != null) {
				var ck:Dynamic = c.key;
				if (Rt.isNString(ck) ? sameBytes(b, (ck : NString).b) : Rt.compare(k, ck) == 0)
					return c;
				c = c.next;
			}
			return null;
		}
		while (c != null) {
			if (cmp == null ? Rt.compare(k, c.key) == 0 : cmp(k, c.key))
				return c;
			c = c.next;
		}
		return null;
	}

	static inline function sameBytes(a:haxe.io.Bytes, b:haxe.io.Bytes):Bool
		return a.length == b.length && a.compare(b) == 0;

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
		for (i in 0...ncells)
			readd(cells[i], cc, n);
		cells = cc;
		ncells = n;
	}

	// Neko re-adds each chain from its end, which keeps the chain's order
	static function readd(c:Null<HCell>, cc:Array<Null<HCell>>, n:Int) {
		if (c == null)
			return;
		readd(c.next, cc, n);
		var k = c.hkey % n;
		c.next = cc[k];
		cc[k] = c;
	}

	// Neko's val_hash (vm/hash.c), stable across runs: it reads the contents of
	//  strings, floats, arrays and objects, and ignores functions and abstracts
	public static function valHash(v:Dynamic):Int {
		// The common keys, without the state hashRec needs for nested values
		if (Rt.isInt(v))
			return (v : Int) & 0x3FFFFFFF;
		if (Rt.isNString(v)) {
			var d = (v : NString).b.getData();
			var h = 0, k = d.length;
			while (k > 0)
				h = h * 19 + signed(cpp.NativeArray.unsafeGet(d, --k));
			return h & 0x3FFFFFFF;
		}
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
