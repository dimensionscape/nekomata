import sys.thread.Deque;
import sys.thread.Lock;
import sys.thread.Mutex;
import sys.thread.Thread;
import sys.thread.Tls;

// Threads that print nothing themselves: what they compute comes back to the main
//  thread in an order that does not depend on scheduling
class CaseThreads {
	static function main() {
		var results = new Deque<String>();
		var lock = new Lock();
		for (i in 0...4)
			Thread.create(() -> {
				var sum = 0;
				for (k in 0...100000)
					sum += k % (i + 2);
				results.add('worker $i sum $sum');
				lock.release();
			});
		for (i in 0...4)
			lock.wait();
		var got = [for (i in 0...4) results.pop(false)];
		got.sort(Reflect.compare);
		Sys.println(got.join("\n"));
		Sys.println("deque empty: " + (results.pop(false) == null));

		var mutex = new Mutex();
		var counter = 0;
		var done = new Lock();
		for (i in 0...8)
			Thread.create(() -> {
				for (k in 0...1000) {
					mutex.acquire();
					counter++;
					mutex.release();
				}
				done.release();
			});
		for (i in 0...8)
			done.wait();
		Sys.println("counter " + counter);
		Sys.println("tryAcquire free: " + mutex.tryAcquire());
		mutex.release();

		var main = Thread.current();
		var worker = Thread.create(() -> {
			var total = 0;
			while (true) {
				var msg:Dynamic = Thread.readMessage(true);
				if (msg == "stop")
					break;
				total += msg;
			}
			main.sendMessage("total " + total);
		});
		for (n in 1...101)
			worker.sendMessage(n);
		worker.sendMessage("stop");
		Sys.println(Thread.readMessage(true));
		Sys.println("no message waiting: " + (Thread.readMessage(false) == null));

		var tls = new Tls<String>();
		tls.value = "main value";
		var tlsLock = new Lock();
		var seen = null;
		Thread.create(() -> {
			seen = "thread sees " + tls.value;
			tls.value = "thread value";
			tlsLock.release();
		});
		tlsLock.wait();
		Sys.println(seen + ", main still sees " + tls.value);
		Sys.println("wait with timeout: " + new Lock().wait(0.05));
		var pipeline = new Deque<Int>();
		var out = new Deque<Int>();
		var stage = Thread.create(() -> {
			while (true) {
				var v = pipeline.pop(true);
				if (v < 0)
					break;
				out.add(v * v);
			}
			out.add(-1);
		});
		for (v in 0...10)
			pipeline.add(v);
		pipeline.add(-1);
		var squares = [];
		while (true) {
			var v = out.pop(true);
			if (v < 0)
				break;
			squares.push(v);
		}
		Sys.println("squares " + squares);
		Sys.println("current is main: " + (Thread.current() == main));
	}
}
