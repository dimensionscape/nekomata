package nekomata;

import haxe.io.Bytes;
import nekomata.neko.Reader;
import nekomata.emit.Emitter;
import nekomata.rt.Boot;
import nekomata.rt.NekoLoader;
import nekomata.rt.NekoStats;
import nekomata.rt.Values;

// The Nekomata host: runs neko .n modules and cppia scripts.
//  nekomata [-jit] [--emit file.cppia] <module | file.cppia> [args...]
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
		// What haxelib starts as neko takes no host options, so the JIT has a switch here
		if (Sys.getEnv("NEKOMATA_JIT") == "1")
			cpp.cppia.Host.enableJit(true);
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

	// Translates a module to cppia and loads it, returning what runs it
	static function translate(m:NModule, bytes:Bytes):() -> Void {
		var text = Emitter.emit(Reader.read(bytes), 'NekoModule${moduleCount++}', m.name);
		if (emitTo != null) {
			sys.io.File.saveContent(emitTo, text);
			emitTo = null;
		}
		var module = cpp.cppia.Module.fromString(text);
		module.boot();
		return function() {
			Boot.pending = m;
			module.run();
		};
	}
}
