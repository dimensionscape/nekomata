// What was printed before Sys.exit reaches the console, and the code comes through
class CaseExit {
	static function main() {
		Sys.print("buffered without newline, ");
		Sys.println("then a line");
		Sys.stderr().writeString("error output\n");
		var code = 0;
		for (i in 0...7)
			code += i;
		Sys.exit(code - 2);
		Sys.println("never printed");
	}
}
