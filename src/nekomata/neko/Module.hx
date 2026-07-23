package nekomata.neko;

import haxe.io.Bytes;

enum Global {
	GVar(name:String);
	// addr is a code index; nargs is -1 for a function that takes any number of arguments
	GFunction(addr:Int, nargs:Int);
	GString(value:Bytes);
	GFloat(text:String);
	GDebug;
	GVersion(version:Int);
}

typedef Position = {
	var file:String;
	var line:Int;
}

@:build(nekomata.build.NoFrames.build())
class Module {
	public var globals:Array<Global> = [];
	// Names the module declares for field hashes, as neko's m->fields
	public var fields:Array<String> = [];
	// Opcodes and parameters interleaved, as neko's m->code after unpacking
	public var code:Array<Int> = [];
	// Whether code[i] is the start of an instruction rather than a parameter
	public var isOp:Array<Bool> = [];
	// The source position of each code index, when the module has debug info
	public var positions:Null<Array<Position>>;
	public var version:Int = 1;

	public function new() {}

	public var codeSize(get, never):Int;

	inline function get_codeSize()
		return code.length;

	public inline function op(pc:Int):Opcode
		return code[pc];

	public inline function param(pc:Int):Int
		return code[pc + 1];

	public inline function next(pc:Int):Int
		return pc + (op(pc).hasParam ? 2 : 1);

	// The stack slot or array index an instruction names: AccStack and AccIndex store
	//  theirs two less, since AccStack0/1 and AccIndex0/1 cover the first two
	public function slot(pc:Int):Int
		return switch op(pc) {
			case AccStack | AccIndex: param(pc) + 2;
			case AccStack0 | AccIndex0: 0;
			case AccStack1 | AccIndex1: 1;
			default: param(pc);
		}

	// Jump, JumpIf, JumpIfNot and Trap parameters are relative to the instruction
	public inline function target(pc:Int):Int
		return pc + param(pc);

	// The global indexes of the module's functions, in code order
	public function functions():Array<Int> {
		var result = [];
		for (i in 0...globals.length)
			switch globals[i] {
				case GFunction(_, _):
					result.push(i);
				default:
			}
		return result;
	}

	// The name for a field hash among the module's declared fields
	public function fieldName(hash:Int):Null<String> {
		if (fieldNames == null) {
			fieldNames = new Map();
			for (f in fields)
				fieldNames.set(Hash.field(f), f);
		}
		return fieldNames.get(hash);
	}

	var fieldNames:Map<Int, String>;
}
