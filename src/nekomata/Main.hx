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
		if (args.remove("-jit"))
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

	// Translates a module to cppia and runs it, returning its exports
	static function load(name:String, bytes:haxe.io.Bytes, loader:NObject):NObject {
		var m = Reader.read(bytes);
		var text = Emitter.emit(m, 'NekoModule${moduleCount++}', name);
		if (emitTo != null) {
			sys.io.File.saveContent(emitTo, text);
			emitTo = null;
		}
		var nm = new NModule(name, loader);
		Boot.pending = nm;
		var module = cpp.cppia.Module.fromString(text);
		module.boot();
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
