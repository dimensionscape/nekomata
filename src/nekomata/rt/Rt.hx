package nekomata.rt;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import nekomata.rt.Values;

// The operations translated neko code calls. Each opcode with more than a trivial
//  translation lands here, with neko's semantics (vm/interp.c, vm/others.c)
@:keep
class Rt {
	// Neko's value tags, as $typeof numbers them
	public static inline var TNULL = 0;
	public static inline var TINT = 1;
	public static inline var TFLOAT = 2;
	public static inline var TBOOL = 3;
	public static inline var TSTRING = 4;
	public static inline var TOBJECT = 5;
	public static inline var TARRAY = 6;
	public static inline var TFUNCTION = 7;
	public static inline var TABSTRACT = 8;

	// What val_compare returns for values that do not compare
	public static inline var INVALID = 0xFE;

	static inline var VT_INT = 0xff;
	static inline var VT_FLOAT = 1;
	static inline var VT_BOOL = 2;
	static inline var VT_STRING = 3;
	static inline var VT_ARRAY = 5;

	static inline function vt(v:Dynamic):Int
		return v == null ? 0 : untyped v.__GetType();

	public static function typeOf(v:Dynamic):Int {
		switch vt(v) {
			case 0:
				return TNULL;
			case VT_INT:
				return TINT;
			case VT_FLOAT:
				return TFLOAT;
			case VT_BOOL:
				return TBOOL;
			case VT_STRING:
				return TSTRING;
			case VT_ARRAY:
				return TARRAY;
			default:
		}
		if (Std.isOfType(v, NObject))
			return TOBJECT;
		if (Std.isOfType(v, NString))
			return TSTRING;
		if (Std.isOfType(v, NFloat))
			return TFLOAT;
		if (Std.isOfType(v, NFunction))
			return TFUNCTION;
		return TABSTRACT;
	}

	public static inline function isInt(v:Dynamic):Bool
		return vt(v) == VT_INT;

	static function isFloat(v:Dynamic):Bool
		return Std.isOfType(v, NFloat) || vt(v) == VT_FLOAT;

	static function isNumber(v:Dynamic):Bool
		return isInt(v) || isFloat(v);

	static function isString(v:Dynamic):Bool
		return Std.isOfType(v, NString) || vt(v) == VT_STRING;

	// A number as a Float, for an int or a float
	public static function num(v:Dynamic):Float {
		if (isInt(v))
			return (v : Int);
		if (Std.isOfType(v, NFloat))
			return (v : NFloat).v;
		return (v : Float);
	}

	public static inline function float(f:Float):NFloat
		return new NFloat(f);

	// Float globals, from their text in the module
	public static function floatOf(text:String):NFloat
		return new NFloat(Std.parseFloat(text));

	// String globals, from hex so any bytes survive the cppia string table
	public static function stringOf(hex:String):NString
		return new NString(Bytes.ofHex(hex));

	public static inline function str(s:String):NString
		return NString.of(s);

	// Bytes of a neko string; a host String counts as one, for errors the host raises
	public static function bytes(v:Dynamic):Bytes {
		if (Std.isOfType(v, NString))
			return (v : NString).b;
		return Bytes.ofString(Std.string(v));
	}

	// -- Errors and exceptions --

	public static function raise(v:Dynamic):Dynamic {
		untyped __cpp__("::hx::Throw({0})", v);
		return null;
	}

	public static function error(msg:String):Dynamic
		return raise(NString.of(msg));

	static function opError(op:String):Dynamic
		return error('Invalid operation ($op)');

	// The value a translated catch sees: errors the host raises become neko strings
	public static function caught(e:Dynamic):Dynamic {
		if (vt(e) == VT_STRING)
			return NString.of((e : String));
		return e;
	}

	// -- Truth --

	public static inline function isTrue(v:Dynamic):Bool
		return vt(v) == VT_BOOL && (v : Bool);

	// The Bool opcode: false for false, null and 0
	public static function toBool(v:Dynamic):Bool {
		return switch vt(v) {
			case 0: false;
			case VT_BOOL: (v : Bool);
			case VT_INT: (v : Int) != 0;
			default: true;
		}
	}

	public static inline function isNotTrue(v:Dynamic):Bool
		return !isTrue(v);

	public static inline function not(v:Dynamic):Bool
		return !toBool(v);

	public static inline function isNull(v:Dynamic):Bool
		return v == null;

	public static inline function isNotNull(v:Dynamic):Bool
		return v != null;

