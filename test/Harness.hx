import haxe.io.Bytes;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import nekomata.emit.Emitter;
import nekomata.neko.Reader;
import nekomata.neko.StackCheck;

using StringTools;

// One run of a command: what it printed and how it ended
typedef Run = {
	var out:String;
	var err:String;
	var code:Int;
	var timedOut:Bool;
	var seconds:Float;
}

typedef Test = {
	var name:String;
	var run:Ctx->Void;
}

typedef Suite = {
	var name:String;
	var about:String;
	var host:Bool;
	var tests:Void->Array<Test>;
}

typedef Env = Map<String, Null<String>>;

typedef Versus = {
	// Fills each run's directory before the run
	var ?setup:String->Void;
	// The arguments for a run in the given directory, when they name it
	var ?argsFor:String->Array<String>;
	// Where to run, when not in the run's own directory
	var ?cwd:String;
	var ?env:Env;
	var ?timeout:Float;
	// Compares what neko's and the host's runs left in their directories
	var ?check:(nekoDir:String, hostDir:String) -> Null<String>;
}

// Nekomata's tests, run from the repository root under Haxe's interpreter:
//  haxe test/harness.hxml [options] [suite[:filter]...]
// Neko is the oracle: a program runs on neko and on each host, interpreted and with
//  the JIT, and must print the same and exit the same way. Tests run at once in worker
//  processes, each a harness started with --worker, which write what their tests
//  report to files the harness prints in order
class Harness {
	static final usage = [
		"usage: haxe test/harness.hxml [options] [suite[:filter]...]",
		"  --host <path>    a host to test, once for each (default bin/host/nekomata.exe, and",
		"                   bin/cppia/Cppia.exe when haxe cppia.hxml has built it)",
		"  --no-jit         run the host interpreted only (default: interpreted and -jit)",
		"  --timeout <s>    kill a run after this many seconds (default 120, more for big suites)",
		"  -j <n>           tests to run at once (default 8)",
		"  --reuse          keep the builds of Haxe's tests in bin/harness and reuse them",
		"  --corpus <path>  add a .n file, or the .n files under a directory, to decode and translate",
		"  --keep           keep the work directories",
		"  --list           list the suites, or the tests of the suites named",
		"A filter runs the tests whose names contain it, as in cases:hash.",
		"A path given in place of a suite adds to the corpus and runs decode and translate.",
	];

	// In the order they run, so decode and translate see what the others built
	static final suites:Array<Suite> = [
		{name: "cases", about: "test/cases programs built with nekoc and haxe", host: true, tests: Cases.tests},
		{name: "neko", about: "neko's benchmarks, and neko's own compilers building neko", host: true, tests: NekoSuite.tests},
		{name: "haxe-unit", about: "Haxe's unit tests", host: true, tests: Upstream.unit},
		{name: "haxe-sys", about: "Haxe's sys tests", host: true, tests: Upstream.sys},
		{name: "haxe-threads", about: "Haxe's threads tests", host: true, tests: Upstream.threads},
		{name: "libhxcpp", about: "libhxcpp's run.n, and a C program built with it", host: true, tests: LibHxcpp.tests},
		{name: "decode", about: "the reader decodes every corpus module as nekoc -d does", host: false, tests: CorpusSuite.decode},
		{name: "translate", about: "every corpus module reads, passes the stack check and translates", host: false,
			tests: CorpusSuite.translate},
	];

	public static var root:String;
	public static var work:String;
	public static var modes = ["interp", "jit"];
	public static var reuse = false;
	public static var corpusPaths:Array<String> = [];
	static var jobs = 8;
	static var keep = false;
	static var timeoutOverride:Null<Float>;
	static var built:Array<String> = [];
	// The options a worker gets, as given to the harness
	static var passOn:Array<String> = [];

