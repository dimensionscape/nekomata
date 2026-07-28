package nekomata;

import nekomata.neko.Reader;
import nekomata.emit.Emitter;
import nekomata.rt.Boot;
import nekomata.rt.NekoLoader;
import nekomata.rt.Rt;
import nekomata.rt.Values;

// The Nekomata host: runs neko .n modules and cppia scripts.
//  nekomata [-jit] [--emit file.cppia] <file.n | file.cppia> [args...]
// Neko code can recurse as deep as neko allows, so Windows gets a native stack that
//  matches: 256M reserved, committed only as it is used, for the main thread and
//  every thread the program starts
@:buildXml('<target id="haxe"><flag value="-STACK:268435456" if="windows"/></target>')
class Main {
	static var moduleCount = 0;
	static var emitTo:Null<String>;

	static function main() {
		var args = Sys.args();
		jit = args.remove("-jit");
		if (jit)
			cpp.cppia.Host.enableJit(true);
		var i = args.indexOf("--emit");
		if (i >= 0) {
			emitTo = args[i + 1];
			args.splice(i, 2);
		}
		if (args.length == 0) {
			Sys.println("usage: nekomata [-jit] [--emit file.cppia] <file.n | file.cppia> [args...]");
			Sys.exit(1);
		}
		var file = args.shift();
		var bytes = sys.io.File.getBytes(file);
		if (bytes.length >= 4 && bytes.getString(0, 4) == "NEKO")
			runNeko(file, bytes, args);
		else
			cpp.cppia.Host.runFile(file);
	}

	static function runNeko(file:String, bytes:haxe.io.Bytes, args:Array<String>) {
		Boot.programPath = sys.FileSystem.fullPath(file);
		Boot.prepareThread();
		// Filled before any neko thread can look them up
		nekomata.rt.NekoBuiltins.init();
		nekomata.rt.Primitives.init();
		Emitter.builtinExists = h -> nekomata.rt.NekoBuiltins.find(h) != null;
		var loader = NekoLoader.create(args);
		NekoLoader.loadModule = loadModuleFile;
		try {
			load(file, bytes, loader);
		} catch (e:Dynamic) {
			var report = nekomata.rt.NekoStack.report(e);
			Sys.stderr().writeBytes(report, 0, report.length);
			Sys.exit(1);
		}
	}

	// NEKOMATA_TIME=1 reports how long each module takes to read, translate and load
	static var timing = Sys.getEnv("NEKOMATA_TIME") == "1";
	static var jit = false;

	// The class a module's code goes in: one per module loaded, all as long, so that a
	//  cached translation can take the name of the class it loads as
	static function className():String {
		var n = Std.string(moduleCount++);
		return "NekoModule" + StringTools.lpad(n, "0", 6);
	}

	// Translates a module to cppia, or takes the cached translation, and runs it,
	//  returning its exports
	static function load(name:String, bytes:haxe.io.Bytes, loader:NObject):NObject {
		var t0 = haxe.Timer.stamp();
		var cls = className();
		var key = Cache.enabled ? Cache.key(bytes, name, jit) : null;
		var cppia = key == null ? null : Cache.get(key, cls);
		var nm = new NModule(name, loader);
		Boot.pending = nm;
		var module:cpp.cppia.Module = null;
		var t1 = haxe.Timer.stamp(), t2 = t1;
		if (cppia != null)
			try {
				module = cpp.cppia.Module.fromData(cppia.getData());
			} catch (e:Dynamic) {
				// A cached translation that does not load is made again, as another class
				cls = className();
			}
		var cached = module != null;
		if (!cached) {
			var m = Reader.read(bytes);
			t1 = haxe.Timer.stamp();
			var t = Emitter.translate(m, cls, name, jit);
			cppia = t.cppia;
			t2 = haxe.Timer.stamp();
			if (key != null)
				Cache.put(key, cppia, t.classAt, cls.length);
		}
		if (emitTo != null) {
			sys.io.File.saveBytes(emitTo, cppia);
			emitTo = null;
		}
		if (!cached)
			module = cpp.cppia.Module.fromData(cppia.getData());
		var t3 = haxe.Timer.stamp();
		module.boot();
		var t4 = haxe.Timer.stamp();
		if (timing) {
			inline function ms(a:Float, b:Float)
				return Std.string(Math.round((b - a) * 1000));
			var how = cached ? 'cached, loaded in ${ms(t0, t3)} ms' : 'read ${ms(t0, t1)} ms, translate ${ms(t1, t2)} ms, load ${ms(t2, t3)} ms';
			Sys.stderr().writeString('[nekomata] $name: ${cppia.length} bytes of cppia, $how, boot ${ms(t3, t4)} ms\n');
		}
		module.run();
		return nm.exports;
	}

	static function loadModuleFile(name:String, loader:NObject):NObject {
		var file = StringTools.endsWith(name, ".n") ? name : name + ".n";
		if (!sys.FileSystem.exists(file))
			// Neko's message carries where in its loader it failed
			Rt.error("load.c(181) : Module not found : " + name);
		return load(name, sys.io.File.getBytes(file), loader);
	}
}
