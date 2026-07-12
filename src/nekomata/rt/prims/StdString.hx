package nekomata.rt.prims;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import nekomata.rt.Values;
import nekomata.rt.Primitives.add;
import nekomata.rt.prims.Conv.*;

// libs/std string.c and utf8.c, on neko's byte strings
@:keep
class StdString {
	static final utf8Kind = new NObject();

	static function isUrlSafe(c:Int):Bool
		return (c >= 'A'.code && c <= 'Z'.code) || (c >= 'a'.code && c <= 'z'.code) || (c >= '0'.code && c <= '9'.code) || c == '_'.code
			|| c == '-'.code || c == '.'.code;

	static function hexDigit(c:Int):Int {
		if (c >= '0'.code && c <= '9'.code)
			return c - '0'.code;
		if (c >= 'a'.code && c <= 'f'.code)
			return c - 'a'.code + 10;
		if (c >= 'A'.code && c <= 'F'.code)
			return c - 'A'.code + 10;
		return -1;
	}

	static function baseBits(base:Bytes, prim:String):Int {
		var nbits = 1;
		while (base.length > 1 << nbits)
			nbits++;
		if (nbits > 8 || base.length != 1 << nbits)
			Primitives.fail(prim);
		return nbits;
	}

	// The code points of UTF-8 text, as neko's utf8 functions decode it
	static function decode(b:Bytes, prim:String):Array<Int> {
		var result = [];
		var i = 0;
		while (i < b.length) {
			var c = b.get(i);
			var code, len;
			if (c < 0x80) {
				code = c;
				len = 1;
			} else if (c < 0xC0) {
				return Primitives.fail(prim);
			} else if (c < 0xE0) {
				code = c & 0x1F;
				len = 2;
			} else if (c < 0xF0) {
				code = c & 0x0F;
				len = 3;
			} else {
				code = c & 0x07;
				len = 4;
			}
			if (i + len > b.length)
				return Primitives.fail(prim);
			for (k in 1...len)
				code = (code << 6) | (b.get(i + k) & 0x3F);
			result.push(code);
			i += len;
		}
		return result;
	}

	static function valid(b:Bytes):Bool {
		var i = 0;
		while (i < b.length) {
			var c = b.get(i);
			var len = c < 0x80 ? 1 : c < 0xC0 ? 0 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : c < 0xF8 ? 4 : 0;
			if (len == 0 || i + len > b.length)
				return false;
			for (k in 1...len)
				if (b.get(i + k) & 0xC0 != 0x80)
					return false;
			i += len;
		}
		return true;
	}

	static function encode(buf:BytesBuffer, c:Int) {
		if (c < 0x80)
			buf.addByte(c);
		else if (c < 0x800) {
			buf.addByte(0xC0 | (c >> 6));
			buf.addByte(0x80 | (c & 63));
		} else if (c < 0x10000) {
			buf.addByte(0xE0 | (c >> 12));
			buf.addByte(0x80 | ((c >> 6) & 63));
			buf.addByte(0x80 | (c & 63));
		} else {
			buf.addByte(0xF0 | (c >> 18));
			buf.addByte(0x80 | ((c >> 12) & 63));
			buf.addByte(0x80 | ((c >> 6) & 63));
			buf.addByte(0x80 | (c & 63));
		}
	}

	static function encodeAll(codes:Array<Int>):NString {
		var buf = new BytesBuffer();
		for (c in codes)
			encode(buf, c);
		return new NString(buf.getBytes());
	}

