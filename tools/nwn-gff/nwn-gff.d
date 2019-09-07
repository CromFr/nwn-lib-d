/// Authors: Thibaut CHARLES (Crom) cromfr@gmail.com
/// License: GPL-3.0
/// Copyright: Copyright Thibaut CHARLES 2016

module tools.nwngff;

import std.stdio;
import std.conv: to, ConvException;
import std.traits;
import std.string;
import std.typecons: Tuple, Nullable;
version(unittest) import std.exception: assertThrown, assertNotThrown;

import tools.common.getopt;
import nwn.gff;


class ArgException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

int main(string[] args){
	version(unittest) if(args.length <= 1) return 0;

	string inputPath, outputPath;
	Format inputFormat = Format.detect, outputFormat = Format.detect;
	string[] setValuesList;
	auto res = getopt(args,
		"i|input", "Input file", &inputPath,
		"j|input-format", "Input file format ("~EnumMembers!Format.stringof[6..$-1]~")", &inputFormat,
		"o|output", "<file>:<format> Output file and format", &outputPath,
		"k|output-format", "Output file format ("~EnumMembers!Format.stringof[6..$-1]~")", &outputFormat,
		"s|set", "Set values in the GFF file. See section SET and PATH.\nEx: 'DayNight.7.SkyDomeModel=my_sky_dome.tga'", &setValuesList,
		);
	if(res.helpWanted){
		improvedGetoptPrinter(
			 "Parsing and serialization tool for GFF files like ifo, are, bic, uti, ...",
			res.options,
			 "===== Section SET =====\n"
			~"The --set argument folows this scheme: Path=Value\n"
			~"Path is explained in the PATH section\n"
			~"Value is converted to the type of the field selected by Path\n"
			~"If Path leads to a Struct or a List field, Value will be parsed as Json and converted to the field type\n"
			~"The Json format used in this case is similar to the format output with --output-format=json.\n"
			~"ex: {\"type\": \"struct\",\"value\":{\"Name\":{\"type\":\"cexostr\",\"value\":\"tk_item_dropped\"}}}\n"
			~"\n"
			~"===== Section PATH =====\n"
			~"A GFF path is a succession of path elements separated by points:\n"
			~"ex: 'VarTable.2.Name', 'DayNight.7.SkyDomeModel', ...\n"
			~"Path element types:\n"
			~"- Any string: If parent is a struct, will select matching child field\n"
			~"- Any integer: If parent is a list, will select Nth child struct\n"
			~"- 'FieldName:FieldType': If parent is a struct, will add a child field named 'FieldName' of type 'FieldType'. 'FieldType' can be any of: byte char word short dword int dword64 int64 float double cexostr resref cexolocstr void struct list\n"
			~"- '$-42': If parent is a list, '$' is replaced by the list length, allowing to access last children of the list\n"
			~"- '$': Will add a child at the end of the list"
			);
		return 1;
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


	//Special cases where FastGFF can be used
	if(inputFormat == Format.gff && outputFormat == Format.pretty && setValuesList.length == 0){
		import nwn.fastgff: FastGff;

		File inputFile = inputPath is null? stdin : File(inputPath, "r");
		auto gff = new FastGff(inputFile.readAll);

		File outputFile = outputPath is null? stdout : File(outputPath, "w");
		outputFile.rawWrite(gff.toPrettyString());
		return 0;
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
			gff = Gff.fromJson(parseJSON(cast(string)inputFile.readAll.idup));
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
		foreach(i, p ; path){
			if(node.type == GffType.Struct){
				auto typesep = p.indexOf(':');
				auto key = typesep == -1 ? p : p[0 .. typesep];

				if(typesep >= 0){
					static GffType stringTypeToGffType(string type){
						import std.string: toLower;
						switch(type) with(GffType){
							case "byte":         return GffType.Byte;
							case "char":         return GffType.Char;
							case "word":         return GffType.Word;
							case "short":        return GffType.Short;
							case "dword":        return GffType.DWord;
							case "int":          return GffType.Int;
							case "dword64":      return GffType.DWord64;
							case "int64":        return GffType.Int64;
							case "float":        return GffType.Float;
							case "double":       return GffType.Double;
							case "cexostr":      return GffType.ExoString;
							case "resref":       return GffType.ResRef;
							case "cexolocstr":   return GffType.ExoLocString;
							case "void":         return GffType.Void;
							case "struct":       return GffType.Struct;
							case "list":         return GffType.List;
							default: throw new GffJsonParseException("Unknown Gff type string: '"~type~"'");
						}
					}

					GffType type;
					try type = stringTypeToGffType(p[typesep + 1 .. $]);
					catch(ConvException e){
						e.msg = "Cannot convert '"~p[typesep + 1 .. $]~"' to GffType at path "~path[0 .. i+1].join(".")~" for argument --set='"~setValue~"': " ~ e.msg;
						throw e;
					}
					node.as!(GffType.Struct)[key] = GffNode(type, key);
				}

				try node = &(*node)[key];
				catch(Exception e){
					e.msg = e.msg~" at path "~path[0 .. i+1].join(".")~" in argument --set='"~setValue~"'";
					throw e;
				}
			}
			else if(node.type == GffType.List){
				size_t idx;

				if(p == "$"){
					idx = node.as!(GffType.List).length;
					// Append empty node
					node.as!(GffType.List) ~= GffNode(GffType.Struct);
				}
				else if(p[0] == '$'){
					try idx = node.as!(GffType.List).length + p[1 .. $].to!int;
					catch(ConvException e){
						e.msg = "Cannot convert '"~p~"' to int in "~path[0 .. i+1].join(".")~" for argument --set='"~setValue~"'" ~ e.msg;
						throw e;
					}
				}
				else{
					try idx = p.to!size_t;
					catch(ConvException e){
						e.msg = "Cannot convert '"~p~"' to uint in "~path[0 .. i+1].join(".")~" for argument --set='"~setValue~"'" ~ e.msg;
						throw e;
					}
				}

				try node = &(*node)[idx];
				catch(Exception e)
					throw new Exception(e.msg~" at path "~path[0 .. i+1].join(".")~" for argument --set='"~setValue~"'");
			}
			else
				throw new Exception("Node "~path[0 .. i].join(".")~" is a "~node.type.to!string~" for argument --set='"~setValue~"'");
		}

		typeswitch:
		final switch(node.type) with(GffType){
			static foreach(TYPE ; EnumMembers!GffType){
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
					import nwnlibd.orderedjson;
					JSONValue json;
					try json = value.parseJSON;
					catch(Exception e){
						e.msg = "Cannot parse value to set as JSON: " ~ e.msg;
						throw e;
					}
					*node = GffNode.fromJson(json, null);
					break typeswitch;
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
		case ".cam"://campaign files
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

ubyte[] readAll(File stream){
	ubyte[] data;
	ubyte[500] buf;

	size_t prevLength;
	do{
		prevLength = data.length;
		data ~= stream.rawRead(buf);
	}while(data.length != prevLength);

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
	assert(main(["./nwn-gff","--help"])==1);
	stdout = stdout_;


	immutable krogarFilePathDup = krogarFilePath~".dup.bic";
	assert(main(["./nwn-gff","-i",krogarFilePath,"-o",krogarFilePathDup])==0);
	assert(krogarFilePath.read == krogarFilePathDup.read);


	assert(main(["./nwn-gff","-i",krogarFilePath,"-o",krogarFilePathDup, "-k","pretty"])==0);
	assert(main(["./nwn-gff","-i",krogarFilePath,"-o",krogarFilePathDup, "-k","pretty"])==0);
	assertThrown!Error(main(["./nwn-gff","-i",krogarFilePath, "-j","pretty"]));


	auto dogeData = cast(ubyte[])import("doge.utc");
	immutable dogePath = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__~".doge.utc");
	dogePath.writeFile(dogeData);

	immutable dogePathJson = dogePath~".json";
	immutable dogePathDup = dogePath~".dup.utc";


	assert(main(["./nwn-gff","-i",dogePath,"-o",dogePathJson])==0);
	assert(main(["./nwn-gff","-i",dogePathJson,"-o",dogePathDup])==0);


	assert(main(["./nwn-gff","-i",dogePath,"-o",dogePath~"modified.gff",
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

	assertThrown!ArgException(main(["./nwn-gff","-i","nothing.yolo","-o","something.gff"]));
	assert(!"nothing.yolo".exists);
	assert(!"something.gff".exists);


	assert(dogePath.read == dogePathDup.read);


	// set struct / lists operations
	dogePath.writeFile(dogeData);
	assert(main([
		"./nwn-gff","-i",dogePath, "-o",dogePathDup,
		"--set", `VarTable.$={"type": "struct","value":{"Name":{"type":"cexostr","value":"tk_item_dropped"},"Type":{"type":"dword","value":1},"Value":{"type":"int","value":1}}}`,
		"--set", `ModelScale.Yolo:int=42`
	])==0);
	gff = new Gff(dogePathDup);
	assert(gff["VarTable"].as!(GffType.List).length == 1);
	assert(gff["VarTable"][0]["Name"].as!(GffType.ExoString) == "tk_item_dropped");
	assert(gff["VarTable"][0]["Type"].as!(GffType.DWord) == 1);

	assert(gff["ModelScale"]["Yolo"].as!(GffType.Int) == 42);

}