	// -- Arithmetic --

	static function objectOp(o:Dynamic, arg:Dynamic, field:String):Dynamic {
		if (!Std.isOfType(o, NObject))
			return NO_OP;
		var f = (o : NObject).find(nekomata.neko.Hash.field(field));
		if (f == null)
			return NO_OP;
		return call1(f, o, arg);
	}

	static final NO_OP = new NObject();

	public static function add(a:Dynamic, b:Dynamic):Dynamic {
		if (isInt(a) && isInt(b))
			return (a : Int) + (b : Int);
		if (isNumber(a) && isNumber(b))
			return new NFloat(num(a) + num(b));
		var r = objectOp(a, b, "__add");
		if (r != NO_OP)
			return r;
		r = objectOp(b, a, "__radd");
		if (r != NO_OP)
			return r;
		if (isString(a) || isString(b)) {
			var buf = new BytesBuffer();
			appendValue(buf, a);
			appendValue(buf, b);
			return new NString(buf.getBytes());
		}
		return opError("+");
	}

	static function numberOp(a:Dynamic, b:Dynamic, op:Int, name:String, field:String, rfield:String):Dynamic {
		if (isInt(a) && isInt(b)) {
			var x:Int = a, y:Int = b;
			return switch op {
				case 0: x - y;
				case 1: x * y;
				default:
					if (y == 0)
						opError("%");
					x % y;
			}
		}
		if (isNumber(a) && isNumber(b)) {
			var x = num(a), y = num(b);
			return new NFloat(switch op {
				case 0: x - y;
				case 1: x * y;
				default: x % y;
			});
		}
		var r = objectOp(a, b, field);
		if (r != NO_OP)
			return r;
		r = objectOp(b, a, rfield);
		if (r != NO_OP)
			return r;
		return opError(name);
	}

	public static function sub(a:Dynamic, b:Dynamic):Dynamic
		return numberOp(a, b, 0, "-", "__sub", "__rsub");

	public static function mult(a:Dynamic, b:Dynamic):Dynamic
		return numberOp(a, b, 1, "*", "__mult", "__rmult");

	public static function mod(a:Dynamic, b:Dynamic):Dynamic
		return numberOp(a, b, 2, "%", "__mod", "__rmod");

	public static function div(a:Dynamic, b:Dynamic):Dynamic {
		if (isNumber(a) && isNumber(b))
			return new NFloat(num(a) / num(b));
		var r = objectOp(a, b, "__div");
		if (r != NO_OP)
			return r;
		r = objectOp(b, a, "__rdiv");
		if (r != NO_OP)
			return r;
		return opError("/");
	}

	static function intOp(a:Dynamic, b:Dynamic, name:String):Int {
		if (!isInt(a) || !isInt(b))
			opError(name);
		return a;
	}

	public static function shl(a:Dynamic, b:Dynamic):Int
		return intOp(a, b, "<<") << (b : Int);

	public static function shr(a:Dynamic, b:Dynamic):Int
		return intOp(a, b, ">>") >> (b : Int);

	public static function ushr(a:Dynamic, b:Dynamic):Int
		return intOp(a, b, ">>>") >>> (b : Int);

	public static function or(a:Dynamic, b:Dynamic):Int
		return intOp(a, b, "|") | (b : Int);

	public static function and(a:Dynamic, b:Dynamic):Int
		return intOp(a, b, "&") & (b : Int);

	public static function xor(a:Dynamic, b:Dynamic):Int
		return intOp(a, b, "^") ^ (b : Int);

	// -- Comparison --

	static inline function icmp(a:Int, b:Int):Int
		return a == b ? 0 : a < b ? -1 : 1;

	static function fcmp(a:Float, b:Float):Int {
		if (Math.isNaN(a) || Math.isNaN(b))
			return INVALID;
		return a == b ? 0 : a < b ? -1 : 1;
	}

	static function bcmp(a:Bytes, b:Bytes):Int {
		var r = a.compare(b);
		return r < 0 ? -1 : r > 0 ? 1 : 0;
	}

