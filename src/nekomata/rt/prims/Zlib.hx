package nekomata.rt.prims;

import haxe.io.Bytes;
import haxe.io.BytesData;
import nekomata.rt.Values;
import nekomata.rt.Primitives.add;
import nekomata.rt.prims.Conv.*;

@:include("hx/StdLibs.h")
extern class NativeZlib {
	@:native("_hx_deflate_init")
	static function deflateOpen(level:Int):Dynamic;
	@:native("_hx_deflate_buffer")
	static function deflateBuffer(handle:Dynamic, src:BytesData, srcPos:Int, dst:BytesData, dstPos:Int):Dynamic;
	@:native("_hx_deflate_end")
	static function deflateClose(handle:Dynamic):Void;
	@:native("_hx_inflate_init")
	static function inflateOpen(windowBits:Dynamic):Dynamic;
	@:native("_hx_inflate_buffer")
	static function inflateBuffer(handle:Dynamic, src:BytesData, srcPos:Int, dst:BytesData, dstPos:Int):Dynamic;
	@:native("_hx_inflate_end")
	static function inflateClose(handle:Dynamic):Void;
	@:native("_hx_zip_set_flush_mode")
	static function setFlushMode(handle:Dynamic, mode:String):Void;
}

// libs/zlib, on libhxcpp's port of it. Its API has no checksums and keeps each stream's
//  z_stream to itself, so the checksums, get_adler32 and deflate_bound call zlib directly
@:keep
@:buildXml('<include name="${HXCPP}/src/hx/libs/zlib/Build.xml"/>')
@:cppFileCode('
#include <hx/zip/Zip.hpp>

// zlib.h is not on the include path of Haxe code, and adding it would change the
//  flags, and so the precompiled header, of every file. These match its declarations
struct nk_z_stream
{
   const unsigned char *next_in;
   unsigned int avail_in;
   unsigned long total_in;
   unsigned char *next_out;
   unsigned int avail_out;
   unsigned long total_out;
   const char *msg;
   void *state;
   void *zalloc;
   void *zfree;
   void *opaque;
   int data_type;
   unsigned long adler;
   unsigned long reserved;
};

extern "C" unsigned long crc32(unsigned long crc, const unsigned char *buf, unsigned int len);
extern "C" unsigned long adler32(unsigned long adler, const unsigned char *buf, unsigned int len);
extern "C" unsigned long deflateBound(nk_z_stream *strm, unsigned long sourceLen);

// The ZLibCompress and ZLibUncompress classes of libhxcpp (src/hx/zip/zlib) hold
//  their z_stream first, after the Zip_obj base
struct nk_zlib_stream_obj : hx::zip::Zip_obj
{
   nk_z_stream *handle;
};

static nk_z_stream *nk_zlib_stream(::Dynamic inHandle)
{
   return static_cast<nk_zlib_stream_obj *>(inHandle.mPtr)->handle;
}

static int nk_zlib_adler(::Dynamic inHandle)
{
   return (int)nk_zlib_stream(inHandle)->adler;
}

static int nk_zlib_avail(::Dynamic inHandle, bool inOut)
{
   nk_z_stream *z = nk_zlib_stream(inHandle);
   return (int)(inOut ? z->avail_out : z->avail_in);
}

static int nk_zlib_bound(::Dynamic inHandle, int inSize)
{
   return (int)deflateBound(nk_zlib_stream(inHandle), inSize);
}

// An empty string has no buffer. Neko passes a pointer to its terminator, and zlib
//  treats a null buffer differently
static const unsigned char nk_zlib_none = 0;

static const unsigned char *nk_zlib_bytes(Array<unsigned char> inBytes, int inPos)
{
   return inBytes->length == 0 ? &nk_zlib_none : (const unsigned char *)inBytes->getBase() + inPos;
}

static int nk_zlib_crc32(int inCrc, Array<unsigned char> inBytes, int inPos, int inLen)
{
   return (int)crc32(inCrc, nk_zlib_bytes(inBytes, inPos), (unsigned int)inLen);
}

static int nk_zlib_adler32(int inAdler, Array<unsigned char> inBytes, int inPos, int inLen)
{
   return (int)adler32(inAdler, nk_zlib_bytes(inBytes, inPos), (unsigned int)inLen);
}
')
class Zlib {
	static final deflateKind = new NObject();
	static final inflateKind = new NObject();
	static final flushModes = ["NO", "SYNC", "FULL", "FINISH", "BLOCK"];
	// Z_NEED_DICT, a stream that wants a preset dictionary
	static inline var NEED_DICT = 2;

	// What an empty neko string becomes in a stream call, at offset 1: zlib refuses a
	//  null output buffer, which is what an empty BytesData has
	static final none:BytesData = Bytes.alloc(1).getData();

	static function isKind(v:Dynamic, kind:Dynamic):Bool
		return Std.isOfType(v, NAbstract) && (v : NAbstract).kind == kind;

	// A stream of either kind, which set_flush_mode and get_adler32 take
	static function anyStream(v:Dynamic, prim:String):Dynamic
		return isKind(v, inflateKind) ? (v : NAbstract).data : data(v, deflateKind, prim);

	// The code and message of an error libhxcpp raised for zlib, which it words as
	//  "ZLib Error <code> (<msg>)"
	static function zlibError(e:Dynamic):Null<{code:Int, msg:Null<String>}> {
		if (!Std.isOfType(e, String))
			return null;
		var s:String = e;
		if (!StringTools.startsWith(s, "ZLib Error "))
			return null;
		var rest = s.substr(11);
		var paren = rest.indexOf(" (");
		var code = Std.parseInt(paren < 0 ? rest : rest.substr(0, paren));
		if (code == null)
			return null;
		return {code: code, msg: paren < 0 ? null : rest.substring(paren + 2, rest.length - 1)};
	}

	// Rethrows an error from libhxcpp as neko words it. Neko leaves the message out
	//  when opening a stream fails
	static function raise(e:Dynamic, withMsg:Bool):Dynamic {
		var err = zlibError(e);
		if (err == null)
			return Rt.raise(fromHost(e));
		var text = withMsg && err.msg != null ? 'ZLib Error : ${err.msg} (${err.code})' : 'ZLib Error : ${err.code}';
		return Rt.raise(NString.of(text));
	}

	static function result(done:Bool, read:Int, write:Int):NObject
		return object([{name: "done", value: done}, {name: "read", value: read}, {name: "write", value: write}]);

	static function buffer(prim:String, inflating:Bool, s:Dynamic, src:Dynamic, srcPos:Dynamic, dst:Dynamic, dstPos:Dynamic):NObject {
		var h = data(s, inflating ? inflateKind : deflateKind, prim);
		var sb = bytes(src, prim), sp = int(srcPos, prim), db = bytes(dst, prim), dp = int(dstPos, prim);
		if (sp < 0 || dp < 0 || sp > sb.length || dp > db.length)
			Primitives.fail(prim);
		var sd = sb.getData(), dd = db.getData();
		if (sb.length == 0) {
			sd = none;
			sp = 1;
		}
		if (db.length == 0) {
			dd = none;
			dp = 1;
		}
		var r:Dynamic;
		try {
			r = inflating ? NativeZlib.inflateBuffer(h, sd, sp, dd, dp) : NativeZlib.deflateBuffer(h, sd, sp, dd, dp);
		} catch (e:Dynamic) {
			// libhxcpp stops at a stream that wants a preset dictionary; neko returns
			//  what it read up to there, as for any call that is not an error
			var err = zlibError(e);
			if (inflating && err != null && err.code == NEED_DICT) {
				var availIn:Int = untyped __cpp__("nk_zlib_avail({0}, false)", h);
				var availOut:Int = untyped __cpp__("nk_zlib_avail({0}, true)", h);
				return result(false, sd.length - sp - availIn, dd.length - dp - availOut);
			}
			return raise(e, true);
		}
		var done:Bool = r.done, read:Int = r.read, write:Int = r.write;
		return result(done, read, write);
	}

	// A neko string as the C string neko compares, up to its first NUL
	static function flushMode(b:Bytes, prim:String):String {
		var n = 0;
		while (n < b.length && b.get(n) != 0)
			n++;
		for (m in flushModes) {
			if (m.length != n)
				continue;
			var same = true;
			for (i in 0...n)
				if (b.get(i) != m.charCodeAt(i)) {
					same = false;
					break;
				}
			if (same)
				return m;
		}
		return Primitives.fail(prim);
	}

	// Neko's checksums take only boxed int32 values; ints and int32 values are the same
	//  here, so any int passes
	static function checkRange(b:Bytes, p:Dynamic, l:Dynamic, prim:String):{pos:Int, len:Int} {
		var pos = int(p, prim), len = int(l, prim);
		if (pos < 0 || len < 0 || pos > b.length - len)
			Primitives.fail(prim);
		return {pos: pos, len: len};
	}

	public static function register() {
		add("zlib@deflate_init", 1, function(l:Dynamic) {
			var level = int(l, "zlib@deflate_init");
			var h:Dynamic;
			try {
				h = NativeZlib.deflateOpen(level);
			} catch (e:Dynamic) {
				return raise(e, false);
			}
			return new NAbstract(deflateKind, h);
		});
		add("zlib@deflate_buffer", 5, (s:Dynamic, src:Dynamic, sp:Dynamic, dst:Dynamic, dp:Dynamic) -> buffer("zlib@deflate_buffer", false, s, src, sp, dst, dp));
		add("zlib@deflate_end", 1, function(s:Dynamic) {
			NativeZlib.deflateClose(data(s, deflateKind, "zlib@deflate_end"));
			// Neko clears the kind of a closed stream, so every primitive refuses it
			(s : NAbstract).kind = null;
			return null;
		});
		add("zlib@deflate_bound", 2, function(s:Dynamic, n:Dynamic) {
			var h = data(s, deflateKind, "zlib@deflate_bound"), size = int(n, "zlib@deflate_bound");
			var bound:Int = untyped __cpp__("nk_zlib_bound({0}, {1})", h, size);
			return bound;
		});
		add("zlib@inflate_init", 1, function(w:Dynamic) {
			var bits:Dynamic = w == null ? null : int(w, "zlib@inflate_init");
			var h:Dynamic;
			try {
				h = NativeZlib.inflateOpen(bits);
			} catch (e:Dynamic) {
				return raise(e, false);
			}
			return new NAbstract(inflateKind, h);
		});
		add("zlib@inflate_buffer", 5, (s:Dynamic, src:Dynamic, sp:Dynamic, dst:Dynamic, dp:Dynamic) -> buffer("zlib@inflate_buffer", true, s, src, sp, dst, dp));
		add("zlib@inflate_end", 1, function(s:Dynamic) {
			NativeZlib.inflateClose(data(s, inflateKind, "zlib@inflate_end"));
			(s : NAbstract).kind = null;
			return null;
		});
		add("zlib@set_flush_mode", 2, function(s:Dynamic, f:Dynamic) {
			var h = anyStream(s, "zlib@set_flush_mode");
			var mode = flushMode(bytes(f, "zlib@set_flush_mode"), "zlib@set_flush_mode");
			NativeZlib.setFlushMode(h, mode);
			return null;
		});
		add("zlib@get_adler32", 1, function(s:Dynamic) {
			var h = anyStream(s, "zlib@get_adler32");
			var adler:Int = untyped __cpp__("nk_zlib_adler({0})", h);
			return adler;
		});
		add("zlib@update_adler32", 4, function(a:Dynamic, s:Dynamic, p:Dynamic, l:Dynamic) {
			var adler = int(a, "zlib@update_adler32"), b = bytes(s, "zlib@update_adler32");
			var r = checkRange(b, p, l, "zlib@update_adler32");
			var d = b.getData();
			var sum:Int = untyped __cpp__("nk_zlib_adler32({0}, {1}, {2}, {3})", adler, d, r.pos, r.len);
			return sum;
		});
		add("zlib@update_crc32", 4, function(c:Dynamic, s:Dynamic, p:Dynamic, l:Dynamic) {
			var crc = int(c, "zlib@update_crc32"), b = bytes(s, "zlib@update_crc32");
			var r = checkRange(b, p, l, "zlib@update_crc32");
			var d = b.getData();
			var sum:Int = untyped __cpp__("nk_zlib_crc32({0}, {1}, {2}, {3})", crc, d, r.pos, r.len);
			return sum;
		});
	}
}