	static function main() {
		root = Path.removeTrailingSlashes(Path.normalize(Sys.getCwd()));
		if (!FileSystem.exists(root + "/test/Harness.hx"))
			quit("run the harness from the repository root: haxe test/harness.hxml");
		var args = Sys.args();
		var hosts:Array<String> = [];
		var list = false;
		var picked = new Map<String, Array<String>>();
		var paths = false;
		var jit = true;
		var worker:Null<{suite:String, tests:Array<Int>, built:String, copies:String}> = null;
		var i = 0;
		function value():String {
			if (i >= args.length)
				quit('${args[i - 1]} needs a value');
			return args[i++];
		}
		while (i < args.length) {
			var a = args[i++];
			switch a {
				case "--host":
					hosts.push(absolute(value()));
				case "--no-jit":
					jit = false;
					passOn.push(a);
				case "--keep":
					keep = true;
				case "--list":
					list = true;
				case "--reuse":
					reuse = true;
					passOn.push(a);
				case "--timeout":
					timeoutOverride = Std.parseFloat(value());
					passOn = passOn.concat([a, args[i - 1]]);
				case "-j" | "--jobs":
					jobs = Std.parseInt(value());
				case "--corpus":
					corpusPaths.push(absolute(value()));
					passOn = passOn.concat([a, corpusPaths[corpusPaths.length - 1]]);
				case "--worker":
					// Internal: runs some of a suite's tests for the harness that started it
					worker = {
						suite: value(),
						tests: [for (t in value().split(",")) Std.parseInt(t)],
						built: value(),
						copies: value()
					};
					work = value();
				case "--help" | "-h":
					for (l in usage)
						Sys.println(l);
					Sys.exit(0);
				case _ if (a.startsWith("-")):
					quit('unknown option $a\n' + usage.join("\n"));
				default:
					var colon = a.indexOf(":");
					var name = colon > 0 ? a.substr(0, colon) : a;
					if (Lambda.exists(suites, s -> s.name == name)) {
						if (!picked.exists(name))
							picked.set(name, []);
						if (colon > 0)
							picked.get(name).push(a.substr(colon + 1).toLowerCase());
					} else if (FileSystem.exists(a)) {
						corpusPaths.push(absolute(a));
						passOn = passOn.concat(["--corpus", corpusPaths[corpusPaths.length - 1]]);
						paths = true;
					} else
						quit('unknown suite $a; the suites are ${[for (s in suites) s.name].join(", ")}');
			}
		}
		if (hosts.length == 0) {
			// The Nekomata host, and the stock cppia host with Nekomata in it once
			//  haxe cppia.hxml has built it
			hosts.push(absolute(FileSystem.exists(root + "/bin/host/nekomata.exe")
				|| !FileSystem.exists(root + "/bin/host/nekomata") ? "bin/host/nekomata.exe" : "bin/host/nekomata"));
			for (c in ["bin/cppia/Cppia.exe", "bin/cppia/Cppia"])
				if (FileSystem.exists(root + "/" + c)) {
					hosts.push(absolute(c));
					break;
				}
		}
		for (h in hosts)
			passOn = passOn.concat(["--host", h]);
		HostBin.setUp(hosts, jit);
		modes = [for (r in HostBin.runners) r.name];
		if (worker != null) {
			runWorker(worker.suite, picked.get(worker.suite), worker.tests, worker.built, worker.copies);
			return;
		}
		if (paths && !picked.keys().hasNext()) {
			picked.set("decode", []);
			picked.set("translate", []);
		}
		var chosen = [for (s in suites) if (!picked.keys().hasNext() || picked.exists(s.name)) s];

		if (list) {
			for (s in chosen) {
				Sys.println('${s.name}: ${s.about}');
				if (picked.keys().hasNext())
					for (t in filtered(s.tests(), picked.get(s.name)))
						Sys.println('  ${t.name}');
			}
			return;
		}

		var tempBase = Sys.getEnv("LOCALAPPDATA") != null ? Sys.getEnv("LOCALAPPDATA") + "/Temp" : Sys.getEnv("TEMP");
		if (tempBase == null || !FileSystem.exists(tempBase))
			tempBase = Sys.getEnv("TEMP");
		work = Path.normalize(tempBase) + "/nekomata-harness/" + DateTools.format(Date.now(), "%Y%m%d-%H%M%S") + "-"
			+ Std.random(100000);
		makeDir(work);

		var nekoVersion = Exec.run("neko", ["-version"], work, null, 60);
		Sys.println('neko ${nekoVersion.out.trim()}, ${[for (h in HostBin.all) '${h.label} at ${h.source}'].join(", ")}');
		Sys.println('runs ${modes.join(", ")}, work in $work');
		var t0 = Sys.time();
		var totals = [];
		var failures = [];
		for (s in chosen) {
			var r = runSuite(s, picked.get(s.name));
			totals.push({name: s.name, result: r});
			failures = failures.concat(r.failures);
		}

		Sys.println("");
		Sys.println("== summary");
		var passed = 0, failed = 0, skipped = 0;
		for (t in totals) {
			var r = t.result;
			passed += r.passed;
			failed += r.failed;
			skipped += r.skipped;
			Sys.println('${t.name.rpad(" ", 13)} ${Std.string(r.passed).lpad(" ", 4)} passed ${Std.string(r.failed).lpad(" ", 4)} failed'
				+ (r.skipped > 0 ? ' ${Std.string(r.skipped).lpad(" ", 4)} skipped' : "") + '   ${seconds(r.seconds)}');
		}
		if (failures.length > 0) {
			Sys.println("");
			Sys.println("failed:");
			for (f in failures)
				Sys.println('  $f');
		}
		Sys.println("");
		Sys.println('$passed passed, $failed failed${skipped > 0 ? ', $skipped skipped' : ""} in ${seconds(Sys.time() - t0)}'
			+ (keep ? ', work kept in $work' : ""));
		if (!keep)
			removeTree(work);
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function quit(message:String):Dynamic {
		Sys.stderr().writeString(message + "\n");
		Sys.exit(2);
		return null;
	}

	static function filtered(tests:Array<Test>, filters:Null<Array<String>>):Array<Test> {
		if (filters == null || filters.length == 0)
			return tests;
		return tests.filter(t -> Lambda.exists(filters, f -> t.name.toLowerCase().indexOf(f) >= 0));
	}

	static function suiteTests(s:Suite, filters:Null<Array<String>>):Array<Test>
		return try filtered(s.tests(), filters) catch (e:Dynamic) [{name: "setup", run: (c:Ctx) -> c.fail("", describe(e))}];

	static function runSuite(s:Suite, filters:Null<Array<String>>) {
		var t0 = Sys.time();
		Sys.println("");
		Sys.println('== ${s.name}: ${s.about}');
		if (s.host)
			for (h in HostBin.all) {
				var problem = h.refresh();
				if (problem != null)
					Sys.println('     $problem');
			}
		var tests = suiteTests(s, filters);
		var results = runTests(s, filters, tests);
		var passed = 0, failed = 0, skipped = 0;
		var failures = [];
		for (o in results) {
			passed += o.passed;
			failed += o.failed;
			skipped += o.skipped;
			failures = failures.concat(o.failures);
			for (b in o.built)
				addBuilt(b);
		}
		var secs = Sys.time() - t0;
		Sys.println('${s.name}: $passed passed, $failed failed${skipped > 0 ? ', $skipped skipped' : ""} in ${seconds(secs)}');
		return {passed: passed, failed: failed, skipped: skipped, seconds: secs, failures: failures};
	}

	static function runOne(suite:String, t:Test):Outcome {
		var c = null;
		try {
			c = new Ctx(suite, t.name);
			t.run(c);
		} catch (e:Dynamic) {
			if (c == null)
				c = new Ctx(suite, t.name, false);
			c.fail("", "harness error: " + describe(e));
		}
		return c.outcome();
	}

	// Runs the tests and prints each one's lines in order as it ends. Haxe's interpreter
	//  deadlocks when one thread sleeps while another waits on a lock, so tests run at
	//  once in worker processes, each a harness given some of the suite's tests
	static function runTests(s:Suite, filters:Null<Array<String>>, tests:Array<Test>):Array<Outcome> {
		var n = tests.length;
		var results:Array<Outcome> = [for (_ in 0...n) null];
		var printed = 0;
		function flush() {
			while (printed < n && results[printed] != null) {
				for (l in results[printed].lines)
					Sys.println(l);
				printed++;
			}
		}
		if (jobs <= 1 || n <= 1) {
			for (i in 0...n) {
				results[i] = runOne(s.name, tests[i]);
				flush();
			}
			return results;
		}
		var dir = work + "/results/" + s.name;
		makeDir(dir);
		var builtFile = dir + "/built.txt";
		File.saveContent(builtFile, built.join("\n"));
		var queue = [for (i in 0...n) i];
		var running:Array<{proc:Proc, tests:Array<Int>}> = [];
		var suiteArg = s.name + (filters != null && filters.length > 0 ? ":" + filters[0] : "");
		var extra = filters == null ? [] : [for (f in filters.slice(1)) s.name + ":" + f];
		while (printed < n) {
			while (running.length < jobs && queue.length > 0) {
				var size = Math.ceil(queue.length / (jobs * 2));
				var chunk = queue.splice(0, size < 1 ? 1 : size > 6 ? 6 : size);
				var copies = [for (h in HostBin.all) h.exe == null ? "" : h.exe].join("|");
				var args = ["-cp", "src", "-cp", "test", "--run", "Harness"].concat(passOn).concat([
					"--worker", s.name, chunk.join(","), builtFile, copies, work, suiteArg
				]).concat(extra);
				running.push({proc: Exec.start("haxe", args, root, null, 6 * 3600), tests: chunk});
			}
			for (w in running.copy()) {
				for (i in w.tests)
					if (results[i] == null)
						results[i] = readOutcome(dir + "/" + i + ".json");
				var r = Exec.poll(w.proc);
				if (r == null)
					continue;
				running.remove(w);
				for (i in w.tests)
					if (results[i] == null)
						results[i] = readOutcome(dir + "/" + i + ".json");
				for (i in w.tests)
					if (results[i] == null) {
						var c = new Ctx(s.name, tests[i].name, false);
						c.fail("", 'harness error: its worker exits ${r.code} with no result\n' + tail(r.err + "\n" + r.out, 8));
						results[i] = c.outcome();
					}
			}
			flush();
			if (printed < n)
				Sys.sleep(0.05);
		}
		return results;
	}

	static function readOutcome(path:String):Null<Outcome> {
		if (!FileSystem.exists(path))
			return null;
		try {
			return haxe.Json.parse(File.getContent(path));
		} catch (_:Dynamic) {
			return null;
		}
	}

	static function runWorker(suite:String, filters:Null<Array<String>>, indexes:Array<Int>, builtFile:String, copies:String) {
		var s = Lambda.find(suites, s -> s.name == suite);
		Exec.tag = suite + "-" + indexes[0];
		if (FileSystem.exists(builtFile))
			built = [for (l in File.getContent(builtFile).split("\n")) if (l.trim() != "") l.trim()];
		var exes = copies.split("|");
		for (i in 0...HostBin.all.length)
			if (i < exes.length && exes[i] != "")
				HostBin.all[i].use(exes[i]);
		var tests = suiteTests(s, filters);
		var dir = work + "/results/" + suite;
		for (i in indexes) {
			var o = runOne(suite, tests[i]);
			o.built = built;
			File.saveContent(dir + "/" + i + ".tmp", haxe.Json.stringify(o));
			FileSystem.rename(dir + "/" + i + ".tmp", dir + "/" + i + ".json");
		}
	}

	public static function describe(e:Dynamic):String {
		if (Std.isOfType(e, haxe.Exception))
			return (e : haxe.Exception).message;
		return Std.string(e);
	}

	// A run's timeout: the suite's, unless --timeout says otherwise
	public static function limit(seconds:Float):Float
		return timeoutOverride != null ? timeoutOverride : seconds;

	public static function addBuilt(path:String)
		if (built.indexOf(path) < 0)
			built.push(path);

	public static function builtModules():Array<String>
		return built.copy();

	// Runs args on neko, or on one of HostBin.runners: a host, interpreted or with the JIT
	public static function on(runner:String, args:Array<String>, cwd:String, ?env:Env, timeout = 120.0):Run {
		if (runner == "neko")
			return Exec.run("neko", args, cwd, env, timeout);
		var rr = Lambda.find(HostBin.runners, r -> r.name == runner);
		if (rr == null)
			throw 'no runner $runner';
		var host = rr.host;
		var full = rr.jit ? ["-jit"].concat(args) : args;
		// Programs the host runs that start "neko" start the host, in the same mode
		var hostEnv:Env = env == null ? new Map() : env.copy();
		if (rr.jit)
			hostEnv.set("NEKOMATA_JIT", "1");
		var r = null;
		// A host that is missing or half written is rebuilding, not failing
		for (attempt in 0...3) {
			if (host.exe == null || !FileSystem.exists(host.exe)) {
				host.invalidate();
				var problem = host.refresh();
				if (problem != null)
					return {out: "", err: problem, code: 9009, timedOut: false, seconds: 0};
			}
			var standIn = host.standIn();
			if (standIn != null)
				hostEnv.set("PATH", win(standIn) + ";" + Sys.getEnv("PATH"));
			r = Exec.run(host.exe, full, cwd, hostEnv, timeout);
			if (!Exec.notStarted(r))
				return r;
			host.invalidate();
		}
		return r;
	}

	// Runs the same command on neko and on the host in each mode, each in a fresh
	//  directory, and checks the host prints what neko prints and exits the same way
	public static function versus(c:Ctx, label:String, args:Array<String>, ?o:Versus):Bool {
		if (o == null)
			o = {};
		var timeout = o.timeout != null ? o.timeout : limit(120);
		var prefix = label == "" ? "" : label + "-";
		function prepare(runner:String):String {
			var d = c.sub(prefix + runner);
			if (o.setup != null)
				o.setup(d);
			return d;
		}
		function start(runner:String, d:String):Run
			return on(runner, o.argsFor != null ? o.argsFor(d) : args, o.cwd != null ? o.cwd : d, o.env, timeout);
		var nd = prepare("neko");
		var exp = start("neko", nd);
		if (exp.timedOut) {
			c.fail(label, 'neko itself times out after ${seconds(exp.seconds)}');
			return false;
		}
		var all = true;
		for (mode in modes) {
			var d = prepare(mode);
			var got = start(mode, d);
			var why = Text.compare(exp, got, [nd], [d]);
			if (why == null && o.check != null)
				why = o.check(nd, d);
			var title = label == "" ? mode : '$label $mode';
			if (why == null)
				c.ok(title, seconds(got.seconds) + (got.seconds >= 1 ? ', neko ${seconds(exp.seconds)}' : ""))
			else {
				c.fail(title, why);
				all = false;
			}
		}
		return all;
	}

	// Checks two directories hold the same bytes at each of the given paths
	public static function sameFiles(nekoDir:String, hostDir:String, rels:Array<String>):Null<String> {
		var problems = [];
		for (rel in rels) {
			var a = nekoDir + "/" + rel, b = hostDir + "/" + rel;
			var hasA = FileSystem.exists(a), hasB = FileSystem.exists(b);
			if (!hasA && !hasB)
				continue;
			if (!hasB)
				problems.push('$rel is missing');
			else if (!hasA)
				problems.push('$rel is written where neko writes none');
			else {
				var x = File.getBytes(a), y = File.getBytes(b);
				var at = firstDifference(x, y);
				if (at >= 0)
					problems.push('$rel differs from byte $at (${y.length} bytes, neko writes ${x.length})');
			}
		}
		if (problems.length == 0)
			return null;
		var more = problems.length > 6 ? ['... ${problems.length - 6} more'] : [];
		return '${problems.length} of ${rels.length} files differ\n' + problems.slice(0, 6).concat(more).join("\n");
	}

	// sameFiles on every file with the extension under either directory
	public static function sameTree(nekoDir:String, hostDir:String, ext:String):Null<String> {
		var rels = walk(nekoDir, ext);
		for (r in walk(hostDir, ext))
			if (rels.indexOf(r) < 0)
				rels.push(r);
		rels.sort(Reflect.compare);
		return sameFiles(nekoDir, hostDir, rels);
	}

	static function firstDifference(a:Bytes, b:Bytes):Int {
		var n = a.length < b.length ? a.length : b.length;
		for (i in 0...n)
			if (a.get(i) != b.get(i))
				return i;
		return a.length == b.length ? -1 : n;
	}

	// Paths of the files with the extension under dir, relative to it
	public static function walk(dir:String, ext:String, prefix = ""):Array<String> {
		var out = [];
		if (!FileSystem.exists(dir))
			return out;
		var names = FileSystem.readDirectory(dir);
		names.sort(Reflect.compare);
		for (n in names) {
			var p = dir + "/" + n;
			if (FileSystem.isDirectory(p))
				out = out.concat(walk(p, ext, prefix + n + "/"));
			else if (n.endsWith(ext))
				out.push(prefix + n);
		}
		return out;
	}

	// Names of the files in dir with the extension, sorted
	public static function files(dir:String, ext:String):Array<String> {
		if (!FileSystem.exists(dir))
			return [];
		var names = [for (n in FileSystem.readDirectory(dir)) if (n.endsWith(ext) && !FileSystem.isDirectory(dir + "/" + n)) n];
		names.sort(Reflect.compare);
		return names;
	}

	public static function copyTree(from:String, to:String, ?skip:String->Bool, rel = "") {
		makeDir(to);
		for (n in FileSystem.readDirectory(from)) {
			var r = rel + n;
			if (skip != null && skip(r))
				continue;
			var s = from + "/" + n, d = to + "/" + n;
			if (FileSystem.isDirectory(s))
				copyTree(s, d, skip, r + "/");
			else
				File.copy(s, d);
		}
	}

	public static function removeTree(path:String) {
		try {
			if (!FileSystem.exists(path))
				return;
			if (FileSystem.isDirectory(path)) {
				for (n in FileSystem.readDirectory(path))
					removeTree(path + "/" + n);
				FileSystem.deleteDirectory(path);
			} else
				FileSystem.deleteFile(path);
		} catch (_:Dynamic) {}
	}

	// Tests running at once may create the same parent directory
	public static function makeDir(path:String) {
		for (attempt in 0...5)
			try {
				FileSystem.createDirectory(path);
				return;
			} catch (e:Dynamic) {
				if (FileSystem.exists(path) && FileSystem.isDirectory(path))
					return;
				if (attempt == 4)
					throw e;
				Sys.sleep(0.05);
			}
	}

	public static function absolute(path:String):String
		return Path.removeTrailingSlashes(Path.normalize(FileSystem.absolutePath(path)));

	public static function win(path:String):String
		return path.replace("/", "\\");

	public static function safeName(name:String):String
		return ~/[^A-Za-z0-9._-]+/g.replace(name, "_");

	public static function seconds(s:Float):String
		return s < 10 ? '${Math.round(s * 10) / 10} s' : '${Math.round(s)} s';

	// The first lines of some output, for a failure's reason
	public static function head(text:String, n = 6):String {
		var lines = text.trim().split("\n");
		return lines.slice(0, n).concat(lines.length > n ? ['... ${lines.length - n} more lines'] : []).join("\n");
	}

	// The last lines, to show where a run that hung or crashed got to
	public static function tail(text:String, n = 4):String {
		var lines = text.trim().split("\n");
		return lines.slice(lines.length > n ? lines.length - n : 0).join("\n");
	}
}

// What a test reported, as a worker hands it to the harness
typedef Outcome = {
	var passed:Int;
	var failed:Int;
	var skipped:Int;
	var lines:Array<String>;
	var failures:Array<String>;
	var built:Array<String>;
}

// A test as it runs: its work directory and what it reports
class Ctx {
	public final suite:String;
	public final name:String;
	public final dir:String;
	public final lines:Array<String> = [];
	public var passed = 0;
	public var failed = 0;
	public var skipped = 0;
	final failures:Array<String> = [];

