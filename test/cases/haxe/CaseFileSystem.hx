import sys.FileSystem;
import sys.io.File;

// Everything happens under the run's own directory
class CaseFileSystem {
	static function listing(dir:String):String {
		var names = FileSystem.readDirectory(dir);
		names.sort(Reflect.compare);
		return names.join(",");
	}

	static function main() {
		var root = "fs_test";
		Sys.println("exists before " + FileSystem.exists(root));
		FileSystem.createDirectory(root + "/a/b/c");
		Sys.println("created " + FileSystem.exists(root + "/a/b/c") + " " + FileSystem.isDirectory(root + "/a/b"));
		File.saveContent(root + "/hello.txt", "hello\nworld\n");
		File.saveContent(root + "/unicode é.txt", "héllo 日本 😀");
		File.saveBytes(root + "/bin.dat", haxe.io.Bytes.ofHex("00ff10203040"));
		Sys.println(listing(root));
		Sys.println(File.getContent(root + "/hello.txt").split("\n") + " " + File.getContent(root + "/unicode é.txt") + " "
			+ File.getBytes(root + "/bin.dat").toHex());
		var st = FileSystem.stat(root + "/hello.txt");
		Sys.println("size " + st.size + " isfile " + !FileSystem.isDirectory(root + "/hello.txt") + " mtime recent "
			+ (Math.abs(st.mtime.getTime() / 1000 - Sys.time()) < 600));
		var out = File.append(root + "/hello.txt");
		out.writeString("appended\n");
		out.close();
		Sys.println(File.getContent(root + "/hello.txt").length);
		var w = File.write(root + "/written.bin", true);
		w.writeInt32(0x01020304);
		w.writeDouble(1.5);
		w.writeString("tail");
		w.close();
		var r = File.read(root + "/written.bin", true);
		Sys.println(r.readInt32() + " " + r.readDouble() + " " + r.readString(4));
		try {
			r.readByte();
		} catch (e:haxe.io.Eof) {
			Sys.println("eof");
		}
		r.close();
		var u = File.update(root + "/written.bin", true);
		u.seek(4, SeekBegin);
		u.writeByte(0xFF);
		Sys.println("tell " + u.tell());
		u.seek(0, SeekEnd);
		Sys.println("end " + u.tell());
		u.close();
		var lines = File.read(root + "/hello.txt", false);
		var got = [];
		try {
			while (true)
				got.push(lines.readLine());
		} catch (e:haxe.io.Eof) {}
		Sys.println(got + " eof flag " + lines.eof());
		lines.close();
		try {
			lines.readLine();
		} catch (e:Dynamic) {
			Sys.println("reading a closed file fails");
		}
		File.copy(root + "/hello.txt", root + "/a/copy.txt");
		FileSystem.rename(root + "/a/copy.txt", root + "/a/b/moved.txt");
		Sys.println(listing(root + "/a") + " | " + listing(root + "/a/b"));
		Sys.println("fullPath ends right: " + StringTools.endsWith(FileSystem.fullPath(root + "/a/b").split("\\").join("/"), "fs_test/a/b")
			+ " absolute: " + haxe.io.Path.isAbsolute(FileSystem.absolutePath(root)));
		for (bad in [root + "/missing.txt", root + "/a"]) {
			try {
				File.getContent(bad);
				Sys.println("read " + bad);
			} catch (e:Dynamic) {
				Sys.println("cannot read " + bad + ": " + Std.string(e).split(root).length);
			}
		}
		try {
			FileSystem.deleteDirectory(root + "/a");
		} catch (e:Dynamic) {
			Sys.println("cannot delete a non-empty directory");
		}
		try {
			FileSystem.stat(root + "/nope");
		} catch (e:Dynamic) {
			Sys.println("cannot stat a missing file");
		}
		FileSystem.deleteFile(root + "/a/b/moved.txt");
		FileSystem.deleteDirectory(root + "/a/b/c");
		FileSystem.deleteDirectory(root + "/a/b");
		FileSystem.deleteDirectory(root + "/a");
		for (f in FileSystem.readDirectory(root))
			FileSystem.deleteFile(root + "/" + f);
		FileSystem.deleteDirectory(root);
		Sys.println("cleaned " + !FileSystem.exists(root));
		var p = new haxe.io.Path("dir/sub/file.name.ext");
		Sys.println(p.dir + " " + p.file + " " + p.ext + " " + haxe.io.Path.join(["a", "b/", "c"]) + " " + haxe.io.Path.normalize("a/./b/../c//d")
			+ " " + haxe.io.Path.withoutExtension("x.tar.gz") + " " + haxe.io.Path.directory("C:\\x\\y.txt"));
	}
}
