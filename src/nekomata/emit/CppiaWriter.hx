package nekomata.emit;

import haxe.io.Bytes;

// A cppia expression, as the loader's createCppiaExpr reads it
enum E {
	EBlock(es:Array<E>);
	EVar(id:Int);
	ESet(l:E, r:E);
	EInt(v:Int);
	EString(s:String);
	EBool(v:Bool);
	ENull;
	ECallStatic(cls:String, field:String, args:Array<E>);
	EStatic(cls:String, field:String);
	EArrayI(arr:E, index:E);
	EArrayDef(items:Array<E>);
	EIf(cond:E, then:E);
	EIfElse(cond:E, then:E, otherwise:E);
	EWhile(cond:E, body:E);
	ESwitch(cond:E, cases:Array<{value:Int, body:E}>);
	ETry(body:E, v:Local, handler:E);
	EReturn(e:E);
	EThrow(e:E);
	EContinue;
	EBreak;
	EDecl(v:Local, init:E);
	// Locals declared together: with no init, a local starts as null, or 0 for an int
	EVars(vars:Array<{v:Local, init:Null<E>}>);
	ENot(e:E);
	EIsNull(e:E);
	ENotNull(e:E);
	// One of cppia's operators on two values, such as + or <
	EBinop(op:String, a:E, b:E);
	// The source line for the expression and the ones it contains; file is a string id
	EPos(file:Int, line:Int, e:E);
}

typedef Local = {
	var name:String;
	var id:Int;
	var type:String;
}

// Writes the text form of cppia (CPPIA magic), as Haxe's gencpp script_writer does
//  with -debug, for the host's loader. The text goes straight into bytes
@:build(nekomata.build.NoFrames.build())
class CppiaWriter {
	public static inline var DYNAMIC = "Dynamic";
	public static inline var ARRAY = "Array.Object";
	public static inline var INT = "int";

	var strings:Array<String> = [];
	var stringIds = new Map<String, Int>();
	var types:Array<String> = [];
	var typeIds = new Map<String, Int>();
	var out = new Out();
	var classCount = 0;
	var classNames:Array<String> = [];
	// Where the names of the classes are in the bytes toBytes gives
	public var classOffsets(default, null):Array<Int> = [];
	var file = 0;
	var line = 0;
	// The return type of the function being written, by id
	var retType = 0;
	var arrayType:Int;
	var dynamicType:Int;

	public function new() {
		// Type 0 means none, as in Haxe's output
		typeId("");
		stringId("");
		arrayType = typeId(ARRAY);
		dynamicType = typeId(DYNAMIC);
	}

	public function stringId(s:String):Int {
		var id = stringIds.get(s);
		if (id == null) {
			id = strings.length;
			strings.push(s);
			stringIds.set(s, id);
		}
		return id;
	}

	public function typeId(name:String):Int {
		var id = typeIds.get(name);
		if (id == null) {
			id = types.length;
			types.push(name);
			typeIds.set(name, id);
		}
		return id;
	}

	inline function w(s:String)
		out.ascii(s);

	inline function wi(i:Int) {
		out.int(i);
		out.byte(" ".code);
	}

	public function beginClass(name:String, fieldCount:Int) {
		classCount++;
		classNames.push(name);
		w("CLASS ");
		wi(typeId(name));
		w("0 0\n");
		wi(fieldCount);
		w("\n");
	}

	public function staticVar(name:String, type:String) {
		w("VAR 1 N N 0 ");
		wi(stringId(name));
		wi(typeId(type));
		w("0\n");
	}

	// file (a string id) and line are the function's own position, which stack frames report
	public function staticFunction(name:String, args:Array<Local>, ret:String, fnBody:E, file:Int, line:Int) {
		this.file = file;
		this.line = line;
		retType = typeId(ret);
		w("FUNCTION 1 0 ");
		wi(stringId(name));
		wi(typeId(ret));
		wi(args.length);
		for (a in args) {
			wi(stringId(a.name));
			w("0 ");
			wi(typeId(a.type));
		}
		w("\n");
		prefix();
		w("FUN ");
		wi(typeId(ret));
		wi(args.length);
		w("\n");
		for (a in args) {
			local(a);
			w("0\n");
		}
		expr(fnBody);
	}

	public function main(e:E) {
		retType = dynamicType;
		w("MAIN\n");
		expr(e);
	}

	// Each expression starts with its file and line
	inline function prefix() {
		wi(file);
		wi(line);
	}

	function local(v:Local) {
		wi(stringId(v.name));
		wi(v.id);
		w("0 ");
		wi(typeId(v.type));
	}

	function exprs(es:Array<E>) {
		wi(es.length);
		w("\n");
		for (e in es)
			expr(e);
	}

