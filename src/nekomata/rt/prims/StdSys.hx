package nekomata.rt.prims;

import haxe.io.Bytes;
import nekomata.rt.Values;
import nekomata.rt.Rt;
import nekomata.rt.Primitives.add;
import nekomata.rt.prims.Conv.*;

// An open file, as neko's fio: the handle and the name errors report
class FileData {
	public var h:Dynamic;
	public var name:String;

	public function new(h:Dynamic, name:String) {
		this.h = h;
		this.name = name;
	}
}

// libs/std sys.c, file.c, process.c, misc.c, md5.c and int32.c, on libhxcpp's ports of them
@:keep
class StdSys {
	static final fileKind = new NObject();
	static final processKind = new NObject();

	// Runs a host std call, turning what it throws into the neko value neko would throw
	public static function host(f:() -> Dynamic):Dynamic {
		try {
			return f();
		} catch (e:Dynamic) {
			return Rt.raise(fromHost(e));
		}
	}

	public static function run(f:() -> Void):Void {
		try {
			f();
		} catch (e:Dynamic) {
			Rt.raise(fromHost(e));
		}
	}

	static function file(v:Dynamic, prim:String):FileData
		return data(v, fileKind, prim);

	static function stdio(h:Dynamic, name:String):NAbstract
		return new NAbstract(fileKind, new FileData(h, name));

