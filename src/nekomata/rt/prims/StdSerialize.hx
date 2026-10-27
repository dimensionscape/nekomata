package nekomata.rt.prims;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import nekomata.rt.Values;
import nekomata.rt.Rt;
import nekomata.rt.NekoBuiltins.NHash;
import nekomata.rt.NekoBuiltins.HCell;
import nekomata.rt.Primitives.add;

// libs/std serialize.c: values as bytes and back, in neko's format. Ints and lengths
//  are 4 bytes little-endian, floats 8. A string, object, array or function seen
//  before is written as a reference counting back from the last one registered.
//  Functions from bytecode are not written: their code offset is gone once the module
//  is translated, so they fail as neko's JIT functions do
@:keep
class StdSerialize {
	static inline var MAX_SIZE = (1 << 28) - 1;
	static final serializeId = nekomata.neko.Hash.field("__serialize");
	static final unserializeId = nekomata.neko.Hash.field("__unserialize");
	static final loadprimId = nekomata.neko.Hash.field("loadprim");
	static final loadmoduleId = nekomata.neko.Hash.field("loadmodule");

	public static function register() {
		add("std@serialize", 1, (v:Dynamic) -> new NString(new Writer().write(v)));
		add("std@unserialize", 2, function(s:Dynamic, loader:Dynamic):Dynamic {
			if (!Rt.isNString(s))
				Primitives.fail("std@unserialize");
			return new Reader((s : NString).b, loader).read();
		});
	}

	static function failure(msg:String, line:Int):Dynamic
		return NekoLoader.failure(msg, "serialize.c", line);

	static function invalid():Dynamic
		return Rt.raise(NString.of("Invalid serialized data"));

	// The name of a module, as neko serializes it: a string
	static function moduleName(m:Null<NModule>):Dynamic
		return m == null ? null : NString.of(m.name);
}

private class Writer {
	final out = new BytesBuffer();
	final refs = new haxe.ds.ObjectMap<Dynamic, Int>();
	var nrefs = 0;
	var depth = 0;

	public function new() {}

	public function write(v:Dynamic):Bytes {
		value(v);
		return out.getBytes();
	}

	function int(n:Int)
		out.addInt32(n);

	// A reference to v when it was written before, else v registered for later ones
	function ref(v:Dynamic):Bool {
		var k = refs.get(v);
		if (k != null) {
			out.addByte("r".code);
			int(nrefs - 1 - k);
			return true;
		}
		refs.set(v, nrefs++);
		return false;
	}

	function value(v:Dynamic) {
		if (++depth > 350)
			@:privateAccess StdSerialize.failure("Serialization stack overflow", 176);
		switch Rt.typeOf(v) {
			case Rt.TNULL:
				out.addByte("N".code);
			case Rt.TBOOL:
				out.addByte((v : Bool) ? "T".code : "F".code);
			case Rt.TINT:
				var i:Int = v;
				// Neko's ints are 31 bits, and boxed int32s the others
				out.addByte(((i + 0x40000000) & 0x80000000) == 0 ? "i".code : "I".code);
				int(i);
			case Rt.TFLOAT:
				out.addByte("f".code);
				out.addDouble(Rt.num(v));
			case Rt.TSTRING:
				if (!ref(v)) {
					var b = (v : NString).b;
					out.addByte("s".code);
					int(b.length);
					out.add(b);
				}
			case Rt.TOBJECT:
				object(v);
			case Rt.TARRAY:
				if (!ref(v)) {
					var a:Array<Dynamic> = v;
					out.addByte("a".code);
					int(a.length);
					for (x in a)
						value(x);
				}
			case Rt.TFUNCTION:
				if (!ref(v)) {
					var f:NFunction = v;
					if (f.kind == Bytecode)
						@:privateAccess StdSerialize.failure("Cannot Serialize JIT method", 254);
					if (f.env != null && f.env.length > 0)
						@:privateAccess StdSerialize.failure("Cannot Serialize Primitive with environment", 247);
					out.addByte("p".code);
					int(f.nargs);
					value(NString.of(f.name));
				}
			case Rt.TABSTRACT if (Rt.isNHash(v)):
				var h = Rt.asNHash(v);
				out.addByte("h".code);
				int(h.ncells);
				int(h.nitems);
				for (i in 0...h.ncells) {
					var c = h.cells[i];
					while (c != null) {
						int(c.hkey);
						value(c.key);
						value(c.value);
						c = c.next;
					}
				}
			default:
				@:privateAccess StdSerialize.failure("Cannot Serialize Abstract", 286);
		}
		depth--;
	}

	function object(o:NObject) {
		if (refs.exists(o)) {
			ref(o);
			return;
		}
		// An object with its own __serialize gives what to write in its place, and the
		//  module whose __unserialize makes it back
		var k = o.ids.indexOf(@:privateAccess StdSerialize.serializeId);
		if (k >= 0) {
			var s:Dynamic = o.values[k];
			if (!Rt.isFunction(s) || ((s : NFunction).nargs != 0 && (s : NFunction).nargs != NFunction.VAR_ARGS))
				@:privateAccess StdSerialize.failure("Invalid __serialize method", 209);
			out.addByte("x".code);
			value(@:privateAccess StdSerialize.moduleName((s : NFunction).module));
			value(Rt.call0(s, o));
			refs.set(o, nrefs++);
			return;
		}
		refs.set(o, nrefs++);
		out.addByte("o".code);
		for (i in 0...o.ids.length) {
			int(o.ids[i]);
			value((o.values[i] : Dynamic));
		}
		int(0);
		if (o.proto == null)
			out.addByte("z".code);
		else {
			out.addByte("p".code);
			value(o.proto);
		}
	}
}

