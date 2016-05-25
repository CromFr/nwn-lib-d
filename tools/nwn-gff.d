module nwngff;

import std.stdio;
import std.conv: to;
import std.traits;
import std.typecons: Tuple;
version(unittest) import std.exception: assertThrown, assertNotThrown;

import nwn.gff;

version(unittest){}
else{
	int main(string[] args){return _main(args);}
}


int _main(string[] args){
	import std.getopt : getopt, defaultGetoptPrinter;
	alias required = std.getopt.config.required;

	string inputArg, outputArg;
	auto res = getopt(args,
		required, "i|input", "<file>:<format> Input file and format", &inputArg,
		          "o|output", "<file>:<format> Output file and format", &outputArg,
		);

	FileFormatTuple iff = parseFileFormat(inputArg, stdin, Format.gff);

	FileFormatTuple off;
	if(outputArg !is null)
		off = parseFileFormat(outputArg, stdout, Format.gff);
	else
		off = FileFormatTuple(stdout, null, Format.pretty);

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
	if(!iff.file.isOpen)
		iff.file.open(iff.path, "r");

	switch(iff.format){
		case Format.gff:
			gff = new Gff(iff.file);
			break;
		case Format.json, Format.json_minified:
			gff = jsonToGff(iff.file);
			break;
		case Format.pretty:
			assert(0, iff.format.to!string~" parsing not supported");
		default:
			assert(0, iff.format.to!string~" parsing not implemented");
	}

	iff.file.close();

	if(!off.file.isOpen)
		off.file.open(off.path, "w");

	//Serialization
	switch(off.format){
		case Format.gff:
			off.file.rawWrite(gff.serialize());
			break;
		case Format.pretty:
			off.file.rawWrite("========== GFF-"~gff.fileType~"-"~gff.fileVersion~" ==========\n"~gff.toPrettyString());
			break;
		case Format.json, Format.json_minified:
			auto json = gff.toJson;
			off.file.rawWrite(iff.format==Format.json? json.toPrettyString : json.toString);
			break;
		default:
			assert(0, iff.format.to!string~" serialization not implemented");
	}
	return 0;
}

enum Format{ gff, json, json_minified, pretty }
alias FileFormatTuple = Tuple!(File,"file", string,"path", Format,"format");

FileFormatTuple parseFileFormat(string fileFormat, ref File defaultFile, Format defaultFormat){
	import std.stdio: File;
	import std.string: lastIndexOf;
	auto ret = FileFormatTuple(defaultFile, null, defaultFormat);

	auto colonIndex = fileFormat.lastIndexOf(':');
	if(colonIndex==-1){
		if(fileFormat.length>0 && fileFormat!="-"){
			ret.file = File.init;
			ret.path = fileFormat;
		}
	}
	else{
		immutable file = fileFormat[0..colonIndex];
		if(file.length>0 && file!="-"){
			ret.file = File.init;
			ret.path = file;
		}

		immutable format = fileFormat[colonIndex+1..$];
		if(format !is null)
			ret.format = format.to!Format;
	}
	return ret;
}

unittest{
	import std.file: tempDir, read, writeFile=write;
	import core.thread;

	auto krogarData = cast(void[])import("krogar.bic");
	auto krogarFilePath = tempDir~"/unittest-nwn-lib-d-"~__MODULE__~".krogar.bic";
	krogarFilePath.writeFile(krogarData);

	auto stdout_ = stdout;
	stdout = File("/dev/null","w");
	assert(_main(["./nwn-gff","--help"])==0);
	stdout = stdout_;


	immutable krogarFilePathDup = krogarFilePath~".dup.bic";
	assert(_main(["./nwn-gff","-i",krogarFilePath~":gff","-o",krogarFilePathDup~":gff"])==0);
	assert(krogarFilePath.read == krogarFilePathDup.read);


	assert(_main(["./nwn-gff","-i",krogarFilePath,"-o",krogarFilePathDup~":pretty"])==0);
	assert(_main(["./nwn-gff","-i",krogarFilePath~":gff","-o",krogarFilePathDup~":pretty"])==0);
	assertThrown!Error(_main(["./nwn-gff","-i",krogarFilePath~":pretty"]));


	auto dogeData = cast(void[])import("doge.utc");
	immutable dogePath = tempDir~"/unittest-nwn-lib-d-"~__MODULE__~".doge.utc";
	dogePath.writeFile(dogeData);

	immutable dogePathJson = dogePath~".json";
	immutable dogePathDup = dogePath~".dup.utc";


	assert(_main(["./nwn-gff","-i",dogePath~":gff","-o",dogePathJson~":json"])==0);
	assert(_main(["./nwn-gff","-i",dogePathJson~":json","-o",dogePathDup~":gff"])==0);

	_main(["./nwn-gff","-i",dogePath~":gff",      "-o","/tmp/from:pretty"]);
	_main(["./nwn-gff","-i",dogePathJson~":json", "-o","/tmp/to:pretty"]);

	assert(dogePath.read == dogePathDup.read);
}

Gff jsonToGff(File stream){
	import std.traits: isIntegral, isFloatingPoint;
	import nwnlibd.orderedjson;

	GffNode ret = GffNode(GffType.Invalid);
	GffNode*[] nodeStack = [&ret];

	string data;
	char[500] buf;
	char[] dataRead;

	do{
		dataRead = stream.rawRead(buf);
		data ~= dataRead;
	}while(dataRead.length>0);

	return Gff.fromJson(parseJSON(data));
}