	public static function register() {
		add("std@string_split", 2, function(o:Dynamic, s:Dynamic) {
			var b = bytes(o, "std@string_split"), sep = bytes(s, "std@string_split");
			var ilen = b.length, slen = sep.length;
			var parts:Array<Dynamic> = [];
			var start = 0;
			var pos = slen == 0 ? 1 : 0;
			while (pos <= ilen - slen) {
				var k = 0;
				while (k < slen && b.get(pos + k) == sep.get(k))
					k++;
				if (k == slen) {
					parts.push(new NString(b.sub(start, pos - start)));
					start = pos + slen;
					if (slen > 0)
						pos = start - 1;
				}
				pos++;
			}
			if (ilen > 0 && slen > 0)
				parts.push(start == 0 ? o : new NString(b.sub(start, ilen - start)));
			return list(parts);
		});
		// neko_sprintf, quirks included: after %% it skips the next character too
		add("std@sprintf", 2, function(f:Dynamic, params:Dynamic) {
			var fmt = bytes(f, "std@sprintf");
			var out = new BytesBuffer();
			var count = 0;
			var last = 0, cur = 0, end = fmt.length;
			inline function at(i:Int):Int
				return i < end ? fmt.get(i) : 0;
			inline function spaces(n:Int)
				for (_ in 0...n)
					out.addByte(' '.code);
			while (cur < end) {
				if (fmt.get(cur) != '%'.code) {
					cur++;
					continue;
				}
				var width = 0, prec = 0;
				out.addBytes(fmt, last, cur - last);
				cur++;
				while (at(cur) >= '0'.code && at(cur) <= '9'.code)
					width = width * 10 + (fmt.get(cur++) - '0'.code);
				if (at(cur) == '.'.code) {
					cur++;
					while (at(cur) >= '0'.code && at(cur) <= '9'.code)
						prec = prec * 10 + (fmt.get(cur++) - '0'.code);
				}
				if (at(cur) == '%'.code) {
					out.addByte('%'.code);
					cur++;
				} else {
					var param:Dynamic;
					var isArray = Rt.typeOf(params) == Rt.TARRAY;
					if (count == 0 && !isArray) {
						param = params;
						count++;
					} else if (!isArray || (params : Array<Dynamic>).length <= count)
						return Primitives.fail("std@sprintf");
					else
						param = (params : Array<Dynamic>)[count++];
					switch at(cur) {
						case 'c'.code:
							var c = int(param, "std@sprintf");
							if (c < 0 || c > 255)
								return Primitives.fail("std@sprintf");
							out.addByte(c);
						case k = 'x'.code | 'X'.code | 'd'.code:
							var n = int(param, "std@sprintf");
							var hex = k != 'd'.code;
							var digits = "";
							var sign = false;
							if (!hex && n < 0) {
								sign = true;
								prec--;
								n = -n;
							} else if (n == 0)
								digits = "0";
							if (hex) {
								var chars = k == 'x'.code ? "0123456789abcdef" : "0123456789ABCDEF";
								while (n != 0) {
									digits = chars.charAt(n & 15) + digits;
									n = n >>> 4;
								}
							} else {
								while (n > 0) {
									digits = String.fromCharCode('0'.code + n % 10) + digits;
									n = Std.int(n / 10);
								}
							}
							var size = digits.length;
							var tsize = size > prec ? size : prec + (sign ? 1 : 0);
							spaces(width - tsize);
							if (sign)
								out.addByte('-'.code);
							for (_ in size...prec)
								out.addByte('0'.code);
							out.addString(digits);
						case 'f'.code:
							if (Rt.typeOf(param) != Rt.TFLOAT)
								return Primitives.fail("std@sprintf");
							Rt.appendValue(out, param);
						case 's'.code:
							var s = bytes(param, "std@sprintf");
							var size = s.length;
							spaces(width - (size > prec ? size : prec));
							spaces(prec - size);
							out.add(s);
						case 'b'.code:
							out.addString(bool(param, "std@sprintf") ? "true" : "false");
						default:
							return Primitives.fail("std@sprintf");
					}
				}
				cur++;
				last = cur;
			}
			if (last < end)
				out.addBytes(fmt, last, end - last);
			return new NString(out.getBytes());
		});
		add("std@url_encode", 1, function(v:Dynamic) {
			var b = bytes(v, "std@url_encode");
			var out = new BytesBuffer();
			for (i in 0...b.length) {
				var c = b.get(i);
				if (isUrlSafe(c))
					out.addByte(c);
				else {
					out.addByte('%'.code);
					out.addByte("0123456789ABCDEF".charCodeAt(c >> 4));
					out.addByte("0123456789ABCDEF".charCodeAt(c & 15));
				}
			}
			return new NString(out.getBytes());
		});
		add("std@url_decode", 1, function(v:Dynamic) {
			var b = bytes(v, "std@url_decode");
			var out = new BytesBuffer();
			var i = 0;
			while (i < b.length) {
				var c = b.get(i++);
				if (c == '+'.code)
					c = ' '.code;
				else if (c == '%'.code) {
					if (b.length - i < 2)
						break;
					var h = hexDigit(b.get(i)), l = hexDigit(b.get(i + 1));
					i += 2;
					if (h < 0 || l < 0)
						continue;
					c = (h << 4) | l;
				}
				out.addByte(c);
			}
			return new NString(out.getBytes());
		});
		add("std@base_encode", 2, function(s:Dynamic, base:Dynamic) {
			var b = bytes(s, "std@base_encode"), chars = bytes(base, "std@base_encode");
			var nbits = baseBits(chars, "std@base_encode");
			var size = Std.int((b.length * 8 + nbits - 1) / nbits);
			var out = Bytes.alloc(size);
			var buf = 0, curbits = 0, at = 0;
			var mask = (1 << nbits) - 1;
			for (i in 0...size) {
				while (curbits < nbits) {
					curbits += 8;
					buf = (buf << 8) | (at < b.length ? b.get(at) : 0);
					at++;
				}
				curbits -= nbits;
				out.set(i, chars.get((buf >> curbits) & mask));
			}
			return new NString(out);
		});
		add("std@base_decode", 2, function(s:Dynamic, base:Dynamic) {
			var b = bytes(s, "std@base_decode"), chars = bytes(base, "std@base_decode");
			var nbits = baseBits(chars, "std@base_decode");
			var tbl = [for (_ in 0...256) -1];
			for (i in 0...chars.length)
				tbl[chars.get(i)] = i;
			var size = Std.int((b.length * nbits) / 8);
			var out = Bytes.alloc(size);
			var buf = 0, curbits = 0, at = 0;
			for (i in 0...size) {
				while (curbits < 8) {
					curbits += nbits;
					var v = at < b.length ? tbl[b.get(at)] : -1;
					at++;
					if (v == -1)
						Primitives.fail("std@base_decode");
					buf = (buf << nbits) | v;
				}
				curbits -= 8;
				out.set(i, (buf >> curbits) & 0xFF);
			}
			return new NString(out);
		});

		// utf8.c
		add("std@utf8_buf_alloc", 1, (n:Dynamic) -> new NAbstract(utf8Kind, new BytesBuffer()));
		add("std@utf8_buf_add", 2, function(b:Dynamic, c:Dynamic) {
			var code = int(c, "std@utf8_buf_add");
			if (code < 0 || code > 0x10FFFF)
				Primitives.fail("std@utf8_buf_add");
			encode(data(b, utf8Kind, "std@utf8_buf_add"), code);
			return null;
		});
		add("std@utf8_buf_content", 1, function(b:Dynamic) {
			var buf:BytesBuffer = data(b, utf8Kind, "std@utf8_buf_content");
			var bytes = buf.getBytes();
			var again = new BytesBuffer();
			again.add(bytes);
			(b : NAbstract).data = again;
			return new NString(bytes);
		});
		add("std@utf8_buf_length", 1, function(b:Dynamic) {
			var buf:BytesBuffer = data(b, utf8Kind, "std@utf8_buf_length");
			var bytes = buf.getBytes();
			var again = new BytesBuffer();
			again.add(bytes);
			(b : NAbstract).data = again;
			return decode(bytes, "std@utf8_buf_length").length;
		});
		add("std@utf8_buf_size", 1, (b:Dynamic) -> (data(b, utf8Kind, "std@utf8_buf_size") : BytesBuffer).length);
		add("std@utf8_get", 2, function(s:Dynamic, n:Dynamic) {
			var codes = decode(bytes(s, "std@utf8_get"), "std@utf8_get"), i = int(n, "std@utf8_get");
			if (i < 0 || i >= codes.length)
				Primitives.fail("std@utf8_get");
			return codes[i];
		});
		add("std@utf8_validate", 1, (s:Dynamic) -> valid(bytes(s, "std@utf8_validate")));
		add("std@utf8_iter", 2, function(s:Dynamic, f:Dynamic) {
			for (c in decode(bytes(s, "std@utf8_iter"), "std@utf8_iter"))
				Rt.call1(f, null, c);
			return null;
		});
		add("std@utf8_length", 1, (s:Dynamic) -> decode(bytes(s, "std@utf8_length"), "std@utf8_length").length);
		add("std@utf8_compare", 2, function(a:Dynamic, b:Dynamic) {
			var x = decode(bytes(a, "std@utf8_compare"), "std@utf8_compare");
			var y = decode(bytes(b, "std@utf8_compare"), "std@utf8_compare");
			var n = x.length < y.length ? x.length : y.length;
			for (i in 0...n)
				if (x[i] != y[i])
					return x[i] < y[i] ? -1 : 1;
			return x.length == y.length ? 0 : x.length < y.length ? -1 : 1;
		});
		add("std@utf8_sub", 3, function(s:Dynamic, p:Dynamic, l:Dynamic) {
			var codes = decode(bytes(s, "std@utf8_sub"), "std@utf8_sub");
			var pos = int(p, "std@utf8_sub"), len = int(l, "std@utf8_sub");
			if (pos < 0 || len < 0 || pos + len > codes.length)
				Primitives.fail("std@utf8_sub");
			return encodeAll(codes.slice(pos, pos + len));
		});
	}
}