	public function expr(e:E) {
		switch e {
			case EPos(f, l, inner):
				var oldFile = file, oldLine = line;
				file = f;
				line = l;
				expr(inner);
				file = oldFile;
				line = oldLine;
				return;
			default:
		}
		prefix();
		switch e {
			case EBlock(es):
				w("BLOCK ");
				exprs(es);
			case EVar(id):
				w("VAR ");
				wi(id);
				w("\n");
			case ESet(l, r):
				w("SET\n");
				expr(l);
				expr(r);
			case EInt(v):
				w("i ");
				wi(v);
				w("\n");
			case EString(s):
				w("s ");
				wi(stringId(s));
				w("\n");
			case EBool(v):
				w(v ? "true\n" : "false\n");
			case ENull:
				w("NULL\n");
			case ECallStatic(cls, field, args):
				w("CALLSTATIC ");
				wi(typeId(cls));
				wi(stringId(field));
				exprs(args);
			case EStatic(cls, field):
				w("FSTATIC ");
				wi(typeId(cls));
				wi(stringId(field));
				w("\n");
			case EArrayI(arr, index):
				w("ARRAYI ");
				wi(arrayType);
				w("\n");
				expr(arr);
				expr(index);
			case EArrayDef(items):
				w("ADEF ");
				wi(arrayType);
				exprs(items);
			case EIf(cond, then):
				w("IF\n");
				expr(cond);
				expr(then);
			case EIfElse(cond, then, otherwise):
				w("IFELSE\n");
				expr(cond);
				expr(then);
				expr(otherwise);
			case EWhile(cond, loop):
				w("WHILE 1\n");
				expr(cond);
				expr(loop);
			case ESwitch(cond, cases):
				w("SWITCH ");
				wi(cases.length);
				w("0\n");
				expr(cond);
				for (c in cases) {
					w("1\n");
					expr(EInt(c.value));
					expr(c.body);
				}
			case ETry(tryBody, v, handler):
				w("TRY 1\n");
				expr(tryBody);
				local(v);
				w("\n");
				expr(handler);
			case EReturn(value):
				w("RETVAL ");
				wi(retType);
				w("\n");
				expr(value);
			case EThrow(value):
				w("THROW\n");
				expr(value);
			case EBreak:
				w("BREAK\n");
			case EContinue:
				w("CONTINUE\n");
			case EVars(vars):
				w("TVARS ");
				wi(vars.length);
				w("\n");
				for (d in vars) {
					if (d.init == null) {
						w("VARDECL ");
						local(d.v);
						w("\n");
					} else {
						w("VARDECLI ");
						local(d.v);
						wi(typeId(d.v.type));
						w("\n");
						expr(d.init);
					}
				}
			case EDecl(v, init):
				w("TVARS 1\nVARDECLI ");
				local(v);
				wi(typeId(v.type));
				w("\n");
				expr(init);
			case ENot(value):
				w("!\n");
				expr(value);
			case EIsNull(value):
				w("ISNULL\n");
				expr(value);
			case ENotNull(value):
				w("NOTNULL\n");
				expr(value);
			case EBinop(op, a, b):
				w(op);
				w("\n");
				expr(a);
				expr(b);
			case EPos(_, _, _):
		}
	}

	// The whole module: header, string and type tables, then the classes and main
	public function toBytes():Bytes {
		var head = new Out();
		head.ascii("CPPIA\n");
		head.int(strings.length);
		head.byte("\n".code);
		for (s in strings) {
			var b = Bytes.ofString(s);
			head.int(b.length);
			head.byte(" ".code);
			head.bytes(b);
			head.byte("\n".code);
		}
		head.int(types.length);
		head.byte("\n".code);
		for (t in types) {
			var b = Bytes.ofString(t);
			head.int(b.length);
			head.byte(" ".code);
			if (classNames.indexOf(t) >= 0)
				classOffsets.push(head.length);
			head.bytes(b);
			head.byte("\n".code);
		}
		head.int(classCount);
		head.byte("\n".code);
		out.ascii("RESOURCES 0\n");
		var result = Bytes.alloc(head.length + out.length);
		result.blit(0, head.buf, 0, head.length);
		result.blit(head.length, out.buf, 0, out.length);
		return result;
	}
}

// A growable run of bytes that ints and ASCII text are written into
@:build(nekomata.build.NoFrames.build())
class Out {
	public var buf:Bytes;
	public var length = 0;

	public function new()
		buf = Bytes.alloc(1 << 16);

	inline function need(n:Int)
		if (length + n > buf.length)
			grow(n);

	function grow(n:Int) {
		var size = buf.length * 2;
		while (size < length + n)
			size *= 2;
		var b = Bytes.alloc(size);
		b.blit(0, buf, 0, length);
		buf = b;
	}

	// Sets a byte the buffer has room for
	inline function put(i:Int, c:Int) {
		#if cpp
		cpp.NativeArray.unsafeSet(buf.getData(), i, c);
		#else
		buf.set(i, c);
		#end
	}

	public inline function byte(c:Int) {
		need(1);
		put(length++, c);
	}

	// Text the writer knows is ASCII
	public function ascii(s:String) {
		var n = s.length;
		need(n);
		for (i in 0...n)
			put(length + i, StringTools.fastCodeAt(s, i));
		length += n;
	}

	public function bytes(b:Bytes) {
		need(b.length);
		buf.blit(length, b, 0, b.length);
		length += b.length;
	}

	public function int(v:Int) {
		need(11);
		if (v < 0) {
			if (v == -2147483648) {
				ascii("-2147483648");
				return;
			}
			put(length++, "-".code);
			v = -v;
		}
		if (v < 10) {
			put(length++, "0".code + v);
			return;
		}
		var digits = 0, t = v;
		while (t > 0) {
			digits++;
			t = div10(t);
		}
		var p = length + digits;
		length = p;
		while (v > 0) {
			var q = div10(v);
			put(--p, "0".code + (v - q * 10));
			v = q;
		}
	}

	static inline function div10(v:Int):Int {
		#if cpp
		return untyped __cpp__("({0} / 10)", v);
		#else
		return Std.int(v / 10);
		#end
	}
}
