package nekomata.rt.prims;

import haxe.io.Bytes;
import haxe.io.BytesData;
import nekomata.rt.Values;
import nekomata.rt.Primitives.add;
import nekomata.rt.prims.Conv.*;

// An open database, as sqlite.c's database: the connection and the result whose
//  statement is still open
private class SqliteDb {
	public var db:Dynamic;
	public var last:NAbstract;

	public function new(db:Dynamic)
		this.db = db;
}

// A request's result, as sqlite.c's result
private class SqliteResult {
	public var database:NAbstract;
	public var r:Dynamic;
	public var ncols = 0;
	public var count = 0;
	public var names:Array<Int> = [];
	public var bools:Array<Bool> = [];
	public var done = false;
	public var first = true;

	public function new(database:NAbstract, r:Dynamic) {
		this.database = database;
		this.r = r;
	}
}

// libs/sqlite sqlite.c, on the SQLite libhxcpp builds. libhxcpp's own port differs
//  from neko's where neko is quirky (rows, step errors, closing), so this calls SQLite
//  as sqlite.c does
@:keep
@:buildXml('<include name="${HXCPP}/src/hx/libs/sqlite/Build.xml"/>')
@:cppFileCode('
extern "C" {
typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;
int sqlite3_open(const char *, sqlite3 **);
int sqlite3_close(sqlite3 *);
const char *sqlite3_errmsg(sqlite3 *);
int sqlite3_prepare(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
int sqlite3_finalize(sqlite3_stmt *);
sqlite3_stmt *sqlite3_next_stmt(sqlite3 *, sqlite3_stmt *);
int sqlite3_column_count(sqlite3_stmt *);
const char *sqlite3_column_name(sqlite3_stmt *, int);
const char *sqlite3_column_decltype(sqlite3_stmt *, int);
int sqlite3_step(sqlite3_stmt *);
int sqlite3_column_type(sqlite3_stmt *, int);
int sqlite3_column_int(sqlite3_stmt *, int);
double sqlite3_column_double(sqlite3_stmt *, int);
const unsigned char *sqlite3_column_text(sqlite3_stmt *, int);
int sqlite3_column_bytes(sqlite3_stmt *, int);
const void *sqlite3_column_blob(sqlite3_stmt *, int);
int sqlite3_changes(sqlite3 *);
long long sqlite3_last_insert_rowid(sqlite3 *);
}

namespace {
// A connection or a statement. A connection the program drops is closed when it is
//  collected, as neko\'s finalizer closes it
struct NkSqlite : public hx::Object
{
   void *ptr;
   int code;

   NkSqlite(void *inPtr, int inCode, bool inDb) : ptr(inPtr), code(inCode)
   {
      if (inDb)
         _hx_set_finalizer(this, finalize);
   }

   static void finalize(Dynamic obj)
   {
      sqlite3 *db = (sqlite3 *)((NkSqlite *)obj.mPtr)->ptr;
      if (!db)
         return;
      sqlite3_stmt *s;
      while ((s = sqlite3_next_stmt(db, 0)) != 0)
         sqlite3_finalize(s);
      sqlite3_close(db);
   }

   String toString() HXCPP_OVERRIDE { return HX_CSTRING("sqlite"); }
};
}

#define NK_PTR(b) (((NkSqlite *)(b).mPtr)->ptr)
#define NK_DB(b) ((sqlite3 *)NK_PTR(b))
#define NK_STMT(b) ((sqlite3_stmt *)NK_PTR(b))

static Array<unsigned char> nk_sqlite_bytes(const void *p, int n)
{
   return Array_obj<unsigned char>::fromData((const unsigned char *)p, n);
}

// A C string as bytes, null for NULL, as alloc_string reads it
static Array<unsigned char> nk_sqlite_cstr(const void *s)
{
   if (!s)
      return null();
   return nk_sqlite_bytes(s, (int)strlen((const char *)s));
}

static Dynamic nk_sqlite_open(Array<unsigned char> name)
{
   sqlite3 *db = 0;
   int err = sqlite3_open((const char *)name->getBase(), &db);
   return new NkSqlite(db, err, true);
}

// code is 1 when SQLite cannot prepare the request, 2 when text follows it
static Dynamic nk_sqlite_prepare(Dynamic db, Array<unsigned char> sql, int len)
{
   sqlite3_stmt *r = 0;
   const char *tl = 0;
   if (sqlite3_prepare(NK_DB(db), (const char *)sql->getBase(), len, &r, &tl) != 0)
      return new NkSqlite(0, 1, false);
   if (*tl)
   {
      sqlite3_finalize(r);
      return new NkSqlite(0, 2, false);
   }
   return new NkSqlite(r, 0, false);
}
')
class Sqlite {
	static final dbKind = new NObject();
	static final resultKind = new NObject();

	// A neko string as C reads it, ending in a NUL
	static function cstr(b:Bytes):BytesData {
		var z = Bytes.alloc(b.length + 1);
		z.blit(0, b, 0, b.length);
		return z.getData();
	}

	static function bytesOf(d:BytesData):Null<NString>
		return d == null ? null : new NString(Bytes.ofData(d));

	// Throws the concatenation of strings and byte runs, as neko's buffers build errors
	static function throwMessage(parts:Array<Dynamic>):Dynamic {
		var b = new haxe.io.BytesBuffer();
		for (p in parts)
			if (Std.isOfType(p, String))
				b.addString(p);
			else if (p != null)
				b.add(Bytes.ofData(p));
		return Rt.raise(new NString(b.getBytes()));
	}

	static function errmsg(db:Dynamic):BytesData
		return untyped __cpp__("nk_sqlite_cstr(sqlite3_errmsg(NK_DB({0})))", db);

	static function finalizeResult(r:SqliteResult, exc:Bool) {
		var db:SqliteDb = r.database.data;
		r.first = false;
		r.done = true;
		if (r.ncols == 0)
			r.count = untyped __cpp__("sqlite3_changes(NK_DB({0}))", db.db);
		var failed:Bool = untyped __cpp__("sqlite3_finalize(NK_STMT({0})) != 0", r.r);
		r.r = null;
		db.last = null;
		r.database = null;
		if (failed && exc)
			Rt.error("Could not finalize request");
	}

	static function freeDb(db:SqliteDb) {
		if (db.last != null)
			finalizeResult(db.last.data, false);
		// Neko ignores what closing says
		untyped __cpp__("sqlite3_close(NK_DB({0}))", db.db);
		untyped __cpp__("NK_PTR({0}) = 0", db.db);
	}

	// result_next. Called for result_get and the like, a step that fails without an
	//  error neko throws leaves the row as it is, since neko ignores what it returns
	static function next(r:SqliteResult, prim:Null<String>):Dynamic {
		if (r.done)
			return null;
		var st = r.r;
		var code:Int = untyped __cpp__("sqlite3_step(NK_STMT({0}))", st);
		switch code {
			case 100:
				r.first = false;
				var o = new NObject();
				for (i in 0...r.ncols) {
					var f:Dynamic = null;
					var t:Int = untyped __cpp__("sqlite3_column_type(NK_STMT({0}), {1})", st, i);
					switch t {
						case 5:
						case 1:
							var n:Int = untyped __cpp__("sqlite3_column_int(NK_STMT({0}), {1})", st, i);
							if (r.bools[i])
								f = n != 0;
							else
								f = n;
						case 2:
							var d:Float = untyped __cpp__("sqlite3_column_double(NK_STMT({0}), {1})", st, i);
							f = new NFloat(d);
						case 3:
							f = bytesOf(untyped __cpp__("nk_sqlite_cstr(sqlite3_column_text(NK_STMT({0}), {1}))", st, i));
						case 4:
							var size:Int = untyped __cpp__("sqlite3_column_bytes(NK_STMT({0}), {1})", st, i);
							var d:BytesData = untyped __cpp__("nk_sqlite_bytes(sqlite3_column_blob(NK_STMT({0}), {1}), {2})", st, i, size);
							f = new NString(Bytes.ofData(d));
						default:
							Rt.error("Unknown Sqlite type #" + t);
					}
					o.fields.set(r.names[i], f);
				}
				return o;
			case 101:
				finalizeResult(r, true);
				return null;
			case 5:
				return Rt.error("Database is busy");
			case 1:
				var db:SqliteDb = r.database.data;
				return throwMessage(["Sqlite error : ", errmsg(db.db)]);
			default:
				return prim == null ? Primitives.fail("sqlite@result_next") : null;
		}
	}

	// The current row's statement for result_get and the like
	static function current(v:Dynamic, n:Dynamic, prim:String):Dynamic {
		var r:SqliteResult = data(v, resultKind, prim);
		var i = int(n, prim);
		if (i < 0 || i >= r.ncols)
			Primitives.fail(prim);
		if (r.first)
			next(r, prim);
		if (r.done)
			Primitives.fail(prim);
		return r.r;
	}

	public static function register() {
		add("sqlite@connect", 1, function(f:Dynamic) {
			var box:Dynamic = untyped __cpp__("nk_sqlite_open({0})", cstr(bytes(f, "sqlite@connect")));
			if ((untyped __cpp__("((NkSqlite *){0}.mPtr)->code", box) : Int) != 0) {
				var msg = errmsg(box);
				untyped __cpp__("NkSqlite::finalize({0})", box);
				untyped __cpp__("NK_PTR({0}) = 0", box);
				return throwMessage(["Sqlite error : ", msg]);
			}
			return new NAbstract(dbKind, new SqliteDb(box));
		});
		add("sqlite@close", 1, function(v:Dynamic) {
			freeDb(data(v, dbKind, "sqlite@close"));
			// Neko clears the kind, so a closed database fails every primitive
			(v : NAbstract).kind = null;
			return null;
		});
		add("sqlite@last_insert_id", 1, function(v:Dynamic) {
			var db:SqliteDb = data(v, dbKind, "sqlite@last_insert_id");
			var id:Int = untyped __cpp__("(int)sqlite3_last_insert_rowid(NK_DB({0}))", db.db);
			return (id << 1) >> 1;
		});
		add("sqlite@request", 2, function(v:Dynamic, s:Dynamic) {
			var db:SqliteDb = data(v, dbKind, "sqlite@request");
			var sql = bytes(s, "sqlite@request");
			var st:Dynamic = untyped __cpp__("nk_sqlite_prepare({0}, {1}, {2})", db.db, cstr(sql), sql.length);
			switch (untyped __cpp__("((NkSqlite *){0}.mPtr)->code", st) : Int) {
				case 1:
					return throwMessage(["Sqlite error in ", sql.getData(), " : ", errmsg(db.db)]);
				case 2:
					return Rt.error("Cannot execute several SQL requests at the same time");
			}
			var r = new SqliteResult(v, st);
			r.ncols = untyped __cpp__("sqlite3_column_count(NK_STMT({0}))", st);
			var names:Array<Dynamic> = [];
			for (i in 0...r.ncols) {
				var nb:BytesData = untyped __cpp__("nk_sqlite_cstr(sqlite3_column_name(NK_STMT({0}), {1}))", st, i);
				var name = Bytes.ofData(nb).toString();
				var id = nekomata.neko.Hash.field(name);
				var dtype:BytesData = untyped __cpp__("nk_sqlite_cstr(sqlite3_column_decltype(NK_STMT({0}), {1}))", st, i);
				for (j in 0...i)
					if (r.names[j] == id) {
						untyped __cpp__("sqlite3_finalize(NK_STMT({0}))", st);
						if ((names[j] : String) == name)
							return throwMessage(["Error, same field is two times in the request ", sql.getData()]);
						return throwMessage(["Error, same field ids for : " + name + " and " + names[j] + "."]);
					}
				names.push(name);
				r.names.push(id);
				r.bools.push(dtype != null && Bytes.ofData(dtype).toString() == "BOOL");
			}
			// $objfields names a row's fields, as val_id records them
			Rt.registerFields(names);
			if (db.last != null)
				finalizeResult(db.last.data, false);
			db.last = new NAbstract(resultKind, r);
			return db.last;
		});
		add("sqlite@result_get_length", 1, function(v:Dynamic) {
			var r:SqliteResult = data(v, resultKind, "sqlite@result_get_length");
			if (r.ncols != 0)
				return Primitives.fail("sqlite@result_get_length");
			return (r.count << 1) >> 1;
		});
		add("sqlite@result_get_nfields", 1, (v:Dynamic) -> (data(v, resultKind, "sqlite@result_get_nfields") : SqliteResult).ncols);
		add("sqlite@result_next", 1, (v:Dynamic) -> next(data(v, resultKind, "sqlite@result_next"), null));
		add("sqlite@result_get", 2, function(v:Dynamic, n:Dynamic) {
			var st = current(v, n, "sqlite@result_get");
			var i:Int = n;
			return bytesOf(untyped __cpp__("nk_sqlite_cstr(sqlite3_column_text(NK_STMT({0}), {1}))", st, i));
		});
		add("sqlite@result_get_int", 2, function(v:Dynamic, n:Dynamic) {
			var st = current(v, n, "sqlite@result_get_int");
			var i:Int = n;
			return (untyped __cpp__("sqlite3_column_int(NK_STMT({0}), {1})", st, i) : Int);
		});
		add("sqlite@result_get_float", 2, function(v:Dynamic, n:Dynamic) {
			var st = current(v, n, "sqlite@result_get_float");
			var i:Int = n;
			var f:Float = untyped __cpp__("sqlite3_column_double(NK_STMT({0}), {1})", st, i);
			return new NFloat(f);
		});
	}
}
