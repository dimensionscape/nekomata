package nekomata.tools;

import nekomata.neko.*;
import nekomata.neko.Module;
import nekomata.neko.StackCheck;

using StringTools;

// Disassembles a .n file: haxe -cp src --run nekomata.tools.Dump <file.n> [--summary | --linear]
//  --linear prints each instruction's code index and opcode in file order, the same
//  columns test/nekoc-compare.sh takes from nekoc -d
class Dump {
	static function main() {
		var args = Sys.args();
		var summary = args.remove("--summary");
		var linear = args.remove("--linear");
		if (args.length != 1) {
			Sys.println("usage: dump <file.n> [--summary | --linear]");
			Sys.exit(1);
		}
		var m = Reader.read(sys.io.File.getBytes(args[0]));
		if (linear) {
			var pc = 0;
			while (pc < m.codeSize) {
				Sys.println(StringTools.hex(pc, 6) + " " + m.op(pc).name);
				pc = m.next(pc);
			}
			return;
		}
		var scopes = StackCheck.run(m);
		if (summary)
			printSummary(m, scopes)
		else
			printCode(m, scopes);
	}

	static function printSummary(m:Module, scopes:Array<Scope>) {
		var counts = new Map<String, Int>();
		var builtins = new Map<String, Bool>();
		for (s in scopes)
			for (pc in s.pcs()) {
				if (pc >= m.codeSize)
					continue;
				var op = m.op(pc);
				counts.set(op.name, (counts.exists(op.name) ? counts.get(op.name) : 0) + 1);
				if (op == AccBuiltin) {
					var n = Builtins.name(m.param(pc));
					builtins.set(n == null ? '#${m.param(pc)}' : n, true);
				}
			}
		var maxDepth = 0;
		for (s in scopes)
			if (s.maxDepth > maxDepth)
				maxDepth = s.maxDepth;

		Sys.println('version ${m.version}, ${m.globals.length} globals, ${m.fields.length} fields, ${m.codeSize} code words');
		Sys.println('${scopes.length - 1} functions, deepest stack $maxDepth, debug info ${m.positions != null ? "yes" : "no"}');
		var names = [for (k in counts.keys()) k];
		names.sort((a, b) -> counts.get(b) - counts.get(a));
		Sys.println('opcodes: ' + [for (n in names) '$n ${counts.get(n)}'].join(", "));
		var bs = [for (k in builtins.keys()) k];
		bs.sort(Reflect.compare);
		Sys.println('builtins (${bs.length}): ' + bs.join(" "));
	}

	static function printCode(m:Module, scopes:Array<Scope>) {
		for (s in scopes) {
			Sys.println(s.global < 0 ? 'module body @${s.entry}' : 'function global ${s.global} @${s.entry}, ${s.nargs} args');
			var lastPos = null;
			for (pc in s.pcs()) {
				if (pc >= m.codeSize)
					continue;
				if (m.positions != null && pc < m.positions.length) {
					var p = m.positions[pc];
					if (p != lastPos) {
						Sys.println('                ; ${p.file}:${p.line}');
						lastPos = p;
					}
				}
				var op = m.op(pc);
				var text = op.name;
				if (op.hasParam)
					text += ' ' + m.param(pc);
				var note = annotate(m, pc);
				var line = '  ${Std.string(pc).lpad(" ", 6)} [${Std.string(s.depth.get(pc)).lpad(" ", 3)}] $text';
				Sys.println(note == null ? line : line.rpad(" ", 40) + ' ; $note');
			}
			Sys.println("");
		}
	}

	static function annotate(m:Module, pc:Int):Null<String> {
		var op = m.op(pc);
		var p = op.hasParam ? m.param(pc) : 0;
		return switch op {
			case AccGlobal | SetGlobal:
				describe(m.globals[p]);
			case AccField | SetField:
				var n = m.fieldName(p);
				n == null ? null : '.$n';
			case AccBuiltin:
				var n = Builtins.name(p);
				n == null ? 'unknown builtin' : "$" + n;
			case Jump | JumpIf | JumpIfNot | Trap:
				'-> ${m.target(pc)}';
			case JumpTable:
				'$p cases';
			case TailCall:
				'${p & 7} args, pop ${p >> 3}';
			default:
				null;
		}
	}

	static function describe(g:Global):String {
		return switch g {
			case GVar(name): 'var $name';
			case GFunction(addr, nargs): 'function @$addr ($nargs args)';
			case GString(b):
				var s = b.toString();
				if (s.length > 40)
					s = s.substr(0, 40) + "...";
				'"' + s.replace("\n", "\\n").replace("\r", "\\r") + '"';
			case GFloat(text): 'float $text';
			case GDebug: 'debug info';
			case GVersion(v): 'version $v';
		}
	}
}
