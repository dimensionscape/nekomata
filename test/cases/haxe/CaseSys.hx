// args: alpha "two words" "" --flag=value
class CaseSys {
	static function main() {
		var args = Sys.args();
		Sys.println(args.length + " args");
		for (a in args)
			Sys.println("  [" + a + "] " + a.length);
		Sys.println("system " + Sys.systemName());
		Sys.println("PATH set: " + (Sys.getEnv("PATH") != null) + ", missing var: " + Sys.getEnv("NEKOMATA_SURELY_UNSET_VARIABLE"));
		Sys.putEnv("NEKOMATA_CASE_VAR", "set by the case");
		Sys.println("putEnv: " + Sys.getEnv("NEKOMATA_CASE_VAR") + ", in environment(): " + Sys.environment().get("NEKOMATA_CASE_VAR"));
		var cwd = Sys.getCwd();
		Sys.println("cwd ends with a separator: " + (StringTools.endsWith(cwd, "\\") || StringTools.endsWith(cwd, "/")));
		sys.FileSystem.createDirectory("sub");
		Sys.setCwd("sub");
		Sys.println("setCwd moves down: " + (Sys.getCwd().length > cwd.length));
		Sys.setCwd("..");
		Sys.println("and back: " + (Sys.getCwd() == cwd));
		try {
			Sys.setCwd("no_such_dir");
		} catch (e:Dynamic) {
			Sys.println("setCwd to a missing directory fails");
		}
		var t = Sys.time();
		var c = Sys.cpuTime();
		Sys.sleep(0.05);
		Sys.println("time moves: " + (Sys.time() > t) + ", cpuTime is a number: " + !Math.isNaN(c));
		Sys.println("programPath ends with CaseSys.n: " + StringTools.endsWith(Sys.programPath(), "CaseSys.n"));
		Sys.println("executablePath is set: " + (Sys.executablePath().length > 0));
		Sys.stdout().writeString("stdout write\n");
		Sys.stderr().writeString("stderr write\n");
		Sys.stdout().flush();
		Sys.print("print ");
		Sys.println("println");
		Sys.println("stdin at end: " + (try {
			Sys.stdin().readLine();
			false;
		} catch (e:haxe.io.Eof) true));
	}
}
