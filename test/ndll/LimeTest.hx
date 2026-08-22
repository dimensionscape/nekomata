// Calls lime.ndll's primitives that only report on the system or work on bytes, from
//  neko, after neko_init as lime's own neko tools call it. The argument is the library,
//  as neko.Lib.load names it: a path without .ndll
class LimeTest {
	static var lib:String;

	static function load(name:String, nargs:Int):Dynamic
		return neko.Lib.load(lib, name, nargs);

	// A primitive's result and its Haxe type, or what it threw. Neko throws a primitive's
	//  name when it returns a C NULL, as lime_system_get_platform_name does on Windows;
	//  under hxcpp's API that is null, as alloc_null() is, so it is left out here
	static function show(label:String, f:Void->Dynamic) {
		var text = try {
			var v = f();
			Std.string(v) + " (" + typeName(v) + ")";
		} catch (e:Dynamic) {
			"throws " + Std.string(e).split("@").pop();
		}
		Sys.println(label + ": " + text);
	}

	static function typeName(v:Dynamic):String {
		return switch Type.typeof(v) {
			case TClass(c): Type.getClassName(c);
			case t: Std.string(t);
		}
	}

	// Of the bytes up to the length: neko's glue gives a buffer one byte more of storage,
	//  which Md5 on neko, a primitive given the whole neko string, would count
	static function md5(b:haxe.io.Bytes):String
		return b == null ? "null" : b.length + " bytes, md5 " + haxe.crypto.Md5.make(b.sub(0, b.length)).toHex();

	static function main() {
		lib = Sys.args()[0];
		var init = load("neko_init", 5);
		init(function(s) return new String(s), function(len:Int) {
			var r = [];
			if (len > 0)
				r[len - 1] = null;
			return r;
		}, null, true, false);

		show("platform label", () -> load("lime_system_get_platform_label", 0)());
		show("platform version", () -> load("lime_system_get_platform_version", 0)());
		show("device model", () -> load("lime_system_get_device_model", 0)());
		show("device vendor", () -> load("lime_system_get_device_vendor", 0)());
		show("locale", () -> load("lime_locale_get_system_locale", 0)());
		// Desktop, fonts and user: lookups that create nothing
		for (type in [2, 4, 5])
			show("directory " + type, () -> load("lime_system_get_directory", 3)(type, "Nekomata", "LimeTest"));
		var timer:Dynamic = load("lime_system_get_timer", 0)();
		Sys.println("timer is a number: " + (Std.isOfType(timer, Float) && timer >= 0));

		// Bytes go both ways: lime reads and fills Haxe Bytes objects
		var file = Sys.args()[1];
		var read:haxe.io.Bytes = load("lime_bytes_read_file", 2)(file, haxe.io.Bytes.alloc(0));
		Sys.println("read " + file.split("/").pop() + ": " + md5(read));
		var text = haxe.io.Bytes.ofString("Nekomata runs neko on cppia. Nekomata runs neko on cppia.");
		for (codec in ["zlib", "deflate", "gzip", "lzma"]) {
			var packed:haxe.io.Bytes = load('lime_${codec}_compress', 2)(text, haxe.io.Bytes.alloc(0));
			var unpacked:haxe.io.Bytes = load('lime_${codec}_decompress', 2)(packed, haxe.io.Bytes.alloc(0));
			Sys.println(codec + ": " + md5(packed) + ", back: " + (unpacked == null ? "null" : unpacked.toString()));
		}
	}
}
