package nekomata.rt.prims;

import sys.thread.Thread;
import nekomata.rt.Values;
import nekomata.rt.Rt;
import nekomata.rt.Boot;
import nekomata.rt.NekoStack;
import nekomata.rt.Primitives.add;
import nekomata.rt.prims.Conv.*;

// libs/std thread.c, on Haxe's sys.thread classes
@:keep
class StdThread {
	static final threadKind = new NObject();
	static final lockKind = new NObject();
	static final mutexKind = new NObject();
	static final tlsKind = new NObject();
	static final dequeKind = new NObject();
	static final condKind = new NObject();

	// Each thread's neko value, so thread_current returns the value thread_create gave
	static var current:sys.thread.Tls<NAbstract>;

	static function self():NAbstract {
		var t = current.value;
		if (t == null) {
			t = new NAbstract(threadKind, Thread.current());
			current.value = t;
		}
		return t;
	}

	public static function register() {
		current = new sys.thread.Tls();

		add("std@thread_create", 2, function(f:Dynamic, p:Dynamic) {
			if (!Rt.isFunction(f) || (f : NFunction).nargs != 1)
				Primitives.fail("std@thread_create");
			var value = new NAbstract(threadKind, null);
			var started = new sys.thread.Lock();
			value.data = Thread.create(function() {
				Boot.prepareThread();
				current.value = value;
				started.release();
				try {
					Rt.call1(f, null, p);
				} catch (e:Dynamic) {
					// Neko reports an uncaught exception in a thread as it does on the main thread
					var report = NekoStack.report(e);
					Sys.stderr().writeBytes(report, 0, report.length);
				}
			});
			started.wait();
			return value;
		});
		add("std@thread_current", 0, () -> self());
		add("std@thread_send", 2, function(t:Dynamic, msg:Dynamic) {
			(data(t, threadKind, "std@thread_send") : Thread).sendMessage(msg);
			return null;
		});
		add("std@thread_read_message", 1, (b:Dynamic) -> Thread.readMessage(bool(b, "std@thread_read_message")));
		add("std@thread_stack", 1, (t:Dynamic) -> null);

		add("std@lock_create", 0, () -> new NAbstract(lockKind, new sys.thread.Lock()));
		add("std@lock_wait", 2, function(l:Dynamic, timeout:Dynamic):Bool {
			var lock:sys.thread.Lock = data(l, lockKind, "std@lock_wait");
			return timeout == null ? lock.wait() : lock.wait(number(timeout, "std@lock_wait"));
		});
		add("std@lock_release", 1, function(l:Dynamic) {
			(data(l, lockKind, "std@lock_release") : sys.thread.Lock).release();
			return null;
		});

		add("std@tls_create", 0, () -> new NAbstract(tlsKind, new sys.thread.Tls<Dynamic>()));
		add("std@tls_get", 1, (t:Dynamic) -> (data(t, tlsKind, "std@tls_get") : sys.thread.Tls<Dynamic>).value);
		add("std@tls_set", 2, function(t:Dynamic, v:Dynamic) {
			(data(t, tlsKind, "std@tls_set") : sys.thread.Tls<Dynamic>).value = v;
			return null;
		});

		add("std@mutex_create", 0, () -> new NAbstract(mutexKind, new sys.thread.Mutex()));
		add("std@mutex_acquire", 1, function(m:Dynamic) {
			(data(m, mutexKind, "std@mutex_acquire") : sys.thread.Mutex).acquire();
			return null;
		});
		add("std@mutex_try", 1, (m:Dynamic) -> (data(m, mutexKind, "std@mutex_try") : sys.thread.Mutex).tryAcquire());
		add("std@mutex_release", 1, function(m:Dynamic) {
			(data(m, mutexKind, "std@mutex_release") : sys.thread.Mutex).release();
			return null;
		});

		add("std@deque_create", 0, () -> new NAbstract(dequeKind, new sys.thread.Deque<Dynamic>()));
		add("std@deque_add", 2, function(d:Dynamic, v:Dynamic) {
			(data(d, dequeKind, "std@deque_add") : sys.thread.Deque<Dynamic>).add(v);
			return null;
		});
		add("std@deque_push", 2, function(d:Dynamic, v:Dynamic) {
			(data(d, dequeKind, "std@deque_push") : sys.thread.Deque<Dynamic>).push(v);
			return null;
		});
		add("std@deque_pop", 2,
			(d:Dynamic, b:Dynamic) -> (data(d, dequeKind, "std@deque_pop") : sys.thread.Deque<Dynamic>).pop(bool(b, "std@deque_pop")));

		add("std@cond_create", 0, () -> new NAbstract(condKind, new sys.thread.Condition()));
		add("std@cond_acquire", 1, function(c:Dynamic) {
			(data(c, condKind, "std@cond_acquire") : sys.thread.Condition).acquire();
			return null;
		});
		add("std@cond_try_acquire", 1, (c:Dynamic) -> (data(c, condKind, "std@cond_try_acquire") : sys.thread.Condition).tryAcquire());
		add("std@cond_release", 1, function(c:Dynamic) {
			(data(c, condKind, "std@cond_release") : sys.thread.Condition).release();
			return null;
		});
		add("std@cond_wait", 1, function(c:Dynamic) {
			(data(c, condKind, "std@cond_wait") : sys.thread.Condition).wait();
			return null;
		});
		add("std@cond_signal", 1, function(c:Dynamic) {
			(data(c, condKind, "std@cond_signal") : sys.thread.Condition).signal();
			return null;
		});
		add("std@cond_broadcast", 1, function(c:Dynamic) {
			(data(c, condKind, "std@cond_broadcast") : sys.thread.Condition).broadcast();
			return null;
		});
	}
}