	public static function register() {
		// sys.c
		add("std@get_env", 1, (v:Dynamic) -> nstr(cpp.NativeSys.get_env(str(v, "std@get_env"))));
		add("std@put_env", 2, function(e:Dynamic, v:Dynamic) {
			cpp.NativeSys.put_env(str(e, "std@put_env"), strOrNull(v, "std@put_env"));
			return true;
		});
		add("std@set_time_locale", 1, (l:Dynamic) -> cpp.NativeSys.set_time_locale(str(l, "std@set_time_locale")));
		add("std@get_cwd", 0, () -> nstr(cpp.NativeSys.get_cwd()));
		add("std@set_cwd", 1, function(d:Dynamic) {
			run(() -> cpp.NativeSys.set_cwd(str(d, "std@set_cwd")));
			return true;
		});
		add("std@sys_sleep", 1, function(f:Dynamic) {
			Sys.sleep(number(f, "std@sys_sleep"));
			return true;
		});
		add("std@sys_command", 1, (c:Dynamic) -> cpp.NativeSys.sys_command(str(c, "std@sys_command")));
		add("std@sys_exit", 1, function(code:Dynamic):Dynamic {
			Sys.stdout().flush();
			Sys.exit(int(code, "std@sys_exit"));
			return true;
		});
		add("std@sys_string", 0, () -> nstr(cpp.NativeSys.sys_string()));
		add("std@sys_is64", 0, () -> cpp.NativeSys.sys_is64());
		add("std@sys_cpu_arch", 0, () -> NString.of(#if HXCPP_ARM64 "arm64" #else "x86_64" #end));
		add("std@sys_exists", 1, (p:Dynamic) -> cpp.NativeSys.sys_exists(str(p, "std@sys_exists")));
		add("std@file_exists", 1, (p:Dynamic) -> cpp.NativeSys.sys_exists(str(p, "std@file_exists")));
		add("std@file_delete", 1, function(p:Dynamic) {
			run(() -> cpp.NativeSys.file_delete(str(p, "std@file_delete")));
			return true;
		});
		add("std@sys_rename", 2, function(p:Dynamic, n:Dynamic) {
			// libhxcpp's rename throws on failure, whatever the extern says it returns
			var from = str(p, "std@sys_rename"), to = str(n, "std@sys_rename");
			run(() -> untyped __cpp__("_hx_std_sys_rename({0}, {1})", from, to));
			return true;
		});
		add("std@sys_stat", 1, function(p:Dynamic) {
			var s:Dynamic = host(() -> cpp.NativeSys.sys_stat(str(p, "std@sys_stat")));
			if (s == null)
				return Primitives.fail("std@sys_stat");
			var fields = [];
			for (f in ["gid", "uid", "atime", "mtime", "ctime", "dev", "ino", "mode", "nlink", "rdev", "size"]) {
				var v:Dynamic = Reflect.field(s, f);
				fields.push({name: f, value: v == null ? null : Std.int(v)});
			}
			return object(fields);
		});
		add("std@sys_file_type", 1, function(p:Dynamic) {
			var t = host(() -> cpp.NativeSys.sys_file_type(str(p, "std@sys_file_type")));
			return t == null ? Primitives.fail("std@sys_file_type") : NString.of(t);
		});
		add("std@sys_create_dir", 2, function(p:Dynamic, mode:Dynamic) {
			if (!host(() -> cpp.NativeSys.sys_create_dir(str(p, "std@sys_create_dir"), int(mode, "std@sys_create_dir"))))
				Primitives.fail("std@sys_create_dir");
			return true;
		});
		add("std@sys_remove_dir", 1, function(p:Dynamic) {
			run(() -> cpp.NativeSys.sys_remove_dir(str(p, "std@sys_remove_dir")));
			return true;
		});
		add("std@sys_time", 0, () -> new NFloat(cpp.NativeSys.sys_time()));
		add("std@sys_cpu_time", 0, () -> new NFloat(cpp.NativeSys.sys_cpu_time()));
		add("std@sys_thread_cpu_time", 0, () -> new NFloat(cpp.NativeSys.sys_cpu_time()));
		add("std@sys_read_dir", 1, function(p:Dynamic) {
			var names:Array<String> = host(() -> cpp.NativeSys.sys_read_dir(str(p, "std@sys_read_dir")));
			if (names == null)
				return Primitives.fail("std@sys_read_dir");
			return list([for (n in names) NString.of(n)]);
		});
		add("std@file_full_path", 1, function(p:Dynamic) {
			var full = host(() -> cpp.NativeSys.file_full_path(str(p, "std@file_full_path")));
			return full == null ? Primitives.fail("std@file_full_path") : NString.of(full);
		});
		add("std@sys_exe_path", 0, () -> nstr(cpp.NativeSys.sys_exe_path()));
		add("std@sys_program_path", 0, () -> nstr(nekomata.rt.Boot.programPath));
		add("std@sys_env", 0, function() {
			// Neko's list cells here are [key, value, next]
			var flat = cpp.NativeSys.sys_env();
			var l:Dynamic = null;
			var i = flat.length - 2;
			while (i >= 0) {
				var cell:Array<Dynamic> = [NString.of(flat[i]), NString.of(flat[i + 1]), l];
				l = cell;
				i -= 2;
			}
			return l;
		});
		add("std@sys_getch", 1, (b:Dynamic) -> cpp.NativeSys.sys_getch(bool(b, "std@sys_getch")));
		add("std@sys_get_pid", 0, () -> cpp.NativeSys.sys_get_pid());
		add("std@win_env_changed", 0, () -> null);

		// file.c
		add("std@file_open", 2, function(f:Dynamic, r:Dynamic) {
			var name = str(f, "std@file_open");
			var h = host(() -> cpp.NativeFile.file_open(name, str(r, "std@file_open")));
			return new NAbstract(fileKind, new FileData(h, name));
		});
		add("std@file_close", 1, function(f:Dynamic) {
			var fd = file(f, "std@file_close");
			run(() -> cpp.NativeFile.file_close(fd.h));
			return true;
		});
		add("std@file_name", 1, (f:Dynamic) -> NString.of(file(f, "std@file_name").name));
		add("std@file_write", 4, function(f:Dynamic, s:Dynamic, p:Dynamic, l:Dynamic) {
			var fd = file(f, "std@file_write"), b = bytes(s, "std@file_write");
			var pos = int(p, "std@file_write"), len = int(l, "std@file_write");
			if (pos < 0 || len < 0 || pos + len > b.length)
				Primitives.fail("std@file_write");
			return host(() -> cpp.NativeFile.file_write(fd.h, b.getData(), pos, len));
		});
		add("std@file_read", 4, function(f:Dynamic, s:Dynamic, p:Dynamic, l:Dynamic) {
			var fd = file(f, "std@file_read"), b = bytes(s, "std@file_read");
			var pos = int(p, "std@file_read"), len = int(l, "std@file_read");
			if (pos < 0 || len < 0 || pos + len > b.length)
				Primitives.fail("std@file_read");
			return host(() -> cpp.NativeFile.file_read(fd.h, b.getData(), pos, len));
		});
		add("std@file_write_char", 2, function(f:Dynamic, c:Dynamic) {
			var fd = file(f, "std@file_write_char"), ch = int(c, "std@file_write_char");
			if (ch < 0 || ch > 255)
				Primitives.fail("std@file_write_char");
			run(() -> cpp.NativeFile.file_write_char(fd.h, ch));
			return true;
		});
		add("std@file_read_char", 1, function(f:Dynamic) {
			var fd = file(f, "std@file_read_char");
			return host(() -> cpp.NativeFile.file_read_char(fd.h));
		});
		add("std@file_seek", 3, function(f:Dynamic, p:Dynamic, k:Dynamic) {
			var fd = file(f, "std@file_seek");
			run(() -> cpp.NativeFile.file_seek(fd.h, int(p, "std@file_seek"), int(k, "std@file_seek")));
			return true;
		});
		add("std@file_tell", 1, function(f:Dynamic) {
			var fd = file(f, "std@file_tell");
			return host(() -> cpp.NativeFile.file_tell(fd.h));
		});
		add("std@file_eof", 1, (f:Dynamic) -> cpp.NativeFile.file_eof(file(f, "std@file_eof").h));
		add("std@file_flush", 1, function(f:Dynamic) {
			var fd = file(f, "std@file_flush");
			run(() -> cpp.NativeFile.file_flush(fd.h));
			return true;
		});
		add("std@file_contents", 1, function(f:Dynamic) {
			var name = str(f, "std@file_contents");
			return new NString(Bytes.ofData(host(() -> cpp.NativeFile.file_contents_bytes(name))));
		});
		add("std@file_stdin", 0, () -> stdio(cpp.NativeFile.file_stdin(), "stdin"));
		add("std@file_stdout", 0, () -> stdio(cpp.NativeFile.file_stdout(), "stdout"));
		add("std@file_stderr", 0, () -> stdio(cpp.NativeFile.file_stderr(), "stderr"));

		// process.c
		add("std@process_run", 2, function(c:Dynamic, a:Dynamic) {
			var cmd = str(c, "std@process_run");
			var args:Array<String> = null;
			if (a != null) {
				if (Rt.typeOf(a) != Rt.TARRAY)
					Primitives.fail("std@process_run");
				args = [for (x in (a : Array<Dynamic>)) str(x, "std@process_run")];
			}
			var p = host(() -> cpp.NativeProcess.process_run(cmd, args));
			if (p == null)
				Primitives.fail("std@process_run");
			return new NAbstract(processKind, p);
		});
		// Neko throws at the end of output, where the host returns 0
		function reader(prim:String, read:(Dynamic, haxe.io.BytesData, Int, Int) -> Int)
			add(prim, 4, function(p:Dynamic, s:Dynamic, pos:Dynamic, l:Dynamic) {
				var h = data(p, processKind, prim), b = bytes(s, prim);
				var at = int(pos, prim), len = int(l, prim);
				if (at < 0 || len < 0 || at + len > b.length)
					Primitives.fail(prim);
				var n = host(() -> read(h, b.getData(), at, len));
				if (n <= 0 && len > 0)
					Primitives.fail(prim);
				return n;
			});
		// Extern functions passed as values would be raw C pointers, so they are wrapped
		reader("std@process_stdout_read", (h, b, p, l) -> cpp.NativeProcess.process_stdout_read(h, b, p, l));
		reader("std@process_stderr_read", (h, b, p, l) -> cpp.NativeProcess.process_stderr_read(h, b, p, l));
		add("std@process_stdin_write", 4, function(p:Dynamic, s:Dynamic, pos:Dynamic, l:Dynamic) {
			var h = data(p, processKind, "std@process_stdin_write"), b = bytes(s, "std@process_stdin_write");
			var at = int(pos, "std@process_stdin_write"), len = int(l, "std@process_stdin_write");
			if (at < 0 || len < 0 || at + len > b.length)
				Primitives.fail("std@process_stdin_write");
			return host(() -> cpp.NativeProcess.process_stdin_write(h, b.getData(), at, len));
		});
		add("std@process_stdin_close", 1, function(p:Dynamic) {
			var h = data(p, processKind, "std@process_stdin_close");
			run(() -> cpp.NativeProcess.process_stdin_close(h));
			return null;
		});
		add("std@process_exit", 1, function(p:Dynamic) {
			var h = data(p, processKind, "std@process_exit");
			var code:Dynamic = host(() -> cpp.NativeProcess.process_exit(h, true));
			return Std.int(code);
		});
		add("std@process_pid", 1, (p:Dynamic) -> cpp.NativeProcess.process_pid(data(p, processKind, "std@process_pid")));
		add("std@process_kill", 1, function(p:Dynamic) {
			cpp.NativeProcess.process_kill(data(p, processKind, "std@process_kill"));
			return null;
		});
		add("std@process_close", 1, function(p:Dynamic) {
			cpp.NativeProcess.process_close(data(p, processKind, "std@process_close"));
			return null;
		});

		// misc.c
		add("std@run_gc", 1, function(major:Dynamic) {
			cpp.vm.Gc.run(major == true);
			return null;
		});
		add("std@gc_stats", 0, () -> object([
			{name: "heap", value: Std.int(cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_RESERVED))},
			{name: "free", value: Std.int(cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_RESERVED) - cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_USAGE))}
		]));
		add("std@enable_jit", 1, (b:Dynamic) -> null);
		add("std@set_trusted", 1, (b:Dynamic) -> null);
		// Neko's same_closure: the same code, module and arguments count, and
		//  environments that hold the same values
		add("std@same_closure", 2, function(a:Dynamic, b:Dynamic) {
			if (!Rt.isFunction(a) || !Rt.isFunction(b))
				return false;
			var fa:NFunction = a, fb:NFunction = b;
			if (fa == fb)
				return true;
			var sameCode:Bool = untyped __cpp__("({0}.mPtr == {1}.mPtr)", fa.fn, fb.fn);
			if (!sameCode || fa.nargs != fb.nargs || fa.module != fb.module || fa.global != fb.global)
				return false;
			var ea = fa.env == null ? [] : fa.env, eb = fb.env == null ? [] : fb.env;
			if (ea.length != eb.length)
				return false;
			for (i in 0...ea.length)
				if (!Rt.physEqual(ea[i], eb[i]))
					return false;
			return true;
		});
		add("std@merge_sort", 3, function(a:Dynamic, n:Dynamic, cmp:Dynamic) {
			if (Rt.typeOf(a) != Rt.TARRAY)
				Primitives.fail("std@merge_sort");
			var arr:Array<Dynamic> = a;
			var len = int(n, "std@merge_sort");
			var part = arr.slice(0, len);
			haxe.ds.ArraySort.sort(part, (x, y) -> Rt.call2(cmp, null, x, y));
			for (i in 0...len)
				arr[i] = part[i];
			return null;
		});
		add("std@float_bytes", 2, function(f:Dynamic, big:Dynamic) {
			var b = Bytes.alloc(4);
			b.setFloat(0, number(f, "std@float_bytes"));
			if (big == true)
				reverse(b);
			return new NString(b);
		});
		add("std@double_bytes", 2, function(f:Dynamic, big:Dynamic) {
			var b = Bytes.alloc(8);
			b.setDouble(0, number(f, "std@double_bytes"));
			if (big == true)
				reverse(b);
			return new NString(b);
		});
		add("std@float_of_bytes", 2, function(s:Dynamic, big:Dynamic) {
			var b = bytes(s, "std@float_of_bytes");
			if (b.length != 4)
				Primitives.fail("std@float_of_bytes");
			var c = b.sub(0, 4);
			if (big == true)
				reverse(c);
			return new NFloat(c.getFloat(0));
		});
		add("std@double_of_bytes", 2, function(s:Dynamic, big:Dynamic) {
			var b = bytes(s, "std@double_of_bytes");
			if (b.length != 8)
				Primitives.fail("std@double_of_bytes");
			var c = b.sub(0, 8);
			if (big == true)
				reverse(c);
			return new NFloat(c.getDouble(0));
		});

