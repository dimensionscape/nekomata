package nekomata.rt;

import haxe.io.Bytes;

// Neko's value kinds that hxcpp has no exact match for. Ints, bools, null and arrays use
//  hxcpp's own Int, Bool, null and Array<Dynamic>

// A neko string: a mutable, fixed-length run of bytes
@:keep
@:build(nekomata.build.NoFrames.build())
class NString {
	public var b:Bytes;

	public function new(b:Bytes)
		this.b = b;

	public static inline function of(s:String):NString
		return new NString(Bytes.ofString(s));

	public function toString():String
		return b.toString();
}

// A neko float. hxcpp boxes a Float with a small integral value as an Int, which would
//  make neko's 2.0 an int, so floats are boxed here instead
@:keep
@:build(nekomata.build.NoFrames.build())
class NFloat {
	public var v:Float;

	public function new(v:Float)
		this.v = v;
}

// A neko object: fields keyed by hash, with an optional prototype
@:keep
@:build(nekomata.build.NoFrames.build())
class NObject {
	// The object's fields as neko's objtable keeps them: field hashes in order, with
	//  their values beside them
	public var ids:Array<Int>;
	public var values:Array<Dynamic>;
	public var proto:Null<NObject>;
	public var fields(get, never):FieldTable;

	public function new(?proto:NObject) {
		ids = [];
		values = [];
		this.proto = proto;
	}

	inline function get_fields():FieldTable
		return cast this;

	public function find(h:Int):Dynamic {
		var o = this;
		while (o != null) {
			var i = o.index(h);
			if (i >= 0)
				return cpp.NativeArray.unsafeGet(o.values, i);
			o = o.proto;
		}
		return null;
	}

	// Whether the field is on the object itself or its prototypes
	public function has(h:Int):Bool {
		var o = this;
		while (o != null) {
			if (o.index(h) >= 0)
				return true;
			o = o.proto;
		}
		return false;
	}

	// Where field h is among the object's own, or -1. Objects have few fields, which a
	//  scan finds sooner than a search; bigger ones are searched by halves
	public function index(h:Int):Int {
		var ids = this.ids;
		var n = ids.length;
		if (n <= 8) {
			for (i in 0...n)
				if (cpp.NativeArray.unsafeGet(ids, i) == h)
					return i;
			return -1;
		}
		var lo = 0, hi = n - 1;
		while (lo <= hi) {
			var mid = (lo + hi) >> 1;
			var id = cpp.NativeArray.unsafeGet(ids, mid);
			if (id == h)
				return mid;
			if (id < h)
				lo = mid + 1;
			else
				hi = mid - 1;
		}
		return -1;
	}

	public function set(h:Int, v:Dynamic):Void {
		var i = index(h);
		if (i >= 0) {
			cpp.NativeArray.unsafeSet(values, i, v);
			return;
		}
		// Kept in order, as neko sorts an object's fields by hash
		var at = ids.length;
		while (at > 0 && cpp.NativeArray.unsafeGet(ids, at - 1) > h)
			at--;
		if (at == ids.length) {
			ids.push(h);
			values.push(v);
		} else {
			ids.insert(at, h);
			values.insert(at, v);
		}
	}

	// The object's own field hashes in neko's order, which sorts them
	public function keys():Array<Int>
		return ids.copy();

	// $new and the New opcode copy an object's own fields and keep its prototype
	public function copy():NObject {
		var o = new NObject(proto);
		o.ids = ids.copy();
		o.values = values.copy();
		return o;
	}
}

// The own fields of an object, read and written by hash
abstract FieldTable(NObject) {
	public inline function get(h:Int):Dynamic {
		var i = this.index(h);
		return i < 0 ? null : cpp.NativeArray.unsafeGet(this.values, i);
	}

	public inline function exists(h:Int):Bool
		return this.index(h) >= 0;

	public inline function set(h:Int, v:Dynamic):Void
		this.set(h, v);

	public function remove(h:Int):Bool {
		var i = this.index(h);
		if (i < 0)
			return false;
		this.ids.splice(i, 1);
		this.values.splice(i, 1);
		return true;
	}
}

enum abstract FunctionKind(Int) {
	// fn(this, env, args...)
	var Bytecode;
	// fn(args...), or fn(args array) when nargs is VAR_ARGS
	var Primitive;
	// fn(this, args...), for loader methods that read val_this()
	var PrimitiveThis;
	// fn(env, args array), after the count is checked against nargs: what $apply,
	//  $closure and partial application make, with env holding [function, this,
	//  bound arguments...] as neko's closures hold theirs
	var Bound;
}

@:keep
@:build(nekomata.build.NoFrames.build())
class NFunction {
	public static inline var VAR_ARGS = -1;

	public var fn:Dynamic;
	public var nargs:Int;
	public var kind:FunctionKind;
	public var env:Array<Dynamic>;
	public var module:Null<NModule>;
	public var name:String;
	// The module global a bytecode function was defined as, which tells a tail call
	//  whether it calls the function it is in
	public var global:Int;

	public function new(fn:Dynamic, nargs:Int, kind:FunctionKind, ?env:Array<Dynamic>, ?module:NModule, name = "", global = -1) {
		this.fn = fn;
		this.nargs = nargs;
		this.kind = kind;
		this.env = env;
		this.module = module;
		this.name = name;
		this.global = global;
	}
}

// A tail call a function returns for its caller to make, so that calls in tail
//  position do not grow the stack, as neko's TailCall reuses the frame. Up to three
//  arguments travel in a, b and c, more in args
@:keep
@:build(nekomata.build.NoFrames.build())
class TailCall {
	public var f:Dynamic;
	public var th:Dynamic;
	public var n:Int;
	public var a:Dynamic;
	public var b:Dynamic;
	public var c:Dynamic;
	public var args:Array<Dynamic>;

	public function new(f:Dynamic, th:Dynamic, n:Int, args:Array<Dynamic>) {
		this.f = f;
		this.th = th;
		this.n = n;
		this.args = args;
	}
}

// A C value with a kind; the kind is compared by identity, as neko compares vkind pointers
@:keep
class NAbstract {
	public var kind:Dynamic;
	public var data:Dynamic;

	public function new(kind:Dynamic, data:Dynamic) {
		this.kind = kind;
		this.data = data;
	}
}

// A loaded neko module: its globals, its exports object and the loader it was given
@:keep
class NModule {
	public var name:String;
	public var globals:Array<Dynamic>;
	public var exports:NObject;
	public var loader:NObject;

	public function new(name:String, loader:NObject) {
		this.name = name;
		this.loader = loader;
		exports = new NObject();
	}
}

// A thrown null, which Rt.raise throws in its place
@:keep
class NullThrown {
	public function new() {}
}