	// Neko's val_compare: 0, -1, 1, or INVALID
	public static function compare(a:Dynamic, b:Dynamic):Int {
		var ta = typeOf(a), tb = typeOf(b);
		if (ta == TINT && tb == TINT)
			return icmp(a, b);
		if ((ta == TINT || ta == TFLOAT) && (tb == TINT || tb == TFLOAT))
			return fcmp(num(a), num(b));
		if (ta == TSTRING && tb == TSTRING)
			return bcmp(bytes(a), bytes(b));
		if (ta == TSTRING && (tb == TINT || tb == TFLOAT || tb == TBOOL))
			return bcmp(bytes(a), valueBytes(b));
		if (tb == TSTRING && (ta == TINT || ta == TFLOAT || ta == TBOOL))
			return bcmp(valueBytes(a), bytes(b));
		if (ta == TBOOL && tb == TBOOL)
			return (a : Bool) == (b : Bool) ? 0 : (a : Bool) ? 1 : -1;
		if (ta == TOBJECT && tb == TOBJECT) {
			if (a == b)
				return 0;
			var f = (a : NObject).find(nekomata.neko.Hash.field("__compare"));
			if (f == null)
				return INVALID;
			var r = call1(f, a, b);
			return isInt(r) ? r : INVALID;
		}
		return same(a, b) ? 0 : INVALID;
	}

	// Physical equality, as neko compares value words
	static function same(a:Dynamic, b:Dynamic):Bool {
		if (isInt(a) && isInt(b))
			return (a : Int) == (b : Int);
		if (vt(a) == VT_BOOL && vt(b) == VT_BOOL)
			return (a : Bool) == (b : Bool);
		return untyped __cpp__("{0}.mPtr == {1}.mPtr", a, b);
	}

	public static function eq(a:Dynamic, b:Dynamic):Bool
		return compare(a, b) == 0;

	public static function neq(a:Dynamic, b:Dynamic):Bool
		return compare(a, b) != 0;

	public static function lt(a:Dynamic, b:Dynamic):Bool {
		var c = compare(a, b);
		return c < 0 && c != INVALID;
	}

	public static function lte(a:Dynamic, b:Dynamic):Bool {
		var c = compare(a, b);
		return c <= 0 && c != INVALID;
	}

	public static function gt(a:Dynamic, b:Dynamic):Bool {
		var c = compare(a, b);
		return c > 0 && c != INVALID;
	}

	public static function gte(a:Dynamic, b:Dynamic):Bool {
		var c = compare(a, b);
		return c >= 0 && c != INVALID;
	}

	// The Compare opcode: null when the values do not compare
	public static function compareOp(a:Dynamic, b:Dynamic):Dynamic {
		var c = compare(a, b);
		return c == INVALID ? null : c;
	}

	public static function physCompare(a:Dynamic, b:Dynamic):Int {
		if (isInt(a) && isInt(b))
			return icmp(a, b);
		if (same(a, b))
			return 0;
		return untyped __cpp__("((size_t){0}.mPtr > (size_t){1}.mPtr) ? 1 : -1", a, b);
	}

	public static function hash(v:Dynamic):Int {
		if (!isString(v))
			error("$hash");
		return nekomata.neko.Hash.field(bytes(v).toString());
	}

	// -- Objects, fields and arrays --

	public static function newObject(proto:Dynamic):NObject {
		if (proto == null)
			return new NObject();
		if (!Std.isOfType(proto, NObject))
			error("$new");
		return (proto : NObject).copy();
	}

	public static function field(o:Dynamic, h:Int):Dynamic {
		if (!Std.isOfType(o, NObject))
			return error("Invalid field access : " + fieldName(h));
		return (o : NObject).find(h);
	}

	public static function setField(o:Dynamic, h:Int, v:Dynamic):Void {
		if (!Std.isOfType(o, NObject))
			error("Invalid field access : " + fieldName(h));
		(o : NObject).fields.set(h, v);
	}

	public static function aget(a:Dynamic, i:Dynamic):Dynamic {
		if (vt(a) == VT_ARRAY && isInt(i)) {
			var arr:Array<Dynamic> = a;
			var k:Int = i;
			return k < 0 || k >= arr.length ? null : arr[k];
		}
		if (Std.isOfType(a, NObject)) {
			var r = objectOp(a, i, "__get");
			if (r != NO_OP)
				return r;
			return error("Unsupported operation");
		}
		return error("Invalid array access");
	}

	// Returns the value the instruction leaves in the accumulator
	public static function aset(a:Dynamic, i:Dynamic, v:Dynamic):Dynamic {
		if (vt(a) == VT_ARRAY && isInt(i)) {
			var arr:Array<Dynamic> = a;
			var k:Int = i;
			if (k >= 0 && k < arr.length)
				arr[k] = v;
			return v;
		}
		if (Std.isOfType(a, NObject)) {
			var f = (a : NObject).find(nekomata.neko.Hash.field("__set"));
			if (f == null)
				return error("Unsupported operation");
			call2(f, a, i, v);
			return v;
		}
		return error("Invalid array access");
	}

