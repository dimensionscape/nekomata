package nekomata;

import haxe.io.Bytes;
import nekomata.neko.Reader;
import nekomata.emit.Emitter;
import nekomata.rt.Boot;
import nekomata.rt.NekoLoader;
import nekomata.rt.NekoStats;
import nekomata.rt.Values;

// The Nekomata host: runs neko .n modules and cppia scripts.
//  nekomata [-interp] [--emit file.cppia] <module | file.cppia> [args...]
//  nekomata boot <file.n> [-o out]
// Named neko (neko.exe), it takes neko's command line instead, so it can stand in for
//  neko. With a module attached to it, by nekomata boot or nekotools boot, it runs that
//  module with all of its arguments.
// Neko code can recurse as deep as neko allows, so Windows gets a native stack that
//  matches: 256M reserved, committed only as it is used, for the main thread and
//  every thread the program starts
@:buildXml('<target id="haxe"><flag value="-STACK:268435456" if="windows"/></target>')
class Main {
	// The neko this host stands in for, as $version and neko -version give it
	static inline var VERSION = "2.4.1";

	static var moduleCount = 0;
	static var emitTo:Null<String>;

	static function main() {
		var args = Sys.args();
		// The JIT is on unless -interp or NEKOMATA_JIT=0 turns it off, the switch for what
		//  haxelib starts as neko, which takes no host options. Where it cannot get
		//  executable memory, modules run in the interpreter without a notice
		cpp.cppia.Host.enableJit(Sys.getEnv("NEKOMATA_JIT") != "0");
		if (!untyped __cpp__("__scriptable_cppia_jit_active()"))
			cpp.cppia.Host.enableJit(false);
		var exe = Sys.programPath();
		var attached = Launcher.attached(exe);
		if (attached != null) {
			var code = runAttached(exe, attached, args);
			if (code != 0)
				Sys.exit(code);
			return;
		}
		var neko = Launcher.isNeko(exe);
		var stats = false;
		// Options come before the module, as neko reads them; the rest is the program's
		while (args.length > 0) {
			switch args[0] {
				case "-interp":
					cpp.cppia.Host.enableJit(false);
				case "-jit":
					cpp.cppia.Host.enableJit(true);
				case "-stats":
					stats = true;
					NekoStats.enabled = true;
					NekoStats.measure("total", true);
				case "-version":
					Sys.println(VERSION);
					return;
				case "--emit" if (args.length > 1):
					emitTo = args[1];
					args.shift();
				default:
					break;
			}
			args.shift();
		}
		if (!neko && args[0] == "boot") {
			boot(args.slice(1));
			return;
		}
		if (args.length == 0) {
			if (neko)
				Sys.print('NekoVM $VERSION (c)2005-2025 Haxe Foundation\n  Usage : neko <file>\n');
			else
				usage();
			Sys.exit(1);
		}
		var file = args.shift();
		if (!neko && isCppia(file)) {
			cpp.cppia.Host.runFile(file);
			return;
		}
		var code = runNeko(file, args, stats);
		if (code != 0)
			Sys.exit(code);
	}

	static function usage() {
		Sys.println("usage: nekomata [-jit] [-interp] [-stats] [--emit file.cppia] <module | file.cppia> [args...]");
		Sys.println("       nekomata boot <file.n> [-o out]");
		Sys.println("       nekomata -version");
	}

	// A file that exists and is not neko bytecode; anything else goes to neko's loader,
	//  which looks for name.n and through NEKOPATH
	static function isCppia(file:String):Bool {
		if (!sys.FileSystem.exists(file) || sys.FileSystem.isDirectory(file))
			return false;
		var f = sys.io.File.read(file, true);
		var head = try f.read(4).toString() catch (e:Dynamic) "";
		f.close();
		return head != "NEKO";
	}

	// Ready to run translated code on this thread
	static function init() {
		Boot.prepareThread();
		// Filled before any neko thread can look them up
		nekomata.rt.NekoBuiltins.init();
		nekomata.rt.Primitives.init();
		NekoLoader.translate = translate;
		Emitter.builtinExists = h -> nekomata.rt.NekoBuiltins.find(h) != null;
	}

