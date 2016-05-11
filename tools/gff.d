import std.stdio;
import std.file;
import std.conv: to;
import std.traits;
import std.typecons: Tuple;

import nwn.gff;

int main(string[] args) {
	import std.getopt : getopt, defaultGetoptPrinter;
	alias required = std.getopt.config.required;

	string inputArg, outputArg;
	auto res = getopt(args,
		required, "i|input", "<file>:<format> Input file and format", &inputArg,
		          "o|output", "<file>:<format> Output file and format", &outputArg,
		);

	FileFormatTuple iff = parseFileFormat(inputArg, stdin, "r", Format.gff);

	FileFormatTuple off;
	if(outputArg !is null)
		off = parseFileFormat(inputArg, stdout, "w", Format.gff);
	else
		off = FileFormatTuple(stdout, Format.pretty);

	if(res.helpWanted){
		defaultGetoptPrinter(
			 "Parsing and serialization tool for GFF files like ifo, are, bic, uti, ...\n"
			~"\n"
			~"file:\n"
			~"    - Path to the file to parse\n"
			~"    - Leave empty or '-' to read from stdin/write to stdout\n"
			~"format:\n"
			~"    - Any of "~EnumMembers!Format.stringof[6..$-1]~"\n"
			//~"    - Leave empty or '-' to guess from file extension\n" //TODO
			,
			res.options);
		return 0;
	}

	//Parsing
	Gff gff;
	switch(iff.format){
		case Format.gff:
			gff = new Gff(iff.file);
			break;
		case Format.pretty:
			assert(0, iff.format.to!string~" parsing not supported");
		default:
			assert(0, iff.format.to!string~" parsing not implemented");
	}

	//Serialization
	switch(off.format){
		case Format.gff:
			off.file.rawWrite(gff.serialize());
			break;
		case Format.pretty:
			off.file.rawWrite(gff.toPrettyString());
			break;
		default:
			assert(0, iff.format.to!string~" serialization not implemented");
	}
	return 0;
}

enum Format{ gff, json, pretty }
alias FileFormatTuple = Tuple!(File,"file", Format,"format");

FileFormatTuple parseFileFormat(string fileFormat, ref File defaultFile, string defaultFileOpenMode, Format defaultFormat){
	import std.stdio: File;
	import std.string: lastIndexOf;
	auto ret = FileFormatTuple(defaultFile, defaultFormat);

	auto colonIndex = fileFormat.lastIndexOf(':');
	if(colonIndex==-1){
		if(fileFormat !is null)
			ret.file = File(fileFormat, defaultFileOpenMode);
	}
	else{
		auto file = fileFormat[0..colonIndex];
		if(file !is null)
			ret.file = File(file, defaultFileOpenMode);

		auto format = fileFormat[colonIndex+1..$];
		if(format !is null)
			ret.format = format.to!Format;
	}
	return ret;
}