		// md5.c
		add("std@make_md5", 1, (s:Dynamic) -> new NString(haxe.crypto.Md5.make(bytes(s, "std@make_md5"))));

		// int32.c: neko's ints already hold 32 bits here, so int32 values are ints
		add("std@int32_new", 1, (v:Dynamic) -> Std.int(number(v, "std@int32_new")));
		add("std@int32_to_int", 1, (v:Dynamic) -> int(v, "std@int32_to_int"));
		add("std@int32_to_float", 1, (v:Dynamic) -> new NFloat(int(v, "std@int32_to_float")));
		add("std@int32_compare", 2, function(a:Dynamic, b:Dynamic) {
			var x = int(a, "std@int32_compare"), y = int(b, "std@int32_compare");
			return x == y ? 0 : x < y ? -1 : 1;
		});
		add("std@int32_ushr", 2, (a:Dynamic, b:Dynamic) -> int(a, "std@int32_ushr") >>> int(b, "std@int32_ushr"));
		add("std@int32_add", 2, (a:Dynamic, b:Dynamic) -> int(a, "std@int32_add") + int(b, "std@int32_add"));
		add("std@int32_shl", 2, (a:Dynamic, b:Dynamic) -> int(a, "std@int32_shl") << int(b, "std@int32_shl"));
	}

	static function reverse(b:Bytes) {
		var n = b.length;
		for (i in 0...n >> 1) {
			var t = b.get(i);
			b.set(i, b.get(n - 1 - i));
			b.set(n - 1 - i, t);
		}
	}
}
