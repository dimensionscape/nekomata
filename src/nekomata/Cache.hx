package nekomata;

import haxe.io.Bytes;

// Translated modules, kept on disk so that a module loads without translating it again.
//  An entry is keyed by a hash of the module's bytecode, its name, whether it was
//  translated for the JIT and the sources of the host that translated it.
//
// NEKOMATA_CACHE names the directory; empty, 0 or off turns the cache off. By default
//  it is nekomata in %LOCALAPPDATA% on Windows, else in $XDG_CACHE_HOME or ~/.cache
@:cppFileCode('
// Two 64-bit hashes of the bytes, FNV-1a and a multiply-xorshift over 8-byte words
static void nk_hash128(const unsigned char *p, int n, unsigned long long *out)
{
   unsigned long long a = 14695981039346656037ULL;
   for(int i=0;i<n;i++)
   {
      a ^= p[i];
      a *= 1099511628211ULL;
   }
   unsigned long long b = 0x9E3779B97F4A7C15ULL ^ (unsigned long long)n;
   int i = 0;
   for(;i+8<=n;i+=8)
   {
      unsigned long long w;
      memcpy(&w, p+i, 8);
      b = (b ^ w) * 0xBF58476D1CE4E5B9ULL;
      b ^= b >> 31;
   }
   for(;i<n;i++)
   {
      b = (b ^ p[i]) * 0x94D049BB133111EBULL;
      b ^= b >> 29;
   }
   out[0] = a;
   out[1] = b;
}
')
class Cache {
	static inline var MAGIC = "NKC2";

	static var dir:Null<String> = findDir();
	static final sources = nekomata.build.SourceHash.get();

	static function findDir():Null<String> {
		var env = Sys.getEnv("NEKOMATA_CACHE");
		if (env != null)
			return env == "" || env == "0" || env.toLowerCase() == "off" ? null : env;
		if (Sys.systemName() == "Windows") {
			var local = Sys.getEnv("LOCALAPPDATA");
			return local == null ? null : local + "/nekomata/cache";
		}
		var xdg = Sys.getEnv("XDG_CACHE_HOME");
		if (xdg != null && xdg != "")
			return xdg + "/nekomata";
		var home = Sys.getEnv("HOME");
		return home == null ? null : home + "/.cache/nekomata";
	}

	public static var enabled(get, never):Bool;

	static inline function get_enabled()
		return dir != null;

	// The key for a module's bytecode, translated under name, for the JIT or not
	public static function key(bytecode:Bytes, name:String, jit:Bool):String {
		var hex:String = untyped __cpp__("[](const unsigned char *p, int n){ unsigned long long h[2]; nk_hash128(p, n, h); char b[40]; snprintf(b, 40, \"%016llx%016llx\", h[0], h[1]); return ::String(b); }((const unsigned char *){0}->GetBase(), {1})", bytecode.getData(), bytecode.length);
		return hex + "-" + haxe.crypto.Md5.encode(name + "\n" + (jit ? "jit" : "interp") + "\n" + sources);
	}

	static function path(key:String):String
		return dir + "/" + key + ".cppia";

	// An entry: the magic, how many class names the cppia has and how long their common
	//  start is, where each is, then the cppia

	// The cached cppia for key with its classes renamed to start with cls, or null. cls
	//  takes the place of the start the entry was written with, which is as long
	public static function get(key:String, cls:String):Null<Bytes> {
		try {
			var p = path(key);
			if (!sys.FileSystem.exists(p))
				return null;
			var data = sys.io.File.getBytes(p);
			if (data.length < 12 || data.getString(0, 4) != MAGIC)
				return null;
			var count = data.getInt32(4), len = data.getInt32(8);
			var start = 12 + 4 * count;
			var name = Bytes.ofString(cls);
			if (count < 0 || name.length != len || start > data.length)
				return null;
			var cppia = data.sub(start, data.length - start);
			for (i in 0...count) {
				var at = data.getInt32(12 + 4 * i);
				if (at < 0 || at + len > cppia.length)
					return null;
				cppia.blit(at, name, 0, len);
			}
			return cppia;
		} catch (e:Dynamic) {
			return null;
		}
	}

	// Keeps cppia for key, where the names of its classes start with len bytes, at
	//  offsets. Each entry is written whole under another name and then renamed, so
	//  another process never reads half of one
	public static function put(key:String, cppia:Bytes, offsets:Array<Int>, len:Int):Void {
		try {
			if (!sys.FileSystem.exists(dir))
				sys.FileSystem.createDirectory(dir);
			var start = 12 + 4 * offsets.length;
			var data = Bytes.alloc(start + cppia.length);
			data.blit(0, Bytes.ofString(MAGIC), 0, 4);
			data.setInt32(4, offsets.length);
			data.setInt32(8, len);
			for (i in 0...offsets.length)
				data.setInt32(12 + 4 * i, offsets[i]);
			data.blit(start, cppia, 0, cppia.length);
			var p = path(key);
			var tmp = p + "." + Std.random(0x7FFFFFFF) + ".tmp";
			sys.io.File.saveBytes(tmp, data);
			try {
				sys.FileSystem.rename(tmp, p);
			} catch (e:Dynamic) {
				if (sys.FileSystem.exists(tmp))
					sys.FileSystem.deleteFile(tmp);
			}
		} catch (e:Dynamic) {}
	}
}
