package nekomata.rt;

import nekomata.rt.Values;

// Neko's default loader (vm/load.c): the $loader object with loadprim and loadmodule
@:keep
class NekoLoader {
	// Reads, translates and runs a module, returning its exports; set by the host
	public static var loadModule:(name:String, loader:NObject) -> NObject;

	// Modules already loaded, by name, as the loader's cache field
	static var cache = new Map<String, NObject>();

	static inline function h(name:String):Int
		return nekomata.neko.Hash.field(name);

	public static function create(args:Array<String>):NObject {
		var o = new NObject();
		var argv:Array<Dynamic> = [for (a in args) NString.of(a)];
		o.fields.set(h("args"), argv);
		o.fields.set(h("path"), null);
		o.fields.set(h("cache"), new NObject());
		o.fields.set(h("loadprim"), new NFunction(loadprim, 2, PrimitiveThis, null, null, "loadprim"));
		o.fields.set(h("loadmodule"), new NFunction(loadmodule, 2, PrimitiveThis, null, null, "loadmodule"));
		return o;
	}

	static function loadprim(th:Dynamic, prim:Dynamic, nargs:Dynamic):Dynamic {
		if (!Std.isOfType(prim, NString) || !Rt.isInt(nargs))
			return Rt.error("loadprim");
		var name = Rt.bytes(prim).toString();
		var n:Int = nargs;
		if (n >= 10 || n < -1)
			return Rt.error("loadprim");
		var f = Primitives.find(name, n);
		if (f != null)
			return f;
		// Neko fails here; the Haxe std loads many primitives it never calls, so the
		//  error waits until the primitive is called
		return new NFunction(function(args:Array<Dynamic>):Dynamic return Rt.error('Primitive not found : $name($n)'), NFunction.VAR_ARGS,
			Primitive, null, null, name);
	}

	static function loadmodule(th:Dynamic, name:Dynamic, vthis:Dynamic):Dynamic {
		if (!Std.isOfType(name, NString))
			return Rt.error("loadmodule");
		var n = Rt.bytes(name).toString();
		var exports = cache.get(n);
		if (exports != null)
			return exports;
		exports = loadModule(n, th);
		cache.set(n, exports);
		return exports;
	}
}
