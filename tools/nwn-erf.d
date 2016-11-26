/// Authors: Thibaut CHARLES (Crom) cromfr@gmail.com
/// License: GPL-3.0
/// Copyright: Copyright Thibaut CHARLES 2016

module nwnerf;

import std.stdio;
import std.conv: to, ConvException;
import std.traits;
import std.string;
import std.typecons: Tuple, Nullable;
import std.file;
import std.path;
alias writeFile = std.file.write;
version(unittest) import std.exception: assertThrown, assertNotThrown;

import nwn.constants;
import nwn.erf;

version(unittest){}
else{
	int main(string[] args){return _main(args);}
}

class ArgException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

int _main(string[] args){
	import std.getopt;

	if(args.length > 2){
		immutable command = args[1];
		args = args[0] ~ args[2..$];

		switch(command){
			case "create":{
				string outputPath;
				auto res = getopt(args,
					"o|output", "Output file name", &outputPath);
				if(res.helpWanted){
					defaultGetoptPrinter(
						"Parsing and serialization tool for ERF archive files (erf, hak, mod, ...)",
						res.options);
					return 0;
				}

				auto erf = new NWN2Erf();
				erf.fileVersion = "V1.1";
				erf.fileType = outputPath.extension[1..$].toUpper;
				writeln(erf.buildDate);

				void addFile(in DirEntry file){
					if(file.isFile){
						erf.files ~= NWN2ErfFile(file);
					}
					else if(file.isDir){
						foreach(path ; file.dirEntries(SpanMode.shallow)){
							addFile(DirEntry(path));
						}
					}
					else{
						writeln("Ignored file: '", file, "'");
					}
				}

				foreach(const ref path ; args[1..$]){
					addFile(DirEntry(path));
				}

				outputPath.writeFile(erf.serialize());

			}break;

			case "info":{
				auto erf = new NWN2Erf(cast(ubyte[])args[$-1].read);
				writeln("File type: ", erf.fileType);
				writeln("File version: ", erf.fileVersion);
				writeln("Build date: ", erf.buildDate);
				writeln("Module description: ", erf.description);
			}break;

			case "list":{
				auto erf = new NWN2Erf(cast(ubyte[])args[$-1].read);

				import std.math: log10;
				int idxColWidth = cast(int)(log10(erf.files.length))+1;
				foreach(i, const ref file ; erf.files){
					writeln(i.to!string.rightJustify(idxColWidth),"|",
						file.name.leftJustify(32+1),
						file.type);
				}
			}break;
			default:
				writeln(command, " not implemented");
				return -1;
		}
	}
	return 0;
}
