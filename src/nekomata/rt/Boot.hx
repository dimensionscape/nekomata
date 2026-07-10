package nekomata.rt;

import nekomata.rt.Values;

// What a translated module's main calls to set itself up and run its body
@:keep
class Boot {
	// The module the host is about to run, and the loader it gets
	public static var pendingName:String;
	public static var pendingLoader:NObject;

	// The module begin made last, for the host to read its exports
	public static var last:NModule;

	public static function begin():NModule {
		last = new NModule(pendingName, pendingLoader);
		return last;
	}

	public static function run(m:NModule, globals:Array<Dynamic>, body:Dynamic):Void {
		m.globals = globals;
		body(null, null);
	}

	public static function loader(m:NModule):NObject
		return m.loader;

	public static function exports(m:NModule):NObject
		return m.exports;
}
