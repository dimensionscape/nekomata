package nekomata.emit;

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
	EWhile(cond:E, body:E);
	ESwitch(cond:E, cases:Array<{value:Int, body:E}>);
	ETry(body:E, v:Local, handler:E);
	EReturn(e:E);
	EThrow(e:E);
	EContinue;
	EDecl(v:Local, init:E);
	// The source position for the expression and the ones it contains
	EPos(file:String, line:Int, e:E);
}

typedef Local = {
	var name:String;
	var id:Int;
	var type:String;
}

// Writes the text form of cppia (CPPIA magic), as Haxe's gencpp script_writer does
//  with -debug, for the host's loader
class CppiaWriter {
	public static inline var DYNAMIC = "Dynamic";
	public static inline var ARRAY = "Array.Any";
	public static inline var INT = "int";

	var strings:Array<String> = [];
	var stringIds = new Map<String, Int>();
	var types:Array<String> = [];
	var typeIds = new Map<String, Int>();
	var body = new StringBuf();
	var classCount = 0;
	var file:String = "";
	var line:Int = 0;

	public function new() {
		// Type 0 means none, as in Haxe's output
		typeId("");
		stringId("");
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
		body.add(s);

	inline function wi(i:Int) {
		body.add(i);
		body.add(" ");
	}

	public function beginClass(name:String, fieldCount:Int) {
		classCount++;
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

	// file and line are the function's own position, which stack frames report
	public function staticFunction(name:String, args:Array<Local>, ret:String, fnBody:E, file:String, line:Int) {
		this.file = file;
		this.line = line;
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
		w("MAIN\n");
		expr(e);
	}

	// Each expression starts with its file and line
	inline function prefix() {
		wi(stringId(file));
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
				wi(typeId(ARRAY));
				w("\n");
				expr(arr);
				expr(index);
			case EArrayDef(items):
				w("ADEF ");
				wi(typeId(ARRAY));
				exprs(items);
			case EIf(cond, then):
				w("IF\n");
				expr(cond);
				expr(then);
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
				wi(typeId(DYNAMIC));
				w("\n");
				expr(value);
			case EThrow(value):
				w("THROW\n");
				expr(value);
			case EContinue:
				w("CONTINUE\n");
			case EDecl(v, init):
				w("TVARS 1\nVARDECLI ");
				local(v);
				wi(typeId(v.type));
				w("\n");
				expr(init);
			case EPos(_, _, _):
		}
	}

	public function toString():String {
		var out = new StringBuf();
		out.add("CPPIA\n");
		out.add(strings.length);
		out.add("\n");
		for (s in strings) {
			out.add(haxe.io.Bytes.ofString(s).length);
			out.add(" ");
			out.add(s);
			out.add("\n");
		}
		out.add(types.length);
		out.add("\n");
		for (t in types) {
			out.add(haxe.io.Bytes.ofString(t).length);
			out.add(" ");
			out.add(t);
			out.add("\n");
		}
		out.add(classCount);
		out.add("\n");
		out.add(body.toString());
		out.add("RESOURCES 0\n");
		return out.toString();
	}
}
