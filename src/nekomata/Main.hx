package nekomata;

import nekomata.neko.Reader;
import nekomata.emit.Emitter;
import nekomata.rt.Boot;
import nekomata.rt.NekoLoader;
import nekomata.rt.Rt;
import nekomata.rt.Values;

// The Nekomata host: runs neko .n modules and cppia scripts.
//  nekomata [-jit] [--emit file.cppia] <file.n | file.cppia> [args...]
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
		var loader = NekoLoader.create(args);
		NekoLoader.loadModule = loadModuleFile;
		try {
			load(file, bytes, loader);
		} catch (e:Dynamic) {
			var out = Sys.stderr();
			out.writeString("Uncaught exception - ");
			var b = Rt.valueBytes(Rt.caught(e));
			out.writeBytes(b, 0, b.length);
			out.writeString("\n");
			Sys.exit(1);
		}
	}

	// Translates a module to cppia and runs it, returning its exports
	static function load(name:String, bytes:haxe.io.Bytes, loader:NObject):NObject {
		var m = Reader.read(bytes);
		var text = Emitter.emit(m, 'NekoModule${moduleCount++}');
		if (emitTo != null) {
			sys.io.File.saveContent(emitTo, text);
			emitTo = null;
		}
		Boot.pendingName = name;
		Boot.pendingLoader = loader;
		var module = cpp.cppia.Module.fromString(text);
		module.boot();
		module.run();
		return Boot.last.exports;
	}

	static function loadModuleFile(name:String, loader:NObject):NObject {
		var file = StringTools.endsWith(name, ".n") ? name : name + ".n";
		if (!sys.FileSystem.exists(file))
			Rt.error("Module not found : " + name);
		return load(name, sys.io.File.getBytes(file), loader);
	}
}
