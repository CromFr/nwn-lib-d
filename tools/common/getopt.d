module tools.common.getopt;


public import std.getopt: getopt, config;
import std.getopt;
import std.stdio;
import std.string;


void improvedGetoptPrinter(string text, Option[] opt, int width=80){
	import std.stdio: writef, writeln;
	import std.algorithm: map, reduce, find;

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

	writeln(text);
	writeln();

	if(hasRequiredOpt)
		writeln("Options with * are required");

	foreach(ref o ; opt){
		writef(" %s%s %*s  ",
			hasRequiredOpt ? (o.required? "* " : "  ") : "",
			o.optShort !is null? o.optShort : "  ",
			widthOptLong, o.optLong );

		auto wrappedText = o.help
			.splitLines
			.map!(a=>a.wrap(width-widthHelpIndentation).splitLines)
			.reduce!(delegate(a, b){return a~b;});

		bool first = true;
		foreach(l ; wrappedText){
			writeln(first? "" : helpIndent, l);
			first = false;
		}
	}
}