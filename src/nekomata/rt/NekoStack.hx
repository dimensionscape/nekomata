package nekomata.rt;

import haxe.CallStack;
import nekomata.rt.Values;

// Neko's view of the call stack, from hxcpp's: the frames of translated neko code, and
//  "a C function" where a builtin or primitive called back into neko code
@:keep
@:cppFileCode('
#include <string.h>

static bool nk_starts(const char *inText, const char *inPrefix)
{
   return inText && strncmp(inText, inPrefix, strlen(inPrefix)) == 0;
}

// Classes whose frames stand for neko C functions
static bool nk_native_class(const char *inClass)
{
   return nk_starts(inClass, "nekomata.rt.prims.") || (inClass && (!strcmp(inClass, "nekomata.rt.NekoBuiltins") ||
      !strcmp(inClass, "nekomata.rt.Primitives") || !strcmp(inClass, "nekomata.rt.StdPrims")));
}

// The frames of this thread as neko sees them, innermost first: [file, line] for a frame of
//  translated code, with the file as the emitter wrote it, and null for a C function
//  that called back into neko code. Read straight from the frames, without the text
//  CallStack makes of every frame
static ::Array< ::Dynamic > nk_raw_frames()
{
   ::Array< ::Dynamic > out = ::Array_obj< ::Dynamic >::__new(0, 8);
   hx::StackContext *ctx = hx::StackContext::getCurrent();
   bool lastNull = true;
   for (int i = ctx->getDepth() - 1; i >= 0; i--)
   {
      hx::StackFrame *f = ctx->getStackFrame(i);
      const char *cls = f->position->className;
      if (nk_starts(cls, "NekoModule"))
      {
         ::Array< ::Dynamic > e = ::Array_obj< ::Dynamic >::__new(2, 2);
         e[0] = ::String::create(f->position->fileName);
         e[1] = f->lineNumber;
         out->push(e);
         lastNull = false;
      }
      else if (!lastNull && nk_native_class(cls))
      {
         out->push(::Dynamic());
         lastNull = true;
      }
   }
   // Calls a C function made on its way back out are not frames neko keeps
   while (out->length > 0 && out[out->length - 1] == null())
      out->pop();
   return out;
}

// How many frames of translated code this thread has
static int nk_neko_depth()
{
   hx::StackContext *ctx = hx::StackContext::getCurrent();
   int depth = 0;
   for (int i = ctx->getDepth() - 1; i >= 0; i--)
      if (nk_starts(ctx->getStackFrame(i)->position->className, "NekoModule"))
         depth++;
   return depth;
}
')
class NekoStack {
	// Classes whose frames stand for neko's C functions
	static function isNative(cls:String):Bool
		return cls == "nekomata.rt.NekoBuiltins" || cls == "nekomata.rt.Primitives" || cls == "nekomata.rt.StdPrims"
			|| StringTools.startsWith(cls, "nekomata.rt.prims.");

	// A neko stack entry: [file, line], a module name for code without debug info, or
	//  null for a C function. Innermost first, as hxcpp lists frames
	static function entries(items:Array<StackItem>):Array<Dynamic> {
		var result:Array<Dynamic> = [];
		for (item in items)
			switch item {
				case FilePos(Method(cls, _), escaped, line, _):
					if (StringTools.startsWith(cls, "NekoModule")) {
						var raw:Array<Dynamic> = [escaped, line];
						result.push(raw);
					} else if (isNative(cls) && result.length > 0 && result[result.length - 1] != null)
						result.push(null);
				default:
			}
		while (result.length > 0 && result[result.length - 1] == null)
			result.pop();
		return result;
	}

	// The neko entry for a raw frame: [file, line], or the module name for code without
	//  debug info
	static function entry(raw:Dynamic):Dynamic {
		if (raw == null)
			return null;
		var r:Array<Dynamic> = raw;
		var file = nekomata.emit.Emitter.unescapeFile(r[0]);
		if (StringTools.endsWith(file, "@"))
			return NString.of(file.substr(0, file.length - 1));
		var pos:Array<Dynamic> = [NString.of(file), r[1]];
		return pos;
	}

	// Neko records where each frame made its call, outermost first. Every exception
	//  comes from a call or a runtime error, both of which record the innermost frame
	static function callSites(raw:Array<Dynamic>):Array<Dynamic> {
		var e = [for (r in raw) entry(r)];
		e.reverse();
		return e;
	}

	static function rawFrames():Array<Dynamic>
		return untyped __cpp__("nk_raw_frames()");

	// The neko stack where the last value was raised, as neko's vm->exc_stack starts,
	//  kept raw until something reads it
	static var thrown = new sys.thread.Tls<{value:Dynamic, raw:Array<Dynamic>}>();
	// What $excstack returns: the part of it inside the trap that caught the value
	static var caughtStack = new sys.thread.Tls<Array<Dynamic>>();

	public static function recordThrow(v:Dynamic):Void
		thrown.value = {value: v, raw: rawFrames()};

	// $rethrow keeps what neko's exc_stack held, the frames the last caught value was
	//  raised through, and adds the frames it is raised from now
	public static function recordRethrow(v:Dynamic):Void {
		var caught = caughtRaw.value;
		thrown.value = {value: v, raw: caught == null ? rawFrames() : caught.concat(rawFrames())};
	}

	// The raw stack v was raised from; hxcpp's own record of the unwind for errors the
	//  host raised without the runtime, which hold fewer neko frames
	static function rawRaisedFrom(v:Dynamic):Array<Dynamic> {
		var t = thrown.value;
		if (t != null && Rt.physEqual(t.value, v))
			return t.raw;
		return entries(CallStack.exceptionStack());
	}

	static function raisedFrom(v:Dynamic):Array<Dynamic>
		return callSites(rawRaisedFrom(v));

	// A trap caught v: neko keeps the frames from the catching function inward. The
	//  entries are made when $excstack reads them
	public static function catchAt(v:Dynamic):Void {
		var raw = rawRaisedFrom(v);
		var depth:Int = untyped __cpp__("nk_neko_depth()");
		// Outermost first, the part from the catching function's frame on
		var seen = 0, end = raw.length;
		var i = raw.length;
		while (i-- > 0)
			if (raw[i] != null && ++seen == depth) {
				end = i + 1;
				break;
			}
		caughtRaw.value = raw.slice(0, end);
		caughtStack.value = null;
	}

	static var caughtRaw = new sys.thread.Tls<Array<Dynamic>>();

	// $excstack: the stack the exception last caught was raised from
	public static function excStack():Array<Dynamic> {
		var s = caughtStack.value;
		if (s == null) {
			var raw = caughtRaw.value;
			if (raw == null)
				return [];
			s = callSites(raw);
			caughtStack.value = s;
		}
		return s.copy();
	}

	// $callstack: the frames of the calls that led here
	public static function callStack():Array<Dynamic>
		return callSites(rawFrames());

	// What neko prints for an exception nothing caught (vm/main.c report)
	public static function report(e:Dynamic):haxe.io.Bytes {
		var buf = new haxe.io.BytesBuffer();
		for (s in raisedFrom(e)) {
			buf.addString("Called from ");
			if (s == null)
				buf.addString("a C function");
			else if (Rt.isNString(s)) {
				buf.add((s : NString).b);
				buf.addString(" (no debug available)");
			} else {
				var pos:Array<Dynamic> = s;
				Rt.appendValue(buf, pos[0]);
				buf.addString(" line ");
				Rt.appendValue(buf, pos[1]);
			}
			buf.addString("\n");
		}
		buf.addString("Uncaught exception - ");
		Rt.appendValue(buf, Rt.caught(e));
		buf.addString("\n");
		return buf.getBytes();
	}
}