	public function new(suite:String, name:String, create = true) {
		this.suite = suite;
		this.name = name;
		dir = Harness.work + "/" + suite + "/" + Harness.safeName(name);
		if (create)
			Harness.makeDir(dir);
	}

	public function outcome():Outcome
		return {
			passed: passed,
			failed: failed,
			skipped: skipped,
			lines: lines,
			failures: failures,
			built: []
		};

	function title(label:String):String
		return label == "" ? name : '$name $label';

	public function ok(label:String, ?note:String) {
		passed++;
		lines.push('ok   ${title(label)}' + (note == null ? "" : ' ($note)'));
	}

	public function fail(label:String, reason:String) {
		failed++;
		var rs = reason.trim().split("\n");
		lines.push('FAIL ${title(label)}: ${rs[0]}');
		for (r in rs.slice(1))
			lines.push('       ' + Text.clip(r));
		failures.push('$suite ${title(label)}: ${rs[0]}');
	}

	public function skip(label:String, reason:String) {
		skipped++;
		lines.push('skip ${title(label)}: $reason');
	}

	public function info(text:String)
		for (l in text.split("\n"))
			lines.push('     $l');

	// A fresh directory in the test's own
	public function sub(name:String):String {
		var d = dir + "/" + Harness.safeName(name);
		Harness.removeTree(d);
		Harness.makeDir(d);
		return d;
	}
}

// A command started by Exec.start
typedef Proc = {
	var p:sys.io.Process;
	var rd:String;
	var cwd:String;
	var start:Float;
	var timeout:Float;
}

// Runs commands through a batch file, their output going to files and their exit code
//  to a file written last. Haxe's interpreter cannot wait on a process or read a pipe
//  with a timeout, and its threads deadlock, so the harness polls for that file and
//  can kill a run that hangs
class Exec {
	// Names this process's runs apart from those of the harness's other processes
	public static var tag = "main";
	static var counter = 0;