	// Field names for hashes, from every module loaded, as neko's global field table
	static var names = new haxe.ds.IntMap<String>();

	public static function registerFields(fields:Array<Dynamic>):Void {
		for (f in fields) {
			var s:String = f;
			names.set(nekomata.neko.Hash.field(s), s);
		}
	}

	public static function fieldName(h:Int):String {
		var n = names.get(h);
		return n == null ? '#$h' : n;
	}

	// -- Functions and calls --

	// A module function value; env is filled in by MakeEnv
	public static function func(fn:Dynamic, nargs:Int, module:NModule):NFunction
		return new NFunction(fn, nargs, Bytecode, null, module);

	public static function makeEnv(f:Dynamic, env:Array<Dynamic>):NFunction {
		if (!Std.isOfType(f, NFunction) || (f : NFunction).kind != Bytecode)
			error("Invalid environment");
		var fn:NFunction = f;
		return new NFunction(fn.fn, fn.nargs, Bytecode, env, fn.module);
	}

	static function invalidCall():Dynamic
		return error("Invalid call");

	// Calls f with the arguments in an array, the way $call and $apply do
	public static function callArgs(f:Dynamic, th:Dynamic, args:Array<Dynamic>):Dynamic {
		if (!Std.isOfType(f, NFunction))
			return invalidCall();
		var fn:NFunction = f;
		var n = args.length;
		switch fn.kind {
			case Bytecode:
				if (fn.nargs != n)
					return invalidCall();
				var all:Array<Dynamic> = [th, fn.env];
				return Reflect.callMethod(null, fn.fn, all.concat(args));
			case Primitive:
				if (fn.nargs == NFunction.VAR_ARGS)
					return fn.fn(args);
				if (fn.nargs != n)
					return invalidCall();
				return Reflect.callMethod(null, fn.fn, args);
			case PrimitiveThis:
				if (fn.nargs == NFunction.VAR_ARGS)
					return fn.fn(th, args);
				if (fn.nargs != n)
					return invalidCall();
				var all:Array<Dynamic> = [th];
				return Reflect.callMethod(null, fn.fn, all.concat(args));
		}
	}

	public static function call0(f:Dynamic, th:Dynamic):Dynamic {
		if (Std.isOfType(f, NFunction)) {
			var fn:NFunction = f;
			if (fn.nargs == 0)
				switch fn.kind {
					case Bytecode:
						return fn.fn(th, fn.env);
					case Primitive:
						return fn.fn();
					case PrimitiveThis:
						return fn.fn(th);
				}
		}
		return callArgs(f, th, []);
	}

	public static function call1(f:Dynamic, th:Dynamic, a:Dynamic):Dynamic {
		if (Std.isOfType(f, NFunction)) {
			var fn:NFunction = f;
			if (fn.nargs == 1)
				switch fn.kind {
					case Bytecode:
						return fn.fn(th, fn.env, a);
					case Primitive:
						return fn.fn(a);
					case PrimitiveThis:
						return fn.fn(th, a);
				}
		}
		return callArgs(f, th, [a]);
	}

	public static function call2(f:Dynamic, th:Dynamic, a:Dynamic, b:Dynamic):Dynamic {
		if (Std.isOfType(f, NFunction)) {
			var fn:NFunction = f;
			if (fn.nargs == 2)
				switch fn.kind {
					case Bytecode:
						return fn.fn(th, fn.env, a, b);
					case Primitive:
						return fn.fn(a, b);
					case PrimitiveThis:
						return fn.fn(th, a, b);
				}
		}
		return callArgs(f, th, [a, b]);
	}

	public static function call3(f:Dynamic, th:Dynamic, a:Dynamic, b:Dynamic, c:Dynamic):Dynamic {
		if (Std.isOfType(f, NFunction)) {
			var fn:NFunction = f;
			if (fn.nargs == 3)
				switch fn.kind {
					case Bytecode:
						return fn.fn(th, fn.env, a, b, c);
					case Primitive:
						return fn.fn(a, b, c);
					case PrimitiveThis:
						return fn.fn(th, a, b, c);
				}
		}
		return callArgs(f, th, [a, b, c]);
	}

