package nekomata;

import haxe.io.Bytes;
import haxe.io.BytesData;
import nekomata.emit.Emitter;
import nekomata.neko.Reader;
import nekomata.rt.Boot;
import nekomata.rt.NekoLoader;
import nekomata.rt.Rt;
import nekomata.rt.Values;

// libhxcpp's cppia loader takes scripts in other formats from a translator the host
//  registers for their magic
extern class CppiaFormats {
	@:native("__scriptable_cppia_register_format")
	static function register(magic:String, translate:Null<(script:BytesData) -> Dynamic>):Void;
}

// Neko bytecode as a script format of the cppia host this is compiled into. The loader
//  hands a script that starts with NEKO to translate, and loads the cppia it returns,
//  so cpp.cppia.Module.fromData and Host.runFile, and with them the stock cppia host's
//  command line, run .n modules as they run .cppia scripts (cppia.hxml builds that host).
// Neko code can recurse as deep as neko allows, so Windows gets the native stack the
//  nekomata host has
@:buildXml('<target id="haxe"><flag value="-STACK:268435456" if="windows"/></target>')
@:keep
class CppiaFormat {
	static var moduleCount = 0;
	// The loader of the modules the host loads itself, made with the first of them
	static var loader:NObject;

	static function __init__()
		CppiaFormats.register("NEKO", translate);

	// The translator libhxcpp calls, for a module the host loads itself. The first is
	//  the program, as neko's main runs it: named on the host's command line, with the
	//  arguments that follow it
	static function translate(script:BytesData):Dynamic {
		// What cpp.cppia.Host.main takes for itself
		var args = Sys.args();
		args.remove("-jit");
		var file = args.shift();
		if (file == null)
			file = "";
		var m:NModule;
		if (loader == null) {
			if (file != "")
				Boot.programPath = sys.FileSystem.fullPath(file);
			Boot.prepareThread();
			// Filled before any neko thread can look them up
			nekomata.rt.NekoBuiltins.init();
			nekomata.rt.Primitives.init();
			NekoLoader.loadModule = loadModule;
			loader = NekoLoader.create(args);
			m = new NModule(file, loader);
			Boot.program = m;
		} else
			m = new NModule(file, loader);
		return emit(m, Bytes.ofData(script));
	}

	// The cppia for a module that runs as m, which its main takes once it runs
	static function emit(m:NModule, bytes:Bytes):String {
		var text = Emitter.emit(Reader.read(bytes), 'NekoModule${moduleCount++}', m.name);
		Boot.pending = m;
		return text;
	}

	// What $loader.loadmodule runs: name.n, translated and run, giving its exports
	static function loadModule(name:String, loader:NObject):NObject {
		var file = StringTools.endsWith(name, ".n") ? name : name + ".n";
		if (!sys.FileSystem.exists(file))
			// Neko's message carries where in its loader it failed
			Rt.error("load.c(181) : Module not found : " + name);
		var m = new NModule(name, loader);
		var module = cpp.cppia.Module.fromString(emit(m, sys.io.File.getBytes(file)));
		module.boot();
		module.run();
		return m.exports;
	}
}
