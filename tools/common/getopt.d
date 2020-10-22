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
		.map!(a => a.smartWrap(width, null, " ").splitLines)
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
			.map!(a => a.smartWrap(width - widthHelpIndentation).splitLines)
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
			.map!((a) {
				auto l = a.smartWrap(width, null, " ").splitLines;
				if(l.length == 0)
					l = [""];
				return l;
			})
			.join
			.each!((a){
				writeln(a);
			});
	}
}


private string smartWrap(in string text, size_t width = 80, in string firstindent = null, in string secondindent = null, in size_t tabsize = 8){
	import std.uni : isWhite;

	return text.splitLines
		.map!((ref l){
			string indent;
			auto indentLen = l.countUntil!(a => !a.isWhite);
			if(indentLen > 0)
				indent = l[0 .. indentLen];

			return l.wrap(width - indent.length, firstindent, secondindent, tabsize)
				.splitLines
				.map!(a => indent ~ a)
				.join("\n");
		})
		.join("\n");
}
unittest{
	assert("   hello".smartWrap() == "   hello");
	assert("   hello world".smartWrap(8) == "   hello\n   world");
	assert("\n".smartWrap(8) == "");
	assert("\n\n".smartWrap(8) == "\n");
	assert("   a\n\n   b".smartWrap(8) == "   a\n\n   b");
}



template multilineStr(string s){
	enum multilineStr = (){
		auto lines = s.splitLines();
		assert(lines[0].strip == "", "First line must be empty");
		assert(lines.length > 1, "Not enough lines");

		const tabLen = lines[1].length - lines[1].stripLeft.length;
		const tab = lines[1][0 .. tabLen];

		return lines[1 .. $]
			.map!((l){
				if(l.strip.length == 0)
					return "";
				assert(l[0 .. tabLen] == tab, "Tab mismatch on line '" ~ l ~ "'");
				return l[tabLen .. $];
			})
			.join("\n");
	}();
}
