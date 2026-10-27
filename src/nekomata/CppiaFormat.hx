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
// Neko code can recurse as deep as neko allows, so the host gets the 256M native stack
//  the nekomata host has: through the linker on Windows and macOS, and on Linux, where
//  the main thread grows as far as RLIMIT_STACK said when the program started, by
//  raising that and starting again
@:buildXml('<target id="haxe">
	<flag value="-STACK:268435456" if="windows"/>
	<flag value="-Wl,-stack_size,0x10000000" if="macos"/>
</target>')
@:cppFileCode('
#ifdef __linux__
#include <sys/resource.h>
#include <string.h>
#include <unistd.h>
#include <stdio.h>
#include <vector>
#include <string>

static void nk_big_main_stack()
{
   const rlim_t want = (rlim_t)256 << 20;
   struct rlimit r;
   if (getrlimit(RLIMIT_STACK, &r) != 0 || r.rlim_cur == RLIM_INFINITY || r.rlim_cur >= want)
      return;
   if (r.rlim_max != RLIM_INFINITY && r.rlim_max < want)
      return;
   FILE *f = fopen("/proc/self/cmdline", "rb");
   if (!f)
      return;
   std::string all;
   char buf[4096];
   size_t n;
   while ((n = fread(buf, 1, sizeof(buf), f)) > 0)
      all.append(buf, n);
   fclose(f);
   std::vector<char *> argv;
   for (size_t i = 0; i < all.size(); i += strlen(&all[i]) + 1)
      argv.push_back(&all[i]);
   argv.push_back(0);
   r.rlim_cur = want;
   if (setrlimit(RLIMIT_STACK, &r) != 0)
      return;
   execv("/proc/self/exe", &argv[0]);
}
#else
static void nk_big_main_stack() { }
#endif
')
@:keep
class CppiaFormat {
	static var moduleCount = 0;
	// The loader of the program, made with the first module the host loads
	static var loader:NObject;

	static function __init__() {
		untyped __cpp__("nk_big_main_stack()");
		CppiaFormats.register("NEKO", translate);
	}

	// The translation for the JIT when it is on, whose switch is a chain of tests
	static function emit(m:NModule, bytes:Bytes):Bytes {
		var jit:Bool = untyped __cpp__("__scriptable_cppia_jit_active()");
		var cls = "NekoModule" + StringTools.lpad(Std.string(moduleCount++), "0", 6);
		return Emitter.emit(Reader.read(bytes), cls, m.name, jit);
	}

	// What NekoLoader runs for a module the program loads in turn
	static function load(m:NModule, bytes:Bytes):() -> Void {
		var module = cpp.cppia.Module.fromData(emit(m, bytes).getData());
		module.boot();
		return function() {
			Boot.pending = m;
			module.run();
		};
	}

	// The translator libhxcpp calls for a module the host loads itself: the program,
	//  as neko's main runs it, named on the host's command line with the arguments
	//  that follow it, and cached by the loader under that name
	static function translate(script:BytesData):Dynamic {
		// What cpp.cppia.Host.main takes for itself
		var args = Sys.args();
		args.remove("-jit");
		var file = args.shift();
		if (file == null)
			file = "";
		if (loader == null) {
			if (file != "")
				Boot.programPath = sys.FileSystem.fullPath(file);
			Boot.prepareThread();
			// Filled before any neko thread can look them up
			nekomata.rt.NekoBuiltins.init();
			nekomata.rt.Primitives.init();
			Emitter.builtinExists = h -> nekomata.rt.NekoBuiltins.find(h) != null;
			NekoLoader.translate = load;
			loader = NekoLoader.create(args);
		}
		var m = new NModule(file, loader);
		nekomata.rt.prims.StdModule.attach(m);
		var cache:NObject = loader.find(nekomata.neko.Hash.field("cache"));
		Rt.registerFields([file]);
		cache.fields.set(nekomata.neko.Hash.field(file), nekomata.rt.prims.StdModule.handle(m));
		Boot.program = m;
		var cppia = emit(m, Bytes.ofData(script));
		Boot.pending = m;
		return cppia.getData();
	}
}
