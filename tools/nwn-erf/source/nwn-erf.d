/// Authors: Thibaut CHARLES (Crom) cromfr@gmail.com
/// License: GPL-3.0
/// Copyright: Copyright Thibaut CHARLES 2016

module tools.nwnerf;

import std.stdio;
import std.conv: to, ConvException;
import std.traits;
import std.string;
import std.typecons: Tuple, Nullable;
import std.file;
import std.exception;
import std.path;
import std.algorithm;
alias writeFile = std.file.write;
version(unittest) import std.exception: assertThrown, assertNotThrown;

import tools.common.getopt;
import nwn.constants;
import nwn.erf;

class ArgException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}


int main(string[] args){
	if(args.length <= 1 || args[1] == "--help" || args[1] == "-h"){
		writeln("Parsing and serialization tool for ERF archive files (erf, hak, mod, pwc, ...)");
		writefln("Usage: %s (create|extract|info|list)", args[0].baseName);
		writeln("Use '", args[0].baseName, " <subcommand> --help' for details on a specific subcommand.");
		return args.length <= 1;
	}
	if(args.any!(a => a == "--version")){
		import nwn.ver: NWN_LIB_D_VERSION;
		writeln(NWN_LIB_D_VERSION);
		return 0;
	}

	immutable command = args[1];
	args = args[0] ~ args[2..$];

	switch(command){
		case "create":{
			string outputPath;
			string buildDateStr;
			string type;
			auto res1 = getopt(args,
				"o|output", "Output file name", &outputPath,
				"t|type", "File type. If not provided the type will be guessed from the file extension. Valid values are: hak, mod, erf, pwc", &type,
				"date", "Set erf build date field. Format 'YYYY-MM-DD', or just 'now'. Defaults to 1900-01-01", &buildDateStr);
			if(res1.helpWanted){
				improvedGetoptPrinter(
					"Pack multiple files into a single NWN2 ERF/HAK/MOD file\n"
					~"Example: "~args[0].baseName~" create -o out_file.erf file1 file2 ...",
					res1.options);
				return 0;
			}
			enforce(args.length > 1, "No input file provided");
			enforce(outputPath !is null, "No output file provided");

			auto erf = new NWN2Erf();
			erf.fileVersion = "V1.1";

			auto ext = (type !is null ? type : outputPath.extension[1..$]).toUpper;
			switch(ext){
				case "HAK", "MOD", "ERF", "PWC":
					erf.fileType = ext;
					break;
				default:
					enforce(0, format!"Unknown ERF file type %s"(ext));
			}

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
			string outputPath = ".";
			bool recover = false;
			auto res1 = getopt(args,
				"o|output", "Output folder path", &outputPath,
				"r|recover", "Recover files from truncated file", &recover,
			);
			if(res1.helpWanted){
				improvedGetoptPrinter(
					"Extract an ERF file content\n"
					~"Example: "~args[0].baseName~" extract -o dir/ yourfile.erf",
					res1.options);
				return !res1.helpWanted;
			}

			enforce(args.length > 1, "No input file provided");
			enforce(args.length <= 2, "Too many input files provided");

			auto erf = new NWN2Erf(cast(ubyte[])args[$-1].read, recover);
			foreach(ref file ; erf.files){
				auto filePath = buildNormalizedPath(
					outputPath,
					file.name ~ "." ~ resourceTypeToFileExtension(file.type));

				if(recover){
					if(file.data.length == 0){
						writeln("No data available for file '", filePath.baseName, "'");
						continue;
					}
					else if(file.data.length != file.expectedLength) {
						filePath ~= ".part";
						writeln("Truncated file: '", filePath.baseName, "'");
					}
				}
				std.file.write(filePath, file.data);
			}

		}break;

		case "info":{
			if(args.any!(a => a == "-h" || a == "--help")){
				writeln("Extract an ERF file content");
				writeln("Example: "~args[0].baseName~" info yourfile.erf");
				return 0;
			}
			enforce(args.length > 1, "No input file provided");
			enforce(args.length <= 2, "Too many input files provided");

			auto erf = new NWN2Erf(cast(ubyte[])args[1].read);
			writeln("File type: ", erf.fileType);
			writeln("File version: ", erf.fileVersion);
			writeln("Build date: ", erf.buildDate);
			writeln("Module description: ", erf.description);
			writeln("File count: ", erf.files.length);
		}break;

		case "list":{
			if(args.any!(a => a == "-h" || a == "--help")){
				writeln("List files contained inside a ERF file");
				writeln("Example: "~args[0].baseName~" list yourfile.erf");
				return 0;
			}
			enforce(args.length > 1, "No input file provided");
			enforce(args.length <= 2, "Too many input files provided");

			auto erf = new NWN2Erf(cast(ubyte[])args[1].read);

			import std.math: log10;
			int idxColWidth = cast(int)(log10(cast(double)erf.files.length))+1;
			foreach(i, const ref file ; erf.files){
				writeln(i.to!string.rightJustify(idxColWidth),"|",
					file.name.leftJustify(32+1),
					file.type);
			}
		}break;

		default:
			writefln("Unknown command '%s'. Try %s --help", command, args[0].baseName);
			return -1;
	}
	return 0;
}

unittest {
	import std.file;
	import std.path;

	auto erfFile = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__~".erf");
	scope(success) std.file.remove(erfFile);

	auto stdout_ = stdout;
	auto tmpOut = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__~".out");
	stdout = File(tmpOut, "w");
	scope(success) std.file.remove(tmpOut);
	scope(exit) stdout = stdout_;



	assert(main(["nwn-erf"]) != 0);
	assert(main(["nwn-erf","--help"]) == 0);
	assert(main(["nwn-erf","--version"]) == 0);

	// Create
	assertThrown(main(["nwn-erf","create"]));
	assert(main(["nwn-erf","create","--help"]) == 0);

	assertThrown(main(["nwn-erf","create","-o","nonstandard.extension","../../unittest/dds_test_rgba.dds"]));
	assert(main(["nwn-erf","create","-o",erfFile,"../../unittest/dds_test_rgba.dds","../../unittest/test_cost_armor.uti","../../unittest/WalkmeshObjects.trx"]) == 0);

	// Info
	assertThrown(main(["nwn-erf","info"]));
	assert(main(["nwn-erf","info","--help"]) == 0);
	assertThrown(main(["nwn-erf","info",erfFile,"too_many_files.erf"]));
	assert(main(["nwn-erf","info",erfFile]) == 0);

	// List
	assertThrown(main(["nwn-erf","list"]));
	assert(main(["nwn-erf","info","--help"]) == 0);
	assertThrown(main(["nwn-erf","list",erfFile,"too_many_files.erf"]));
	stdout.reopen(null, "w");
	assert(main(["nwn-erf","list",erfFile]) == 0);
	stdout.flush();
	assert(tmpOut.readText.splitLines.length == 3);

	// Extract
	assertThrown(main(["nwn-erf","extract"]));
	assert(main(["nwn-erf","extract","--help"]) == 0);
	assert(main(["nwn-erf","extract","-o",tempDir,erfFile]) == 0);

	foreach(f ; ["dds_test_rgba.dds","test_cost_armor.uti","walkmeshobjects.trx"])
		std.file.remove(buildPath(tempDir, f));
}
