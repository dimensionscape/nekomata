package nekomata.rt.prims;

import nekomata.rt.Values;
import nekomata.rt.Primitives.add;
import nekomata.rt.prims.Conv.*;

// libs/std date.c: dates are seconds since 1970 as 32-bit ints, broken down with the C
//  library as neko does
@:keep
@:cppFileCode('
#include <time.h>
#include <string.h>
#include <stdio.h>

static bool nk_tm(int inDate, bool inUtc, struct tm *outTm)
{
   time_t raw = (time_t)inDate;
   #ifdef _WIN32
   return (inUtc ? gmtime_s(outTm, &raw) : localtime_s(outTm, &raw)) == 0;
   #else
   return (inUtc ? gmtime_r(&raw, outTm) : localtime_r(&raw, outTm)) != 0;
   #endif
}

// Field 0-5: year, month (1-12), day, hour, minute, second; -1 when the date has none
static int nk_date_field(int inDate, bool inUtc, int inField)
{
   struct tm t;
   if (!nk_tm(inDate, inUtc, &t))
      return -1;
   switch(inField)
   {
      case 0: return t.tm_year + 1900;
      case 1: return t.tm_mon + 1;
      case 2: return t.tm_mday;
      case 3: return t.tm_hour;
      case 4: return t.tm_min;
      default: return t.tm_sec;
   }
}

static bool nk_date_format(int inDate, bool inUtc, const char *inFmt, ::String &outResult)
{
   struct tm t;
   char buf[128];
   if (!nk_tm(inDate, inUtc, &t))
      return false;
   if (strftime(buf, 127, inFmt, &t) == 0)
      return false;
   outResult = ::String(buf);
   return true;
}

// Replaces the day or the time of a local date; false when mktime cannot
static bool nk_date_set(int inDate, bool inDay, int a, int b, int c, int &outDate)
{
   struct tm t;
   if (!nk_tm(inDate, false, &t))
      return false;
   if (inDay)
   {
      t.tm_year = a - 1900;
      t.tm_mon = b - 1;
      t.tm_mday = c;
   }
   else
   {
      t.tm_hour = a;
      t.tm_min = b;
      t.tm_sec = c;
   }
   time_t d = mktime(&t);
   if (d == (time_t)-1)
      return false;
   outDate = (int)d;
   return true;
}

static int nk_date_make(int y, int mo, int d, int h, int mi, int s)
{
   struct tm t;
   memset(&t, 0, sizeof(t));
   t.tm_year = y - 1900;
   t.tm_mon = mo - 1;
   t.tm_mday = d;
   t.tm_hour = h;
   t.tm_min = mi;
   t.tm_sec = s;
   t.tm_isdst = -1;
   return (int)mktime(&t);
}

static int nk_date_tz(int inDate)
{
   struct tm local, gmt;
   if (!nk_tm(inDate, false, &local) || !nk_tm(inDate, true, &gmt))
      return 0x7fffffff;
   int diff = (local.tm_hour - gmt.tm_hour) * 60 + (local.tm_min - gmt.tm_min);
   if (gmt.tm_year > local.tm_year || gmt.tm_yday > local.tm_yday)
      diff -= 24 * 60;
   else if (gmt.tm_year < local.tm_year || gmt.tm_yday < local.tm_yday)
      diff += 24 * 60;
   return diff;
}
')
class StdDate {
	static function field(d:Int, utc:Bool, which:Int, prim:String):Int {
		var v:Int = untyped __cpp__("nk_date_field({0}, {1}, {2})", d, utc, which);
		if (v == -1 && which == 0)
			Primitives.fail(prim);
		return v;
	}

	static function format(o:Dynamic, f:Dynamic, utc:Bool, prim:String):Dynamic {
		var d = int(o, prim);
		var fmt = f == null ? "%Y-%m-%d %H:%M:%S" : str(f, prim);
		var result:String = null;
		var ok:Bool = untyped __cpp__("nk_date_format({0}, {1}, {2}.utf8_str(), {3})", d, utc, fmt, result);
		if (!ok)
			Primitives.fail(prim);
		return NString.of(result);
	}

	static function set(o:Dynamic, a:Dynamic, b:Dynamic, c:Dynamic, day:Bool, prim:String):Dynamic {
		var d = int(o, prim), x = int(a, prim), y = int(b, prim), z = int(c, prim);
		var out = 0;
		var ok:Bool = untyped __cpp__("nk_date_set({0}, {1}, {2}, {3}, {4}, {5})", d, day, x, y, z, out);
		if (!ok)
			Primitives.fail(prim);
		return out;
	}

	public static function register() {
		add("std@date_now", 0, () -> Std.int(Date.now().getTime() / 1000));
		add("std@date_new", 1, function(s:Dynamic):Dynamic {
			if (s == null)
				return Std.int(Date.now().getTime() / 1000);
			var text = str(s, "std@date_new");
			function num(from:Int, len:Int):Int {
				var v = Std.parseInt(text.substr(from, len));
				return v == null ? 0 : v;
			}
			switch text.length {
				case 19:
					var y = num(0, 4), mo = num(5, 2), d = num(8, 2), h = num(11, 2), mi = num(14, 2), sec = num(17, 2);
					return untyped __cpp__("nk_date_make({0}, {1}, {2}, {3}, {4}, {5})", y, mo, d, h, mi, sec);
				case 8:
					return num(6, 2) + num(3, 2) * 60 + num(0, 2) * 3600;
				case 10:
					var y = num(0, 4), mo = num(5, 2), d = num(8, 2);
					return untyped __cpp__("nk_date_make({0}, {1}, {2}, 0, 0, 0)", y, mo, d);
				default:
					return Rt.error("Invalid date format : " + text);
			}
		});
		add("std@date_format", 2, (o:Dynamic, f:Dynamic) -> format(o, f, false, "std@date_format"));
		add("std@date_utc_format", 2, (o:Dynamic, f:Dynamic) -> format(o, f, true, "std@date_utc_format"));
		add("std@date_set_hour", 4, (o:Dynamic, h:Dynamic, m:Dynamic, s:Dynamic) -> set(o, h, m, s, false, "std@date_set_hour"));
		add("std@date_set_day", 4, (o:Dynamic, y:Dynamic, m:Dynamic, d:Dynamic) -> set(o, y, m, d, true, "std@date_set_day"));
		function day(prim:String, utc:Bool)
			add(prim, 1, function(o:Dynamic) {
				var d = int(o, prim);
				return object([
					{name: "y", value: field(d, utc, 0, prim)},
					{name: "m", value: field(d, utc, 1, prim)},
					{name: "d", value: field(d, utc, 2, prim)}
				]);
			});
		function hour(prim:String, utc:Bool)
			add(prim, 1, function(o:Dynamic) {
				var d = int(o, prim);
				field(d, utc, 0, prim);
				return object([
					{name: "h", value: field(d, utc, 3, prim)},
					{name: "m", value: field(d, utc, 4, prim)},
					{name: "s", value: field(d, utc, 5, prim)}
				]);
			});
		day("std@date_get_day", false);
		day("std@date_get_utc_day", true);
		hour("std@date_get_hour", false);
		hour("std@date_get_utc_hour", true);
		add("std@date_get_tz", 1, function(o:Dynamic) {
			var tz:Int = untyped __cpp__("nk_date_tz({0})", int(o, "std@date_get_tz"));
			return tz == 0x7fffffff ? Primitives.fail("std@date_get_tz") : tz;
		});
	}
}