	public static function run(cmd:String, args:Array<String>, cwd:String, ?env:Env, timeout = 120.0):Run {
		var h = start(cmd, args, cwd, env, timeout);
		var pause = 0.005;
		while (true) {
			var r = poll(h);
			if (r != null)
				return r;
			Sys.sleep(pause);
			if (pause < 0.05)
				pause *= 1.5;
		}
	}

	public static function start(cmd:String, args:Array<String>, cwd:String, ?env:Env, timeout = 120.0):Proc {
		var rd = Harness.work + "/runs/" + tag + "-" + (counter++);
		Harness.makeDir(rd);
		var w = Harness.win(rd);
		var b = new StringBuf();
		b.add("@echo off\r\n");
		b.add('cd /d "${Harness.win(cwd)}" || goto nodir\r\n');
		if (env != null)
			for (k => v in env)
				b.add('set "$k=${v == null ? "" : v.replace("%", "%%")}"\r\n');
		b.add(commandLine(cmd, args) + ' < nul > "$w\\out" 2> "$w\\err"\r\n');
		b.add('(echo %ERRORLEVEL%)> "$w\\code.tmp"\r\n');
		b.add('ren "$w\\code.tmp" code\r\n');
		b.add("exit /b 0\r\n");
		b.add(":nodir\r\n");
		b.add('(echo 9998)> "$w\\code.tmp"\r\n');
		b.add('ren "$w\\code.tmp" code\r\n');
		File.saveContent(rd + "/run.bat", b.toString());
		return {
			p: new sys.io.Process(w + "\\run.bat"),
			rd: rd,
			cwd: cwd,
			start: Sys.time(),
			timeout: timeout
		};
	}

	// The run, once it has ended or been killed for taking too long
	public static function poll(h:Proc):Null<Run> {
		var timedOut = false;
		if (!FileSystem.exists(h.rd + "/code")) {
			if (Sys.time() - h.start <= h.timeout)
				return null;
			// The whole tree, as the host may have started processes of its own
			Sys.command('taskkill /F /T /PID ${h.p.getPid()} > nul 2>&1');
			timedOut = true;
		}
		var secs = Sys.time() - h.start;
		h.p.close();
		var code = -1;
		if (!timedOut) {
			var c = Std.parseInt(read(h.rd + "/code").trim());
			code = c == null ? -1 : c;
		}
		var err = read(h.rd + "/err");
		if (code == 9998)
			err = 'cannot enter ${h.cwd}';
		return {out: read(h.rd + "/out"), err: err, code: code, timedOut: timedOut, seconds: secs};
	}

	static function read(path:String):String {
		for (attempt in 0...5)
			try {
				if (!FileSystem.exists(path))
					return "";
				return Text.decode(File.getBytes(path));
			} catch (_:Dynamic) {
				// Still held by a process taskkill is ending
				Sys.sleep(0.2);
			}
		return "";
	}

	// Whether cmd.exe could not start the program at all, which then printed nothing,
	//  rather than a program that ran and failed
	public static function notStarted(r:Run):Bool {
		if (r.timedOut || r.out != "")
			return false;
		var e = r.err.trim();
		return (r.code == 9009 && (e == "" || e.indexOf("is not recognized as an internal or external command") >= 0))
			|| e.startsWith("The system cannot execute the specified program") || e.indexOf("is not compatible with the version of Windows") >= 0
			|| e.startsWith("Access is denied");
	}

	// The command as a batch file line: quoted for the program's own argument parsing,
	//  then escaped for cmd.exe, which would otherwise read & | < > ^ ( ) % and quotes.
	//  cmd.exe reads the file in the console's code page, so arguments past ASCII do not
	//  arrive as written
	static function commandLine(cmd:String, args:Array<String>):String {
		var parts = [cmd.indexOf(" ") >= 0 ? '"$cmd"' : cmd];
		for (a in args) {
			var q = haxe.SysTools.quoteWinArg(a, false);
			var b = new StringBuf();
			for (i in 0...q.length) {
				var ch = q.charAt(i);
				switch ch {
					case "%":
						b.add("%%");
					case "(" | ")" | "!" | "^" | "\"" | "<" | ">" | "&" | "|" | " ":
						b.add("^" + ch);
					default:
						b.add(ch);
				}
			}
			parts.push(b.toString());
		}
		return parts.join(" ");
	}
}

typedef Runner = {
	var name:String;
	var host:HostBin;
	var jit:Bool;
}

// A host under test. It runs from a private copy, so a rebuild can replace the binary
//  while tests run, and a missing or half written binary means wait, not fail. Next to
//  the copy, standin/neko.exe is the host named neko, which takes neko's command line,
//  so programs that start "neko" start the host
class HostBin {
	public static var all:Array<HostBin> = [];
	// Each host interpreted and with the JIT, named for reports and directories
	public static var runners:Array<Runner> = [];

	public final source:String;
	public final label:String;
	public var exe:Null<String>;
	var stamp:Null<String>;
	var copies = 0;

	public static function setUp(paths:Array<String>, jit:Bool) {
		all = [];
		for (p in paths) {
			var label = Path.withoutExtension(Path.withoutDirectory(p));
			var n = 2;
			while (Lambda.exists(all, h -> h.label == label))
				label = Path.withoutExtension(Path.withoutDirectory(p)) + n++;
			all.push(new HostBin(p, label));
		}
		runners = [];
		for (h in all)
			for (j in (jit ? [false, true] : [false]))
				runners.push({name: (all.length > 1 ? h.label + " " : "") + (j ? "jit" : "interp"), host: h, jit: j});
	}

	function new(source:String, label:String) {
		this.source = source;
		this.label = label;
	}

	static function stampOf(path:String):Null<String> {
		try {
			if (!FileSystem.exists(path))
				return null;
			var s = FileSystem.stat(path);
			return s.size + "@" + s.mtime.getTime();
		} catch (_:Dynamic) {
			return null;
		}
	}

	// A worker takes the copy the harness made
	public function use(path:String) {
		exe = path;
		stamp = stampOf(source);
	}

	// Only the Nekomata host takes neko's command line; programs another host runs
	//  start the first Nekomata host for "neko"
	public function standIn():Null<String> {
		var h = label.toLowerCase().startsWith("nekomata") ? this : Lambda.find(all, h -> h.label.toLowerCase().startsWith("nekomata"));
		return h == null || h.exe == null ? null : Path.directory(h.exe) + "/standin";
	}

	public function invalidate()
		stamp = null;

	// Copies the host when it changed since the last copy; null when there is one to use
	public function refresh():Null<String>
		return try update() catch (e:Dynamic) Harness.describe(e);

