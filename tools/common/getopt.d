module tools.common.getopt;


public import std.getopt: getopt, config;
import std.getopt;
import std.stdio;
import std.string;
import std.algorithm;


void improvedGetoptPrinter(string text, Option[] opt, string footer = null, int width=80){

	version(Posix){
		import core.sys.posix.sys.ioctl;
		static if(__traits(compiles, winsize, winsize.ws_row, TIOCGWINSZ)){
			//pragma(msg, "Terminal width detection");
			winsize w;
			ioctl(stdout.fileno, TIOCGWINSZ, &w);
			width = w.ws_col;
		}
	}

	size_t widthOptLong;
	bool hasRequiredOpt = false;
	size_t widthHelpIndentation;
	foreach(ref o ; opt){
		if(o.optLong.length > widthOptLong)
			widthOptLong = o.optLong.length;
		if(o.required)
			hasRequiredOpt = true;
	}
	widthHelpIndentation = widthOptLong + (hasRequiredOpt? 8 : 6);
	auto helpIndent = "".leftJustify(widthHelpIndentation);


	// Print text
	text
		.splitLines
		.map!(a => a.wrap(width, null, " ").splitLines)
		.join
		.each!((a){
			writeln(a);
		});
	writeln();

	if(hasRequiredOpt)
		writeln("Options with * are required");

	// Print options
	foreach(ref o ; opt){
		writef(" %s%s %*s  ",
			hasRequiredOpt ? (o.required? "* " : "  ") : "",
			o.optShort !is null? o.optShort : "  ",
			widthOptLong, o.optLong );

		bool first = true;
		o.help
			.splitLines
			.map!(a => a.wrap(width - widthHelpIndentation).splitLines)
			.join
			.each!((a){
				writeln(first ? "" : helpIndent, a);
				first = false;
			});
	}

	// Print footer
	if(footer !is null){
		writeln();

		footer
			.splitLines
			.map!(a => a.wrap(width, null, " ").splitLines)
			.join
			.each!((a){
				writeln(a);
			});
	}
}
