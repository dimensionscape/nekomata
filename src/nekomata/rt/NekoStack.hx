package nekomata.rt;

import haxe.CallStack;
import nekomata.rt.Values;

// Neko's view of the call stack, from hxcpp's: the frames of translated neko code, and
//  "a C function" where a builtin or primitive called back into neko code
@:keep
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
					var file = StringTools.replace(escaped, nekomata.emit.Emitter.COLONS, "::");
					if (StringTools.startsWith(cls, "NekoModule")) {
						if (StringTools.endsWith(file, "@"))
							result.push(NString.of(file.substr(0, file.length - 1)));
						else {
							var pos:Array<Dynamic> = [NString.of(file), line];
							result.push(pos);
						}
					} else if (isNative(cls) && result.length > 0 && result[result.length - 1] != null)
						result.push(null);
				default:
			}
		// Calls a C function made on its way back out are not frames neko keeps
		while (result.length > 0 && result[result.length - 1] == null)
			result.pop();
		return result;
	}

	// Neko records where each frame made its call, outermost first. Every exception
	//  comes from a call or a runtime error, both of which record the innermost frame
	static function callSites(items:Array<StackItem>):Array<Dynamic> {
		var e = entries(items);
		e.reverse();
		return e;
	}

	// The neko stack where the last value was raised, as neko's vm->exc_stack starts
	static var thrown = new sys.thread.Tls<{value:Dynamic, stack:Array<Dynamic>}>();
	// What $excstack returns: the part of it inside the trap that caught the value
	static var caughtStack = new sys.thread.Tls<Array<Dynamic>>();

	public static function recordThrow(v:Dynamic):Void
		thrown.value = {value: v, stack: callSites(CallStack.callStack())};

	// The stack v was raised from; hxcpp's own record of the unwind for errors the host
	//  raised without the runtime, which hold fewer neko frames
	static function raisedFrom(v:Dynamic):Array<Dynamic> {
		var t = thrown.value;
		if (t != null && Rt.physEqual(t.value, v))
			return t.stack;
		return callSites(CallStack.exceptionStack());
	}

	// A trap caught v: neko keeps the frames from the catching function inward
	public static function catchAt(v:Dynamic):Void {
		var stack = raisedFrom(v);
		var depth = 0;
		for (e in entries(CallStack.callStack()))
			if (e != null)
				depth++;
		var seen = 0, start = 0;
		for (i in 0...stack.length)
			if (stack[i] != null && ++seen == depth) {
				start = i;
				break;
			}
		caughtStack.value = stack.slice(start);
	}

	// $excstack: the stack the exception last caught was raised from
	public static function excStack():Array<Dynamic> {
		var s = caughtStack.value;
		return s == null ? [] : s.copy();
	}

	// $callstack: the frames of the calls that led here
	public static function callStack():Array<Dynamic> {
		var e = entries(CallStack.callStack());
		e.reverse();
		return e;
	}

	// What neko prints for an exception nothing caught (vm/main.c report)
	public static function report(e:Dynamic):haxe.io.Bytes {
		var buf = new haxe.io.BytesBuffer();
		for (s in raisedFrom(e)) {
			buf.addString("Called from ");
			if (s == null)
				buf.addString("a C function");
			else if (Std.isOfType(s, NString)) {
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
