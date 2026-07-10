import nekomata.neko.*;
import nekomata.neko.Module;

// Reads, stack-checks and translates every .n file given, or found under the directories given:
//  haxe test.hxml <file.n | dir>...
class Corpus {
	static function main() {
		var files = [];
		for (a in Sys.args())
			collect(a, files);
		var failed = 0;
		for (f in files) {
			try {
				var m = Reader.read(sys.io.File.getBytes(f));
				var scopes = StackCheck.run(m);
				var unnamed = unnamedFields(m);
				var cppia = nekomata.emit.Emitter.emit(m, "Check");
				Sys.println('ok   $f (${scopes.length - 1} functions, ${Std.int(cppia.length / 1024)} KB of cppia${unnamed > 0 ? ', $unnamed field hashes without a declared name' : ""})');
			} catch (e:haxe.Exception) {
				failed++;
				Sys.println('FAIL $f: ${e.message}');
			}
		}
		Sys.println('${files.length - failed} of ${files.length} modules read, checked and translated');
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function collect(path:String, out:Array<String>) {
		if (sys.FileSystem.isDirectory(path)) {
			var names = sys.FileSystem.readDirectory(path);
			names.sort(Reflect.compare);
			for (n in names)
				collect(path + "/" + n, out);
		} else if (StringTools.endsWith(path, ".n"))
			out.push(path);
	}

	// Field instructions whose hash matches none of the module's declared names
	static function unnamedFields(m:Module):Int {
		var count = 0;
		var pc = 0;
		while (pc < m.codeSize) {
			switch m.op(pc) {
				case AccField | SetField:
					if (m.fieldName(m.param(pc)) == null)
						count++;
				default:
			}
			pc = m.next(pc);
		}
		return count;
	}
}