	function update():Null<String> {
		var start = Sys.time();
		var said = false;
		var problem = "";
		while (true) {
			var s = stampOf(source);
			if (s != null && s == stamp && exe != null && FileSystem.exists(exe))
				return null;
			if (s != null) {
				// Still being written when it changes under us
				Sys.sleep(1);
				if (stampOf(source) == s) {
					var dir = Harness.work + "/host/" + label + "-" + Exec.tag + "-" + (copies++);
					Harness.makeDir(dir + "/standin");
					var name = Path.withoutDirectory(source);
					var to = dir + "/" + name;
					try {
						File.copy(source, to);
						File.copy(source, dir + "/standin/" + (name.endsWith(".exe") ? "neko.exe" : "neko"));
						var from = Path.directory(source);
						for (n in FileSystem.readDirectory(from))
							if (n.endsWith(".dll") || n.endsWith(".ndll")) {
								File.copy(from + "/" + n, dir + "/" + n);
								File.copy(from + "/" + n, dir + "/standin/" + n);
							}
						var r = Exec.run(to, [], dir, null, 60);
						if (!Exec.notStarted(r) && !r.timedOut) {
							exe = to;
							stamp = s;
							return null;
						}
						problem = 'it does not start: ${r.err.trim()}';
					} catch (e:Dynamic) {
						problem = 'cannot copy it: ${Harness.describe(e)}';
					}
				}
			} else
				problem = "it is missing";
			if (Sys.time() - start > 900)
				return 'no usable host at $source after 15 minutes: $problem';
			if (!said) {
				Sys.println('     waiting for the host at $source: $problem');
				said = true;
			}
			Sys.sleep(5);
		}
	}
}

class Text {
	// Output as text, without the CRs Windows adds; bytes that are not UTF-8 read as Latin-1
	public static function decode(b:Bytes):String {
		var out = Bytes.alloc(b.length);
		var n = 0;
		for (i in 0...b.length) {
			var c = b.get(i);
			if (c != 13)
				out.set(n++, c);
		}
		var clean = out.sub(0, n);
		if (validUtf8(clean))
			return clean.toString();
		var s = new StringBuf();
		for (i in 0...n)
			s.addChar(clean.get(i));
		return s.toString();
	}

	static function validUtf8(b:Bytes):Bool {
		var i = 0, n = b.length;
		while (i < n) {
			var c = b.get(i);
			var extra = c < 0x80 ? 0 : c >= 0xC2 && c < 0xE0 ? 1 : c >= 0xE0 && c < 0xF0 ? 2 : c >= 0xF0 && c < 0xF5 ? 3 : -1;
			if (extra < 0 || i + extra >= n)
				return false;
			for (k in 1...extra + 1)
				if (b.get(i + k) & 0xC0 != 0x80)
					return false;
			if (extra > 1) {
				// Overlong forms, surrogates and code points past 0x10FFFF
				var c1 = b.get(i + 1);
				if ((c == 0xE0 && c1 < 0xA0) || (c == 0xED && c1 >= 0xA0) || (c == 0xF0 && c1 < 0x90) || (c == 0xF4 && c1 >= 0x90))
					return false;
			}
			i += extra + 1;
		}
		return true;
	}

	// Replaces each directory, in any of the spellings a program may print, with <dir>
	public static function norm(s:String, dirs:Array<String>):String {
		for (d in dirs)
			for (v in [d, d.replace("/", "\\"), d.replace("/", "\\\\")])
				s = replaceNoCase(s, v, "<dir>");
		return s;
	}

	static function replaceNoCase(s:String, find:String, by:String):String {
		var low = s.toLowerCase(), f = find.toLowerCase();
		var i = low.indexOf(f);
		if (i < 0)
			return s;
		var b = new StringBuf();
		var last = 0;
		while (i >= 0) {
			b.add(s.substring(last, i));
			b.add(by);
			last = i + f.length;
			i = low.indexOf(f, last);
		}
		b.add(s.substr(last));
		return b.toString();
	}

	// What differs between neko's run and the host's, or null when nothing does
	public static function compare(exp:Run, got:Run, expDirs:Array<String>, gotDirs:Array<String>):Null<String> {
		if (got.timedOut)
			return 'timed out after ${Harness.seconds(got.seconds)}' + (got.out.trim() != "" ? "\nlast output:\n" + Harness.tail(got.out) : "");
		var problems = [], details = [];
		var eo = norm(exp.out, expDirs), go = norm(got.out, gotDirs);
		if (eo != go) {
			problems.push("stdout differs");
			details.push(diff(eo, go, "stdout"));
		}
		var ee = norm(exp.err, expDirs), ge = norm(got.err, gotDirs);
		if (ee != ge) {
			problems.push("stderr differs");
			details.push(diff(ee, ge, "stderr"));
		}
		if (exp.code != got.code)
			problems.push('exits ${got.code}${describeCode(got.code)} where neko exits ${exp.code}');
		if (problems.length == 0)
			return null;
		return problems.join(", ") + (details.length > 0 ? "\n" + details.join("\n") : "");
	}

	// The lines between the common start and end of two outputs: - neko's, + the host's
	public static function diff(exp:String, got:String, what:String):String {
		var e = exp.split("\n"), g = got.split("\n");
		var p = 0;
		while (p < e.length && p < g.length && e[p] == g[p])
			p++;
		var s = 0;
		while (s < e.length - p && s < g.length - p && e[e.length - 1 - s] == g[g.length - 1 - s])
			s++;
		var out = ['$what from line ${p + 1}:'];
		var a = e.slice(p, e.length - s), b = g.slice(p, g.length - s);
		if (a.length * b.length > 1000000) {
			// Too long to align: the start of each side
			function side(lines:Array<String>, mark:String) {
				for (k in 0...(lines.length < 4 ? lines.length : 4))
					out.push('$mark ${lines[k]}');
				if (lines.length > 4)
					out.push('$mark ... ${lines.length - 4} more lines');
			}
			side(a, "-");
			side(b, "+");
			return out.join("\n");
		}
		// The lines that differ, aligned on a longest common subsequence
		var w = b.length + 1;
		var lcs = new haxe.ds.Vector<Int>((a.length + 1) * w);
		for (i in 0...(a.length + 1) * w)
			lcs[i] = 0;
		var i = a.length - 1;
		while (i >= 0) {
			var j = b.length - 1;
			while (j >= 0) {
				lcs[i * w + j] = a[i] == b[j] ? lcs[(i + 1) * w + j + 1] + 1 : Std.int(Math.max(lcs[(i + 1) * w + j], lcs[i * w + j + 1]));
				j--;
			}
			i--;
		}
		var shown = 0, hidden = 0;
		var x = 0, y = 0;
		function line(text:String) {
			if (shown < 8) {
				out.push(text);
				shown++;
			} else
				hidden++;
		}
		while (x < a.length || y < b.length) {
			if (x < a.length && y < b.length && a[x] == b[y]) {
				x++;
				y++;
			} else if (y >= b.length || (x < a.length && lcs[(x + 1) * w + y] >= lcs[x * w + y + 1])) {
				line('- ${a[x]}');
				x++;
			} else {
				line('+ ${b[y]}');
				y++;
			}
		}
		if (hidden > 0)
			out.push('... $hidden more differing lines');
		return out.join("\n");
	}

	public static function clip(s:String):String
		return s.length > 220 ? s.substr(0, 220) + "..." : s;

	public static function describeCode(code:Int):String {
		return switch code {
			case -1073741819: " (access violation)";
			case -1073741571: " (native stack overflow)";
			case -1073740791: " (fail fast)";
			case -1073741676: " (integer division by zero)";
			case -1073741795: " (illegal instruction)";
			case -2147483645: " (breakpoint)";
			case -1073740940: " (heap corruption)";
			case 9009: " (did not start)";
			default: "";
		}
	}
}

// test/cases: neko/*.neko built with nekoc next to every module in neko/lib, and
//  haxe/*.hx built with haxe -neko. A Haxe case's first comment lines can say
//  "// flags: <haxe options>", "// args: <program arguments>" and
//  "// variant: <haxe options>", which also runs the case built with those options
class Cases {
	public static function tests():Array<Test> {
		var tests:Array<Test> = [];
		var nekoDir = Harness.root + "/test/cases/neko";
		var libs = Harness.files(nekoDir + "/lib", ".neko");
		for (f in Harness.files(nekoDir, ".neko")) {
			var name = Path.withoutExtension(f);
			var d = directives(File.getContent(nekoDir + "/" + f));
			tests.push({name: 'neko/$name', run: c -> neko(c, nekoDir, f, libs, d.args)});
			for (a in d.runs)
				tests.push({name: 'neko/$name ' + a.join(" "), run: c -> neko(c, nekoDir, f, libs, a)});
		}
		var hxDir = Harness.root + "/test/cases/haxe";
		for (f in Harness.files(hxDir, ".hx")) {
			var name = Path.withoutExtension(f);
			var d = directives(File.getContent(hxDir + "/" + f));
			tests.push({name: 'haxe/$name', run: c -> haxe(c, name, d.flags, d.args)});
			for (a in d.runs)
				tests.push({name: 'haxe/$name ' + a.join(" "), run: c -> haxe(c, name, d.flags, a)});
			for (v in d.variants)
				tests.push({name: 'haxe/$name[${v.join(" ")}]', run: c -> haxe(c, name, d.flags.concat(v), d.args)});
		}
		return tests;
	}

