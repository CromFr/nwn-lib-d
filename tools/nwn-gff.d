/// Authors: Thibaut CHARLES (Crom) cromfr@gmail.com
/// License: GPL-3.0
/// Copyright: Copyright Thibaut CHARLES 2016

module nwngff;

import std.stdio;
import std.conv: to, ConvException;
import std.traits;
import std.string;
import std.typecons: Tuple, Nullable;
version(unittest) import std.exception: assertThrown, assertNotThrown;

import nwn.gff;

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
	import std.getopt : getopt, defaultGetoptPrinter;
	alias required = std.getopt.config.required;

	string inputArg, outputArg;
	string[] setValuesList;
	auto res = getopt(args,
		required, "i|input", "<file>:<format> Input file and format", &inputArg,
		          "o|output", "<file>:<format> Output file and format", &outputArg,
		          "set", "Set values in the GFF file. Ex: 'DayNight.7.SkyDomeModel=my_sky_dome.tga'", &setValuesList,
		);
	if(res.helpWanted){
		defaultGetoptPrinter(
			 "Parsing and serialization tool for GFF files like ifo, are, bic, uti, ...\n"
			~"\n"
			~"file:\n"
			~"    - Path to the file to parse\n"
			~"    - Leave empty or '-' to read from stdin/write to stdout\n"
			~"format:\n"
			~"    - Any of "~EnumMembers!Format.stringof[6..$-1]~"\n"
			~"    - Leave empty or '-' to guess from file extension\n"
			,
			res.options);
		return 0;
	}

	FileFormatTuple iff = parseFileFormat(inputArg);
	if(iff.format.isNull)
		throw new ArgException("Cannot guess input format using stdin. Please set '-i -:<format>'");

	FileFormatTuple off;
	if(outputArg !is null){
		off = parseFileFormat(outputArg);
	}
	if(off.format.isNull)
		iff.format = Format.pretty;

	//Parsing
	Gff gff;
	File inputFile = iff.path is null? stdin : File(iff.path, "r");

	switch(iff.format){
		case Format.gff:
			gff = new Gff(inputFile);
			break;
		case Format.json, Format.json_minified:
			import nwnlibd.orderedjson;
			gff = Gff.fromJson(parseJSON(inputFile.readAllString));
			break;
		case Format.pretty:
			assert(0, iff.format.to!string~" parsing not supported");
		default:
			assert(0, iff.format.to!string~" parsing not implemented");
	}
	inputFile.close();



	//Modifications
	foreach(setValue ; setValuesList){
		GffNode* node = &gff.root;

		auto eq = setValue.indexOf('=');
		string[] path = setValue[0 .. eq].split(".");
		string value = setValue[eq+1..$];
		foreach(p ; path){
			if(node.type == GffType.Struct){
				try node = &(*node)[p];
				catch(Exception e)
					throw new Exception(e.msg~" for argument --set '"~setValue~"'");
			}
			else if(node.type == GffType.List){
				size_t idx;
				try idx = p.to!size_t;
				catch(ConvException e)
					throw new Exception("Cannot convert '"~p~"' to int for argument --set='"~setValue~"'");

				try node = &(*node)[idx];
				catch(Exception e)
					throw new Exception(e.msg~" for argument --set '"~setValue~"'");
			}
		}

		typeswitch:
		final switch(node.type) with(GffType){
			foreach(TYPE ; EnumMembers!GffType){
				case TYPE:
				static if(TYPE==Invalid){
					assert(0);
				}
				else static if(TYPE==ExoLocString){
					node.as!(GffType.ExoLocString).strings[0] = value;
				}
				else static if(TYPE==Struct || TYPE==List){
					throw new Exception("Cannot set GffType."~TYPE.to!string);
				}
				else{
					node.as!TYPE = value.to!(gffTypeToNative!TYPE);
					break typeswitch;
				}
			}
		}
	}






	//Serialization
	File outputFile = off.path is null? stdout : File(off.path, "w");
	switch(off.format){
		case Format.gff:
			outputFile.rawWrite(gff.serialize());
			break;
		case Format.pretty:
			outputFile.rawWrite(gff.toPrettyString());
			break;
		case Format.json, Format.json_minified:
			auto json = gff.toJson;
			outputFile.rawWrite(iff.format==Format.json? json.toPrettyString : json.toString);
			break;
		default:
			assert(0, iff.format.to!string~" serialization not implemented");
	}
	return 0;
}

