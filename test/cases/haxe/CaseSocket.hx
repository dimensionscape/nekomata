import sys.net.Host;
import sys.net.Socket;
import sys.thread.Lock;
import sys.thread.Thread;

// A server and a client in one process, over the loopback interface
class CaseSocket {
	static function main() {
		var server = new Socket();
		server.bind(new Host("127.0.0.1"), 0);
		server.listen(1);
		var port = server.host().port;
		Sys.println("bound to a port: " + (port > 0) + " host " + server.host().host);
		var done = new Lock();
		var serverLog = [];
		Thread.create(() -> {
			var client = server.accept();
			var line = client.input.readLine();
			serverLog.push("server got " + line);
			client.output.writeString("pong " + line.toUpperCase() + "\n");
			var bytes = client.input.read(4);
			serverLog.push("server got bytes " + bytes.toHex());
			client.output.writeInt32(0x7F000001);
			client.output.flush();
			client.close();
			done.release();
		});
		var s = new Socket();
		s.connect(new Host("127.0.0.1"), port);
		s.output.writeString("ping\n");
		s.output.flush();
		Sys.println("client got " + s.input.readLine());
		s.output.write(haxe.io.Bytes.ofHex("deadbeef"));
		s.output.flush();
		Sys.println("client got int " + s.input.readInt32());
		try {
			s.input.readByte();
			Sys.println("read past close");
		} catch (e:haxe.io.Eof) {
			Sys.println("eof after the server closes");
		}
		s.close();
		done.wait();
		Sys.println(serverLog.join("; "));
		server.close();
		Sys.println("localhost resolves: " + (new Host("localhost").ip != 0) + " " + (Host.localhost().length > 0));
		Sys.println(new Host("127.0.0.1").toString() + " " + (new Host("127.0.0.1").reverse().length > 0));
		var refused = new Socket();
		try {
			refused.connect(new Host("127.0.0.1"), port);
			Sys.println("connected to a closed port");
		} catch (e:Dynamic) {
			Sys.println("connecting to a closed port fails");
		}
		refused.close();
	}
}
