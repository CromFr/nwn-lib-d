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

	string inputPath, outputPath;
	Format inputFormat = Format.detect, outputFormat = Format.detect;
	string[] setValuesList;
	auto res = getopt(args,
		"i|input", "Input file", &inputPath,
		"j|input-format", "Input file format ("~EnumMembers!Format.stringof[6..$-1]~")", &inputFormat,
		"o|output", "<file>:<format> Output file and format", &outputPath,
		"k|output-format", "Output file format ("~EnumMembers!Format.stringof[6..$-1]~")", &outputFormat,
		"s|set", "Set values in the GFF file. Ex: 'DayNight.7.SkyDomeModel=my_sky_dome.tga'", &setValuesList,
		);
	if(res.helpWanted){
		defaultGetoptPrinter(
			 "Parsing and serialization tool for GFF files like ifo, are, bic, uti, ...",
			res.options);
		return 0;
	}

	if(inputFormat == Format.detect){
		if(inputPath is null)
			inputFormat = Format.gff;
		else
			inputFormat = guessFormat(inputPath);
	}
	if(outputFormat == Format.detect){
		if(outputPath is null)
			outputFormat = Format.pretty;
		else
			outputFormat = guessFormat(outputPath);
	}

	//Parsing
	Gff gff;
	File inputFile = inputPath is null? stdin : File(inputPath, "r");

	switch(inputFormat){
		case Format.gff:
			gff = new Gff(inputFile);
			break;
		case Format.json, Format.json_minified:
			import nwnlibd.orderedjson;
			gff = Gff.fromJson(parseJSON(inputFile.readAllString));
			break;
		case Format.pretty:
			assert(0, inputFormat.to!string~" parsing not supported");
		default:
			assert(0, inputFormat.to!string~" parsing not implemented");
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
					node.as!(GffType.ExoLocString).strref = -1;
					node.as!(GffType.ExoLocString).strings[0] = value;
					break typeswitch;
				}
				else static if(TYPE==Struct || TYPE==List){
					throw new Exception("Cannot set GffType."~TYPE.to!string);
				}
				else static if(TYPE==Void){
					import std.base64: Base64;
					node.as!TYPE = Base64.decode(value);
					break typeswitch;
				}
				else{
					node.as!TYPE = value.to!(gffTypeToNative!TYPE);
					break typeswitch;
				}
			}
		}
	}






	//Serialization
	File outputFile = outputPath is null? stdout : File(outputPath, "w");
	switch(outputFormat){
		case Format.gff:
			outputFile.rawWrite(gff.serialize());
			break;
		case Format.pretty:
			outputFile.rawWrite(gff.toPrettyString());
			break;
		case Format.json, Format.json_minified:
			auto json = gff.toJson;
			outputFile.rawWrite(outputFormat==Format.json? json.toPrettyString : json.toString);
			break;
		default:
			assert(0, outputFormat.to!string~" serialization not implemented");
	}
	return 0;
}

enum Format{ detect, gff, json, json_minified, pretty }

Format guessFormat(in string fileName){
	import std.path: extension;
	import std.string: toLower;
	assert(fileName !is null);

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
	assert(_main(["./nwn-gff","-i",krogarFilePath,"-o",krogarFilePathDup])==0);
	assert(krogarFilePath.read == krogarFilePathDup.read);


	assert(_main(["./nwn-gff","-i",krogarFilePath,"-o",krogarFilePathDup, "-k","pretty"])==0);
	assert(_main(["./nwn-gff","-i",krogarFilePath,"-o",krogarFilePathDup, "-k","pretty"])==0);
	assertThrown!Error(_main(["./nwn-gff","-i",krogarFilePath, "-j","pretty"]));


	auto dogeData = cast(ubyte[])import("doge.utc");
	immutable dogePath = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__~".doge.utc");
	dogePath.writeFile(dogeData);

	immutable dogePathJson = dogePath~".json";
	immutable dogePathDup = dogePath~".dup.utc";


	assert(_main(["./nwn-gff","-i",dogePath,"-o",dogePathJson])==0);
	assert(_main(["./nwn-gff","-i",dogePathJson,"-o",dogePathDup])==0);


	assert(_main(["./nwn-gff","-i",dogePath,"-o",dogePath~"modified.gff",
		"--set","Subrace=1",
		"--set","ACRtHip.Tintable.Tint.3.a=42",
		"--set","SkillList.0.Rank=10",
		"--set","FirstName=Hello",
		"--set","Tag=tag_hello"])==0);
	auto gff = new Gff(dogePath~"modified.gff");
	assert(gff["Subrace"].to!int == 1);
	assert(gff["ACRtHip"]["Tintable"]["Tint"]["3"]["a"].to!int == 42);
	assert(gff["SkillList"][0]["Rank"].to!int == 10);
	assert(gff["FirstName"].to!string == "Hello");
	assert(gff["Tag"].to!string == "tag_hello");

	assertThrown!ArgException(_main(["./nwn-gff","-i","nothing.yolo","-o","something.gff"]));
	assert(!"nothing.yolo".exists);
	assert(!"something.gff".exists);


	assert(dogePath.read == dogePathDup.read);
}

