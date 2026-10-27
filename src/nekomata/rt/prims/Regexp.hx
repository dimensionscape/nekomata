package nekomata.rt.prims;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import nekomata.rt.Values;
import nekomata.rt.Primitives.add;
import nekomata.rt.prims.Conv.*;

// A compiled regexp and the string it last matched, whose bytes its positions index
class RegexpData {
	public var handle:Dynamic;
	public var groups:Int;
	public var subject:Null<NString>;

	public function new(handle:Dynamic, groups:Int) {
		this.handle = handle;
		this.groups = groups;
	}
}

// libs/regexp, as neko builds it: PCRE2 on the bytes of neko strings, a byte a
//  character unless the u option asks for UTF-8, which libhxcpp's EReg always does
@:keep
@:buildXml('<files id="haxe"><compilerflag value="-I${HXCPP}/project/thirdparty/pcre2-10.42/src"/></files>')
@:cppFileCode('
#define PCRE2_STATIC
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

// A pattern PCRE2 compiled and the match data its matches fill, freed with the regexp
struct nk_pcre : public ::hx::Object
{
   pcre2_code_8 *code;
   pcre2_match_data_8 *data;

   static void finalize(::Dynamic inObj)
   {
      nk_pcre *p = (nk_pcre *)inObj.mPtr;
      if (p->data)
         pcre2_match_data_free_8(p->data);
      if (p->code)
         pcre2_code_free_8(p->code);
      p->data = 0;
      p->code = 0;
   }
};

static PCRE2_SPTR8 nk_pcre_bytes(Array<unsigned char> inBytes, int inLen)
{
   return inLen ? (PCRE2_SPTR8)inBytes->getBase() : (PCRE2_SPTR8)"";
}

// The compiled pattern with its group count, or null with PCRE2s message
static ::Dynamic nk_pcre_compile(Array<unsigned char> inPattern, int inLen, int inFlags, ::String &outError, int &outGroups)
{
   int err = 0;
   PCRE2_SIZE offset = 0;
   pcre2_code_8 *code = pcre2_compile_8(nk_pcre_bytes(inPattern, inLen), inLen, inFlags, &err, &offset, 0);
   if (!code)
   {
      PCRE2_UCHAR8 buf[256];
      pcre2_get_error_message_8(err, buf, sizeof(buf));
      outError = ::String((const char *)buf);
      return null();
   }
   nk_pcre *p = new nk_pcre();
   p->code = code;
   p->data = pcre2_match_data_create_from_pattern_8(code, 0);
   uint32_t n = 0;
   pcre2_pattern_info_8(code, PCRE2_INFO_CAPTURECOUNT, &n);
   outGroups = (int)n + 1;
   _hx_set_finalizer(p, nk_pcre::finalize);
   return p;
}

// pcre2_match over the first inLen bytes, from inPos: 1 for a match, 0 for none, or
//  the error PCRE2 gives
static int nk_pcre_match(::Dynamic inRe, Array<unsigned char> inSubject, int inLen, int inPos)
{
   nk_pcre *p = (nk_pcre *)inRe.mPtr;
   int r = pcre2_match_8(p->code, nk_pcre_bytes(inSubject, inLen), inLen, inPos, 0, p->data, 0);
   return r >= 0 ? 1 : r == PCRE2_ERROR_NOMATCH ? 0 : r;
}

// Where group n of the last match starts and ends, -1 for a group that took no part
static int nk_pcre_offset(::Dynamic inRe, int inIndex)
{
   PCRE2_SIZE *o = pcre2_get_ovector_pointer_8(((nk_pcre *)inRe.mPtr)->data);
   return (int)o[inIndex];
}
')
class Regexp {
	static final kind = new NObject();

	static function regexp(r:Dynamic, prim:String):RegexpData
		return data(r, kind, prim);

	static function start(r:RegexpData, n:Int):Int
		return untyped __cpp__("nk_pcre_offset({0}, {1})", r.handle, 2 * n);

	static function end(r:RegexpData, n:Int):Int
		return untyped __cpp__("nk_pcre_offset({0}, {1})", r.handle, 2 * n + 1);

	// do_match: a failed match forgets the subject, and an error other than no match
	//  throws
	static function run(r:RegexpData, b:Bytes, len:Int, pos:Int):Bool {
		var res:Int = untyped __cpp__("nk_pcre_match({0}, {1}, {2}, {3})", r.handle, b.getData(), len, pos);
		if (res == 1)
			return true;
		r.subject = null;
		if (res != 0)
			Rt.raise(NString.of("An error occurred while running pcre2_match"));
		return false;
	}

	static function compile(source:Bytes, options:Bytes, prim:String):NAbstract {
		var flags = 0;
		for (i in 0...options.length) {
			var c = options.get(i);
			var flag:Int = if (c == "i".code) untyped __cpp__("PCRE2_CASELESS") else if (c == "s".code) untyped __cpp__("PCRE2_DOTALL") else if (c == "m".code)
				untyped __cpp__("PCRE2_MULTILINE") else if (c == "u".code) untyped __cpp__("PCRE2_UTF") else if (c == "g".code) untyped __cpp__("PCRE2_UNGREEDY") else
				Primitives.fail(prim);
			flags |= flag;
		}
		var error = "", groups = 0;
		var handle:Dynamic = untyped __cpp__("nk_pcre_compile({0}, {1}, {2}, {3}, {4})", source.getData(), source.length, flags, error, groups);
		if (handle == null)
			NekoLoader.failure("Regexp compilation error : " + error + " in " + source.toString(), "regexp.c", 129);
		return new NAbstract(kind, new RegexpData(handle, groups));
	}

	// The group of the last match, checked as neko checks it
	static function matchedGroup(re:Dynamic, n:Dynamic, prim:String):{r:RegexpData, m:Int} {
		var r = regexp(re, prim);
		var m = int(n, prim);
		if (m < 0 || m >= r.groups || r.subject == null)
			Primitives.fail(prim);
		return {r: r, m: m};
	}

	// regexp_replace and regexp_replace_all
	static function replace(re:Dynamic, s:Dynamic, by:Dynamic, all:Bool, prim:String):NString {
		var r = regexp(re, prim);
		var b = bytes(s, prim), with = bytes(by, prim);
		var out = new BytesBuffer();
		var pos = 0;
		while (run(r, b, b.length, pos)) {
			var m0 = start(r, 0), m1 = end(r, 0);
			out.addBytes(b, pos, m0 - pos);
			out.add(with);
			// Neko starts the next match where an empty one ended, and so never stops
			var stuck = m1 == pos;
			pos = m1;
			if (!all || stuck)
				break;
		}
		r.subject = null;
		out.addBytes(b, pos, b.length - pos);
		return new NString(out.getBytes());
	}

	public static function register() {
		add("regexp@regexp_new_options", 2, function(s:Dynamic, o:Dynamic)
			return compile(bytes(s, "regexp@regexp_new_options"), bytes(o, "regexp@regexp_new_options"), "regexp@regexp_new_options"));
		add("regexp@regexp_new", 1, (s:Dynamic) -> compile(bytes(s, "regexp@regexp_new"), Bytes.alloc(0), "regexp@regexp_new"));
		add("regexp@regexp_match", 4, function(re:Dynamic, s:Dynamic, p:Dynamic, l:Dynamic) {
			var r = regexp(re, "regexp@regexp_match");
			var b = bytes(s, "regexp@regexp_match");
			var pos = int(p, "regexp@regexp_match"), len = int(l, "regexp@regexp_match");
			if (pos < 0 || len < 0 || pos > b.length || pos + len > b.length)
				Primitives.fail("regexp@regexp_match");
			if (run(r, b, pos + len, pos)) {
				r.subject = s;
				return true;
			}
			return false;
		});
		add("regexp@regexp_matched", 2, function(re:Dynamic, n:Dynamic):Dynamic {
			var g = matchedGroup(re, n, "regexp@regexp_matched");
			var from = start(g.r, g.m);
			if (from == -1)
				return null;
			return new NString(g.r.subject.b.sub(from, end(g.r, g.m) - from));
		});
		add("regexp@regexp_matched_pos", 2, function(re:Dynamic, n:Dynamic):Dynamic {
			var g = matchedGroup(re, n, "regexp@regexp_matched_pos");
			var from = start(g.r, g.m);
			return object([{name: "pos", value: from}, {name: "len", value: end(g.r, g.m) - from}]);
		});
		add("regexp@regexp_matched_num", 1, function(re:Dynamic):Dynamic {
			var r = regexp(re, "regexp@regexp_matched_num");
			return r.subject == null ? -1 : r.groups;
		});
		add("regexp@regexp_replace", 3, (re:Dynamic, s:Dynamic, by:Dynamic) -> replace(re, s, by, false, "regexp@regexp_replace"));
		add("regexp@regexp_replace_all", 3, (re:Dynamic, s:Dynamic, by:Dynamic) -> replace(re, s, by, true, "regexp@regexp_replace_all"));
		add("regexp@regexp_replace_fun", 3, function(re:Dynamic, s:Dynamic, f:Dynamic) {
			var r = regexp(re, "regexp@regexp_replace_fun");
			var b = bytes(s, "regexp@regexp_replace_fun");
			if (!Rt.isFunction(f) || ((f : NFunction).nargs != 1 && (f : NFunction).nargs != NFunction.VAR_ARGS))
				Primitives.fail("regexp@regexp_replace_fun");
			var out = new BytesBuffer();
			var pos = 0;
			r.subject = s;
			while (run(r, b, b.length, pos)) {
				var m0 = start(r, 0), m1 = end(r, 0);
				out.addBytes(b, pos, m0 - pos);
				out.add(Rt.valueBytes(Rt.call1(f, null, re)));
				var stuck = m1 == pos;
				pos = m1;
				if (stuck)
					break;
			}
			r.subject = null;
			out.addBytes(b, pos, b.length - pos);
			return new NString(out.getBytes());
		});
	}
}
