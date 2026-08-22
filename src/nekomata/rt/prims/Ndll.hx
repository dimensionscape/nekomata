package nekomata.rt.prims;

import haxe.io.Bytes;
import haxe.io.BytesData;
import nekomata.rt.Values;

// What a CFFI library's primitives remember about it: the file, and what its neko_init
//  was given. Neko's CFFI glue makes Haxe Strings and Arrays with the two constructors
//  that neko_init passes, so values the library returns are made the same way here
@:keep
class NdllLib {
	// The file as neko's search names it, for messages, and its full path for libhxcpp
	public var file:String;
	public var path:String;
	public var newString:Dynamic;
	public var newArray:Dynamic;

	public function new(file:String, path:String) {
		this.file = file;
		this.path = path;
	}
}

// Third-party ndlls built with hxcpp's CFFI (hx/CFFI.h), as lime's and openfl's are. The
//  same binary runs on neko and on hxcpp, since it finds its val_* API at run time from
//  whichever host loaded it, so libhxcpp loads it here and it gets hxcpp's API.
//
//  Its primitives then take and return hxcpp values, and neko values convert at the
//  boundary the way Haxe's neko values map onto Haxe's hxcpp ones: a Haxe String object
//  is a String, a neko string is the byte array a Haxe BytesData is on hxcpp (a CFFI
//  buffer), a float is a Float. Objects, arrays and functions go over as proxies that
//  read, write and call the neko value itself, so an ndll that keeps one and fills it in
//  or calls it later works on the neko value. What comes back is made as neko's CFFI glue
//  makes it: strings and arrays with neko_init's constructors when the program called it,
//  objects as neko objects.
//
//  Ndlls built against libneko itself (neko.dll, libneko.so) read neko's value layout
//  directly, and need a libneko of Nekomata's own; PLAN.md describes it
@:keep
@:cppFileCode('
typedef hx::Object *(*nk_prim0)();
typedef hx::Object *(*nk_prim1)(hx::Object *);
typedef hx::Object *(*nk_prim2)(hx::Object *, hx::Object *);
typedef hx::Object *(*nk_prim3)(hx::Object *, hx::Object *, hx::Object *);
typedef hx::Object *(*nk_prim4)(hx::Object *, hx::Object *, hx::Object *, hx::Object *);
typedef hx::Object *(*nk_prim5)(hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *);
typedef hx::Object *(*nk_prim6)(hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *);
typedef hx::Object *(*nk_prim7)(hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *);
typedef hx::Object *(*nk_prim8)(hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *);
typedef hx::Object *(*nk_prim9)(hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *, hx::Object *);
typedef hx::Object *(*nk_prim_mult)(hx::Object **, int);

// A primitive an ndll gave: its C function and how many arguments it takes
struct NkPrim : public hx::Object
{
   void *mProc;
   int mArgs;
   NkPrim(void *inProc, int inArgs) : mProc(inProc), mArgs(inArgs) { }
   String __ToString() const HXCPP_OVERRIDE { return HX_CSTRING("#ndll_primitive"); }
};

// The primitive inName of the library at inPath, loading the library the first time,
//  as cpp.Lib.load does. Null when the library has no such primitive; throws when it
//  does not load. The symbol is a function that returns the primitive; libhxcpp calls
//  it even when the symbol is missing if asked to fail quietly, so it is called here
static ::Dynamic nk_ndll_proc(String inPath, String inName, int inArgs)
{
   typedef void *(*Query)();
   Query query = (Query)__hxcpp_get_proc_address(inPath, inName, false, true);
   void *proc = query ? query() : 0;
   if (!proc)
      return null();
   return new NkPrim(proc, inArgs);
}

static ::Dynamic nk_ndll_call(::Dynamic inPrim, Array< ::Dynamic > a)
{
   NkPrim *p = static_cast<NkPrim *>(inPrim.mPtr);
   void *f = p->mProc;
   #define NK_A(i) a[i].mPtr
   switch(p->mArgs)
   {
      case 0: return ((nk_prim0)f)();
      case 1: return ((nk_prim1)f)(NK_A(0));
      case 2: return ((nk_prim2)f)(NK_A(0), NK_A(1));
      case 3: return ((nk_prim3)f)(NK_A(0), NK_A(1), NK_A(2));
      case 4: return ((nk_prim4)f)(NK_A(0), NK_A(1), NK_A(2), NK_A(3));
      case 5: return ((nk_prim5)f)(NK_A(0), NK_A(1), NK_A(2), NK_A(3), NK_A(4));
      case 6: return ((nk_prim6)f)(NK_A(0), NK_A(1), NK_A(2), NK_A(3), NK_A(4), NK_A(5));
      case 7: return ((nk_prim7)f)(NK_A(0), NK_A(1), NK_A(2), NK_A(3), NK_A(4), NK_A(5), NK_A(6));
      case 8: return ((nk_prim8)f)(NK_A(0), NK_A(1), NK_A(2), NK_A(3), NK_A(4), NK_A(5), NK_A(6), NK_A(7));
      case 9: return ((nk_prim9)f)(NK_A(0), NK_A(1), NK_A(2), NK_A(3), NK_A(4), NK_A(5), NK_A(6), NK_A(7), NK_A(8));
      default: return ((nk_prim_mult)f)((hx::Object **)a->GetBase(), a->length);
   }
   #undef NK_A
}

enum { nkObject, nkArray, nkFunction };

// A neko object, array or function as the hxcpp value an ndll reads, writes and calls:
//  val_field, alloc_field, val_array_i, val_call and the rest reach the neko value
struct NkProxy : public hx::Object
{
   int mKind;
   ::Dynamic mValue;
   // The object a function was read from, its this when the ndll calls it
   ::Dynamic mThis;
   ::Dynamic mLib;

   NkProxy(int inKind, ::Dynamic inValue, ::Dynamic inThis, ::Dynamic inLib)
      : mKind(inKind), mValue(inValue), mThis(inThis), mLib(inLib) { }

   int __GetType() const HXCPP_OVERRIDE
      { return mKind==nkFunction ? vtFunction : mKind==nkArray ? vtArray : vtObject; }

   hx::Val __Field(const String &inName, hx::PropertyAccess inCallProp) HXCPP_OVERRIDE
      { return ::nekomata::rt::prims::Ndll_obj::proxyField(mLib, mValue, inName); }

   hx::Val __SetField(const String &inName, const hx::Val &inValue, hx::PropertyAccess inCallProp) HXCPP_OVERRIDE
   {
      ::nekomata::rt::prims::Ndll_obj::proxySetField(mLib, mValue, inName, (::Dynamic)inValue);
      return inValue;
   }

   void __GetFields(Array<String> &outFields) HXCPP_OVERRIDE
      { ::nekomata::rt::prims::Ndll_obj::proxyFields(mValue, outFields); }

   int __length() const HXCPP_OVERRIDE
      { return ::nekomata::rt::prims::Ndll_obj::proxyLength(mValue); }

   ::Dynamic __GetItem(int inIndex) const HXCPP_OVERRIDE
      { return ::nekomata::rt::prims::Ndll_obj::proxyItem(mLib, mValue, inIndex); }

   ::Dynamic __SetItem(int inIndex, ::Dynamic inValue) HXCPP_OVERRIDE
   {
      ::nekomata::rt::prims::Ndll_obj::proxySetItem(mLib, mValue, inIndex, inValue);
      return inValue;
   }

   int __ArgCount() const HXCPP_OVERRIDE
      { return mKind==nkFunction ? ::nekomata::rt::prims::Ndll_obj::proxyArgCount(mValue) : -1; }

   ::Dynamic __Run(const Array< ::Dynamic > &inArgs) HXCPP_OVERRIDE
      { return ::nekomata::rt::prims::Ndll_obj::proxyCall(mLib, mValue, mThis, inArgs); }

   String toString() HXCPP_OVERRIDE
      { return ::nekomata::rt::prims::Ndll_obj::proxyString(mValue); }

   String __ToString() const HXCPP_OVERRIDE
      { return ::nekomata::rt::prims::Ndll_obj::proxyString(mValue); }

   void __Mark(hx::MarkContext *__inCtx) HXCPP_OVERRIDE
   {
      HX_MARK_MEMBER(mValue);
      HX_MARK_MEMBER(mThis);
      HX_MARK_MEMBER(mLib);
   }

   #ifdef HXCPP_VISIT_ALLOCS
   void __Visit(hx::VisitContext *__inCtx) HXCPP_OVERRIDE
   {
      HX_VISIT_MEMBER(mValue);
      HX_VISIT_MEMBER(mThis);
      HX_VISIT_MEMBER(mLib);
   }
   #endif
};

static ::Dynamic nk_proxy(int inKind, ::Dynamic inValue, ::Dynamic inThis, ::Dynamic inLib)
{
   return new NkProxy(inKind, inValue, inThis, inLib);
}

static bool nk_is_proxy(::Dynamic inValue)
{
   return dynamic_cast<NkProxy *>(inValue.mPtr) != 0;
}

static ::Dynamic nk_unproxy(::Dynamic inValue)
{
   return static_cast<NkProxy *>(inValue.mPtr)->mValue;
}

// The byte array of a CFFI buffer (what val_to_buffer accepts), or null
static Array<unsigned char> nk_buffer(::Dynamic inValue)
{
   hx::Object *obj = inValue.mPtr;
   hx::ArrayCommon *common = dynamic_cast<hx::ArrayCommon *>(obj);
   if (common)
      obj = common->__GetRealObject();
   Array_obj<unsigned char> *bytes = dynamic_cast<Array_obj<unsigned char> *>(obj);
   return bytes ? Array<unsigned char>(bytes) : Array<unsigned char>();
}

// Neko strings end in a NUL, which ndlls reading val_string count on; a Haxe byte array
//  gets one past its end, in room the array owns
static void nk_terminate(Array<unsigned char> inBytes)
{
   int len = inBytes->length;
   if (inBytes->capacity() <= len)
      inBytes->reserve(len + 1);
   inBytes->GetBase()[len] = 0;
}

static bool nk_contains(Array<unsigned char> inData, String inText)
{
   const char *text = inText.utf8_str();
   int n = (int)strlen(text);
   const unsigned char *p = (const unsigned char *)inData->GetBase();
   int len = inData->length;
   for(int i = 0; i + n <= len; i++)
      if (p[i]==(unsigned char)text[0] && !memcmp(p + i, text, n))
         return true;
   return false;
}
')
class Ndll {
	// Neko's own libraries, which are built against libneko: Nekomata serves what it
	//  supports of them from Haxe code, and a primitive it lacks fails when it is called
	static final NEKO_LIBS = [
		"std", "regexp", "zlib", "ssl", "sqlite", "mysql", "mysql5", "ui", "mod_neko", "mod_neko2", "mod_tora", "mod_tora2"
	];

	static inline var VT_NULL = 0;
	static inline var VT_FLOAT = 1;
	static inline var VT_BOOL = 2;
	static inline var VT_STRING = 3;
	static inline var VT_OBJECT = 4;
	static inline var VT_ARRAY = 5;
	static inline var VT_FUNCTION = 6;
	static inline var VT_CLASS = 8;
	static inline var VT_INT = 0xff;

	static inline var PROXY_OBJECT = 0;
	static inline var PROXY_ARRAY = 1;
	static inline var PROXY_FUNCTION = 2;

	static var trace = Sys.getEnv("NEKOMATA_TRACE") == "1";

	// The libraries opened, by the name before the @, as neko's loader keeps them; and
	//  by full path, as several names can find one file and its neko_init is shared
	static var libs = new Map<String, NdllLib>();
	static var files = new Map<String, NdllLib>();
	static var lock = new sys.thread.Mutex();

	static var H_S = nekomata.neko.Hash.field("__s");
	static var H_A = nekomata.neko.Hash.field("__a");
	static var H_LENGTH = nekomata.neko.Hash.field("length");
	static var H_SET = nekomata.neko.Hash.field("__set");
	static var H_PATH = nekomata.neko.Hash.field("path");

	// The primitive lib@name with nargs arguments from lib.ndll, found as neko finds it.
	//  Null for neko's own libraries and names without a library; otherwise it fails as
	//  neko does when the library does not load or lacks the primitive
	public static function find(loader:Dynamic, name:String, nargs:Int):Null<NFunction> {
		var at = name.indexOf("@");
		if (at < 0)
			return null;
		var libName = name.substr(0, at);
		if (NEKO_LIBS.indexOf(libName) >= 0)
			return null;
		var prim = name.substr(at + 1);
		var lib:NdllLib = null;
		lock.acquire();
		try {
			lib = open(loader, libName);
		} catch (e:Dynamic) {
			lock.release();
			untyped __cpp__("::hx::Throw({0})", e);
		}
		lock.release();
		var symbol = prim + (nargs == NFunction.VAR_ARGS ? "__MULT" : "__" + nargs);
		var proc:Dynamic = prim.length > 90 ? null : untyped __cpp__("nk_ndll_proc({0}, {1}, {2})", lib.path, symbol, nargs);
		if (proc == null)
			return failure('Primitive not found : $name($nargs)', 357);
		if (trace)
			Sys.stderr().writeString('[nekomata] ndll primitive $name($nargs) from ${lib.file}
');
		// neko_init hands neko's glue the values it builds with; the glue is not used under
		//  libhxcpp's API, so the call only records the constructors
		if (prim == "neko_init" && nargs == 5)
			return new NFunction(function(newString:Dynamic, newArray:Dynamic, nul:Dynamic, t:Dynamic, f:Dynamic):Dynamic {
				lib.newString = newString;
				lib.newArray = newArray;
				return null;
			}, 5, Primitive, null, null, name);
		return new NFunction(fixedArity(nargs, args -> invoke(lib, proc, args)), nargs, Primitive, null, null, name);
	}

	// load_primitive: the library a loader opened under this name, or the file neko's
	//  search finds, loaded once
	static function open(loader:Dynamic, libName:String):NdllLib {
		var lib = libs.get(libName);
		if (lib != null)
			return lib;
		var path = Std.isOfType(loader, NObject) ? (loader : NObject).find(H_PATH) : null;
		var file = selectFile(path, libName, ".ndll");
		if (!sys.FileSystem.exists(file) || sys.FileSystem.isDirectory(file))
			failure("Failed to load library : " + file, 237);
		var full = sys.FileSystem.fullPath(file);
		lib = files.get(full);
		if (lib == null) {
			var data = sys.io.File.getBytes(full).getData();
			// Every CFFI library exports hx_set_loader, which libhxcpp gives its API to
			if (!untyped __cpp__("nk_contains({0}, {1})", data, "hx_set_loader"))
				failure("Failed to load library : " + file + " (not built with hxcpp's CFFI, and Nekomata has no libneko)", 237);
			lib = new NdllLib(file, full);
			try {
				// A name no library registers, so libhxcpp loads the file instead of finding
				//  the primitive among those other libraries registered
				untyped __cpp__("nk_ndll_proc({0}, {1}, 0)", full, "__nekomata_open__");
			} catch (e:Dynamic) {
				if (trace)
					Sys.stderr().writeString('[nekomata] $full: ${Std.string(e)}
');
				failure("Failed to load library : " + file, 237);
			}
			if (trace)
				Sys.stderr().writeString('[nekomata] loaded ndll $full
');
			files.set(full, lib);
		}
		libs.set(libName, lib);
		return lib;
	}

	// neko_select_file: the file itself, then each directory of the loader's path
	static function selectFile(path:Dynamic, file:String, ext:String):String {
		var ff = file + ext;
		if (sys.FileSystem.exists(ff))
			return file.indexOf("/") >= 0 || file.indexOf("\\") >= 0 ? ff : "./" + ff;
		while (Std.isOfType(path, Array) && (path : Array<Dynamic>).length == 2) {
			var cell:Array<Dynamic> = path;
			var p = Rt.valueBytes(cell[0]).toString() + ff;
			if (sys.FileSystem.exists(p))
				return p;
			path = cell[1];
		}
		return ff;
	}

	// What neko's failure() throws: an object that prints as file(line) : msg
	static function failure(msg:String, line:Int):Dynamic {
		Rt.registerFields(["msg", "file", "line", "__string"]);
		var o = new NObject();
		o.fields.set(nekomata.neko.Hash.field("msg"), NString.of(msg));
		o.fields.set(nekomata.neko.Hash.field("file"), NString.of("load.c"));
		o.fields.set(nekomata.neko.Hash.field("line"), line);
		o.fields.set(nekomata.neko.Hash.field("__string"), new NFunction(function(th:Dynamic):Dynamic {
			var f:NObject = th;
			var b = new haxe.io.BytesBuffer();
			Rt.appendValue(b, f.find(nekomata.neko.Hash.field("file")));
			b.addString("(");
			Rt.appendValue(b, f.find(nekomata.neko.Hash.field("line")));
			b.addString(") : ");
			Rt.appendValue(b, f.find(nekomata.neko.Hash.field("msg")));
			return new NString(b.getBytes());
		}, 0, PrimitiveThis, null, null, "failure_to_string"));
		return Rt.raise(o);
	}

	// A neko function of nargs arguments that hands them to call as an array
	static function fixedArity(nargs:Int, call:Array<Dynamic>->Dynamic):Dynamic {
		return switch nargs {
			case 0: function():Dynamic return call([]);
			case 1: function(a:Dynamic):Dynamic return call([a]);
			case 2: function(a:Dynamic, b:Dynamic):Dynamic return call([a, b]);
			case 3: function(a:Dynamic, b:Dynamic, c:Dynamic):Dynamic return call([a, b, c]);
			case 4: function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic):Dynamic return call([a, b, c, d]);
			case 5: function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic):Dynamic return call([a, b, c, d, e]);
			case 6: function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic, f:Dynamic):Dynamic return call([a, b, c, d, e, f]);
			case 7: function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic, f:Dynamic, g:Dynamic):Dynamic return call([a, b, c, d, e, f, g]);
			case 8: function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic, f:Dynamic, g:Dynamic,
					h:Dynamic):Dynamic return call([a, b, c, d, e, f, g, h]);
			case 9: function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic, f:Dynamic, g:Dynamic, h:Dynamic,
					i:Dynamic):Dynamic return call([a, b, c, d, e, f, g, h, i]);
			default: call;
		}
	}

	static function invoke(lib:NdllLib, proc:Dynamic, args:Array<Dynamic>):Dynamic {
		var host:Array<Dynamic> = [for (a in args) toHost(lib, a)];
		var r:Dynamic = null;
		try {
			r = untyped __cpp__("nk_ndll_call({0}, {1})", proc, host);
		} catch (e:Dynamic) {
			raised(lib, e);
		}
		return toNeko(lib, r);
	}

	// Calls an hxcpp function an ndll returned
	static function callHost(lib:NdllLib, f:Dynamic, args:Array<Dynamic>):Dynamic {
		var host:Array<Dynamic> = [for (a in args) toHost(lib, a)];
		var r:Dynamic = null;
		try {
			r = Reflect.callMethod(null, f, host);
		} catch (e:Dynamic) {
			raised(lib, e);
		}
		return toNeko(lib, r);
	}

	// An exception out of an ndll call. One neko code raised in a callback goes on as it
	//  is; one the ndll raised (val_throw, hx_fail, neko_error) is a neko value from here
	static function raised(lib:NdllLib, e:Dynamic):Dynamic {
		var v = toNeko(lib, e);
		if (untyped __cpp__("{0}.mPtr == {1}.mPtr", v, e))
			untyped __cpp__("::hx::Throw({0})", e);
		return Rt.raise(v);
	}

	static inline function vt(v:Dynamic):Int
		return v == null ? VT_NULL : untyped v.__GetType();

	// -- Neko values as an ndll takes them --

	public static function toHost(lib:Dynamic, v:Dynamic, ?th:Dynamic):Dynamic {
		var t = vt(v);
		if (t == VT_ARRAY)
			return untyped __cpp__("nk_proxy({0}, {1}, null(), {2})", PROXY_ARRAY, v, lib);
		// Ints, bools, null, and host values the runtime passes as they are
		if (t != VT_CLASS)
			return v;
		if (Std.isOfType(v, NFloat))
			return (v : NFloat).v;
		if (Std.isOfType(v, NString)) {
			var d = (v : NString).b.getData();
			untyped __cpp__("nk_terminate({0})", d);
			return d;
		}
		if (Std.isOfType(v, NObject)) {
			var o:NObject = v;
			var s = o.fields.get(H_S);
			if (Std.isOfType(s, NString)) {
				// A Haxe String
				var b = (s : NString).b;
				var len = o.fields.get(H_LENGTH);
				return Rt.isInt(len) && (len : Int) >= 0 && (len : Int) <= b.length ? b.getString(0, len) : b.toString();
			}
			if (isHaxeArray(o))
				return untyped __cpp__("nk_proxy({0}, {1}, null(), {2})", PROXY_ARRAY, v, lib);
			return untyped __cpp__("nk_proxy({0}, {1}, null(), {2})", PROXY_OBJECT, v, lib);
		}
		if (Std.isOfType(v, NFunction))
			return untyped __cpp__("nk_proxy({0}, {1}, {2}, {3})", PROXY_FUNCTION, v, th, lib);
		// Abstracts, of the runtime or of an ndll, pass as they are
		return v;
	}

	static function isHaxeArray(o:NObject):Bool
		return vt(o.fields.get(H_A)) == VT_ARRAY && Rt.isInt(o.fields.get(H_LENGTH));

	// -- What an ndll gives, as neko values --

	public static function toNeko(lib:Dynamic, v:Dynamic):Dynamic
		return convert(lib, v, null);

	static function convert(lib:NdllLib, v:Dynamic, seen:Null<haxe.ds.ObjectMap<Dynamic, Dynamic>>):Dynamic {
		var t = vt(v);
		switch t {
			case VT_NULL | VT_INT | VT_BOOL:
				return v;
			case VT_FLOAT:
				return new NFloat(v);
			case VT_STRING:
				return haxeString(lib, NString.of(v));
			case VT_OBJECT | VT_ARRAY | VT_FUNCTION:
				if (untyped __cpp__("nk_is_proxy({0})", v))
					return untyped __cpp__("nk_unproxy({0})", v);
				if (t == VT_FUNCTION)
					return hostFunction(lib, v);
				var bytes:BytesData = untyped __cpp__("nk_buffer({0})", v);
				if (bytes != null)
					return new NString(Bytes.ofData(bytes));
				if (seen == null)
					seen = new haxe.ds.ObjectMap();
				var done = seen.get(v);
				if (done != null)
					return done;
				if (t == VT_OBJECT) {
					var o = new NObject();
					seen.set(v, o);
					for (name in Reflect.fields(v)) {
						Rt.registerFields([name]);
						o.fields.set(nekomata.neko.Hash.field(name), convert(lib, Reflect.field(v, name), seen));
					}
					return o;
				}
				var n:Int = untyped v.__length();
				var result = haxeArray(lib, n);
				seen.set(v, result);
				var store = proxyStore(result);
				for (i in 0...n)
					store[i] = convert(lib, untyped v.__GetItem(i), seen);
				return result;
			default:
				// The runtime's own values, and abstracts
				return v;
		}
	}

	// A string as neko's glue makes one: a Haxe String once neko_init gave the
	//  constructor, a neko string before
	static function haxeString(lib:NdllLib, s:NString):Dynamic {
		if (lib == null || !Std.isOfType(lib.newString, NFunction))
			return s;
		return Rt.call1(lib.newString, null, s);
	}

	// An array of n nulls as neko's glue makes one: a Haxe Array from neko_init's
	//  constructor, or else a neko array
	static function haxeArray(lib:NdllLib, n:Int):Dynamic {
		if (lib != null && Std.isOfType(lib.newArray, NFunction)) {
			var a = Rt.call1(lib.newArray, null, n);
			if (Std.isOfType(a, NObject) && isHaxeArray(a) && proxyStore(a).length >= n)
				return a;
		}
		return [for (i in 0...n) null];
	}

	static function hostFunction(lib:NdllLib, f:Dynamic):NFunction {
		var n:Int = untyped f.__ArgCount();
		if (n < NFunction.VAR_ARGS || n > 9)
			n = NFunction.VAR_ARGS;
		return new NFunction(fixedArity(n, args -> callHost(lib, f, args)), n, Primitive, null, null, "ndll_function");
	}

	// -- The proxies' side (NkProxy above) --

	public static function proxyField(lib:Dynamic, v:Dynamic, name:String):Dynamic {
		if (!Std.isOfType(v, NObject))
			return name == "length" ? proxyLength(v) : null;
		var o:NObject = v;
		if (name == "length" && isHaxeArray(o))
			return o.fields.get(H_LENGTH);
		return toHost(lib, o.find(nekomata.neko.Hash.field(name)), o);
	}

	public static function proxySetField(lib:Dynamic, v:Dynamic, name:String, value:Dynamic):Void {
		if (!Std.isOfType(v, NObject))
			return;
		Rt.registerFields([name]);
		(v : NObject).fields.set(nekomata.neko.Hash.field(name), toNeko(lib, value));
	}

	public static function proxyFields(v:Dynamic, out:Array<String>):Void {
		if (!Std.isOfType(v, NObject))
			return;
		for (k in (v : NObject).keys()) {
			var name = Rt.fieldName(k);
			// A field whose name no module declared cannot be named back to its hash
			if (nekomata.neko.Hash.field(name) == k)
				out.push(name);
		}
	}

	public static function proxyLength(v:Dynamic):Int {
		if (Std.isOfType(v, NObject))
			return (v : NObject).fields.get(H_LENGTH);
		return (v : Array<Dynamic>).length;
	}

	static function proxyStore(v:Dynamic):Array<Dynamic>
		return Std.isOfType(v, NObject) ? (v : NObject).fields.get(H_A) : v;

	public static function proxyItem(lib:Dynamic, v:Dynamic, i:Int):Dynamic {
		if (i < 0 || i >= proxyLength(v))
			return null;
		return toHost(lib, proxyStore(v)[i]);
	}

	public static function proxySetItem(lib:Dynamic, v:Dynamic, i:Int, value:Dynamic):Void {
		if (i < 0)
			return;
		var item = toNeko(lib, value);
		if (i < proxyLength(v)) {
			proxyStore(v)[i] = item;
			return;
		}
		// A Haxe Array grows through its own __set; a neko array has a fixed size
		if (Std.isOfType(v, NObject)) {
			var set = (v : NObject).find(H_SET);
			if (set != null)
				Rt.call2(set, v, i, item);
		}
	}

	public static function proxyArgCount(f:Dynamic):Int
		return (f : NFunction).nargs;

	public static function proxyCall(lib:Dynamic, f:Dynamic, th:Dynamic, args:Array<Dynamic>):Dynamic {
		var nargs:Array<Dynamic> = [for (a in args) toNeko(lib, a)];
		return toHost(lib, Rt.callArgs(f, th, nargs));
	}

	public static function proxyString(v:Dynamic):String
		return Rt.valueBytes(v).toString();
}
