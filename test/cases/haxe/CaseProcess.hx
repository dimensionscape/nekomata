import sys.io.Process;

class CaseProcess {
	static function main() {
		var p = new Process("haxe", ["-version"]);
		var out = p.stdout.readAll().toString();
		var err = p.stderr.readAll().toString();
		var code = p.exitCode();
		p.close();
		Sys.println("haxe -version: [" + StringTools.trim(out + err) + "] exit " + code);
		var p2 = new Process("haxe", ["--no-such-flag"]);
		var e2 = p2.stderr.readAll().toString();
		p2.stdout.readAll();
		Sys.println("bad flag exits non zero: " + (p2.exitCode() != 0) + ", says something: " + (e2.length > 0));
		p2.close();
		var p3 = new Process("haxe -version");
		Sys.println("as one command: [" + StringTools.trim(p3.stdout.readAll().toString() + p3.stderr.readAll().toString()) + "] " + p3.exitCode());
		p3.close();
		var p4 = new Process("cmd", ["/c", "echo", "from cmd"]);
		Sys.println("cmd: [" + StringTools.trim(p4.stdout.readAll().toString()) + "] " + p4.exitCode());
		p4.close();
		var p5 = new Process("cmd", ["/c", "exit", "3"]);
		Sys.println("exit code 3: " + p5.exitCode());
		p5.close();
		var p6 = new Process("findstr", ["x"]);
		p6.stdin.writeString("one\nxtwo\nthree x\n");
		p6.stdin.close();
		Sys.println("stdin through findstr: " + StringTools.trim(p6.stdout.readAll().toString()).split("\r").join("").split("\n") + " " + p6.exitCode());
		p6.close();
		Sys.println("Sys.command: " + Sys.command("cmd", ["/c", "exit", "5"]));
		var pid = new Process("haxe", ["-version"]);
		Sys.println("pid positive: " + (pid.getPid() > 0));
		pid.exitCode();
		pid.close();
		try {
			var bad = new Process("no_such_program_anywhere", []);
			Sys.println("started, exit " + (bad.exitCode() != 0));
			bad.close();
		} catch (e:Dynamic) {
			Sys.println("cannot start: " + e);
		}
	}
}