	// What neko's main does: the module from the loader's path, its args the rest
	static function runNeko(name:String, args:Array<String>, stats:Bool):Int {
		init();
		var loader = NekoLoader.create(args);
		var file = NekoLoader.moduleFile(loader.find(nekomata.neko.Hash.field("path")), name);
		Boot.programPath = sys.FileSystem.exists(file) ? sys.FileSystem.fullPath(file) : name;
		var code = 0;
		try {
			NekoLoader.run(loader, name);
		} catch (e:Dynamic) {
			report(e);
			code = 1;
		}
		if (stats) {
			NekoStats.measure("total", false);
			Sys.print(NekoStats.report());
		}
		return code;
	}

	static function runAttached(exe:String, bytes:Bytes, args:Array<String>):Int {
		init();
		var loader = NekoLoader.create(args);
		Boot.programPath = sys.FileSystem.fullPath(exe);
		try {
			NekoLoader.runSelf(loader, bytes);
		} catch (e:Dynamic) {
			report(e);
			return 1;
		}
		return 0;
	}

	// Uncaught exceptions print as neko prints them, after what the program printed
	static function report(e:Dynamic) {
		var report = nekomata.rt.NekoStack.report(e);
		Sys.stdout().flush();
		Sys.stderr().writeBytes(report, 0, report.length);
	}

	static function boot(args:Array<String>) {
		var out:Null<String> = null;
		var i = args.indexOf("-o");
		if (i >= 0 && i + 1 < args.length) {
			out = args[i + 1];
			args.splice(i, 2);
		}
		if (args.length != 1) {
			usage();
			Sys.exit(1);
		}
		try {
			Launcher.boot(args[0], out);
		} catch (e:Dynamic) {
			Sys.stderr().writeString('nekomata boot: $e\n');
			Sys.exit(1);
		}
	}

	// NEKOMATA_TIME=1 reports how long each module takes to read, translate and load
	static var timing = Sys.getEnv("NEKOMATA_TIME") == "1";

	// The class a module's code goes in: one per module loaded, all as long, so that a
	//  cached translation can take the name of the class it loads as
	static function className():String
		return "NekoModule" + StringTools.lpad(Std.string(moduleCount++), "0", 6);

	// Translates a module to cppia, or takes the cached translation, and loads it,
	//  returning what runs it
	static function translate(m:NModule, bytes:Bytes):() -> Void {
		var t0 = haxe.Timer.stamp();
		// The JIT's switch is a chain of tests, which the translation allows for
		var jit:Bool = untyped __cpp__("__scriptable_cppia_jit_active()");
		var cls = className();
		var key = Cache.enabled ? Cache.key(bytes, m.name, jit) : null;
		var cppia = key == null ? null : Cache.get(key, cls);
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
			var code = Reader.read(bytes);
			t1 = haxe.Timer.stamp();
			var t = Emitter.translate(code, cls, m.name, jit);
			cppia = t.cppia;
			t2 = haxe.Timer.stamp();
			if (key != null)
				Cache.put(key, cppia, t.classOffsets, cls.length);
		}
		if (emitTo != null) {
			sys.io.File.saveBytes(emitTo, cppia);
			emitTo = null;
		}
		if (!cached)
			module = cpp.cppia.Module.fromData(cppia.getData());
		var t3 = haxe.Timer.stamp();
		module.boot();
		if (timing) {
			inline function ms(a:Float, b:Float)
				return Std.string(Math.round((b - a) * 1000));
			var how = cached ? 'cached, loaded in ${ms(t0, t3)} ms' : 'read ${ms(t0, t1)} ms, translate ${ms(t1, t2)} ms, load ${ms(t2, t3)} ms';
			Sys.stderr().writeString('[nekomata] ${m.name}: ${cppia.length} bytes of cppia, $how\n');
		}
		return function() {
			Boot.pending = m;
			module.run();
		};
	}
}
