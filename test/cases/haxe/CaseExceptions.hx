import haxe.Exception;

class MyError extends Exception {
	public var code:Int;

	public function new(msg:String, code:Int, ?previous:Exception) {
		super(msg, previous);
		this.code = code;
	}
}

class OtherError extends MyError {}

enum Failure {
	Bad(reason:String);
}

class CaseExceptions {
	static function level3(kind:Int):Int {
		switch kind {
			case 0:
				throw "a string";
			case 1:
				throw 42;
			case 2:
				throw new MyError("my error", 7);
			case 3:
				throw new OtherError("other", 8);
			case 4:
				throw Bad("enum value");
			case 5:
				throw {field: "anonymous"};
			case 6:
				var a:Array<Int> = null;
				return a[0];
			case 7:
				var o:Dynamic = null;
				return o.field;
			case 8:
				throw new haxe.exceptions.NotImplementedException();
			case 9:
				throw new haxe.exceptions.ArgumentException("arg", "bad argument");
			case 10:
				return Std.parseInt(null) + 1;
		}
		return -1;
	}

	static function level2(kind:Int)
		return level3(kind) + 1;

	static function level1(kind:Int)
		return level2(kind) * 2;

	static function main() {
		for (kind in 0...11) {
			try {
				Sys.println('$kind returned ${level1(kind)}');
			} catch (e:OtherError) {
				Sys.println('$kind OtherError ${e.message} ${e.code}');
			} catch (e:MyError) {
				Sys.println('$kind MyError ${e.message} ${e.code} ${Std.isOfType(e, Exception)}');
			} catch (e:String) {
				Sys.println('$kind String $e');
			} catch (e:Int) {
				Sys.println('$kind Int $e');
			} catch (e:Failure) {
				Sys.println('$kind Failure $e');
			} catch (e:haxe.exceptions.NotImplementedException) {
				Sys.println('$kind NotImplemented ${e.message}');
			} catch (e:Exception) {
				Sys.println('$kind Exception ${Type.getClassName(Type.getClass(e))} [${e.message}]');
			} catch (e:Dynamic) {
				Sys.println('$kind Dynamic ${Std.string(e)}');
			}
		}
		try {
			try {
				throw new MyError("inner", 1);
			} catch (e:MyError) {
				throw new MyError("outer", 2, e);
			}
		} catch (e:MyError) {
			Sys.println(e.message + " caused by " + e.previous.message + " " + e.toString());
		}
		try {
			try {
				throw "rethrown string";
			} catch (e) {
				Sys.println("caught as Exception: " + e.message + " " + Type.getClassName(Type.getClass(e)));
				throw e;
			}
		} catch (e:String) {
			Sys.println("caught again as String: " + e);
		}
		var e = new Exception("wrapped");
		Sys.println(e.message + " " + e.toString() + " " + (e.native != null));
		var finallyLog = [];
		function withCleanup(fail:Bool) {
			try {
				finallyLog.push("start");
				if (fail)
					throw "fail";
				finallyLog.push("end");
			} catch (e:String) {
				finallyLog.push("caught " + e);
			}
			finallyLog.push("after");
		}
		withCleanup(false);
		withCleanup(true);
		Sys.println(finallyLog);
		var count = 0;
		for (i in 0...10000) {
			try {
				if (i % 3 == 0)
					throw i;
				count++;
			} catch (n:Int) {
				count += 100;
			}
		}
		Sys.println("loop " + count);
		Sys.println(try level1(1) catch (n:Int) n * 1000);
	}
}
