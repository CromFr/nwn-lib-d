/// Authors: Thibaut CHARLES (Crom) cromfr@gmail.com
/// License: GPL-3.0
/// Copyright: Copyright Thibaut CHARLES 2016

module tools.nwntlk;

import std.stdio;
import std.conv: to, ConvException;
import std.traits;
import std.string;
import std.path;
import std.exception;
import std.typecons: Tuple, Nullable;
version(unittest) import std.exception: assertThrown, assertNotThrown;

import tools.common.getopt;
import nwn.tlk;

class ArgException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

int main(string[] args){
	version(unittest) if(args.length <= 1) return 0;

	string inputPath, outputPath;
	Format inputFormat = Format.detect, outputFormat = Format.detect;
	bool baseIndices, userIndices;
	auto res = getopt(args,
		"i|input", "Input file", &inputPath,
		"j|input-format", "Input file format ("~EnumMembers!Format.stringof[6..$-1]~")", &inputFormat,
		"o|output", "<file> Output file", &outputPath,
		"k|output-format", "Output file format ("~EnumMembers!Format.stringof[6..$-1]~")", &outputFormat,
		"b|base", "Display TLK base indices (starting from 0)", &baseIndices,
		"u|user", "Display TLK user indices (starting from 16777216)", &userIndices,
		);
	if(res.helpWanted){
		improvedGetoptPrinter(
			"Parsing and serialization tool for TLK files",
			res.options);
		return 1;
	}


	size_t offset = 0;
	if(baseIndices || userIndices){
		enforce(baseIndices ^ userIndices,
			"You cannot provide both --base and --user");
		if(userIndices)
			offset = 16777216;
	}
	else{
		if(!inputPath.baseName.stripExtension.toLower.startsWith("dialog"))
			offset = 16777216;
	}

	if(inputFormat == Format.detect){
		if(inputPath is null)
			inputFormat = Format.tlk;
		else
			inputFormat = guessFormat(inputPath);
	}
	if(outputFormat == Format.detect){
		if(outputPath is null)
			outputFormat = Format.text;
		else
			outputFormat = guessFormat(outputPath);
	}

	//Parsing
	Tlk tlk;
	File inputFile = inputPath is null? stdin : File(inputPath, "r");

	switch(inputFormat){
		case Format.tlk:
			tlk = new Tlk(inputFile.readAll);
			break;
		default:
			assert(0, inputFormat.to!string~" parsing not implemented");
	}
	inputFile.close();

	//Serialization
	File outputFile = outputPath is null? stdout : File(outputPath, "w");
	switch(outputFormat){
		case Format.tlk:
			outputFile.rawWrite(tlk.serialize());
			break;
		case Format.text:
			import std.math: log10;
			int idColLength = cast(int)log10(offset + tlk.length) + 1;
			foreach(strref, str ; tlk){
				import std.typecons: Yes;
				foreach(i, ref line ; str.splitLines(Yes.keepTerminator)){
					outputFile.write((i == 0? (offset + strref).to!string : null).rightJustify(idColLength), "|", line);
				}
				writeln();
			}
			break;
		default:
			assert(0, outputFormat.to!string~" serialization not implemented");
	}
	return 0;
}

enum Format{ detect, tlk, text }

Format guessFormat(in string fileName){
	import std.path: extension;
	import std.string: toLower;
	assert(fileName !is null);

	immutable ext = fileName.extension.toLower;
	switch(ext){
		case ".tlk":
			return Format.tlk;
		case ".txt":
			return Format.text;
		default:
			throw new ArgException("Unrecognized file extension: '"~ext~"'");
	}

}

ubyte[] readAll(File stream){
	ubyte[] data;
	ubyte[500] buf;
	ubyte[] dataRead;

	do{
		dataRead = stream.rawRead(buf);
		data ~= dataRead;
	}while(dataRead.length>0);

	return data;
}
