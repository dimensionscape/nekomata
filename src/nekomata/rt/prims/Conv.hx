package nekomata.rt.prims;

import haxe.io.Bytes;
import nekomata.rt.Values;

// Converting between neko values and the hxcpp values libhxcpp's std functions take
@:keep
class Conv {
	// A neko string as a host String; anything else fails the primitive
	public static function str(v:Dynamic, prim:String):String {
		if (!Std.isOfType(v, NString))
			Primitives.fail(prim);
		return (v : NString).b.toString();
	}

	public static function strOrNull(v:Dynamic, prim:String):Null<String>
		return v == null ? null : str(v, prim);

	public static function nstr(s:Null<String>):Null<NString>
		return s == null ? null : NString.of(s);

	public static function int(v:Dynamic, prim:String):Int {
		if (!Rt.isInt(v))
			Primitives.fail(prim);
		return v;
	}

	public static function number(v:Dynamic, prim:String):Float {
		var t = Rt.typeOf(v);
		if (t != Rt.TINT && t != Rt.TFLOAT)
			Primitives.fail(prim);
		return Rt.num(v);
	}

	public static function bool(v:Dynamic, prim:String):Bool {
		if (Rt.typeOf(v) != Rt.TBOOL)
			Primitives.fail(prim);
		return v;
	}

	public static function bytes(v:Dynamic, prim:String):Bytes {
		if (!Std.isOfType(v, NString))
			Primitives.fail(prim);
		return (v : NString).b;
	}

	// The data of an abstract of the given kind
	public static function data(v:Dynamic, kind:Dynamic, prim:String):Dynamic {
		if (!Std.isOfType(v, NAbstract) || (v : NAbstract).kind != kind)
			Primitives.fail(prim);
		return (v : NAbstract).data;
	}

	// A neko list: nested [value, next] arrays ending in null
	public static function list(values:Array<Dynamic>):Dynamic {
		var l:Dynamic = null;
		var i = values.length;
		while (i-- > 0) {
			var cell:Array<Dynamic> = [values[i], l];
			l = cell;
		}
		return l;
	}

	public static function object(fields:Array<{name:String, value:Dynamic}>):NObject {
		var o = new NObject();
		for (f in fields)
			o.fields.set(nekomata.neko.Hash.field(f.name), f.value);
		return o;
	}

	// Values the host's std functions return or throw, as neko values: Strings become
	//  neko strings and typed arrays become neko arrays
	public static function fromHost(v:Dynamic):Dynamic {
		if (v == null)
			return null;
		var t:Int = untyped v.__GetType();
		if (t == 3)
			return NString.of(v);
		if (t == 5 && !Std.isOfType(v, NObject)) {
			var len:Int = v.length;
			var result:Array<Dynamic> = [];
			for (i in 0...len)
				result.push(fromHost(v[i]));
			return result;
		}
		if (t == 1)
			return new NFloat(v);
		return v;
	}

	// The UTF-16 offset of each byte offset of UTF-8 text, as hxcpp's Strings count
	//  positions when the text is not all ASCII; null when it is
	public static function utf16Offsets(b:Bytes):Null<Array<Int>> {
		var ascii = true;
		for (i in 0...b.length)
			if (b.get(i) >= 0x80) {
				ascii = false;
				break;
			}
		if (ascii)
			return null;
		var result = [];
		var units = 0;
		var i = 0;
		while (i < b.length) {
			var c = b.get(i);
			var len = c < 0x80 ? 1 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : 4;
			for (k in 0...len)
				if (i + k < b.length)
					result.push(units);
			units += len == 4 ? 2 : 1;
			i += len;
		}
		result.push(units);
		return result;
	}
}
