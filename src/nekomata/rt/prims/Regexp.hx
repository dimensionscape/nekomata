package nekomata.rt.prims;

import haxe.io.Bytes;
import nekomata.rt.Values;
import nekomata.rt.Primitives.add;
import nekomata.rt.prims.Conv.*;

@:include("hx/StdLibs.h")
extern class NativeRegexp {
	@:native("_hx_regexp_new_options")
	static function newOptions(s:String, options:String):Dynamic;
	@:native("_hx_regexp_match")
	static function match(handle:Dynamic, string:String, pos:Int, len:Int):Bool;
	@:native("_hx_regexp_matched_pos")
	static function matchedPos(handle:Dynamic, n:Int):Dynamic;
}

// A compiled regexp and the text it last matched. libhxcpp counts positions in the
//  units of its Strings; neko counts bytes, so non-ASCII text needs both
class RegexpData {
	public var handle:Dynamic;
	public var subject:Bytes;
	// Byte offset to String offset, and back; null while the subject is ASCII
	public var toUnits:Null<Array<Int>>;
	public var toBytes:Null<Array<Int>>;

	public function new(handle:Dynamic)
		this.handle = handle;
}

// libs/regexp, on libhxcpp's port of it
@:keep
class Regexp {
	static final kind = new NObject();

	static function regexp(r:Dynamic, prim:String):RegexpData
		return data(r, kind, prim);

	static function unitPos(r:RegexpData, byte:Int):Int
		return r.toUnits == null ? byte : r.toUnits[byte];

	static function bytePos(r:RegexpData, unit:Int):Int
		return r.toBytes == null ? unit : r.toBytes[unit];

	// The match of group n in bytes, or null when the group did not take part. A group
	//  the regexp lacks, or asking before any match, fails as in neko; libhxcpp gives null
	static function group(r:RegexpData, n:Int, prim:String):Null<{pos:Int, len:Int}> {
		if (r.subject == null)
			return Primitives.fail(prim);
		var p:Dynamic = StdSys.host(() -> NativeRegexp.matchedPos(r.handle, n));
		if (p == null)
			return Primitives.fail(prim);
		var pos:Int = p.pos, len:Int = p.len;
		if (pos < 0)
			return null;
		var start = bytePos(r, pos);
		return {pos: start, len: bytePos(r, pos + len) - start};
	}

	public static function register() {
		add("regexp@regexp_new_options", 2, function(s:Dynamic, o:Dynamic) {
			var source = str(s, "regexp@regexp_new_options"), options = str(o, "regexp@regexp_new_options");
			return new NAbstract(kind, new RegexpData(StdSys.host(() -> NativeRegexp.newOptions(source, options))));
		});
		add("regexp@regexp_new", 1, function(s:Dynamic) {
			var source = str(s, "regexp@regexp_new");
			return new NAbstract(kind, new RegexpData(StdSys.host(() -> NativeRegexp.newOptions(source, ""))));
		});
		add("regexp@regexp_match", 4, function(re:Dynamic, s:Dynamic, p:Dynamic, l:Dynamic) {
			var r = regexp(re, "regexp@regexp_match");
			var b = bytes(s, "regexp@regexp_match");
			var pos = int(p, "regexp@regexp_match"), len = int(l, "regexp@regexp_match");
			if (pos < 0 || len < 0 || pos + len > b.length)
				Primitives.fail("regexp@regexp_match");
			if (r.subject != b) {
				r.subject = b;
				r.toUnits = Conv.utf16Offsets(b);
				r.toBytes = null;
				if (r.toUnits != null) {
					var units = r.toUnits[r.toUnits.length - 1];
					var back = [for (_ in 0...units + 1) -1];
					for (i in 0...r.toUnits.length) {
						var u = r.toUnits[i];
						if (back[u] == -1)
							back[u] = i;
					}
					// Units inside a surrogate pair map to the character's first byte
					for (u in 1...back.length)
						if (back[u] == -1)
							back[u] = back[u - 1];
					r.toBytes = back;
				}
			}
			var text = b.toString();
			var start = unitPos(r, pos);
			return StdSys.host(() -> NativeRegexp.match(r.handle, text, start, unitPos(r, pos + len) - start));
		});
		add("regexp@regexp_matched", 2, function(re:Dynamic, n:Dynamic):Dynamic {
			var r = regexp(re, "regexp@regexp_matched");
			var g = group(r, int(n, "regexp@regexp_matched"), "regexp@regexp_matched");
			return g == null ? null : new NString(r.subject.sub(g.pos, g.len));
		});
		add("regexp@regexp_matched_pos", 2, function(re:Dynamic, n:Dynamic):Dynamic {
			var r = regexp(re, "regexp@regexp_matched_pos");
			var g = group(r, int(n, "regexp@regexp_matched_pos"), "regexp@regexp_matched_pos");
			return g == null ? null : object([{name: "pos", value: g.pos}, {name: "len", value: g.len}]);
		});
	}
}
