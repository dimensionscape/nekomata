package nekomata.neko;

// Neko opcodes, in the order of neko's vm/opcodes.h
enum abstract Opcode(Int) from Int to Int {
	var AccNull;
	var AccTrue;
	var AccFalse;
	var AccThis;
	var AccInt;
	var AccStack;
	var AccGlobal;
	var AccEnv;
	var AccField;
	var AccArray;
	var AccIndex;
	var AccBuiltin;
	var SetStack;
	var SetGlobal;
	var SetEnv;
	var SetField;
	var SetArray;
	var SetIndex;
	var SetThis;
	var Push;
	var Pop;
	var Call;
	var ObjCall;
	var Jump;
	var JumpIf;
	var JumpIfNot;
	var Trap;
	var EndTrap;
	var Ret;
	var MakeEnv;
	var MakeArray;
	var Bool;
	var IsNull;
	var IsNotNull;
	var Add;
	var Sub;
	var Mult;
	var Div;
	var Mod;
	var Shl;
	var Shr;
	var UShr;
	var Or;
	var And;
	var Xor;
	var Eq;
	var Neq;
	var Gt;
	var Gte;
	var Lt;
	var Lte;
	var Not;
	var TypeOf;
	var Compare;
	var Hash;
	var New;
	var JumpTable;
	var Apply;
	var AccStack0;
	var AccStack1;
	var AccIndex0;
	var AccIndex1;
	var PhysCompare;
	var TailCall;
	var Loop;
	// Never in a file: neko's loader rewrites MakeArray and AccInt into these
	var MakeArray2;
	var AccInt32;
	var Last;

	// The stack effect when it depends on the parameter
	public static inline var P = 0xFF;

	static final names = [
		"AccNull", "AccTrue", "AccFalse", "AccThis", "AccInt", "AccStack", "AccGlobal", "AccEnv", "AccField", "AccArray", "AccIndex",
		"AccBuiltin", "SetStack", "SetGlobal", "SetEnv", "SetField", "SetArray", "SetIndex", "SetThis", "Push", "Pop", "Call", "ObjCall",
		"Jump", "JumpIf", "JumpIfNot", "Trap", "EndTrap", "Ret", "MakeEnv", "MakeArray", "Bool", "IsNull", "IsNotNull", "Add", "Sub",
		"Mult", "Div", "Mod", "Shl", "Shr", "UShr", "Or", "And", "Xor", "Eq", "Neq", "Gt", "Gte", "Lt", "Lte", "Not", "TypeOf",
		"Compare", "Hash", "New", "JumpTable", "Apply", "AccStack0", "AccStack1", "AccIndex0", "AccIndex1", "PhysCompare", "TailCall",
		"Loop", "MakeArray2", "AccInt32", "Last"
	];

	static final params = [
		0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0
	];

	static final stack = [
		0, 0, 0, 0, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0, -1, -2, -1, 0, 1, -P, -P, -P, 0, 0, 0, 6, -6, 0, -P, -P, 0, 0, 0, -1, -1, -1, -1,
		-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, 0, -1, 0, 0, 0, -P, 0, 0, 0, 0, -1, 0, 0, -P, 0, 0
	];

	public var name(get, never):String;

	inline function get_name()
		return this >= 0 && this < names.length ? names[this] : 'Op$this';

	// Whether the instruction is followed by a parameter word
	public var hasParam(get, never):Bool;

	inline function get_hasParam()
		return params[this] != 0;

	// The stack effect, or P / -P when the parameter says how many slots it pushes or pops
	public var stackEffect(get, never):Int;

	inline function get_stackEffect()
		return stack[this];
}