private class Reader {
	final b:Bytes;
	final loader:Dynamic;
	var pos = 0;
	final refs:Array<Dynamic> = [];

	public function new(b:Bytes, loader:Dynamic) {
		this.b = b;
		this.loader = loader;
	}

	function char():Int
		return pos < b.length ? b.get(pos++) : -1;

	function int():Int {
		if (pos + 4 > b.length)
			@:privateAccess StdSerialize.invalid();
		var n = b.getInt32(pos);
		pos += 4;
		return n;
	}

	function method(o:Dynamic, id:Int):Dynamic {
		if (!Rt.isObject(o))
			Rt.error("Invalid call");
		return (o : NObject).find(id);
	}

	function moduleExports(name:Dynamic):NObject {
		var exp = Rt.call2(method(loader, @:privateAccess StdSerialize.loadmoduleId), loader, name, loader);
		if (!Rt.isObject(exp))
			@:privateAccess StdSerialize.failure("module " + Rt.valueBytes(name).toString() + " is not an object", 508);
		return exp;
	}

	public function read():Dynamic {
		switch char() {
			case "N".code:
				return null;
			case "T".code:
				return true;
			case "F".code:
				return false;
			case "i".code:
				// alloc_int keeps 31 bits
				return (int() << 1) >> 1;
			case "I".code:
				return int();
			case "f".code:
				if (pos + 8 > b.length)
					@:privateAccess StdSerialize.invalid();
				var d = b.getDouble(pos);
				pos += 8;
				return Rt.float(d);
			case "s".code:
				var l = int();
				if (l < 0 || l > @:privateAccess StdSerialize.MAX_SIZE)
					@:privateAccess StdSerialize.invalid();
				var s = new NString(Bytes.alloc(l));
				refs.push(s);
				if (pos + l > b.length)
					@:privateAccess StdSerialize.invalid();
				s.b.blit(0, b, pos, l);
				pos += l;
				return s;
			case "o".code:
				var o = new NObject();
				refs.push(o);
				var f;
				while ((f = int()) != 0)
					o.fields.set(f, read());
				switch char() {
					case "p".code:
						var p = read();
						if (!Rt.isObject(p))
							@:privateAccess StdSerialize.invalid();
						o.proto = p;
					case "z".code:
					default:
						@:privateAccess StdSerialize.invalid();
				}
				return o;
			case "r".code:
				var n = int();
				if (n < 0 || n >= refs.length)
					@:privateAccess StdSerialize.invalid();
				return refs[refs.length - n - 1];
			case "a".code:
				var n = int();
				if (n < 0 || n > @:privateAccess StdSerialize.MAX_SIZE)
					@:privateAccess StdSerialize.invalid();
				var a:Array<Dynamic> = [];
				if (n > 0)
					a[n - 1] = null;
				refs.push(a);
				for (i in 0...n)
					a[i] = read();
				return a;
			case "p".code:
				var nargs = int();
				var slot = refs.length;
				refs.push(null);
				var name = read();
				var f = Rt.call2(method(loader, @:privateAccess StdSerialize.loadprimId), loader, name, nargs);
				if (!Rt.isFunction(f) || (f : NFunction).nargs != nargs)
					@:privateAccess StdSerialize.failure("Loader returned not-a-function", 437);
				refs[slot] = f;
				return f;
			case "L".code:
				refs.push(null);
				var name = read();
				int();
				int();
				if (Rt.typeOf(read()) != Rt.TARRAY)
					@:privateAccess StdSerialize.invalid();
				moduleExports(name);
				// The code offset names a function only in the bytecode, which is not kept
				return @:privateAccess StdSerialize.failure("module " + Rt.valueBytes(name).toString() + " has been modified", 493);
			case "x".code:
				var name = read();
				var data = read();
				var exp = moduleExports(name);
				var s = Rt.call1(exp.find(@:privateAccess StdSerialize.unserializeId), exp, data);
				refs.push(s);
				return s;
			case "h".code:
				var ncells = int(), nitems = int();
				if (ncells <= 0 || nitems < 0)
					@:privateAccess StdSerialize.invalid();
				var h = new NHash(ncells);
				for (i in 0...nitems) {
					var c = new HCell(int(), null, null, null);
					c.key = read();
					c.value = read();
					var k = c.hkey % ncells;
					if (k < 0)
						@:privateAccess StdSerialize.invalid();
					if (h.cells[k] == null)
						h.cells[k] = c;
					else {
						var last = h.cells[k];
						while (last.next != null)
							last = last.next;
						last.next = c;
					}
				}
				h.nitems = nitems;
				return h;
			default:
				return @:privateAccess StdSerialize.invalid();
		}
	}
}
