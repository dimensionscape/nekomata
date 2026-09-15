package nekomata;

import haxe.io.Bytes;
import sys.io.FileSeek;

// Executables with a neko module attached, in the format nekotools boot writes: the
//  executable, zeros up to a multiple of 4 bytes, the module, then "NEKO" and the
//  offset of the module as a 4-byte little-endian int
class Launcher {
	static inline var MAGIC = "NEKO";

	// Whether the host runs under neko's name, and so takes neko's command line
	public static function isNeko(exe:String):Bool {
		var cut = Std.int(Math.max(exe.lastIndexOf("/"), exe.lastIndexOf("\\")));
		var name = exe.substr(cut + 1).toLowerCase();
		if (StringTools.endsWith(name, ".exe"))
			name = name.substr(0, name.length - 4);
		return name == "neko";
	}

	static function isModule(b:Bytes, pos = 0):Bool
		return b.length - pos >= 4 && b.getString(pos, 4) == MAGIC;

	// Where an attached module starts, from the 8 bytes that end the file, or -1
	static function offset(trailer:Bytes, size:Int):Int {
		if (trailer.getString(0, 4) != MAGIC)
			return -1;
		var start = trailer.getInt32(4);
		return start >= 0 && start <= size - 12 ? start : -1;
	}

	// The module attached to an executable on disk, or null. Reads only its end, since
	//  every start of the host asks
	public static function attached(exe:String):Null<Bytes> {
		var f = try sys.io.File.read(exe, true) catch (e:Dynamic) null;
		if (f == null)
			return null;
		var result:Null<Bytes> = null;
		try {
			f.seek(0, SeekEnd);
			var size = f.tell();
			if (size >= 12) {
				f.seek(size - 8, SeekBegin);
				var start = offset(f.read(8), size);
				if (start >= 0) {
					f.seek(start, SeekBegin);
					var m = f.read(size - 8 - start);
					if (isModule(m))
						result = m;
				}
			}
		} catch (e:Dynamic) {
			result = null;
		}
		f.close();
		return result;
	}

	// The executable a file holds before any module attached to it, and that module
	static function split(b:Bytes):{exe:Bytes, module:Null<Bytes>} {
		if (b.length >= 12) {
			var start = offset(b.sub(b.length - 8, 8), b.length);
			if (start >= 0 && isModule(b, start))
				return {exe: b.sub(0, start), module: b.sub(start, b.length - 8 - start)};
		}
		return {exe: b, module: null};
	}

	// nekotools boot: the host with the module attached, by default named after the
	//  module without its extension. The module can also come from an executable
	//  that has one attached
	public static function boot(input:String, ?out:String):String {
		var data = sys.io.File.getBytes(input);
		var module = isModule(data) ? data : split(data).module;
		if (module == null)
			throw '$input is not a neko module';
		var self = Sys.programPath();
		var exe = split(sys.io.File.getBytes(self)).exe;
		var windows = Sys.systemName() == "Windows";
		if (out == null) {
			var cut = Std.int(Math.max(input.lastIndexOf("/"), input.lastIndexOf("\\")));
			var dot = input.lastIndexOf(".");
			out = (dot > cut ? input.substr(0, dot) : input) + (windows ? ".exe" : "");
		}
		if (sys.FileSystem.exists(out) && sys.FileSystem.fullPath(out) == sys.FileSystem.fullPath(self))
			throw 'cannot write over the running host $out';
		var b = new haxe.io.BytesBuffer();
		b.add(exe);
		while (b.length & 3 != 0)
			b.addByte(0);
		var start = b.length;
		b.add(module);
		b.addString(MAGIC);
		b.addInt32(start);
		sys.io.File.saveBytes(out, b.getBytes());
		if (!windows)
			Sys.command("chmod", ["755", out]);
		return out;
	}
}