	static function directives(source:String) {
		var r = {flags: [], args: [], variants: [], runs: []};
		for (l in source.split("\n")) {
			l = l.trim();
			if (!l.startsWith("//"))
				break;
			var text = l.substr(2).trim();
			var colon = text.indexOf(":");
			if (colon < 0)
				continue;
			// Words split at spaces, but not inside double quotes
			var words = [];
			var quoted = ~/"([^"]*)"|(\S+)/;
			var rest = text.substr(colon + 1);
			while (quoted.match(rest)) {
				words.push(quoted.matched(1) != null ? quoted.matched(1) : quoted.matched(2));
				rest = quoted.matchedRight();
			}
			switch text.substr(0, colon) {
				case "flags":
					r.flags = r.flags.concat(words);
				case "args":
					r.args = r.args.concat(words);
				case "variant":
					r.variants.push(words);
				case "run":
					r.runs.push(words);
				default:
			}
		}
		return r;
	}

	static function neko(c:Ctx, dir:String, file:String, libs:Array<String>, args:Array<String>) {
		var b = c.sub("build");
		File.copy(dir + "/" + file, b + "/" + file);
		for (l in libs)
			File.copy(dir + "/lib/" + l, b + "/" + l);
		var r = Exec.run("nekoc", [file].concat(libs), b, null, Harness.limit(120));
		var main = Path.withoutExtension(file) + ".n";
		if (r.code != 0 || !FileSystem.exists(b + "/" + main)) {
			c.fail("build", "nekoc fails:\n" + Harness.head(r.out + r.err));
			return;
		}
		var modules = Harness.files(b, ".n");
		Harness.addBuilt(b + "/" + main);
		Harness.versus(c, "", [main].concat(args), {
			setup: d -> for (m in modules)
				File.copy(b + "/" + m, d + "/" + m)
		});
	}

	static function haxe(c:Ctx, name:String, flags:Array<String>, args:Array<String>) {
		var b = c.sub("build");
		var out = b + "/" + name + ".n";
		var r = Exec.run("haxe", ["-cp", "test/cases/haxe", "-main", name, "-neko", out].concat(flags), Harness.root, null, Harness.limit(300));
		if (r.code != 0 || !FileSystem.exists(out)) {
			c.fail("build", "haxe fails:\n" + Harness.head(r.err + r.out));
			return;
		}
		Harness.addBuilt(out);
		Harness.versus(c, "", [name + ".n"].concat(args), {setup: d -> File.copy(out, d + "/" + name + ".n")});
	}
}

// Neko's own sources: its benchmarks, and its bootstrap compilers run on the host
class NekoSuite {
	static var src(get, never):String;
	static var boot(get, never):String;

	static function get_src()
		return Harness.root + "/test/upstream/neko/src";

	static function get_boot()
		return Harness.root + "/test/upstream/neko/boot";

	public static function tests():Array<Test> {
		if (!FileSystem.exists(src))
			throw 'missing $src: run test/upstream/fetch.sh';
		var tests:Array<Test> = [
			{name: "bootstrap", run: bootstrap},
			{name: "nekoml.n neko/Ast.nml", run: smallNekoml}
		];
		for (f in Harness.files(src + "/benchs", ".neko"))
			tests.push({name: "bench/" + Path.withoutExtension(f), run: c -> bench(c, f)});
		for (rel in Harness.walk(src, ".neko"))
			tests.push({name: "nekoc.n " + rel, run: c -> selfCompile(c, rel)});
		return tests;
	}

	static function bench(c:Ctx, f:String) {
		var b = c.sub("build");
		File.copy(src + "/benchs/" + f, b + "/" + f);
		var r = Exec.run("nekoc", [f], b, null, Harness.limit(120));
		var m = Path.withoutExtension(f) + ".n";
		if (r.code != 0 || !FileSystem.exists(b + "/" + m)) {
			c.fail("build", "nekoc fails:\n" + Harness.head(r.out + r.err));
			return;
		}
		Harness.addBuilt(b + "/" + m);
		Harness.versus(c, "", [m], {
			timeout: Harness.limit(600),
			setup: d -> {
				File.copy(b + "/" + m, d + "/" + m);
				// module.neko loads boot/nekoc.n over and over
				Harness.makeDir(d + "/boot");
				File.copy(boot + "/nekoc.n", d + "/boot/nekoc.n");
			}
		});
	}

	// nekoml.n compiling one module and the core library it uses: what the bootstrap's
	//  first step does, small enough to finish when the host runs nekoml slowly
	static function smallNekoml(c:Ctx) {
		Harness.versus(c, "", [Harness.win(boot + "/nekoml.n"), "-nostd", "-p", "core", "neko/Ast.nml"], {
			timeout: Harness.limit(300),
			setup: d -> Harness.copyTree(src, d),
			check: (nd, d) -> Harness.sameTree(nd, d, ".n"),
		});
	}

	// boot/nekoc.n on the host compiles one of neko's sources to the same bytes
	static function selfCompile(c:Ctx, rel:String) {
		var file = Path.withoutDirectory(rel);
		var out = Path.withoutExtension(file) + ".n";
		Harness.versus(c, "", [Harness.win(boot + "/nekoc.n"), file], {
			timeout: Harness.limit(300),
			setup: d -> File.copy(src + "/" + rel, d + "/" + file),
			check: (nd, d) -> Harness.sameFiles(nd, d, [out]),
		});
	}

	// Neko's build of itself, on neko and on the host side by side: nekoml compiles the
	//  compilers, nekoc links them, and the linked nekoc compiles the benchmarks
	static function bootstrap(c:Ctx) {
		var nekoc = Harness.win(boot + "/nekoc.n");
		var benchs = [for (f in Harness.files(src + "/benchs", ".neko")) "benchs/" + f];
		var steps:Array<{label:String, args:Array<String>, outputs:Null<Array<String>>}> = [
			{label: "nekoml", args: [Harness.win(boot + "/nekoml.n"), "-nostd", "neko/Main.nml", "nekoml/Main.nml"], outputs: null},
			{label: "link nekoc", args: [nekoc, "-link", "nekoc.n", "neko/Main"], outputs: ["nekoc.n"]},
			{label: "link nekoml", args: [nekoc, "-link", "nekoml.n", "nekoml/Main"], outputs: ["nekoml.n"]},
			{label: "linked nekoc", args: ["nekoc.n"].concat(benchs), outputs: [for (b in benchs) Path.withoutExtension(b) + ".n"]},
		];
		var dirs = new Map<String, String>();
		for (r in ["neko"].concat(Harness.modes)) {
			var d = c.sub(r) + "/src";
			Harness.copyTree(src, d);
			dirs.set(r, d);
		}
		// After a step fails on the host, the next ones start from what neko's run of it
		//  wrote, so each step is checked on its own
		var alive = [for (m in Harness.modes) m => true];
		for (s in steps) {
			var nd = dirs.get("neko");
			var exp = Harness.on("neko", s.args, nd, null, Harness.limit(600));
			if (exp.timedOut || exp.code != 0) {
				c.fail(s.label, 'fails on neko itself, exit ${exp.code}\n' + Harness.head(exp.out + exp.err));
				return;
			}
			if (s.label == "link nekoc")
				Harness.addBuilt(nd + "/nekoc.n");
			if (s.label == "link nekoml")
				Harness.addBuilt(nd + "/nekoml.n");
			for (m in Harness.modes) {
				var title = '${s.label} $m';
				var d = dirs.get(m);
				var seeded = !alive.get(m);
				if (seeded) {
					Harness.removeTree(d);
					Harness.copyTree(nd, d);
					// Without what neko's run of this step writes
					if (s.outputs != null)
						for (o in s.outputs)
							Harness.removeTree(d + "/" + o);
					alive.set(m, true);
				}
				var got = Harness.on(m, s.args, d, null, Harness.limit(600));
				var why = Text.compare(exp, got, [nd], [d]);
				if (why == null)
					why = s.outputs == null ? Harness.sameTree(nd, d, ".n") : Harness.sameFiles(nd, d, s.outputs);
				var from = seeded ? ", from neko's earlier steps" : "";
				if (why == null)
					c.ok(title, Harness.seconds(got.seconds) + from);
				else {
					why = why + (seeded ? "\n(starting from neko's earlier steps)" : "");
					c.fail(title, why);
					alive.set(m, false);
				}
			}
		}
	}
}

