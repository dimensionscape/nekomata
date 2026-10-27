package nekomata.rt.prims;

import haxe.io.Bytes;
import nekomata.rt.Values;
import nekomata.rt.Rt;
import nekomata.rt.Primitives.add;
import nekomata.rt.prims.Conv.*;
import nekomata.rt.prims.StdSys.host;
import nekomata.rt.prims.StdSys.run;

// libs/std socket.c, on libhxcpp's port of it
@:keep
class StdSocket {
	static final socketKind = new NObject();

	static function socket(v:Dynamic, prim:String):Dynamic
		return data(v, socketKind, prim);

	static inline function h(name:String):Int
		return nekomata.neko.Hash.field(name);

	// The host handles of an array of neko sockets
	static function handles(v:Dynamic, prim:String):Array<Dynamic> {
		if (v == null)
			return null;
		if (Rt.typeOf(v) != Rt.TARRAY)
			Primitives.fail(prim);
		return [for (s in (v : Array<Dynamic>)) socket(s, prim)];
	}

	// The neko sockets among `from` whose handles the host returned, as neko returns
	//  the values it was given
	static function pick(from:Dynamic, chosen:Dynamic):Array<Dynamic> {
		var result:Array<Dynamic> = [];
		if (from == null || chosen == null)
			return result;
		var all:Array<Dynamic> = from;
		var picked:Array<Dynamic> = chosen;
		for (c in picked)
			for (s in all)
				if ((s : NAbstract).data == c) {
					result.push(s);
					break;
				}
		return result;
	}

	static function pair(a:Array<Int>):Array<Dynamic>
		return a == null ? null : [a[0], a[1]];

	static function checkRange(b:Bytes, p:Dynamic, l:Dynamic, prim:String):{pos:Int, len:Int} {
		var pos = int(p, prim), len = int(l, prim);
		if (pos < 0 || len < 0 || pos + len > b.length)
			Primitives.fail(prim);
		return {pos: pos, len: len};
	}

