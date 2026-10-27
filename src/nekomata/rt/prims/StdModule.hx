package nekomata.rt.prims;

import haxe.io.Bytes;
import nekomata.rt.Values;
import nekomata.rt.Rt;
import nekomata.rt.Primitives.add;
import nekomata.rt.prims.Conv.*;

// libs/std module.c: modules as abstracts of their own kind
@:keep
class StdModule {
	static final kind = new NObject();

	// Neko gives each module it reads an abstract for itself as $exports.__module, where
	//  Haxe's Sys.programPath finds the name of the module it runs in
	public static function attach(m:NModule)
		m.exports.fields.set(nekomata.neko.Hash.field("__module"), new NAbstract(kind, m));

	static function module(v:Dynamic, prim:String):NModule
		return data(v, kind, prim);

	// Another abstract for the module, as the loader's cache holds
	public static function handle(m:NModule):NAbstract
		return new NAbstract(kind, m);

	// The module an abstract stands for, or null for any other value
	public static function of(v:Dynamic):Null<NModule>
		return Rt.isAbstract(v) && (v : NAbstract).kind == kind ? (v : NAbstract).data : null;

	static function loader(v:Dynamic, prim:String):NObject {
		if (!Rt.isObject(v))
			Primitives.fail(prim);
		return v;
	}

	static function read(b:Bytes, name:String, l:NObject, prim:String):NAbstract {
		var m = NekoLoader.readModule(b, name, l);
		if (m == null)
			Primitives.fail(prim);
		return handle(m);
	}

	// What a read function gives until it gives nothing. Neko asks it for exactly the
	//  bytes the module holds; a module is translated whole, so this reads on to the
	//  end, which a Haxe Input marks by throwing
	static function readAll(fread:Dynamic, prim:String):Bytes {
		var out = new haxe.io.BytesBuffer();
		var chunk = 4096;
		var buf = new NString(Bytes.alloc(chunk));
		while (true) {
			var n:Dynamic;
			try {
				n = Rt.call3(fread, null, buf, 0, chunk);
			} catch (e:Dynamic) {
				if (out.length == 0)
					Rt.raise(e);
				break;
			}
			if (!Rt.isInt(n) || (n : Int) < 0 || (n : Int) > chunk)
				Primitives.fail(prim);
			if (n == 0)
				break;
			out.addBytes(buf.b, 0, n);
		}
		return out.getBytes();
	}

	public static function register() {
		add("std@module_name", 1, (m:Dynamic) -> NString.of(module(m, "std@module_name").name));
		add("std@module_set_name", 2, function(m:Dynamic, n:Dynamic) {
			module(m, "std@module_set_name").name = str(n, "std@module_set_name");
			return null;
		});
		add("std@module_exports", 1, (m:Dynamic) -> module(m, "std@module_exports").exports);
		add("std@module_loader", 1, (m:Dynamic) -> module(m, "std@module_loader").loader);
		add("std@module_nglobals", 1, function(m:Dynamic) {
			var g = module(m, "std@module_nglobals").globals;
			return g == null ? 0 : g.length;
		});
		add("std@module_global_get", 2, function(m:Dynamic, p:Dynamic) {
			var g = module(m, "std@module_global_get").globals, i = int(p, "std@module_global_get");
			if (g == null || i < 0 || i >= g.length)
				return Primitives.fail("std@module_global_get");
			return g[i];
		});
		add("std@module_global_set", 3, function(m:Dynamic, p:Dynamic, v:Dynamic) {
			var g = module(m, "std@module_global_set").globals, i = int(p, "std@module_global_set");
			if (g == null || i < 0 || i >= g.length)
				return Primitives.fail("std@module_global_set");
			g[i] = v;
			return v;
		});
		add("std@module_read", 2, function(fread:Dynamic, l:Dynamic) {
			if (!Rt.isFunction(fread) || (fread : NFunction).nargs != 3)
				Primitives.fail("std@module_read");
			var ld = loader(l, "std@module_read");
			return read(readAll(fread, "std@module_read"), "", ld, "std@module_read");
		});
		add("std@module_read_string", 2, function(s:Dynamic, l:Dynamic) {
			var b = bytes(s, "std@module_read_string");
			return read(b.sub(0, b.length), "", loader(l, "std@module_read_string"), "std@module_read_string");
		});
		add("std@module_read_path", 3, function(path:Dynamic, n:Dynamic, l:Dynamic) {
			var name = str(n, "std@module_read_path");
			var ld = loader(l, "std@module_read_path");
			var file = NekoLoader.moduleFile(path, name);
			if (!sys.FileSystem.exists(file) || sys.FileSystem.isDirectory(file))
				NekoLoader.failure("Module not found : " + name, "module.c", 122);
			var m = NekoLoader.readModule(sys.io.File.getBytes(file), name, ld);
			if (m == null)
				NekoLoader.failure("Invalid module : " + name, "module.c", 129);
			return handle(m);
		});
		add("std@module_exec", 1, function(m:Dynamic) {
			NekoLoader.execModule(module(m, "std@module_exec"));
			return null;
		});
	}
}