typedef UtestResult = {
	var done:Bool;
	var ok:Bool;
	var assertions:String;
	var failing:Array<{name:String, why:String}>;
}

// Haxe's unit, sys and threads tests, built and run the way Haxe's CI runs them for
//  neko (tests/runci/targets/Neko.hx), each run in a fresh copy of the build
class Upstream {
	public static function unit():Array<Test>
		return [{name: "unit.n", run: c -> run(c, "unit", ["compile-neko.hxml"], ["bin/unit.n"], null)}];

	public static function sys():Array<Test>
		return [
			{
				name: "sys.n",
				run: c -> run(c, "sys", ["compile-neko.hxml"], [
					"bin/neko/sys.n",
					"bin/neko/TestArguments.n",
					"bin/neko/UtilityProcess.n",
					"bin/neko/ExitCode.n"
				], ["EXISTS" => "1"])
			}
		];

	public static function threads():Array<Test>
		return [
			{name: "threads.n", run: c -> run(c, "threads", ["build.hxml", "--neko", "export/threads.n"], ["export/threads.n"], null)}
		];

	static function skipped(rel:String):Bool
		return rel == ".haxelib" || rel == "bin" || rel == "export" || rel == "dump" || (rel.startsWith("temp/") && rel != "temp/.gitignore");

	// Builds the tests in dir, then runs outputs[0] on neko and the host. The host passes
	//  when every test that passes on neko passes on it too, and it exits as neko does
	static function run(c:Ctx, dir:String, build:Array<String>, outputs:Array<String>, env:Null<Env>) {
		var from = Harness.root + "/test/upstream/haxe/tests/" + dir;
		var utest = Harness.root + "/test/upstream/utest";
		if (!FileSystem.exists(from) || !FileSystem.exists(utest)) {
			c.fail("", 'missing $from or $utest: run test/upstream/fetch.sh');
			return;
		}
		var b = Harness.reuse ? Harness.root + "/bin/harness/" + dir : c.dir + "/build";
		if (Harness.reuse && Lambda.foreach(outputs, o -> FileSystem.exists(b + "/" + o)))
			c.info('reusing the build in $b');
		else {
			Harness.removeTree(b);
			Harness.copyTree(from, b, skipped);
			Exec.run("haxelib", ["newrepo"], b, null, 60);
			var r = Exec.run("haxelib", ["dev", "utest", Harness.win(utest)], b, null, 60);
			if (r.code != 0) {
				c.fail("build", "haxelib dev utest fails:\n" + Harness.head(r.out + r.err));
				return;
			}
			r = Exec.run("haxe", build, b, null, Harness.limit(900));
			if (r.code != 0 || !Lambda.foreach(outputs, o -> FileSystem.exists(b + "/" + o))) {
				c.fail("build", 'haxe ${build.join(" ")} fails:\n' + Harness.head(r.err + r.out, 10));
				return;
			}
			c.ok("build", Harness.seconds(r.seconds));
		}
		for (o in outputs)
			Harness.addBuilt(b + "/" + o);

		var module = outputs[0];
		var expected:UtestResult = null;
		var nekoRun:Run = null;
		for (runner in ["neko"].concat(Harness.modes)) {
			// Named as upstream, since the sys tests look for their own directory by name
			var d = c.sub(runner) + "/" + dir;
			Harness.copyTree(b, d, rel -> rel == ".haxelib" || rel == "dump");
			var r = Harness.on(runner, [module], d, env, Harness.limit(900));
			var u = results(r.out);
			if (runner == "neko") {
				nekoRun = r;
				expected = u;
				if (!u.done) {
					c.fail("neko", 'neko itself reports no results, exit ${r.code}\n' + Harness.tail(r.out + "\n" + r.err, 6));
					return;
				}
				c.info('neko: ${u.ok ? "ALL TESTS OK" : '${u.failing.length} tests fail'} (${u.assertions} assertions, ${Harness.seconds(r.seconds)})');
				for (f in u.failing)
					c.info('  on neko too: ${f.name}: ${f.why}');
				continue;
			}
			if (r.timedOut) {
				c.fail(runner, 'timed out after ${Harness.seconds(r.seconds)}\nlast output:\n' + Harness.tail(r.out + "\n" + r.err, 6));
				continue;
			}
			if (!u.done) {
				c.fail(runner, 'no results, exit ${r.code}${Text.describeCode(r.code)}\n' + Harness.tail(r.out + "\n" + r.err, 8));
				continue;
			}
			var extra = u.failing.filter(f -> !Lambda.exists(expected.failing, e -> e.name == f.name));
			if (extra.length == 0 && r.code == nekoRun.code) {
				c.ok(runner, '${u.assertions} assertions, ${Harness.seconds(r.seconds)}');
				continue;
			}
			var lines = [for (f in extra.slice(0, 30)) '${f.name}: ${f.why}'];
			if (extra.length > 30)
				lines.push('... ${extra.length - 30} more');
			var head = extra.length > 0 ? '${extra.length} tests fail that pass on neko' : 'the same tests pass';
			c.fail(runner, '$head, ${u.assertions} assertions, exit ${r.code}${Text.describeCode(r.code)} where neko exits ${nekoRun.code}\n'
				+ lines.join("\n"));
		}
	}

	// Reads utest's plain text report: the last "results:" line, then each failing class
	//  and its failing methods, indented, with their messages below them
	public static function results(out:String):UtestResult {
		var lines = out.split("\n");
		var start = -1;
		for (i in 0...lines.length)
			if (lines[i].startsWith("results: "))
				start = i;
		if (start < 0)
			return {done: false, ok: false, assertions: "?", failing: []};
		var assertions = "?";
		var i = start;
		while (i-- > 0)
			if (lines[i].startsWith("assertations: ")) {
				assertions = lines[i].substr("assertations: ".length).trim();
				break;
			}
		var failing = [];
		var cls = "";
		for (k in start + 1...lines.length) {
			var l = lines[k];
			if (l.trim() == "" || l.startsWith("Called from"))
				continue;
			if (!l.startsWith(" "))
				cls = l.trim();
			else if (l.startsWith("  ") && !l.startsWith("   ")) {
				var m = l.trim();
				var colon = m.indexOf(": ");
				var name = colon > 0 ? m.substr(0, colon) : m;
				var status = colon > 0 ? m.substr(colon + 2).split(" ")[0] : "";
				var why = k + 1 < lines.length && lines[k + 1].startsWith("    ") ? lines[k + 1].trim() : "";
				failing.push({name: '$cls.$name', why: '$status $why'.trim()});
			}
		}
		return {done: true, ok: lines[start].indexOf("ALL TESTS OK") >= 0, assertions: assertions, failing: failing};
	}
}

// libhxcpp's run.n, run the way haxelib runs it, from the libhxcpp checkout itself
class LibHxcpp {
	static function dir():String {
		var dev = Harness.root + "/.haxelib/hxcpp/.dev";
		if (FileSystem.exists(dev)) {
			var d = Path.removeTrailingSlashes(Path.normalize(File.getContent(dev).trim()));
			if (FileSystem.exists(d + "/run.n"))
				return d;
		}
		return "C:/Repository/libhxcpp";
	}

