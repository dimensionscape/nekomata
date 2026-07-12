package nekomata.rt;

import nekomata.rt.Values;

// What a translated module's main calls to set itself up and run its body
@:keep
@:cppFileCode('
// libhxcpp gives each thread a fixed 128K stack for script frames, a few hundred
//  translated neko calls deep. Neko grows its stack to 256K values, so a thread swaps
//  in a bigger one before its first script frame. The GC scans only the used part
static void nk_grow_script_stack(int inSize)
{
   hx::StackContext *ctx = hx::StackContext::getCurrent();
   if (ctx->pointer != ctx->frame || ctx->frame != ctx->stack + sizeof(hx::Object *))
      return;
   unsigned char *old = ctx->stack;
   ctx->stack = new unsigned char[inSize];
   ctx->stackEnd = ctx->stack + inSize - 16*1024;
   ctx->pointer = ctx->stack;
   ctx->push((hx::Object *)0);
   ctx->frame = ctx->pointer;
   delete [] old;
}
')
class Boot {
	// Bytes of script stack each thread running neko code gets
	static inline var SCRIPT_STACK = 16 << 20;

	// Call on a thread before it runs any translated code
	public static function prepareThread():Void
		untyped __cpp__("nk_grow_script_stack({0})", SCRIPT_STACK);

	// The path of the module the host was asked to run, for std@sys_program_path
	public static var programPath:String;

	// The module the host is about to run. Its main takes it before running any code,
	//  so a module it loads in turn does not replace it
	public static var pending:NModule;

	public static function begin():NModule {
		var m = pending;
		pending = null;
		return m;
	}

	public static function run(m:NModule, globals:Array<Dynamic>, body:Dynamic):Void {
		m.globals = globals;
		Rt.finish(body(null, null));
	}

	public static function loader(m:NModule):NObject
		return m.loader;

	public static function exports(m:NModule):NObject
		return m.exports;
}
