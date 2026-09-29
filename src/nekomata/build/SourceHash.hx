package nekomata.build;

#if macro
import haxe.macro.Context;
#end

// The MD5 of the host's own sources, worked out when the host is built: translated
//  modules cached by one build are only reused by a build of the same sources
class SourceHash {
	public static macro function get():haxe.macro.Expr {
		var main = Context.resolvePath("nekomata/Main.hx");
		var root = haxe.io.Path.directory(main);
		var files = [];
		function collect(dir:String) {
			var names = sys.FileSystem.readDirectory(dir);
			names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
			for (n in names) {
				var p = dir + "/" + n;
				if (sys.FileSystem.isDirectory(p))
					collect(p);
				else if (StringTools.endsWith(n, ".hx"))
					files.push(p);
			}
		}
		collect(root);
		var all = new StringBuf();
		for (f in files) {
			Context.registerModuleDependency("nekomata.build.SourceHash", f);
			all.add(f.substr(root.length));
			all.add("\n");
			all.add(sys.io.File.getContent(f));
		}
		return macro $v{haxe.crypto.Md5.encode(all.toString())};
	}
}