	public static function tests():Array<Test> {
		var hxcpp = dir();
		if (!FileSystem.exists(hxcpp + "/run.n"))
			throw 'no run.n in $hxcpp';
		var env:Env = ["HAXELIB_RUN" => "1", "HXCPP_COMPILE_CACHE" => null];
		var tests:Array<Test> = [];
		for (args in [[], ["-version"], ["nonexistent.xml"]])
			tests.push({
				name: (["run.n"].concat(args)).join(" "),
				run: c -> Harness.versus(c, "", [], {
					cwd: hxcpp,
					env: env,
					// haxelib passes the directory it was run from last
					argsFor: d -> ["run.n"].concat(args).concat([Harness.win(d) + "\\"]),
				})
			});
		tests.push({
			name: "run.n Build.xml",
			run: c -> Harness.versus(c, "", [], {
				cwd: hxcpp,
				env: env,
				timeout: Harness.limit(900),
				setup: d -> {
					File.saveContent(d + "/Build.xml", [
						'<xml>',
						'  <include name="$${HXCPP}/build-tool/BuildCommon.xml"/>',
						'  <files id="main"><file name="hello.c"/></files>',
						'  <target id="default" output="hello" tool="linker" toolid="exe"><files id="main"/></target>',
						'</xml>',
						''
					].join("\n"));
					File.saveContent(d + "/hello.c", '#include <stdio.h>\nint main(void) { printf("hello from c %d\\n", 6 * 7); return 0; }\n');
				},
				argsFor: d -> ["run.n", "Build.xml", Harness.win(d) + "\\"],
				check: (nd, d) -> {
					if (!FileSystem.exists(d + "/hello.exe"))
						return "builds no hello.exe";
					var a = Exec.run(Harness.win(nd + "/hello.exe"), [], nd, null, 60);
					var b = Exec.run(Harness.win(d + "/hello.exe"), [], d, null, 60);
					if (b.out != a.out || b.code != a.code || b.out.trim() != "hello from c 42")
						return 'the hello.exe it builds prints "${b.out.trim()}" and exits ${b.code}, where neko\'s prints "${a.out.trim()}" and exits ${a.code}';
					return null;
				}
			})
		});
		return tests;
	}
}

// The modules decode and translate check: every .n haxelib has installed, libhxcpp's,
//  neko's compilers, what the other suites built, and --corpus paths
class CorpusSuite {
	static function haxeLib():String {
		var hp = Sys.getEnv("HAXEPATH");
		return Path.removeTrailingSlashes(Path.normalize(hp != null ? hp : "C:/HaxeToolkit/haxe")) + "/lib";
	}

	static function libhxcpp():String {
		var dev = Harness.root + "/.haxelib/hxcpp/.dev";
		return FileSystem.exists(dev) ? Path.removeTrailingSlashes(Path.normalize(File.getContent(dev).trim())) : "C:/Repository/libhxcpp";
	}

	static function modules():Array<{name:String, path:String}> {
		var out = [];
		var seen = new Map<String, Bool>();
		var names = [
			{dir: haxeLib(), name: "haxelib"},
			{dir: libhxcpp(), name: "libhxcpp"},
			{dir: Harness.root + "/test/upstream", name: "upstream"},
			{dir: Harness.root + "/bin/harness", name: "built"},
		];
		if (Harness.work != null)
			names.push({dir: Harness.work, name: "built"});
		function add(path:String) {
			path = Path.normalize(path);
			var key = path.toLowerCase();
			if (seen.exists(key) || !FileSystem.exists(path))
				return;
			seen.set(key, true);
			var name = path;
			for (n in names)
				if (key.startsWith(n.dir.toLowerCase() + "/")) {
					name = n.name + "/" + path.substr(n.dir.length + 1).replace("/build/", "/");
					break;
				}
			out.push({name: name, path: path});
		}
		for (rel in Harness.walk(haxeLib(), ".n"))
			add(haxeLib() + "/" + rel);
		add(libhxcpp() + "/run.n");
		add(libhxcpp() + "/hxcpp.n");
		for (f in Harness.files(Harness.root + "/test/upstream/neko/boot", ".n"))
			add(Harness.root + "/test/upstream/neko/boot/" + f);
		var builtList = Harness.builtModules();
		builtList.sort(Reflect.compare);
		var builtNames = [for (b in builtList) Path.withoutDirectory(b).toLowerCase()];
		for (b in builtList)
			add(b);
		// What another checkout of Haxe's tests left, when this run built none of its own
		var tests = Harness.root + "/test/upstream/haxe/tests";
		for (p in [tests + "/unit/bin/unit.n", tests + "/threads/export/threads.n"].concat([
			for (f in Harness.files(tests + "/sys/bin/neko", ".n")) tests + "/sys/bin/neko/" + f
		]))
			if (builtNames.indexOf(Path.withoutDirectory(p).toLowerCase()) < 0)
				add(p);
		for (p in Harness.corpusPaths)
			if (FileSystem.isDirectory(p))
				for (rel in Harness.walk(p, ".n"))
					add(p + "/" + rel);
			else
				add(p);
		return out;
	}

	public static function decode():Array<Test>
		return [for (m in modules()) {name: m.name, run: c -> decodeOne(c, m.path)}];

	public static function translate():Array<Test>
		return [for (m in modules()) {name: m.name, run: c -> translateOne(c, m.path)}];

	static inline function inProcess<T>(f:Void->T):T
		return f();

	// The reader's instructions, as code index and opcode, against nekoc -d's
	static function decodeOne(c:Ctx, path:String) {
		File.copy(path, c.dir + "/t.n");
		var r = Exec.run("nekoc", ["-d", "t.n"], c.dir, null, Harness.limit(300));
		if (r.code != 0 || !FileSystem.exists(c.dir + "/t.dump")) {
			c.fail("", "nekoc -d fails:\n" + Harness.head(r.out + r.err));
			return;
		}
		// Line by line: a big module's dump is tens of megabytes, more than the
		//  interpreter splits in one go
		var theirs = [];
		var inCode = false;
		var dump = File.read(c.dir + "/t.dump", true);
		var columns = ~/^\s*([0-9A-Fa-f]+)\s+\d+\s+([A-Za-z0-9]+)/;
		try {
			while (true) {
				var l = dump.readLine();
				if (!inCode) {
					inCode = l.startsWith("CODE =");
					continue;
				}
				if (columns.match(l) && columns.matched(1) != "END")
					theirs.push(columns.matched(1) + " " + columns.matched(2));
			}
		} catch (_:haxe.io.Eof) {}
		dump.close();
		var ours = try inProcess(() -> {
			var m = Reader.read(File.getBytes(path));
			var lines = [];
			var pc = 0;
			while (pc < m.codeSize) {
				lines.push(StringTools.hex(pc, 6) + " " + m.op(pc).name);
				pc = m.next(pc);
			}
			lines;
		}) catch (e:Dynamic) {
			c.fail("", "the reader fails: " + Harness.describe(e));
			return;
		}
		var n = ours.length < theirs.length ? ours.length : theirs.length;
		var at = -1;
		for (i in 0...n)
			if (ours[i] != theirs[i]) {
				at = i;
				break;
			}
		if (at < 0 && ours.length != theirs.length)
			at = n;
		if (at < 0)
			c.ok("", '${ours.length} instructions');
		else {
			var lines = ['instruction $at of ${theirs.length} differs from nekoc -d'];
			for (k in at...(at + 3 < n + 1 ? at + 3 : n + 1)) {
				if (k < theirs.length)
					lines.push('- ${theirs[k]}');
				if (k < ours.length)
					lines.push('+ ${ours[k]}');
			}
			c.fail("", lines.join("\n"));
		}
	}

	static function translateOne(c:Ctx, path:String) {
		try {
			var note = inProcess(() -> {
				var m = Reader.read(File.getBytes(path));
				var scopes = StackCheck.run(m);
				var cppia = Emitter.emit(m, "Check", Path.withoutDirectory(path));
				'${scopes.length - 1} functions, ${Std.int(cppia.length / 1024)} KB of cppia';
			});
			c.ok("", note);
		} catch (e:Dynamic) {
			c.fail("", Harness.describe(e));
		}
	}
}
