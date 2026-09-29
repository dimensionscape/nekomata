package nekomata.neko;

import haxe.io.Bytes;
import nekomata.neko.Module;

class ReadError extends haxe.Exception {}

// Reads a .n file the way neko's neko_read_module does, with the same checks
@:build(nekomata.build.NoFrames.build())
class Reader {
	var bytes:Bytes;
	var pos:Int;

	public static function read(bytes:Bytes):Module
		return new Reader(bytes).module();

	function new(bytes:Bytes) {
		this.bytes = bytes;
		pos = 0;
	}

	function fail(what:String):Dynamic
		throw new ReadError('Invalid module: $what (at byte $pos)');

	function byte():Int {
		if (pos >= bytes.length)
			fail("unexpected end of file");
		return bytes.get(pos++);
	}

	function short():Int {
		var lo = byte();
		return lo | (byte() << 8);
	}

	function long():Int {
		if (pos + 4 > bytes.length)
			fail("unexpected end of file");
		var v = bytes.getInt32(pos);
		pos += 4;
		return v;
	}

	function cstring():String {
		var start = pos;
		while (byte() != 0) {}
		return bytes.getString(start, pos - 1 - start);
	}

	function module():Module {
		if (long() != 0x4F4B454E)
			fail("no NEKO magic");
		var nglobals = long();
		var nfields = long();
		var codeSize = long();
		if (nglobals < 0 || nglobals > 0xFFFF || nfields < 0 || nfields > 0xFFFF || codeSize < 0 || codeSize > 0xFFFFFF)
			fail("bad header counts");

		var m = new Module();
		var hasDebug = false;
		for (i in 0...nglobals) {
			var g = switch byte() {
				case 1:
					GVar(cstring());
				case 2:
					var v = long();
					if ((v & 0xFFFFFF) >= codeSize)
						fail('function $i starts past the code');
					GFunction(v & 0xFFFFFF, v >> 24);
				case 3:
					var len = short();
					if (pos + len > bytes.length)
						fail("unexpected end of file");
					var s = bytes.sub(pos, len);
					pos += len;
					GString(s);
				case 4:
					GFloat(cstring());
				case 5:
					m.positions = debugInfos(codeSize);
					GDebug;
				case 6:
					m.version = byte();
					GVersion(m.version);
				case t:
					fail('unknown global type $t');
			}
			m.globals.push(g);
		}
		for (i in 0...nfields)
			m.fields.push(cstring());

		unpack(m, codeSize);
		check(m);
		return m;
	}

	function unpack(m:Module, codeSize:Int) {
		var code = m.code;
		var isOp = m.isOp;
		while (code.length < codeSize) {
			var t = byte();
			isOp.push(true);
			switch t & 3 {
				case 0:
					code.push(t >> 2);
				case 1:
					code.push(t >> 3);
					isOp.push(false);
					code.push((t >> 2) & 1);
				case 2:
					if (t == 2) {
						// An opcode past 63 in the next byte
						code.push(byte());
					} else {
						code.push(t >> 2);
						isOp.push(false);
						code.push(byte());
					}
				default:
					code.push(t >> 2);
					isOp.push(false);
					code.push(long());
			}
		}
		if (code.length != codeSize)
			fail("the last instruction runs past the code size");
	}

	function check(m:Module) {
		var code = m.code;
		var size = code.length;
		var i = 0;
		while (i < size) {
			var op:Opcode = code[i];
			if ((op : Int) < 0 || (op : Int) >= (Opcode.Last : Int))
				fail('bad opcode $op at $i');
			var paramFollows = i + 1 < size && !m.isOp[i + 1];
			if (paramFollows != op.hasParam)
				fail('${op.name} at $i has the wrong parameter shape');
			var p = op.hasParam ? code[i + 1] : 0;
			switch op {
				case AccGlobal | SetGlobal:
					if (p < 0 || p >= m.globals.length)
						fail('${op.name} at $i names global $p');
				case Jump | JumpIf | JumpIfNot | Trap:
					var to = i + p;
					if (to < 0 || to > size || (to < size && !m.isOp[to]))
						fail('${op.name} at $i jumps to $to');
				case AccStack:
					// Stored two less, since AccStack0 and AccStack1 cover the first slots
					if (p + 2 < 0)
						fail('AccStack at $i has a negative parameter');
				case SetStack | Ret | Pop | AccEnv | SetEnv:
					if (p < 0)
						fail('${op.name} at $i has a negative parameter');
				case Call | ObjCall:
					if (p > 5)
						fail('${op.name} at $i passes $p arguments');
				case TailCall:
					if ((p & 7) > 5)
						fail('TailCall at $i passes ${p & 7} arguments');
				case Apply:
					if (p == 0 || p >= 5)
						fail('Apply at $i binds $p arguments');
				case MakeEnv:
					if (p > 0xFF)
						fail('MakeEnv at $i is too big');
				case MakeArray:
					if (p > 0x10000)
						fail('MakeArray at $i is too big');
				case JumpTable:
					if (p > 512 || i + 1 + p * 2 >= size)
						fail('JumpTable at $i runs past the code');
				default:
			}
			i = m.next(i);
		}
	}

	function debugInfos(codeSize:Int):Array<Position> {
		var c = byte();
		var manyFiles = c >= 0x80;
		var nfiles = manyFiles ? ((c & 0x7F) << 8) | byte() : c;
		if (nfiles == 0)
			fail("debug info with no files");
		var files = [for (_ in 0...nfiles) cstring()];
		var npos = long();
		if (npos != codeSize)
			fail("debug info does not cover the code");

		var result:Array<Position> = [];
		var file = files[0];
		var line = 0;
		var current:Null<Position> = null;
		inline function fresh()
			current = {file: file, line: line};
		while (result.length < npos) {
			var c = byte();
			if (c & 1 != 0) {
				var f = c >> 1;
				if (manyFiles)
					f = (f << 8) | byte();
				if (f >= files.length)
					fail("debug info names an unknown file");
				file = files[f];
				current = null;
			} else if (c & 2 != 0) {
				var delta = c >> 6;
				var count = (c >> 2) & 15;
				if (result.length + count > npos)
					fail("debug info runs past the code");
				if (current == null)
					fresh();
				for (_ in 0...count)
					result.push(current);
				if (delta != 0) {
					line += delta;
					current = null;
				}
			} else if (c & 4 != 0) {
				line += c >> 3;
				fresh();
				result.push(current);
			} else {
				var b2 = byte();
				var b3 = byte();
				line = (c >> 3) | (b2 << 5) | (b3 << 13);
				fresh();
				result.push(current);
			}
		}
		return result;
	}
}