enum Format{ gff, json, json_minified, pretty }
alias FileFormatTuple = Tuple!(string,"path", Nullable!Format,"format");

FileFormatTuple parseFileFormat(string str){
	import std.stdio: File;
	import std.string: lastIndexOf;
	import std.path: driveName;

	size_t driveNameLength;
	if(str.driveName!="-:")
		driveNameLength = str.driveName.length;

	auto colonIndex = str[driveNameLength..$].lastIndexOf(':');
	if(colonIndex==-1){
		immutable filePath = str;
		if(filePath.length>0 && str!="-")
			return FileFormatTuple(filePath, Nullable!Format(guessFormat(filePath)));
		else
			return FileFormatTuple(null, Nullable!Format());
	}
	else{
		colonIndex += driveNameLength;
		immutable filePath = str[0..colonIndex];
		immutable format = str[colonIndex+1..$];

		auto ret = FileFormatTuple(null, Nullable!Format());

		if(filePath.length>0 && filePath!="-"){
			ret.path = filePath;
		}
		if(format.length>0 && format!="-")
			ret.format = format.to!Format;
		else
			ret.format = guessFormat(filePath);

		return ret;
	}
}
Format guessFormat(in string fileName){
	import std.path: extension;
	import std.string: toLower;
	if(fileName is null || fileName=="-")
		assert(0, "Cannot guess file format without file name. Please specify format using <filename>:<format>'");

	immutable ext = fileName.extension.toLower;
	switch(ext){
		case ".gff":
		case ".are",".gic",".git"://areas
		case ".dlg"://dialogs
		case ".fac",".ifo",".jrl"://module files
		case ".bic"://characters
		case ".ult",".upe",".utc",".utd",".ute",".uti",".utm",".utp",".utr",".utt",".utw",".pfb"://blueprints
			return Format.gff;

		case ".json":
			return Format.json;

		case ".txt":
			return Format.pretty;

		default:
			throw new ArgException("Unrecognized file extension: '"~ext~"'");
	}

}

string readAllString(File stream){
	string data;
	char[500] buf;
	char[] dataRead;

	do{
		dataRead = stream.rawRead(buf);
		data ~= dataRead;
	}while(dataRead.length>0);

	return data;
}






unittest{
	import std.file: tempDir, read, writeFile=write, exists;
	import std.path: buildPath;
	import core.thread;

	auto krogarData = cast(ubyte[])import("krogar.bic");
	auto krogarFilePath = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__~".krogar.bic");
	krogarFilePath.writeFile(krogarData);

	auto stdout_ = stdout;
	version(Windows) stdout = File("nul","w");
	else             stdout = File("/dev/null","w");
	assert(_main(["./nwn-gff","--help"])==0);
	stdout = stdout_;


	immutable krogarFilePathDup = krogarFilePath~".dup.bic";
	assert(_main(["./nwn-gff","-i",krogarFilePath~":gff","-o",krogarFilePathDup~":gff"])==0);
	assert(krogarFilePath.read == krogarFilePathDup.read);


	assert(_main(["./nwn-gff","-i",krogarFilePath,"-o",krogarFilePathDup~":pretty"])==0);
	assert(_main(["./nwn-gff","-i",krogarFilePath~":gff","-o",krogarFilePathDup~":pretty"])==0);
	assertThrown!Error(_main(["./nwn-gff","-i",krogarFilePath~":pretty"]));


	auto dogeData = cast(ubyte[])import("doge.utc");
	immutable dogePath = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__~".doge.utc");
	dogePath.writeFile(dogeData);

	immutable dogePathJson = dogePath~".json";
	immutable dogePathDup = dogePath~".dup.utc";


	assert(_main(["./nwn-gff","-i",dogePath~":gff","-o",dogePathJson~":json"])==0);
	assert(_main(["./nwn-gff","-i",dogePathJson~":json","-o",dogePathDup~":gff"])==0);

	assertThrown!ArgException(_main(["./nwn-gff","-i","nothing.yolo","-o","something:gff"]));
	assert(!"nothing.yolo".exists);
	assert(!"something".exists);


	assert(dogePath.read == dogePathDup.read);
}