	public static function call4(f:Dynamic, th:Dynamic, a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic):Dynamic
		return callArgs(f, th, [a, b, c, d]);

	public static function call5(f:Dynamic, th:Dynamic, a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic):Dynamic
		return callArgs(f, th, [a, b, c, d, e]);

	// The Apply opcode: bind the first arguments, or call when they are all there
	public static function apply(f:Dynamic, th:Dynamic, args:Array<Dynamic>):Dynamic {
		if (!Std.isOfType(f, NFunction))
			return error("$apply");
		var fn:NFunction = f;
		if (fn.nargs == args.length || fn.nargs == NFunction.VAR_ARGS)
			return callArgs(f, th, args);
		if (args.length > fn.nargs)
			return error("$apply");
		var bound = args.copy();
		return new NFunction(function(rest:Array<Dynamic>) return callArgs(fn, null, bound.concat(rest)), fn.nargs - args.length, Primitive);
	}

	// JumpTable: the case for an int below n, or n for the default
	public static function tableIndex(v:Dynamic, n:Int):Int {
		if (isInt(v)) {
			var k:Int = v;
			if (k >= 0 && k < n)
				return k;
		}
		return n;
	}

	// The code index a JumpTable at pc goes to: the Jump for case k, or past the table
	public static function tableTarget(v:Dynamic, n:Int, pc:Int):Int
		return pc + 2 + 2 * tableIndex(v, n);

	// -- Traps --

	public static function trapPush(traps:Array<Dynamic>, pc:Int, th:Dynamic):Void {
		traps.push(th);
		traps.push(pc);
	}

	public static function trapPop(traps:Array<Dynamic>):Void {
		traps.pop();
		traps.pop();
	}

	public static inline function trapEmpty(traps:Array<Dynamic>):Bool
		return traps.length == 0;

	public static function trapPc(traps:Array<Dynamic>):Int
		return traps[traps.length - 1];

	public static function trapThis(traps:Array<Dynamic>):Dynamic
		return traps[traps.length - 2];

	// -- Strings of values --

	static function formatFloat(f:Float):String {
		return untyped __cpp__("[](double d){ char b[40]; snprintf(b,40,\"%.15g\",d); return ::String(b); }({0})", f);
	}

	public static function valueBytes(v:Dynamic):Bytes {
		if (Std.isOfType(v, NString))
			return (v : NString).b;
		var buf = new BytesBuffer();
		appendValue(buf, v);
		return buf.getBytes();
	}

	public static function toNString(v:Dynamic):NString {
		if (Std.isOfType(v, NString))
			return v;
		return new NString(valueBytes(v));
	}

	public static function appendValue(buf:BytesBuffer, v:Dynamic, ?seen:Array<Dynamic>):Void {
		if (seen != null)
			for (s in seen)
				if (s == v) {
					buf.addString("...");
					return;
				}
		switch typeOf(v) {
			case TNULL:
				buf.addString("null");
			case TINT:
				buf.addString(Std.string((v : Int)));
			case TFLOAT:
				buf.addString(formatFloat(num(v)));
			case TBOOL:
				buf.addString((v : Bool) ? "true" : "false");
			case TSTRING:
				buf.add(bytes(v));
			case TFUNCTION:
				buf.addString('#function:${(v : NFunction).nargs}');
			case TARRAY:
				var arr:Array<Dynamic> = v;
				var inner = seen == null ? [v] : seen.concat([v]);
				buf.addString("[");
				for (i in 0...arr.length) {
					appendValue(buf, arr[i], inner);
					if (i != arr.length - 1)
						buf.addString(",");
				}
				buf.addString("]");
			case TOBJECT:
				var o:NObject = v;
				var f = o.find(nekomata.neko.Hash.field("__string"));
				if (f != null) {
					var s = call0(f, o);
					if (isString(s)) {
						buf.add(bytes(s));
						return;
					}
				}
				var inner = seen == null ? [v] : seen.concat([v]);
				var first = true;
				buf.addString("{");
				for (k in o.keys()) {
					buf.addString(first ? " " : ", ");
					first = false;
					buf.addString(fieldName(k));
					buf.addString(" => ");
					appendValue(buf, o.fields.get(k), inner);
				}
				buf.addString(first ? "}" : " }");
			default:
				buf.addString("#abstract");
		}
	}

	public static function print(v:Dynamic):Void {
		var b = valueBytes(v);
		Sys.stdout().writeBytes(b, 0, b.length);
	}
}
