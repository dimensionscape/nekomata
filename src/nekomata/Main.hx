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
// Neko code can recurse as deep as neko allows, so it gets a native stack that matches:
//  256M reserved, committed only as it is used. Windows sets it for the main thread and
//  every thread the program starts. Elsewhere the main thread keeps the 8M the system
//  gives it, so modules run on a thread of their own with that stack, and on Linux the
//  threads a program starts get it too
@:buildXml('<target id="haxe"><flag value="-STACK:268435456" if="windows"/></target>')
@:cppFileCode('
#ifndef _WIN32
#include <pthread.h>

static const size_t NK_STACK_SIZE = 256 << 20;

struct nk_stack_run
{
   ::Dynamic fn;
   int result;
   ::Dynamic thrown;
   bool threw;
};

static void *nk_stack_main(void *inArg)
{
   nk_stack_run *run = (nk_stack_run *)inArg;
   int top = 0;
   ::hx::SetTopOfStack(&top, true);
   try
   {
      run->result = run->fn();
   }
   catch(::Dynamic e)
   {
      run->thrown = e;
      run->threw = true;
   }
   ::hx::UnregisterCurrentThread();
   return 0;
}
#endif

// Runs inFn, which gives an exit code, with NK_STACK_SIZE of native stack; what it
//  throws is thrown on to the caller
static int nk_on_big_stack(::Dynamic inFn)
{
   #ifdef _WIN32
   return inFn();
   #else
   #ifdef __linux__
   static bool defaulted = false;
   if (!defaulted)
   {
      defaulted = true;
      pthread_attr_t def;
      if (pthread_getattr_default_np(&def) == 0)
      {
         pthread_attr_setstacksize(&def, NK_STACK_SIZE);
         pthread_setattr_default_np(&def);
         pthread_attr_destroy(&def);
      }
   }
   #endif
   nk_stack_run run;
   run.fn = inFn;
   run.result = 0;
   run.threw = false;
   ::hx::GCAddRoot(&run.fn.mPtr);
   ::hx::GCAddRoot(&run.thrown.mPtr);
   ::hx::GCPrepareMultiThreaded();
   pthread_attr_t attr;
   pthread_attr_init(&attr);
   pthread_attr_setstacksize(&attr, NK_STACK_SIZE);
   pthread_t t;
   bool started = pthread_create(&t, &attr, nk_stack_main, &run) == 0;
   pthread_attr_destroy(&attr);
   if (started)
   {
      ::hx::EnterGCFreeZone();
      pthread_join(t, 0);
      ::hx::ExitGCFreeZone();
   }
   ::Dynamic fn = run.fn, thrown = run.thrown;
   ::hx::GCRemoveRoot(&run.fn.mPtr);
   ::hx::GCRemoveRoot(&run.thrown.mPtr);
   if (!started)
      return fn();
   if (run.threw)
      ::hx::Throw(thrown);
   return run.result;
   #endif
}
')
class Main {
	// The neko this host stands in for, as $version and neko -version give it
	static inline var VERSION = "2.4.1";

	static var moduleCount = 0;
	static var emitTo:Null<String>;
	static var onBigStack = false;

	static function main() {
		var code = run(Sys.args());
		if (code != 0)
			Sys.exit(code);
	}

	// What the host does with its command line, or as neko with neko's, giving the exit
	//  code it ends with. A module that calls Sys.exit, or nekomata boot that fails, ends the
	//  process itself
	public static function run(args:Array<String>):Int
		return bigStack(() -> command(args.copy()));

	// Runs the neko module at path with args, as neko runs it: the exit code, with an
	//  exception nothing caught reported on stderr as neko reports it. The JIT is on
	//  unless NEKOMATA_JIT=0
	public static function runModule(path:String, args:Array<String>):Int
		return bigStack(() -> {
			setUpJit();
			return runNeko(path, args.copy(), false);
		});

	// What std@sys_exe_path gives, the host's own path unless set, as a program that runs
	//  modules inside itself can name the neko it stands in for
	public static function setExePath(path:Null<String>)
		Boot.exePath = path;

	static function bigStack(f:() -> Int):Int {
		if (onBigStack)
			return f();
		onBigStack = true;
		try {
			var code:Int = untyped __cpp__("nk_on_big_stack({0})", f);
			onBigStack = false;
			return code;
		} catch (e:Dynamic) {
			onBigStack = false;
			throw e;
		}
	}

	// The JIT is on unless -interp or NEKOMATA_JIT=0 turns it off, the switch for what
	//  haxelib starts as neko, which takes no host options. Where it cannot get
	//  executable memory, modules run in the interpreter without a notice
	static function setUpJit() {
		cpp.cppia.Host.enableJit(Sys.getEnv("NEKOMATA_JIT") != "0");
		if (!untyped __cpp__("__scriptable_cppia_jit_active()"))
			cpp.cppia.Host.enableJit(false);
	}

	static function command(args:Array<String>):Int {
		setUpJit();
		var exe = Sys.programPath();
		var attached = Launcher.attached(exe);
		if (attached != null)
			return runAttached(exe, attached, args);
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
					return 0;
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
			return 0;
		}
		if (args.length == 0) {
			if (neko)
				Sys.print('NekoVM $VERSION (c)2005-2025 Haxe Foundation\n  Usage : neko <file>\n');
			else
				usage();
			return 1;
		}
		var file = args.shift();
		if (!neko && isCppia(file)) {
			cpp.cppia.Host.runFile(file);
			return 0;
		}
		return runNeko(file, args, stats);
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