	public static function register() {
		add("std@socket_init", 0, function() {
			cpp.NativeSocket.socket_init();
			return null;
		});
		add("std@socket_new", 1, (udp:Dynamic) -> new NAbstract(socketKind, host(() -> cpp.NativeSocket.socket_new(bool(udp, "std@socket_new")))));
		add("std@socket_close", 1, function(s:Dynamic) {
			var sh = socket(s, "std@socket_close");
			run(() -> cpp.NativeSocket.socket_close(sh));
			// Neko clears the kind, so the closed socket fails every later call
			(s : NAbstract).kind = null;
			return null;
		});
		add("std@socket_send_char", 2, function(s:Dynamic, c:Dynamic) {
			var sh = socket(s, "std@socket_send_char"), ch = int(c, "std@socket_send_char");
			if (ch < 0 || ch > 255)
				Primitives.fail("std@socket_send_char");
			run(() -> cpp.NativeSocket.socket_send_char(sh, ch));
			return null;
		});
		add("std@socket_send", 4, function(s:Dynamic, buf:Dynamic, p:Dynamic, l:Dynamic) {
			var sh = socket(s, "std@socket_send"), b = bytes(buf, "std@socket_send");
			var r = checkRange(b, p, l, "std@socket_send");
			return host(() -> cpp.NativeSocket.socket_send(sh, b.getData(), r.pos, r.len));
		});
		add("std@socket_recv", 4, function(s:Dynamic, buf:Dynamic, p:Dynamic, l:Dynamic) {
			var sh = socket(s, "std@socket_recv"), b = bytes(buf, "std@socket_recv");
			var r = checkRange(b, p, l, "std@socket_recv");
			return host(() -> cpp.NativeSocket.socket_recv(sh, b.getData(), r.pos, r.len));
		});
		add("std@socket_recv_char", 1, function(s:Dynamic) {
			var sh = socket(s, "std@socket_recv_char");
			return host(() -> cpp.NativeSocket.socket_recv_char(sh));
		});
		add("std@socket_write", 2, function(s:Dynamic, buf:Dynamic) {
			var sh = socket(s, "std@socket_write"), b = bytes(buf, "std@socket_write");
			run(() -> cpp.NativeSocket.socket_write(sh, b.getData()));
			return null;
		});
		add("std@socket_read", 1, function(s:Dynamic) {
			var sh = socket(s, "std@socket_read");
			var d:haxe.io.BytesData = host(() -> cpp.NativeSocket.socket_read(sh));
			return new NString(Bytes.ofData(d));
		});
		add("std@socket_connect", 3, function(s:Dynamic, ip:Dynamic, port:Dynamic) {
			var sh = socket(s, "std@socket_connect"), addr = int(ip, "std@socket_connect"), pn = int(port, "std@socket_connect");
			// libhxcpp throws EOF for a refused connection; neko fails with the primitive's
			//  name, which Haxe's std turns into "Failed to connect on host:port"
			try
				cpp.NativeSocket.socket_connect(sh, addr, pn)
			catch (e:Dynamic) {
				if (Std.string(e) == "Blocking")
					Rt.raise(NString.of("Blocking"));
				Primitives.fail("std@socket_connect");
			}
			return true;
		});
		add("std@socket_bind", 3, function(s:Dynamic, ip:Dynamic, port:Dynamic) {
			var sh = socket(s, "std@socket_bind"), addr = int(ip, "std@socket_bind"), pn = int(port, "std@socket_bind");
			run(() -> cpp.NativeSocket.socket_bind(sh, addr, pn));
			return null;
		});
		add("std@socket_listen", 2, function(s:Dynamic, n:Dynamic) {
			var sh = socket(s, "std@socket_listen"), count = int(n, "std@socket_listen");
			run(() -> cpp.NativeSocket.socket_listen(sh, count));
			return null;
		});
		add("std@socket_accept", 1, function(s:Dynamic) {
			var sh = socket(s, "std@socket_accept");
			return new NAbstract(socketKind, host(() -> cpp.NativeSocket.socket_accept(sh)));
		});
		add("std@socket_select", 4, function(rs:Dynamic, ws:Dynamic, es:Dynamic, timeout:Dynamic) {
			var r = handles(rs, "std@socket_select"), w = handles(ws, "std@socket_select"), e = handles(es, "std@socket_select");
			var t:Dynamic = timeout == null ? null : number(timeout, "std@socket_select");
			var result:Array<Dynamic> = host(() -> cpp.NativeSocket.socket_select(r, w, e, t));
			var lists:Array<Dynamic> = [pick(rs, result[0]), pick(ws, result[1]), pick(es, result[2])];
			return lists;
		});
		add("std@socket_peer", 1, function(s:Dynamic) {
			var sh = socket(s, "std@socket_peer");
			return pair(host(() -> cpp.NativeSocket.socket_peer(sh)));
		});
		add("std@socket_host", 1, function(s:Dynamic) {
			var sh = socket(s, "std@socket_host");
			return pair(host(() -> cpp.NativeSocket.socket_host(sh)));
		});
		add("std@socket_set_timeout", 2, function(s:Dynamic, t:Dynamic) {
			var sh = socket(s, "std@socket_set_timeout");
			var time:Dynamic = t == null ? null : number(t, "std@socket_set_timeout");
			run(() -> cpp.NativeSocket.socket_set_timeout(sh, time));
			return null;
		});
		add("std@socket_shutdown", 3, function(s:Dynamic, r:Dynamic, w:Dynamic) {
			var sh = socket(s, "std@socket_shutdown"), read = bool(r, "std@socket_shutdown"), write = bool(w, "std@socket_shutdown");
			run(() -> cpp.NativeSocket.socket_shutdown(sh, read, write));
			return null;
		});
		add("std@socket_set_blocking", 2, function(s:Dynamic, b:Dynamic) {
			var sh = socket(s, "std@socket_set_blocking"), on = bool(b, "std@socket_set_blocking");
			run(() -> cpp.NativeSocket.socket_set_blocking(sh, on));
			return null;
		});
		add("std@socket_set_fast_send", 2, function(s:Dynamic, b:Dynamic) {
			var sh = socket(s, "std@socket_set_fast_send"), on = bool(b, "std@socket_set_fast_send");
			run(() -> cpp.NativeSocket.socket_set_fast_send(sh, on));
			return null;
		});
		add("std@socket_set_broadcast", 2, function(s:Dynamic, b:Dynamic) {
			var sh = socket(s, "std@socket_set_broadcast"), on = bool(b, "std@socket_set_broadcast");
			run(() -> cpp.NativeSocket.socket_set_broadcast(sh, on));
			return null;
		});
		// UDP addresses are neko objects with host and port fields
		add("std@socket_send_to", 5, function(s:Dynamic, buf:Dynamic, p:Dynamic, l:Dynamic, a:Dynamic) {
			var sh = socket(s, "std@socket_send_to"), b = bytes(buf, "std@socket_send_to");
			var r = checkRange(b, p, l, "std@socket_send_to");
			if (!Rt.isObject(a))
				Primitives.fail("std@socket_send_to");
			var addr = {host: (a : NObject).find(h("host")), port: (a : NObject).find(h("port"))};
			return host(() -> cpp.NativeSocket.socket_send_to(sh, b.getData(), r.pos, r.len, addr));
		});
		add("std@socket_recv_from", 5, function(s:Dynamic, buf:Dynamic, p:Dynamic, l:Dynamic, a:Dynamic) {
			var sh = socket(s, "std@socket_recv_from"), b = bytes(buf, "std@socket_recv_from");
			var r = checkRange(b, p, l, "std@socket_recv_from");
			if (!Rt.isObject(a))
				Primitives.fail("std@socket_recv_from");
			var addr = {host: 0, port: 0};
			var n:Int = host(() -> cpp.NativeSocket.socket_recv_from(sh, b.getData(), r.pos, r.len, addr));
			(a : NObject).fields.set(h("host"), addr.host);
			(a : NObject).fields.set(h("port"), addr.port);
			return n;
		});

		add("std@host_resolve", 1, function(n:Dynamic) {
			var name = str(n, "std@host_resolve");
			return host(() -> cpp.NativeSocket.host_resolve(name));
		});
		add("std@host_to_string", 1, (ip:Dynamic) -> NString.of(cpp.NativeSocket.host_to_string(int(ip, "std@host_to_string"))));
		add("std@host_reverse", 1, function(ip:Dynamic) {
			var addr = int(ip, "std@host_reverse");
			return NString.of(host(() -> cpp.NativeSocket.host_reverse(addr)));
		});
		add("std@host_local", 0, () -> NString.of(cpp.NativeSocket.host_local()));
	}
}
