package nekomata.rt;

import haxe.io.Bytes;

// Neko's value kinds that hxcpp has no exact match for. Ints, bools, null and arrays use
//  hxcpp's own Int, Bool, null and Array<Dynamic>

// A neko string: a mutable, fixed-length run of bytes
@:keep
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
class NFloat {
	public var v:Float;

	public function new(v:Float)
		this.v = v;
}

// A neko object: fields keyed by hash, with an optional prototype
@:keep
class NObject {
	public var fields:haxe.ds.IntMap<Dynamic>;
	public var proto:Null<NObject>;

	public function new(?proto:NObject) {
		fields = new haxe.ds.IntMap();
		this.proto = proto;
	}

	public function find(h:Int):Dynamic {
		var o = this;
		while (o != null) {
			if (o.fields.exists(h))
				return o.fields.get(h);
			o = o.proto;
		}
		return null;
	}

	// Whether the field is on the object itself or its prototypes
	public function has(h:Int):Bool {
		var o = this;
		while (o != null) {
			if (o.fields.exists(h))
				return true;
			o = o.proto;
		}
		return false;
	}

	// The object's own field hashes in neko's order, which sorts them
	public function keys():Array<Int> {
		var result = [for (k in fields.keys()) k];
		result.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		return result;
	}

	// $new and the New opcode copy an object's own fields and keep its prototype
	public function copy():NObject {
		var o = new NObject(proto);
		for (k in fields.keys())
			o.fields.set(k, fields.get(k));
		return o;
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
//  position do not grow the stack, as neko's TailCall reuses the frame
@:keep
class TailCall {
	public var f:Dynamic;
	public var th:Dynamic;
	public var args:Array<Dynamic>;

	public function new(f:Dynamic, th:Dynamic, args:Array<Dynamic>) {
		this.f = f;
		this.th = th;
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
