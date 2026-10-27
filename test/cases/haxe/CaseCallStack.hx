import haxe.CallStack;

class CaseCallStack {
	static function deepest():Array<StackItem>
		return CallStack.callStack();

	static function middle()
		return deepest();

	static function top()
		return middle();

	static function thrower(n:Int) {
		if (n == 0)
			throw "from thrower";
		thrower(n - 1);
	}

	static function describe(s:Array<StackItem>):String
		return [
			for (item in s)
				switch item {
					case FilePos(Method(cls, m), file, line, _): '$cls.$m ($file:$line)';
					case FilePos(LocalFunction(n), file, line, _): 'local $n ($file:$line)';
					case FilePos(null, file, line, _): '$file:$line';
					case FilePos(other, file, line, _): '$other ($file:$line)';
					case CFunction: "C function";
					case Module(m): 'module $m';
					case Method(cls, m): '$cls.$m';
					case LocalFunction(n): 'local $n';
				}
		].join("\n  ");

	static function main() {
		Sys.println("callStack:\n  " + describe(top()));
		try {
			thrower(3);
		} catch (e:Dynamic) {
			var s = CallStack.exceptionStack();
			Sys.println("exceptionStack:\n  " + describe(s));
			Sys.println("toString:" + CallStack.toString(s));
		}
		try {
			thrower(1);
		} catch (e:haxe.Exception) {
			Sys.println("exception.stack:\n  " + describe([for (i in 0...e.stack.length) e.stack[i]]));
			Sys.println("details: " + e.details());
		}
		var f = function() return CallStack.callStack().length > 0;
		Sys.println("local function sees a stack: " + f());
	}
}
