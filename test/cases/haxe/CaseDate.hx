class CaseDate {
	static function show(d:Date)
		return '${d.toString()} y${d.getFullYear()} m${d.getMonth()} d${d.getDate()} wd${d.getDay()} h${d.getHours()} mi${d.getMinutes()} s${d.getSeconds()}'
			+ ' utc ${d.getUTCFullYear()}-${d.getUTCMonth()}-${d.getUTCDate()} ${d.getUTCHours()}:${d.getUTCMinutes()} wd${d.getUTCDay()}';

	static function main() {
		// Local time depends on the machine's time zone, which neko and the host share
		for (t in [0.0, 86400000.0, 951782400000.0, 1234567890000.0, 1700000000000.0, 2147483647000.0])
			Sys.println(t + " " + show(Date.fromTime(t)) + " " + Date.fromTime(t).getTime());
		var d = new Date(2020, 1, 29, 13, 45, 1);
		Sys.println(show(d) + " " + (d.getTime() == Date.fromString("2020-02-29 13:45:01").getTime()));
		Sys.println(Date.fromString("2001-09-09") + " " + Date.fromString("12:34:56").getHours());
		Sys.println(new Date(2021, 0, 31, 0, 0, 0).getDay() + " " + new Date(2021, 12, 1, 0, 0, 0) + " " + new Date(2021, 0, 32, 25, 61, 61));
		for (f in ["%Y-%m-%d %H:%M:%S", "%d/%m/%y", "%a %A %b %B", "%j %e %I %p %T %D %%"])
			Sys.println(f + " => " + DateTools.format(d, f));
		Sys.println(DateTools.delta(d, DateTools.days(1)).toString() + " " + DateTools.getMonthDays(d) + " " + DateTools.getMonthDays(new Date(2019, 1, 1, 0, 0, 0)));
		Sys.println(DateTools.hours(2) + " " + DateTools.minutes(3) + " " + DateTools.seconds(4) + " " + DateTools.make({ms: 1, seconds: 2, minutes: 3, hours: 4, days: 5}));
		var p = DateTools.parse(123456789.0);
		Sys.println(p.days + " " + p.hours + " " + p.minutes + " " + p.seconds + " " + p.ms);
		var off = d.getTimezoneOffset();
		Sys.println("offset is a whole number of minutes: " + (off == Std.int(off)));
		var now = Date.now();
		Sys.println("now is after 2020: " + (now.getFullYear() >= 2020) + ", Sys.time agrees: " + (Math.abs(now.getTime() / 1000 - Sys.time()) < 5));
		try {
			Date.fromString("not a date");
			Sys.println("parsed");
		} catch (e:Dynamic) {
			Sys.println("bad date: " + e);
		}
	}
}
