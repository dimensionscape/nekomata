package nekomata.rt;

import haxe.io.Bytes;
import nekomata.rt.Values;

// Neko's default loader (vm/load.c): the $loader object with its search path, its
//  module cache, loadprim and loadmodule
@:keep
class NekoLoader {
	// Reads and translates a module's bytecode, returning what runs it; set by the host.
	//  Throws ReadError or StackError for bytecode that is not a valid module
	public static var translate:(m:NModule, bytes:Bytes) -> (() -> Void);

	// NEKOMATA_TRACE=1 reports each primitive a module loads that the runtime lacks
	static var trace = Sys.getEnv("NEKOMATA_TRACE") == "1";

	// What runs each module read and not yet run, for loadmodule and std@module_exec
	static var runners = new haxe.ds.ObjectMap<NModule, () -> Void>();
	static var lock = new sys.thread.Mutex();
	// The kind of the __libs abstract, where neko keeps the ndlls a loader has opened
	static var libsKind = new NObject();

	static inline function h(name:String):Int
		return nekomata.neko.Hash.field(name);

	// The loader neko's main gives the module it runs: args are what follows the module
	//  name, and the path comes from NEKOPATH or else the host's own directory
	public static function create(args:Array<String>):NObject {
		// Neko names these fields in its own field table
		Rt.registerFields(["args", "path", "cache", "__libs", "loadprim", "loadmodule", "__module", "msg", "file", "line", "__string"]);
		var o = new NObject();
		var argv:Array<Dynamic> = [for (a in args) NString.of(a)];
		var env = Sys.getEnv("NEKOPATH");
		o.fields.set(h("path"), initPath(env != null ? env : defaultPath()));
		o.fields.set(h("cache"), new NObject());
		o.fields.set(h("__libs"), new NAbstract(libsKind, null));
		o.fields.set(h("args"), argv);
		o.fields.set(h("loadprim"), new NFunction(loadprim, 2, PrimitiveThis, null, null, "loadprim"));
		o.fields.set(h("loadmodule"), new NFunction(loadmodule, 2, PrimitiveThis, null, null, "loadmodule"));
		return o;
	}

	// Neko on Windows searches the directory neko.dll is in, elsewhere the directory it
	//  was installed to and the usual system ones; the host stands in for both
	static function defaultPath():String {
		var exe = Sys.programPath();
		var cut = Std.int(Math.max(exe.lastIndexOf("/"), exe.lastIndexOf("\\")));
		var dir = cut < 0 ? "." : exe.substr(0, cut);
		if (Sys.systemName() == "Windows")
			return dir;
		return dir + ":/usr/local/lib/neko:/usr/lib/neko:/usr/local/bin:/usr/bin";
	}

	// init_path: a neko list of directories, each ending in a slash, last one first.
	//  ':' and ';' both separate them, except a drive letter's colon
	public static function initPath(path:String):Dynamic {
		var l:Dynamic = null;
		while (true) {
			var from = path.length > 1 && path.charAt(1) == ":" ? 2 : 0;
			var p = path.indexOf(":", from);
			var p2 = path.indexOf(";", from);
			if (p < 0 || (p2 >= 0 && p2 < p))
				p = p2;
			var dir = p < 0 ? path : path.substr(0, p);
			var last = dir.charAt(dir.length - 1);
			if (last != "/" && last != "\\")
				dir += "/";
			var cell:Array<Dynamic> = [NString.of(dir), l];
			l = cell;
			if (p < 0)
				break;
			path = path.substr(p + 1);
		}
		return l;
	}

	// neko_select_file: the file itself, then each directory of the path in turn. A file
	//  found in the current directory by a bare name comes back as ./name
	public static function selectFile(path:Dynamic, file:String, ext:String):String {
		var ff = file + ext;
		if (sys.FileSystem.exists(ff))
			return file.indexOf("/") >= 0 || file.indexOf("\\") >= 0 ? ff : "./" + ff;
		while (Std.isOfType(path, Array) && (path : Array<Dynamic>).length == 2) {
			var cell:Array<Dynamic> = path;
			var b = new haxe.io.BytesBuffer();
			Rt.appendValue(b, cell[0]);
			b.addString(ff);
			var p = b.getBytes().toString();
			if (sys.FileSystem.exists(p))
				return p;
			path = cell[1];
		}
		return ff;
	}

	// open_module: names ending in .n are taken as they are, others get .n added
	public static function moduleFile(path:Dynamic, name:String):String
		return selectFile(path, name, StringTools.endsWith(name, ".n") ? "" : ".n");

	// What neko's failure() throws: an object that prints as file(line) : msg
	public static function failure(msg:String, file:String, line:Int):Dynamic {
		var o = new NObject();
		o.fields.set(h("msg"), NString.of(msg));
		o.fields.set(h("file"), NString.of(file));
		o.fields.set(h("line"), line);
		o.fields.set(h("__string"), new NFunction(failureString, 0, PrimitiveThis, null, null, "failure_to_string"));
		return Rt.raise(o);
	}

