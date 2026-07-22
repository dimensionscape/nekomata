package nekomata.build;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

// @:build(nekomata.build.NoFrames.build()) marks every field of a class @:noDebug, so its
//  functions push no host stack frame and record no lines. hxcpp's generator takes the
//  meta on fields only, not on the class
class NoFrames {
	public static macro function build():Array<Field> {
		var fields = Context.getBuildFields();
		for (f in fields)
			if (f.meta == null)
				f.meta = [{name: ":noDebug", pos: f.pos}];
			else
				f.meta.push({name: ":noDebug", pos: f.pos});
		return fields;
	}
}
