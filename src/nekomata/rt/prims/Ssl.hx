package nekomata.rt.prims;

import haxe.io.Bytes;
import cpp.NativeSsl;
import nekomata.rt.Values;
import nekomata.rt.Primitives.add;
import nekomata.rt.prims.Conv.*;
import nekomata.rt.prims.StdSys.host;
import nekomata.rt.prims.StdSys.run;

// libs/ssl, on libhxcpp's port of it
@:keep
@:cppFileCode('
#include <string.h>

// A String of exactly these bytes. libhxcpp hands mbedTLS the bytes of a String that
//  is not UTF-16 as they are, so mbedTLS sees what neko would give it
static ::String nk_ssl_string(Array<unsigned char> inBytes, int len)
{
   char *s = ::hx::NewString(len);
   if (len)
      memcpy(s, inBytes->GetBase(), len);
   return ::String(s, len);
}
')
class Ssl {
	static final confKind = new NObject();
	static final sslKind = new NObject();
	static final certKind = new NObject();
	static final keyKind = new NObject();

	// What a servername callback threw. mbedTLS called it, so it is raised again from
	//  the handshake once mbedTLS has returned rather than unwound through it
	static final sniError = new sys.thread.Tls<{e:Dynamic}>();

	static function conf(v:Dynamic, prim:String):Dynamic
		return data(v, confKind, prim);

	static function ssl(v:Dynamic, prim:String):Dynamic
		return data(v, sslKind, prim);

	static function cert(v:Dynamic, prim:String):Dynamic
		return data(v, certKind, prim);

	static function key(v:Dynamic, prim:String):Dynamic
		return data(v, keyKind, prim);

	static inline function h(name:String):Int
		return nekomata.neko.Hash.field(name);

	// A neko string as the host String libhxcpp reads its bytes from
	static function raw(v:Dynamic, prim:String):String
		return ofBytes(bytes(v, prim));

	static function ofBytes(b:Bytes):String
		return untyped __cpp__("nk_ssl_string({0}, {1})", b.getData(), b.length);

	static final initLock = new sys.thread.Mutex();
	static var ready = false;

	// neko seeds its generator once, when the library loads; here the first primitive
	//  that can need it does, on whichever thread gets there first
	static function init() {
		if (ready)
			return;
		initLock.acquire();
		if (!ready) {
			NativeSsl.init();
			ready = true;
		}
		initLock.release();
	}

	static function abstractOf(kind:Dynamic, v:Dynamic):Dynamic
		return v == null ? null : new NAbstract(kind, v);

	static function handshake(sh:Dynamic) {
		try {
			NativeSsl.ssl_handshake(sh);
		} catch (e:Dynamic) {
			var thrown = sniError.value;
			if (thrown != null) {
				sniError.value = null;
				Rt.raise(thrown.e);
			}
			Rt.raise(fromHost(e));
		}
	}

	// The handle of an abstract the callback returned, or null for libhxcpp to refuse
	static function handleOf(v:Dynamic, kind:Dynamic):Dynamic
		return Std.isOfType(v, NAbstract) && (v : NAbstract).kind == kind ? (v : NAbstract).data : null;

	static function servername(cb:NFunction):String->Dynamic {
		return function(name:String):Dynamic {
			try {
				var r:Dynamic = Rt.call1(cb, null, NString.of(name));
				if (r == null)
					return null;
				var o:NObject = Std.isOfType(r, NObject) ? r : new NObject();
				return {cert: handleOf(o.find(h("cert")), certKind), key: handleOf(o.find(h("key")), keyKind)};
			} catch (e:Dynamic) {
				sniError.value = {e: e};
				return null;
			}
		}
	}

	// mbedtls_x509_crt_parse_file keeps the certificates of a file that parse and fails
	//  only when none does; libhxcpp fails when any does, so that case parses again
	static function loadFile(file:String):Dynamic {
		try {
			return NativeSsl.cert_load_file(file);
		} catch (e:Dynamic) {
			var data = try sys.io.File.getBytes(file) catch (_:Dynamic) null;
			if (data == null)
				Rt.raise(e);
			return NativeSsl.cert_add_pem(null, ofBytes(data));
		}
	}

	// mbedtls_x509_crt_parse_path skips the files of a directory that do not parse
	static function loadPath(path:String):Dynamic {
		try {
			return NativeSsl.cert_load_path(path);
		} catch (e:Dynamic) {
			var names = try sys.FileSystem.readDirectory(path) catch (_:Dynamic) null;
			if (names == null)
				Rt.raise(e);
			var chain:Dynamic = null;
			for (name in names) {
				var file = path + "/" + name;
				if (sys.FileSystem.isDirectory(file))
					continue;
				var data = try sys.io.File.getBytes(file) catch (_:Dynamic) null;
				if (data != null)
					try {
						chain = NativeSsl.cert_add_pem(chain, ofBytes(data));
					} catch (_:Dynamic) {}
			}
			if (chain == null)
				Rt.raise(e);
			return chain;
		}
	}

	static function checkRange(b:Bytes, p:Dynamic, l:Dynamic, prim:String):{pos:Int, len:Int} {
		var pos = int(p, prim), len = int(l, prim);
		if (pos < 0 || len < 0 || pos > b.length || len > b.length - pos)
			Primitives.fail(prim);
		return {pos: pos, len: len};
	}

	static function date(a:Array<Int>):Array<Dynamic>
		return [for (x in a) x];

	// libhxcpp takes &buf[0] of what it hashes and parses, which makes an empty array
	//  one zero byte long: an empty string is passed as a fresh array it can grow
	static function dataOf(b:Bytes):haxe.io.BytesData
		return b.length == 0 ? new haxe.io.BytesData() : b.getData();

	// The digest of the empty string under each name mbedTLS knows, which libhxcpp
	//  cannot give: it hashes one zero byte instead (see dataOf)
	static final emptyDigests = [
		"MD5" => "d41d8cd98f00b204e9800998ecf8427e",
		"RIPEMD160" => "9c1185a5c5e9fc54612808977ee8f548b2258d31",
		"SHA1" => "da39a3ee5e6b4b0d3255bfef95601890afd80709",
		"SHA" => "da39a3ee5e6b4b0d3255bfef95601890afd80709",
		"SHA224" => "d14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f",
		"SHA256" => "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"SHA384" => "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b",
		"SHA512" => "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e",
		"SHA3-224" => "6b4e03423667dbb73b6e15454f0eb1abd4597f9a1b078e3f5b5a6bc7",
		"SHA3-256" => "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a",
		"SHA3-384" => "0c63a75b845e4f7d01107d852e4c2485c51a50aaaa94fc61995e71bbee983a2ac3713831264adb47fb6bd1e058d5f004",
		"SHA3-512" => "a69f73cca23a9ac5c8b567dc185a756e97c982164fe25859e0d1dcc1475c80a615b2123af1f5f94c11e3e9402c3ac558f500199d95b6d3e301758586281dcd26",
	];

	// mbedTLS reads the name as a C string
	static function cName(b:Bytes):String {
		var end = 0;
		while (end < b.length && b.get(end) != 0)
			end++;
		return b.getString(0, end);
	}

	public static function register() {
		add("ssl@ssl_new", 1, function(c:Dynamic) {
			var ch = conf(c, "ssl@ssl_new");
			return new NAbstract(sslKind, host(() -> NativeSsl.ssl_new(ch)));
		});
		// neko clears a closed handle's kind, so using it again fails the primitive
		add("ssl@ssl_close", 1, function(s:Dynamic) {
			var sh = ssl(s, "ssl@ssl_close");
			NativeSsl.ssl_close(sh);
			(s : NAbstract).kind = null;
			return true;
		});
		add("ssl@ssl_handshake", 1, function(s:Dynamic) {
			handshake(ssl(s, "ssl@ssl_handshake"));
			return true;
		});
		// The socket is std@socket_new's abstract, its data the host socket. libhxcpp
		//  takes any object that is not a class instance it can find a socket in
		add("ssl@ssl_set_socket", 2, function(s:Dynamic, sock:Dynamic) {
			var sh = ssl(s, "ssl@ssl_set_socket");
			if (!Std.isOfType(sock, NAbstract) || (sock : NAbstract).kind == null)
				Primitives.fail("ssl@ssl_set_socket");
			var handle:Dynamic = (sock : NAbstract).data;
			var isClass:Bool = handle == null || untyped __cpp__("{0}->__GetType() == vtClass", handle);
			if (isClass)
				Primitives.fail("ssl@ssl_set_socket");
			var ok = try {
				NativeSsl.ssl_set_socket(sh, handle);
				true;
			} catch (_:Dynamic) false;
			if (!ok)
				Primitives.fail("ssl@ssl_set_socket");
			return true;
		});
		add("ssl@ssl_set_hostname", 2, function(s:Dynamic, n:Dynamic) {
			var sh = ssl(s, "ssl@ssl_set_hostname"), name = raw(n, "ssl@ssl_set_hostname");
			run(() -> NativeSsl.ssl_set_hostname(sh, name));
			return true;
		});
		add("ssl@ssl_get_peer_certificate", 1, function(s:Dynamic) {
			var sh = ssl(s, "ssl@ssl_get_peer_certificate");
			return abstractOf(certKind, host(() -> NativeSsl.ssl_get_peer_certificate(sh)));
		});
		add("ssl@ssl_get_verify_result", 1, function(s:Dynamic) {
			var sh = ssl(s, "ssl@ssl_get_verify_result");
			return host(() -> NativeSsl.ssl_get_verify_result(sh));
		});

		// neko writes the byte and does not look at how the write went
		add("ssl@ssl_send_char", 2, function(s:Dynamic, c:Dynamic) {
			var sh = ssl(s, "ssl@ssl_send_char"), ch = int(c, "ssl@ssl_send_char");
			if (ch < 0 || ch > 255)
				Primitives.fail("ssl@ssl_send_char");
			try {
				NativeSsl.ssl_send_char(sh, ch);
			} catch (_:Dynamic) {}
			return true;
		});
		add("ssl@ssl_send", 4, function(s:Dynamic, d:Dynamic, p:Dynamic, l:Dynamic) {
			var sh = ssl(s, "ssl@ssl_send"), b = bytes(d, "ssl@ssl_send");
			var r = checkRange(b, p, l, "ssl@ssl_send");
			return host(() -> NativeSsl.ssl_send(sh, dataOf(b), r.pos, r.len));
		});
		add("ssl@ssl_write", 2, function(s:Dynamic, d:Dynamic) {
			var sh = ssl(s, "ssl@ssl_write"), b = bytes(d, "ssl@ssl_write");
			run(() -> NativeSsl.ssl_write(sh, dataOf(b)));
			return true;
		});
		// neko reports a failed read with mbedTLS's message for its code. A socket that
		//  would block, or fails, gives back recv's -1, which mbedTLS passes through and
		//  names as its generic error, so neko never says Blocking here
		add("ssl@ssl_recv_char", 1, function(s:Dynamic) {
			var sh = ssl(s, "ssl@ssl_recv_char");
			try {
				return NativeSsl.ssl_recv_char(sh);
			} catch (e:Dynamic) {
				var text:Dynamic = fromHost(e);
				if (Std.isOfType(text, NString) && ((text : NString).toString() == "Blocking" || (text : NString).toString() == "ssl network error"))
					text = NString.of("ERROR - Generic error");
				return Rt.raise(text);
			}
		});
		add("ssl@ssl_recv", 4, function(s:Dynamic, d:Dynamic, p:Dynamic, l:Dynamic) {
			var sh = ssl(s, "ssl@ssl_recv"), b = bytes(d, "ssl@ssl_recv");
			var r = checkRange(b, p, l, "ssl@ssl_recv");
			return host(() -> NativeSsl.ssl_recv(sh, dataOf(b), r.pos, r.len));
		});
		add("ssl@ssl_read", 1, function(s:Dynamic) {
			var sh = ssl(s, "ssl@ssl_read");
			var d:haxe.io.BytesData = host(() -> NativeSsl.ssl_read(sh));
			return new NString(Bytes.ofData(d));
		});

		add("ssl@conf_new", 1, function(server:Dynamic) {
			var isServer = bool(server, "ssl@conf_new");
			init();
			return new NAbstract(confKind, host(() -> NativeSsl.conf_new(isServer)));
		});
		add("ssl@conf_close", 1, function(c:Dynamic) {
			var ch = conf(c, "ssl@conf_close");
			NativeSsl.conf_close(ch);
			(c : NAbstract).kind = null;
			return true;
		});
		add("ssl@conf_set_ca", 2, function(c:Dynamic, x:Dynamic) {
			var ch = conf(c, "ssl@conf_set_ca");
			var xh:Dynamic = x == null ? null : cert(x, "ssl@conf_set_ca");
			NativeSsl.conf_set_ca(ch, xh);
			return true;
		});
		// null verifies without requiring it to pass, as libhxcpp's mode 2
		add("ssl@conf_set_verify", 2, function(c:Dynamic, b:Dynamic) {
			var ch = conf(c, "ssl@conf_set_verify");
			var mode = b == null ? 2 : bool(b, "ssl@conf_set_verify") ? 1 : 0;
			NativeSsl.conf_set_verify(ch, mode);
			return true;
		});
		add("ssl@conf_set_cert", 3, function(c:Dynamic, x:Dynamic, k:Dynamic) {
			var ch = conf(c, "ssl@conf_set_cert"), xh = cert(x, "ssl@conf_set_cert"), kh = key(k, "ssl@conf_set_cert");
			run(() -> NativeSsl.conf_set_cert(ch, xh, kh));
			return true;
		});
		// The callback takes the name the client asked for and returns null or an object
		//  with the cert and key to answer with
		add("ssl@conf_set_servername_callback", 2, function(c:Dynamic, cb:Dynamic) {
			var ch = conf(c, "ssl@conf_set_servername_callback");
			if (!Std.isOfType(cb, NFunction) || ((cb : NFunction).nargs != 1 && (cb : NFunction).nargs != NFunction.VAR_ARGS))
				Primitives.fail("ssl@conf_set_servername_callback");
			NativeSsl.conf_set_servername_callback(ch, servername(cb));
			return true;
		});

		add("ssl@cert_load_defaults", 0, function() {
			init();
			return abstractOf(certKind, host(() -> NativeSsl.cert_load_defaults()));
		});
		add("ssl@cert_load_file", 1, function(f:Dynamic) {
			var file = raw(f, "ssl@cert_load_file");
			init();
			return new NAbstract(certKind, host(() -> loadFile(file)));
		});
		add("ssl@cert_load_path", 1, function(p:Dynamic) {
			var path = raw(p, "ssl@cert_load_path");
			init();
			return new NAbstract(certKind, host(() -> loadPath(path)));
		});
		// Names are bytes, as neko copies them, with control characters as ?
		add("ssl@cert_get_subject", 2, function(x:Dynamic, n:Dynamic) {
			var xh = cert(x, "ssl@cert_get_subject"), name = raw(n, "ssl@cert_get_subject");
			return nstr(host(() -> NativeSsl.cert_get_subject(xh, name)));
		});
		add("ssl@cert_get_issuer", 2, function(x:Dynamic, n:Dynamic) {
			var xh = cert(x, "ssl@cert_get_issuer"), name = raw(n, "ssl@cert_get_issuer");
			return nstr(host(() -> NativeSsl.cert_get_issuer(xh, name)));
		});
		add("ssl@cert_get_altnames", 1, function(x:Dynamic) {
			var xh = cert(x, "ssl@cert_get_altnames");
			var names:Array<String> = host(() -> NativeSsl.cert_get_altnames(xh));
			return names.length == 0 ? null : list([for (n in names) NString.of(n)]);
		});
		// Dates are [year, month, day, hour, minute, second]
		add("ssl@cert_get_notbefore", 1, function(x:Dynamic) {
			var xh = cert(x, "ssl@cert_get_notbefore");
			return date(host(() -> NativeSsl.cert_get_notbefore(xh)));
		});
		add("ssl@cert_get_notafter", 1, function(x:Dynamic) {
			var xh = cert(x, "ssl@cert_get_notafter");
			return date(host(() -> NativeSsl.cert_get_notafter(xh)));
		});
		add("ssl@cert_get_next", 1, function(x:Dynamic) {
			var xh = cert(x, "ssl@cert_get_next");
			return abstractOf(certKind, NativeSsl.cert_get_next(xh));
		});
		// A null certificate starts a new chain; either way the chain is returned
		add("ssl@cert_add_pem", 2, function(x:Dynamic, d:Dynamic) {
			var pem = raw(d, "ssl@cert_add_pem");
			var xh:Dynamic = x == null ? null : cert(x, "ssl@cert_add_pem");
			init();
			var chain:Dynamic = host(() -> NativeSsl.cert_add_pem(xh, pem));
			return x == null ? new NAbstract(certKind, chain) : x;
		});
		add("ssl@cert_add_der", 2, function(x:Dynamic, d:Dynamic) {
			var der = bytes(d, "ssl@cert_add_der");
			var xh:Dynamic = x == null ? null : cert(x, "ssl@cert_add_der");
			init();
			var chain:Dynamic = host(() -> NativeSsl.cert_add_der(xh, dataOf(der)));
			return x == null ? new NAbstract(certKind, chain) : x;
		});

		add("ssl@key_from_der", 2, function(d:Dynamic, p:Dynamic) {
			var der = bytes(d, "ssl@key_from_der"), pub = bool(p, "ssl@key_from_der");
			init();
			return new NAbstract(keyKind, host(() -> NativeSsl.key_from_der(dataOf(der), pub)));
		});
		add("ssl@key_from_pem", 3, function(d:Dynamic, p:Dynamic, pw:Dynamic) {
			var pem = raw(d, "ssl@key_from_pem"), pub = bool(p, "ssl@key_from_pem");
			var pass:String = pw == null ? null : raw(pw, "ssl@key_from_pem");
			init();
			return new NAbstract(keyKind, host(() -> NativeSsl.key_from_pem(pem, pub, pass)));
		});

		add("ssl@dgst_make", 2, function(d:Dynamic, a:Dynamic) {
			var b = bytes(d, "ssl@dgst_make"), alg = raw(a, "ssl@dgst_make");
			if (b.length == 0) {
				var empty = emptyDigests.get(cName(bytes(a, "ssl@dgst_make")));
				if (empty != null)
					return new NString(Bytes.ofHex(empty));
			}
			init();
			var out:haxe.io.BytesData = host(() -> NativeSsl.dgst_make(dataOf(b), alg));
			return new NString(Bytes.ofData(out));
		});
		add("ssl@dgst_sign", 3, function(d:Dynamic, k:Dynamic, a:Dynamic) {
			var b = bytes(d, "ssl@dgst_sign"), kh = key(k, "ssl@dgst_sign"), alg = raw(a, "ssl@dgst_sign");
			init();
			var out:haxe.io.BytesData = host(() -> NativeSsl.dgst_sign(dataOf(b), kh, alg));
			return new NString(Bytes.ofData(out));
		});
		add("ssl@dgst_verify", 4, function(d:Dynamic, s:Dynamic, k:Dynamic, a:Dynamic) {
			var b = bytes(d, "ssl@dgst_verify"), sig = bytes(s, "ssl@dgst_verify");
			var kh = key(k, "ssl@dgst_verify"), alg = raw(a, "ssl@dgst_verify");
			init();
			return host(() -> NativeSsl.dgst_verify(dataOf(b), dataOf(sig), kh, alg));
		});
	}
}
