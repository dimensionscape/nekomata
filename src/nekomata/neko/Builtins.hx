package nekomata.neko;

class Builtins {
	// Neko's builtins (vm/builtins.c), plus the loader and exports AccBuiltin also names
	public static final names = [
		"print", "array", "amake", "acopy", "asize", "asub", "ablit", "aconcat", "smake", "ssize", "scopy", "ssub", "sget", "sset",
		"sblit", "sfind", "sget16", "sget32", "sgetf", "sgetd", "sset16", "sset32", "ssetf", "ssetd", "itof", "itod", "ftoi", "dtoi",
		"isbigendian", "new", "objget", "objset", "objcall", "objfield", "objremove", "objfields", "hash", "fasthash", "field",
		"objsetproto", "objgetproto", "int", "float", "string", "typeof", "closure", "apply", "varargs", "compare", "pcompare", "not",
		"throw", "rethrow", "nargs", "call", "isnan", "isinfinite", "istrue", "getkind", "iskind", "hnew", "hget", "hmem", "hset",
		"hadd", "hremove", "hresize", "hkey", "hcount", "hsize", "hiter", "iadd", "isub", "imult", "idiv", "excstack", "callstack",
		"version", "neko_build_year", "setresolver", "loader", "exports"
	];

	static var byHash:Map<Int, String>;

	public static function name(hash:Int):Null<String> {
		if (byHash == null) {
			byHash = new Map();
			for (n in names)
				byHash.set(Hash.field(n), n);
		}
		return byHash.get(hash);
	}
}