	static function failureString(th:Dynamic):Dynamic {
		if (!Std.isOfType(th, NObject))
			return Rt.error("failure_to_string");
		var o:NObject = th;
		var b = new haxe.io.BytesBuffer();
		Rt.appendValue(b, o.find(h("file")));
		b.addString("(");
		Rt.appendValue(b, o.find(h("line")));
		b.addString(") : ");
		Rt.appendValue(b, o.find(h("msg")));
		return new NString(b.getBytes());
	}

	// neko_read_module: a module with its exports and loader, ready to run. Null when
	//  the bytes are not a valid module
	public static function readModule(bytes:Bytes, name:String, loader:NObject):Null<NModule> {
		var m = new NModule(name, loader);
		nekomata.rt.prims.StdModule.attach(m);
		var run:() -> Void;
		try {
			run = translate(m, bytes);
		} catch (e:nekomata.neko.Reader.ReadError) {
			invalid(name, e);
			return null;
		} catch (e:nekomata.neko.StackCheck.StackError) {
			invalid(name, e);
			return null;
		}
		lock.acquire();
		runners.set(m, run);
		lock.release();
		return m;
	}

	static function invalid(name:String, e:haxe.Exception) {
		if (trace)
			Sys.stderr().writeString('[nekomata] $name: ${e.message}
');
	}

	// Runs a module read by readModule. Neko runs a module again each time it is asked,
	//  with its globals as the last run left them; a translated module runs once
	public static function execModule(m:NModule):Void {
		lock.acquire();
		var run = runners.get(m);
		runners.remove(m);
		lock.release();
		if (run != null)
			run();
	}

	static function loadprim(th:Dynamic, prim:Dynamic, nargs:Dynamic):Dynamic {
		if (!Std.isOfType(th, NObject) || !Std.isOfType(prim, NString) || !Rt.isInt(nargs))
			return Rt.error("loadprim");
		var name = Rt.bytes(prim).toString();
		var n:Int = nargs;
		if (n >= 10 || n < -1)
			return Rt.error("loadprim");
		var f = Primitives.find(name, n);
		if (f == null) f = nekomata.rt.prims.Ndll.find(th, name, n);
		if (f != null)
			return NekoStats.enabled && n <= 6 ? NekoStats.wrap(f) : f;
		if (trace)
			Sys.stderr().writeString('[nekomata] no primitive $name($n)
');
		// Neko fails here; the Haxe std loads many primitives it never calls, so the
		//  error waits until the primitive is called
		return new NFunction(function(args:Array<Dynamic>):Dynamic return failure('Primitive not found : $name($n)', "load.c", 357),
			NFunction.VAR_ARGS, Primitive, null, null, name);
	}

	static function loadmodule(th:Dynamic, name:Dynamic, vthis:Dynamic):Dynamic {
		if (!Std.isOfType(th, NObject) || !Std.isOfType(name, NString) || !Std.isOfType(vthis, NObject))
			return Rt.error("loadmodule");
		var o:NObject = th;
		var cache = o.find(h("cache"));
		if (!Std.isOfType(cache, NObject))
			return Rt.error("loadmodule");
		return load(o, cache, Rt.bytes(name).toString(), vthis);
	}

	// loader_loadmodule: a module already in the loader's cache under its name, or the
	//  file found through the loader's path, cached before it runs so that modules that
	//  load each other get each other's exports
	static function load(o:NObject, cache:NObject, name:String, loader:NObject):NObject {
		// The cache field is named in neko's field table, as val_id names it
		Rt.registerFields([name]);
		var mid = h(name);
		var cached = nekomata.rt.prims.StdModule.of(cache.find(mid));
		if (cached != null)
			return cached.exports;
		var file = moduleFile(o.find(h("path")), name);
		if (!sys.FileSystem.exists(file) || sys.FileSystem.isDirectory(file))
			failure("Module not found : " + name, "load.c", 181);
		if (trace)
			Sys.stderr().writeString('[nekomata] loading module $name from $file
');
		NekoStats.measure("neko_read_module", true);
		var m = readModule(sys.io.File.getBytes(file), name, loader);
		NekoStats.measure("neko_read_module", false);
		if (m == null)
			failure("Invalid module : " + name, "load.c", 398);
		cache.fields.set(mid, nekomata.rt.prims.StdModule.handle(m));
		NekoStats.measure(name, true);
		execModule(m);
		NekoStats.measure(name, false);
		return m.exports;
	}

	// What neko's main does with the module named on its command line
	public static function run(loader:NObject, name:String):NObject {
		var cache:NObject = loader.find(h("cache"));
		return load(loader, cache, name, loader);
	}

	// What an executable with a module attached does with it (neko_execute_self): the
	//  module has no name, and the cache holds it as _self
	public static function runSelf(loader:NObject, bytes:Bytes):Void {
		var m = readModule(bytes, "", loader);
		if (m == null)
			Rt.error("std@module_read");
		Rt.registerFields(["_self"]);
		var cache:NObject = loader.find(h("cache"));
		cache.fields.set(h("_self"), nekomata.rt.prims.StdModule.handle(m));
		execModule(m);
	}
}
