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

	if(args.length > 1){
		if(args[1] == "--help" || args[1] == "-h"){
			writeln("Parsing and serialization tool for ERF archive files (erf, hak, mod, ...)");
			writeln("Usage: ", args[0], " (create|info|list)");
		}
	}

	if(args.length > 2){
		immutable command = args[1];
		args = args[0] ~ args[2..$];

		switch(command){
			case "create":{
				string outputPath;
				string buildDateStr;
				auto res = getopt(args,
					config.required, "o|output", "Output file name", &outputPath,
					"date", "Set erf build date field. Format 'YYYY-MM-DD', or just 'now'. Defaults to 1900-01-01", &buildDateStr);
				if(res.helpWanted){
					defaultGetoptPrinter(
						"Pack multiple files into a single NWN2 ERF/HAK/MOD file\n"
						~"Example: "~args[0]~" create -o out_file.erf file1 file2 ...",
						res.options);
					return 0;
				}

				auto erf = new NWN2Erf();
				erf.fileVersion = "V1.1";
				erf.fileType = outputPath.extension[1..$].toUpper;

				import std.datetime: Clock, Date;
				if(buildDateStr == "now")
					erf.buildDate = cast(Date)Clock.currTime;
				else if(buildDateStr !is null)
					erf.buildDate = Date.fromISOExtString(buildDateStr);


				void addFile(DirEntry file){
					if(file.isFile){
						erf.files ~= NWN2ErfFile(file);
					}
					else if(file.isDir){
						import std.algorithm: sort;
						import std.array: array;
						import std.uni: icmp;
						foreach(path ; file.dirEntries(SpanMode.shallow).array.sort!"icmp(a.name, b.name) < 0"){
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

				erf.writeToFile(File(outputPath, "w+"));

			}break;

			case "extract":{
				string outputPath;
				auto res = getopt(args,
					config.required, "o|output", "Output folder path", &outputPath);
				if(res.helpWanted){
					defaultGetoptPrinter(
						"Extract an ERF file content"
						~"Example: "~args[0]~" extract -o dir/ yourfile.erf",
						res.options);
					return 0;
				}

				auto erf = new NWN2Erf(cast(ubyte[])args[$-1].read);
				foreach(ref file ; erf.files){
					immutable filePath = buildNormalizedPath(
						outputPath,
						file.name ~ "." ~ resourceTypeToFileExtension(file.type));
					std.file.write(filePath, file.data);
				}

			}break;

			case "info":{
				auto erf = new NWN2Erf(cast(ubyte[])args[$-1].read);
				writeln("File type: ", erf.fileType);
				writeln("File version: ", erf.fileVersion);
				writeln("Build date: ", erf.buildDate);
				writeln("Module description: ", erf.description);
				writeln("File count: ", erf.files.length);
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
				writeln("Unknown command '",command, "'. Try ",args[0]," --help");
				return -1;
		}
	}
	return 0;
}
