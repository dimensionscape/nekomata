package nekomata.rt;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import nekomata.rt.Values;

// The operations translated neko code calls. Each opcode with more than a trivial
//  translation lands here, with neko's semantics (vm/interp.c, vm/others.c).
// Its functions push no host stack frames (NoFrames): neko's stack traces skip them, and
//  the push and pop cost more than most of them do
@:keep
@:build(nekomata.build.NoFrames.build())
@:cppFileCode('
// The neko type of a host object that is not an int, float, bool, string or array,
//  from its class in one virtual call
static int nk_object_type(::hx::Object *o)
{
   ::hx::Class_obj *c = o->__GetClass().mPtr;
   if (c == ::nekomata::rt::NObject_obj::__mClass.mPtr)
      return 5;
   if (c == ::nekomata::rt::NString_obj::__mClass.mPtr)
      return 4;
   if (c == ::nekomata::rt::NFloat_obj::__mClass.mPtr)
      return 2;
   if (c == ::nekomata::rt::NFunction_obj::__mClass.mPtr)
      return 7;
   return 8;
}
')
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


	// -- Entry points --
	//
	// cppia links a call of a host function by looking for its name in the class's
	//  functions one after another, in the order they are declared, so the ones
	//  translated code calls most come first

	public static function field(o:Dynamic, h:Int):Dynamic {
		if (!isObject(o))
			return invalidFieldAccess(h);
		var obj = asObject(o);
		var v = obj.find(h);
		if (v == null) {
			var r = resolver.value;
			if (r != null && !obj.has(h))
				return call2(r, null, o, h);
		}
		return v;
	}

	// ObjCall of a field, o.f(args): the field as AccField reads it, called on o
	public static function method1(o:Dynamic, h:Int, a:Dynamic):Dynamic
		return finish(enter1(field(o, h), o, a));

	public static function setField(o:Dynamic, h:Int, v:Dynamic):Void {
		if (!isObject(o))
			invalidFieldAccess(h);
		asObject(o).fields.set(h, v);
	}

	public static function method2(o:Dynamic, h:Int, a:Dynamic, b:Dynamic):Dynamic
		return finish(enter2(field(o, h), o, a, b));

	public static function method0(o:Dynamic, h:Int):Dynamic
		return finish(enter0(field(o, h), o));

	public static function method3(o:Dynamic, h:Int, a:Dynamic, b:Dynamic, c:Dynamic):Dynamic
		return finish(enter3(field(o, h), o, a, b, c));

	// Operations with an int constant on the right, as most in loops and recursion are:
	//  the int goes into the call as it is, and only the other value is looked at
	public static function addI(a:Dynamic, b:Int):Dynamic
		return isInt(a) ? (a : Int) + b : add(a, b);

	public static function subI(a:Dynamic, b:Int):Dynamic
		return isInt(a) ? (a : Int) - b : sub(a, b);

	public static function ltI(a:Dynamic, b:Int):Bool
		return isInt(a) ? (a : Int) < b : lt(a, b);

	public static function lteI(a:Dynamic, b:Int):Bool
		return isInt(a) ? (a : Int) <= b : lte(a, b);

	public static function gtI(a:Dynamic, b:Int):Bool
		return isInt(a) ? (a : Int) > b : gt(a, b);

	public static function gteI(a:Dynamic, b:Int):Bool
		return isInt(a) ? (a : Int) >= b : gte(a, b);

	public static function eqI(a:Dynamic, b:Int):Bool
		return isInt(a) ? (a : Int) == b : eq(a, b);

	public static function neqI(a:Dynamic, b:Int):Bool
		return isInt(a) ? (a : Int) != b : neq(a, b);

	public static function newObject(proto:Dynamic):NObject {
		if (proto == null)
			return new NObject();
		if (!isObject(proto))
			error("$new");
		return asObject(proto).copy();
	}

	public static function call1(f:Dynamic, th:Dynamic, a:Dynamic):Dynamic
		return finish(enter1(f, th, a));

	public static function call2(f:Dynamic, th:Dynamic, a:Dynamic, b:Dynamic):Dynamic
		return finish(enter2(f, th, a, b));

	public static function call0(f:Dynamic, th:Dynamic):Dynamic
		return finish(enter0(f, th));

	public static function call3(f:Dynamic, th:Dynamic, a:Dynamic, b:Dynamic, c:Dynamic):Dynamic
		return finish(enter3(f, th, a, b, c));

	// A module function value; env is filled in by MakeEnv
	public static function func(fn:Dynamic, nargs:Int, module:NModule, global:Int):NFunction
		return new NFunction(fn, nargs, Bytecode, null, module, "", global);

	// String globals, from hex so any bytes survive the cppia string table
	public static function stringOf(hex:String):NString
		return new NString(Bytes.ofHex(hex));

	// Float globals, from their text in the module
	public static function floatOf(text:String):NFloat
		return new NFloat(Std.parseFloat(text));

	// Arrays are read through hxcpp's virtual item access, the same for the arrays the
	//  runtime makes and the ones cppia makes, where an Array<Dynamic> cast would
	//  dynamic_cast and wrap
	public static function aget(a:Dynamic, i:Dynamic):Dynamic {
		if (vt(a) == VT_ARRAY && isInt(i)) {
			return untyped __cpp__("[](::hx::Object *o, int k) -> ::Dynamic { return k < 0 || k >= o->__length() ? ::Dynamic() : o->__GetItem(k); }({0}.mPtr, {1})", a, (i : Int));
		}
		if (isObject(a)) {
			var r:Dynamic = objectOp(a, i, H_GET);
			if (!missing(r))
				return r;
			return error("Unsupported operation");
		}
		return error("Invalid array access");
	}

	public static function add(a:Dynamic, b:Dynamic):Dynamic {
		var ta = kind(a), tb = kind(b);
		if (ta == TINT && tb == TINT)
			return (a : Int) + (b : Int);
		if (numeric(ta) && numeric(tb))
			return new NFloat(numberOf(a, ta) + numberOf(b, tb));
		var r:Dynamic = objectOp(a, b, H_ADD);
		if (!missing(r))
			return r;
		r = objectOp(b, a, H_RADD);
		if (!missing(r))
			return r;
		if (ta == TSTRING || ta == K_HOST_STRING || tb == TSTRING || tb == K_HOST_STRING) {
			var buf = new BytesBuffer();
			appendValue(buf, a);
			appendValue(buf, b);
			return new NString(buf.getBytes());
		}
		return opError("+");
	}
	public static function eq(a:Dynamic, b:Dynamic):Bool {
		if (isInt(a) && isInt(b))
			return (a : Int) == (b : Int);
		return compare(a, b) == 0;
	}

	public static function makeEnv(f:Dynamic, env:Array<Dynamic>):NFunction {
		if (!isFunction(f) || asFunction(f).kind != Bytecode)
			error("Invalid environment");
		var fn = asFunction(f);
		return new NFunction(fn.fn, fn.nargs, Bytecode, env, fn.module, "", fn.global);
	}

	// Whether a tail call calls the function it is in, so it can loop instead
	public static inline function isNotTrue(v:Dynamic):Bool
		return !isTrue(v);

	public static inline function isTrue(v:Dynamic):Bool
		return vt(v) == VT_BOOL && (v : Bool);

	public static function lt(a:Dynamic, b:Dynamic):Bool {
		if (isInt(a) && isInt(b))
			return (a : Int) < (b : Int);
		var c = compare(a, b);
		return c < 0 && c != INVALID;
	}

	public static function sub(a:Dynamic, b:Dynamic):Dynamic {
		var ta = kind(a), tb = kind(b);
		if (ta == TINT && tb == TINT)
			return (a : Int) - (b : Int);
		if (numeric(ta) && numeric(tb))
			return new NFloat(numberOf(a, ta) - numberOf(b, tb));
		return objectOps(a, b, H_SUB, H_RSUB, "-");
	}

	public static function neq(a:Dynamic, b:Dynamic):Bool {
		if (isInt(a) && isInt(b))
			return (a : Int) != (b : Int);
		return compare(a, b) != 0;
	}

	public static function method4(o:Dynamic, h:Int, a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic):Dynamic
		return callArgs(field(o, h), o, [a, b, c, d]);

	public static function method5(o:Dynamic, h:Int, a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic):Dynamic
		return callArgs(field(o, h), o, [a, b, c, d, e]);

	public static function call4(f:Dynamic, th:Dynamic, a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic):Dynamic
		return callArgs(f, th, [a, b, c, d]);

	public static function typeOf(v:Dynamic):Int {
		var k = kind(v);
		return k == K_HOST_FLOAT ? TFLOAT : k == K_HOST_STRING ? TSTRING : k;
	}

	// typeOf, with the host's own floats and strings, which primitives and host errors
	//  give, told apart from the runtime's NFloat and NString
	static inline var K_HOST_FLOAT = 9;
	static inline var K_HOST_STRING = 10;

	static function kind(v:Dynamic):Int {
		switch vt(v) {
			case 0:
				return TNULL;
			case VT_INT:
				return TINT;
			case VT_FLOAT:
				return K_HOST_FLOAT;
			case VT_BOOL:
				return TBOOL;
			case VT_STRING:
				return K_HOST_STRING;
			case VT_ARRAY:
				return TARRAY;
			default:
				return untyped __cpp__("nk_object_type({0}.mPtr)", v);
		}
	}

	// -- Values --

	static inline function vt(v:Dynamic):Int
		return v == null ? 0 : untyped v.__GetType();

	// Whether v is an instance of one of the runtime's value classes, in one virtual call
	//  where Std.isOfType makes several, and the value as that class without a second check
	public static inline function isFunction(v:Dynamic):Bool
		return untyped __cpp__("[](::hx::Object *o){ return o && o->_hx_isInstanceOf(::nekomata::rt::NFunction_obj::_hx_ClassId); }({0}.mPtr)", v);

	public static inline function isObject(v:Dynamic):Bool
		return untyped __cpp__("[](::hx::Object *o){ return o && o->_hx_isInstanceOf(::nekomata::rt::NObject_obj::_hx_ClassId); }({0}.mPtr)", v);

	public static inline function isNString(v:Dynamic):Bool
		return untyped __cpp__("[](::hx::Object *o){ return o && o->_hx_isInstanceOf(::nekomata::rt::NString_obj::_hx_ClassId); }({0}.mPtr)", v);

	public static inline function isNFloat(v:Dynamic):Bool
		return untyped __cpp__("[](::hx::Object *o){ return o && o->_hx_isInstanceOf(::nekomata::rt::NFloat_obj::_hx_ClassId); }({0}.mPtr)", v);

	static inline function isTailCall(v:Dynamic):Bool
		return untyped __cpp__("[](::hx::Object *o){ return o && o->_hx_isInstanceOf(::nekomata::rt::TailCall_obj::_hx_ClassId); }({0}.mPtr)", v);

	public static inline function asFunction(v:Dynamic):NFunction
		return untyped __cpp__("::nekomata::rt::NFunction(static_cast< ::nekomata::rt::NFunction_obj * >({0}.mPtr))", v);

	public static inline function asObject(v:Dynamic):NObject
		return untyped __cpp__("::nekomata::rt::NObject(static_cast< ::nekomata::rt::NObject_obj * >({0}.mPtr))", v);

	public static inline function asNString(v:Dynamic):NString
		return untyped __cpp__("::nekomata::rt::NString(static_cast< ::nekomata::rt::NString_obj * >({0}.mPtr))", v);

	static inline function asNFloat(v:Dynamic):NFloat
		return untyped __cpp__("::nekomata::rt::NFloat(static_cast< ::nekomata::rt::NFloat_obj * >({0}.mPtr))", v);

	static inline function asTailCall(v:Dynamic):TailCall
		return untyped __cpp__("::nekomata::rt::TailCall(static_cast< ::nekomata::rt::TailCall_obj * >({0}.mPtr))", v);

	public static inline function isInt(v:Dynamic):Bool
		return vt(v) == VT_INT;

	static inline function isFloat(v:Dynamic):Bool
		return isNFloat(v) || vt(v) == VT_FLOAT;

	static inline function isNumber(v:Dynamic):Bool
		return isInt(v) || isFloat(v);

	static inline function isString(v:Dynamic):Bool
		return isNString(v) || vt(v) == VT_STRING;

	// A number as a Float, for an int or a float
	public static function num(v:Dynamic):Float {
		if (isInt(v))
			return (v : Int);
		if (isNFloat(v))
			return asNFloat(v).v;
		return (v : Float);
	}

	public static inline function float(f:Float):NFloat
		return new NFloat(f);

	public static inline function str(s:String):NString
		return NString.of(s);

	// Bytes of a neko string; a host String counts as one, for errors the host raises
	public static function bytes(v:Dynamic):Bytes {
		if (isNString(v))
			return asNString(v).b;
		return Bytes.ofString(Std.string(v));
	}

	// -- Errors and exceptions --

	// cppia's JIT keeps a pending exception where null means none, so it catches a thrown
	//  null as an empty string; null travels as this marker instead
	static final NULL_THROWN = new NullThrown();

	public static function raise(v:Dynamic):Dynamic {
		if (v == null)
			v = NULL_THROWN;
		NekoStack.recordThrow(v);
		untyped __cpp__("::hx::Throw({0})", v);
		return null;
	}

	public static function error(msg:String):Dynamic
		return raise(NString.of(msg));

	static function opError(op:String):Dynamic
		return error('Invalid operation ($op)');

	// What a trap that catches e leaves in the accumulator, recording the stack
	//  $excstack then returns
	public static function trapped(e:Dynamic):Dynamic {
		NekoStack.catchAt(e);
		return caught(e);
	}

	// The value a translated catch sees: errors the host raises become neko strings
	public static function caught(e:Dynamic):Dynamic {
		if (Std.isOfType(e, NullThrown))
			return null;
		if (vt(e) == VT_STRING)
			return NString.of((e : String));
		if (typeOf(e) == TABSTRACT && !Std.isOfType(e, NAbstract)) {
			// An error the host raised, such as a null access: neko would have its message
			var text = Std.isOfType(e, haxe.Exception) ? (e : haxe.Exception).message : Std.string(e);
			if (trace) {
				Sys.stderr().writeString('[nekomata] host error: $text
');
				for (item in haxe.CallStack.exceptionStack())
					Sys.stderr().writeString('  ${Std.string(item)}
');
			}
			return NString.of(text);
		}
		return e;
	}

	// -- Truth --

	// The Bool opcode: false for false, null and 0
	public static function toBool(v:Dynamic):Bool {
		return switch vt(v) {
			case 0: false;
			case VT_BOOL: (v : Bool);
			case VT_INT: (v : Int) != 0;
			default: true;
		}
	}

	public static inline function not(v:Dynamic):Bool
		return !toBool(v);

	public static inline function isNull(v:Dynamic):Bool
		return v == null;

	public static inline function isNotNull(v:Dynamic):Bool
		return v != null;

	// -- Arithmetic --

	static final H_ADD = nekomata.neko.Hash.field("__add");
	static final H_RADD = nekomata.neko.Hash.field("__radd");
	static final H_SUB = nekomata.neko.Hash.field("__sub");
	static final H_RSUB = nekomata.neko.Hash.field("__rsub");
	static final H_MULT = nekomata.neko.Hash.field("__mult");
	static final H_RMULT = nekomata.neko.Hash.field("__rmult");
	static final H_MOD = nekomata.neko.Hash.field("__mod");
	static final H_RMOD = nekomata.neko.Hash.field("__rmod");
	static final H_DIV = nekomata.neko.Hash.field("__div");
	static final H_RDIV = nekomata.neko.Hash.field("__rdiv");
	static final H_COMPARE = nekomata.neko.Hash.field("__compare");
	static final H_GET = nekomata.neko.Hash.field("__get");
	static final H_SET = nekomata.neko.Hash.field("__set");
	static final H_STRING = nekomata.neko.Hash.field("__string");

	static function objectOp(o:Dynamic, arg:Dynamic, field:Int):Dynamic {
		if (!isObject(o))
			return NO_OP;
		var f = asObject(o).find(field);
		if (f == null)
			return NO_OP;
		return call1(f, o, arg);
	}

	static final NO_OP = new NObject();

	// Whether objectOp found no operator, by identity: an operator may return anything
	static inline function missing(r:Dynamic):Bool
		return untyped __cpp__("({0}.mPtr == {1}.mPtr)", r, NO_OP);

	// Whether a neko type is int or float
	static inline function numeric(t:Int):Bool
		return t == TINT || t == TFLOAT || t == K_HOST_FLOAT;

	// A number of kind k as a Float
	static inline function numberOf(v:Dynamic, k:Int):Float
		return k == TINT ? (v : Int) : k == TFLOAT ? asNFloat(v).v : (v : Float);


	// The operator fields of objects, for an operation on numbers whose operands are not
	//  both numbers
	static function objectOps(a:Dynamic, b:Dynamic, field:Int, rfield:Int, name:String):Dynamic {
		var r:Dynamic = objectOp(a, b, field);
		if (!missing(r))
			return r;
		r = objectOp(b, a, rfield);
		if (!missing(r))
			return r;
		return opError(name);
	}

	public static function mult(a:Dynamic, b:Dynamic):Dynamic {
		var ta = kind(a), tb = kind(b);
		if (ta == TINT && tb == TINT)
			return (a : Int) * (b : Int);
		if (numeric(ta) && numeric(tb))
			return new NFloat(numberOf(a, ta) * numberOf(b, tb));
		return objectOps(a, b, H_MULT, H_RMULT, "*");
	}

	public static function mod(a:Dynamic, b:Dynamic):Dynamic {
		var ta = kind(a), tb = kind(b);
		if (ta == TINT && tb == TINT) {
			var y:Int = b;
			if (y == 0)
				opError("%");
			return (a : Int) % y;
		}
		if (numeric(ta) && numeric(tb))
			return new NFloat(numberOf(a, ta) % numberOf(b, tb));
		return objectOps(a, b, H_MOD, H_RMOD, "%");
	}

	public static function div(a:Dynamic, b:Dynamic):Dynamic {
		var ta = kind(a), tb = kind(b);
		if (numeric(ta) && numeric(tb))
			return new NFloat(numberOf(a, ta) / numberOf(b, tb));
		return objectOps(a, b, H_DIV, H_RDIV, "/");
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
		var ka = kind(a), kb = kind(b);
		if (ka == TINT && kb == TINT)
			return icmp(a, b);
		if (numeric(ka) && numeric(kb))
			return fcmp(numberOf(a, ka), numberOf(b, kb));
		var ta = ka == K_HOST_FLOAT ? TFLOAT : ka == K_HOST_STRING ? TSTRING : ka;
		var tb = kb == K_HOST_FLOAT ? TFLOAT : kb == K_HOST_STRING ? TSTRING : kb;
		if (ta == TSTRING && tb == TSTRING)
			return bcmp(bytes(a), bytes(b));
		if (ta == TSTRING && (tb == TINT || tb == TFLOAT || tb == TBOOL))
			return bcmp(bytes(a), valueBytes(b));
		if (tb == TSTRING && (ta == TINT || ta == TFLOAT || ta == TBOOL))
			return bcmp(valueBytes(a), bytes(b));
		if (ta == TBOOL && tb == TBOOL)
			return (a : Bool) == (b : Bool) ? 0 : (a : Bool) ? 1 : -1;
		if (ta == TOBJECT && tb == TOBJECT) {
			if (untyped __cpp__("{0}.mPtr == {1}.mPtr", a, b))
				return 0;
			var f = asObject(a).find(H_COMPARE);
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

	public static function lte(a:Dynamic, b:Dynamic):Bool {
		if (isInt(a) && isInt(b))
			return (a : Int) <= (b : Int);
		var c = compare(a, b);
		return c <= 0 && c != INVALID;
	}

	public static function gt(a:Dynamic, b:Dynamic):Bool {
		if (isInt(a) && isInt(b))
			return (a : Int) > (b : Int);
		var c = compare(a, b);
		return c > 0 && c != INVALID;
	}

	public static function gte(a:Dynamic, b:Dynamic):Bool {
		if (isInt(a) && isInt(b))
			return (a : Int) >= (b : Int);
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

	// What $setresolver set, per thread as neko's is per VM: called for a field an
	//  object and its prototypes lack
	public static var resolver = new sys.thread.Tls<Dynamic>();

	// Neko names the field when some module declared its name
	static function invalidFieldAccess(h:Int):Dynamic {
		var n = names.get(h);
		return error(n == null ? "Invalid field access" : "Invalid field access : " + n);
	}

	// Returns the value the instruction leaves in the accumulator
	public static function aset(a:Dynamic, i:Dynamic, v:Dynamic):Dynamic {
		if (vt(a) == VT_ARRAY && isInt(i)) {
			untyped __cpp__("[](::hx::Object *o, int k, const ::Dynamic &v) { if (k >= 0 && k < o->__length()) o->__SetItem(k, v); }({0}.mPtr, {1}, {2})", a, (i : Int), v);
			return v;
		}
		if (isObject(a)) {
			var f = asObject(a).find(H_SET);
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

	public static function isSelf(f:Dynamic, module:Dynamic, global:Int):Bool {
		if (!isFunction(f))
			return false;
		var fn = asFunction(f);
		return fn.global == global && fn.kind == Bytecode && untyped __cpp__("{0}.mPtr == {1}.mPtr", fn.module, module);
	}

	public static inline function envOf(f:Dynamic):Array<Dynamic>
		return asFunction(f).env;

	// A tail call becomes a TailCall for the caller to make once the function has
	//  returned: its frame is gone, as neko's TailCall pops it before calling, so neither
	//  the stack nor neko's stack traces keep it
	public static function tailCall(f:Dynamic, th:Dynamic, args:Array<Dynamic>):Dynamic
		return new TailCall(f, th, args.length, args);

	public static function tail0(f:Dynamic, th:Dynamic):Dynamic
		return new TailCall(f, th, 0, null);

	public static function tail1(f:Dynamic, th:Dynamic, a:Dynamic):Dynamic {
		var t = new TailCall(f, th, 1, null);
		t.a = a;
		return t;
	}

	public static function tail2(f:Dynamic, th:Dynamic, a:Dynamic, b:Dynamic):Dynamic {
		var t = new TailCall(f, th, 2, null);
		t.a = a;
		t.b = b;
		return t;
	}

	public static function tail3(f:Dynamic, th:Dynamic, a:Dynamic, b:Dynamic, c:Dynamic):Dynamic {
		var t = new TailCall(f, th, 3, null);
		t.a = a;
		t.b = b;
		t.c = c;
		return t;
	}

	// What a bytecode function returned, once the tail calls it handed back are made.
	//  Each is made from here, so a chain of them does not grow the stack
	public static function finish(r:Dynamic):Dynamic {
		while (isTailCall(r)) {
			var t = asTailCall(r);
			r = switch t.n {
				case 0: enter0(t.f, t.th);
				case 1: enter1(t.f, t.th, t.a);
				case 2: enter2(t.f, t.th, t.a, t.b);
				case 3: enter3(t.f, t.th, t.a, t.b, t.c);
				default: enterArgs(t.f, t.th, t.args);
			}
		}
		return r;
	}

	// NEKOMATA_TRACE=1 says what each failed call was given
	static var trace = Sys.getEnv("NEKOMATA_TRACE") == "1";

	// The translated neko frames on the stack, innermost first
	public static function printStack():Void {
		for (item in haxe.CallStack.callStack())
			switch item {
				case FilePos(_, file, line, _) if (!StringTools.startsWith(file, "nekomata/")):
					Sys.stderr().writeString('  at $file line $line
');
				default:
			}
	}

	static function invalidCall(f:Dynamic, n:Int):Dynamic {
		if (trace) {
			var what = isFunction(f) ? 'a function of ${asFunction(f).nargs} arguments ${asFunction(f).name}' : 'a value of type ${typeOf(f)} (${valueBytes(f).toString().substr(0, 60)})';
			Sys.stderr().writeString('[nekomata] invalid call: $what, given $n
');
			printStack();
		}
		return error("Invalid call");
	}

	// Calls f with the arguments in an array, the way $call and $apply do
	public static function callArgs(f:Dynamic, th:Dynamic, args:Array<Dynamic>):Dynamic
		return finish(enterArgs(f, th, args));

	// The enter functions call f once; a bytecode function may return a TailCall, which
	//  finish makes. The call functions make it too
	static function enterArgs(f:Dynamic, th:Dynamic, args:Array<Dynamic>):Dynamic {
		var n = args.length;
		if (!isFunction(f))
			return invalidCall(f, n);
		var fn = asFunction(f);
		switch fn.kind {
			case Bytecode:
				if (fn.nargs != n)
					return invalidCall(f, n);
				switch n {
					case 0: return fn.fn(th, fn.env);
					case 1: return fn.fn(th, fn.env, args[0]);
					case 2: return fn.fn(th, fn.env, args[0], args[1]);
					case 3: return fn.fn(th, fn.env, args[0], args[1], args[2]);
					default:
						var all:Array<Dynamic> = [th, fn.env];
						return Reflect.callMethod(null, fn.fn, all.concat(args));
				}
			case Primitive:
				if (fn.nargs == NFunction.VAR_ARGS)
					return fn.fn(args);
				if (fn.nargs != n)
					return invalidCall(f, n);
				return Reflect.callMethod(null, fn.fn, args);
			case PrimitiveThis:
				if (fn.nargs == NFunction.VAR_ARGS)
					return fn.fn(th, args);
				if (fn.nargs != n)
					return invalidCall(f, n);
				var all:Array<Dynamic> = [th];
				return Reflect.callMethod(null, fn.fn, all.concat(args));
			case Bound:
				if (fn.nargs != NFunction.VAR_ARGS && fn.nargs != n)
					return invalidCall(f, n);
				return fn.fn(fn.env, args);
		}
	}

	static function enter0(f:Dynamic, th:Dynamic):Dynamic {
		if (isFunction(f)) {
			var fn = asFunction(f);
			if (fn.nargs == 0)
				switch fn.kind {
					case Bytecode:
						return fn.fn(th, fn.env);
					case Primitive:
						return fn.fn();
					case PrimitiveThis:
						return fn.fn(th);
					case Bound:
						return fn.fn(fn.env, []);
				}
		}
		return enterArgs(f, th, []);
	}

	static function enter1(f:Dynamic, th:Dynamic, a:Dynamic):Dynamic {
		if (isFunction(f)) {
			var fn = asFunction(f);
			if (fn.nargs == 1)
				switch fn.kind {
					case Bytecode:
						return fn.fn(th, fn.env, a);
					case Primitive:
						return fn.fn(a);
					case PrimitiveThis:
						return fn.fn(th, a);
					case Bound:
						return fn.fn(fn.env, [a]);
				}
		}
		return enterArgs(f, th, [a]);
	}

	static function enter2(f:Dynamic, th:Dynamic, a:Dynamic, b:Dynamic):Dynamic {
		if (isFunction(f)) {
			var fn = asFunction(f);
			if (fn.nargs == 2)
				switch fn.kind {
					case Bytecode:
						return fn.fn(th, fn.env, a, b);
					case Primitive:
						return fn.fn(a, b);
					case PrimitiveThis:
						return fn.fn(th, a, b);
					case Bound:
						return fn.fn(fn.env, [a, b]);
				}
		}
		return enterArgs(f, th, [a, b]);
	}

	static function enter3(f:Dynamic, th:Dynamic, a:Dynamic, b:Dynamic, c:Dynamic):Dynamic {
		if (isFunction(f)) {
			var fn = asFunction(f);
			if (fn.nargs == 3)
				switch fn.kind {
					case Bytecode:
						return fn.fn(th, fn.env, a, b, c);
					case Primitive:
						return fn.fn(a, b, c);
					case PrimitiveThis:
						return fn.fn(th, a, b, c);
					case Bound:
						return fn.fn(fn.env, [a, b, c]);
				}
		}
		return enterArgs(f, th, [a, b, c]);
	}

	public static function call5(f:Dynamic, th:Dynamic, a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic):Dynamic
		return callArgs(f, th, [a, b, c, d, e]);

	// The Apply opcode: bind the first arguments, or call when they are all there
	public static function apply(f:Dynamic, th:Dynamic, args:Array<Dynamic>):Dynamic {
		if (!isFunction(f))
			return error("$apply");
		var fn = asFunction(f);
		if (fn.nargs == args.length || fn.nargs == NFunction.VAR_ARGS)
			return callArgs(f, th, args);
		if (args.length > fn.nargs)
			return error("$apply");
		return bind(fn, th, args, fn.nargs - args.length);
	}

	// The one native function every bound function shares, so same_closure can tell
	//  two of them apart by their environments alone, as neko does
	public static var boundCall:Dynamic = function(env:Array<Dynamic>, args:Array<Dynamic>):Dynamic
		return callArgs(env[0], env[1], env.slice(2).concat(args));

	// f with this and the first arguments bound, taking nargs more
	public static function bind(f:Dynamic, th:Dynamic, args:Array<Dynamic>, nargs:Int):NFunction {
		var env:Array<Dynamic> = [f, th];
		return new NFunction(boundCall, nargs, Bound, env.concat(args));
	}

	// Physical equality of neko values: ints by value, everything else by identity
	public static function physEqual(a:Dynamic, b:Dynamic):Bool
		return same(a, b);

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
		if (isNString(v))
			return asNString(v).b;
		var buf = new BytesBuffer();
		appendValue(buf, v);
		return buf.getBytes();
	}

	public static function toNString(v:Dynamic):NString {
		if (isNString(v))
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
				buf.addString('#function:${asFunction(v).nargs}');
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
				var o = asObject(v);
				var f = o.find(H_STRING);
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
