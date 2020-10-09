/// Authors: Thibaut CHARLES (Crom) cromfr@gmail.com
/// License: GPL-3.0
/// Copyright: Copyright Thibaut CHARLES 2016

module tools.nwngff;

import std.stdio;
import std.conv: to, ConvException;
import std.traits;
import std.string;
import std.exception: enforce;
import std.base64: Base64;
import std.algorithm: remove;
import std.typecons: Tuple, Nullable, tuple;
version(unittest) import std.exception: assertThrown, assertNotThrown;

import tools.common.getopt;
import nwn.gff;
import nwnlibd.orderedjson;


class ArgException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
class GffPathException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

int main(string[] args){
	version(unittest) if(args.length <= 1) return 0;

	string inputPath, outputPath;
	Format inputFormat = Format.detect, outputFormat = Format.detect;
	string[] setValuesList;
	string[] removeValuesList;
	bool cleanLocale = false;
	auto res = getopt(args,
		"i|input", "Input file", &inputPath,
		"j|input-format", "Input file format ("~EnumMembers!Format.stringof[6..$-1]~")", &inputFormat,
		"o|output", "<file>:<format> Output file and format", &outputPath,
		"k|output-format", "Output file format ("~EnumMembers!Format.stringof[6..$-1]~")", &outputFormat,
		"s|set", "Set values in the GFF file. See section SET and PATH.\nEx: 'DayNight.7.SkyDomeModel=my_sky_dome.tga'", &setValuesList,
		"r|remove", "Removes a GFF node. See section PATH.\nEx: 'DayNight.7.SkyDomeModel'", &removeValuesList,
		"locale-clean", "Remove empty values from localized strings.\n", &cleanLocale,
		);
	if(res.helpWanted){
		improvedGetoptPrinter(
			 "Parsing and serialization tool for GFF files like ifo, are, bic, uti, ...",
			res.options,
			 "===== Setting values =====\n"
			~"There are 3 ways to set a GFF value:\n"
			~"\n"
			~"--set <path_to_node>=<node_value>\n"
			~"    Sets the value of an existing GFF node, without changing its type\n"
			~"    Ex: --set 'ItemList.0.Tag=test-tag'\n"
			~"--set <path_to_node>:<node_type>=<node_value>\n"
			~"    Sets the value and type of a GFF node, creating it if does not exist.\n"
			~"    Structs and Lists cannot be set using this technique.\n"
			~"    Ex: --set 'ItemList.0.Tag:cexostr=test-tag'\n"
			~"--set <path_to_node>:json=<json_value>\n"
			~"    Sets the value and type of a GFF node using a JSON object.\n"
			~"    Ex: --set 'ItemList.0.Tag:json={\"type\": \"cexostr\", \"value\": \"test-tag\"}'\n"
			~"\n"
			~"<path_to_node> Dot-separated path to the node to set (see section PATH)\n"
			~"<node_type>    GFF type. Any of byte, char, word, short, dword, int, dword64, int64, float, double, cexostr, resref, cexolocstr, void\n"
			~"<node_value>   GFF value.\n"
			~"               'void' values must be encoded in base64.\n"
			~"               'cexolocstr' values can be either an integer (sets the resref) or a string (sets the english string).\n"
			~"<json_value>   GFF JSON value, as represented in .\n"
			~"\n"


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
			gff = new Gff(parseJSON(cast(string)inputFile.readAll.idup));
			break;
		case Format.pretty:
			assert(0, inputFormat.to!string~" parsing not supported");
		default:
			assert(0, inputFormat.to!string~" parsing not implemented");
	}
	inputFile.close();

	// Returns a pointer to the GFF node pointed by path
	auto getGffNode(in string[] path, bool write){
		void* node = &gff.root;
		GffType nodeType = GffType.Struct;
		foreach(i, string nextName ; path){
			GffType targetType = GffType.Invalid;
			auto col = nextName.lastIndexOf(':');
			if(col >= 0){
				targetType = compatStrToGffType(nextName[col + 1 .. $]);
				enforce!GffPathException(targetType != GffType.Invalid, "Unknown GFF type string: " ~ nextName[col + 1 .. $]);
				nextName = nextName[0 .. col];
			}

			if(nodeType == GffType.Struct){
				auto gffStruct = cast(GffStruct*)node;

				if(auto next = (nextName in *gffStruct)){
					// Select labeled value
					if(targetType != GffType.Invalid){
						// Change node type
						enforce!GffPathException(write, format!"Node %s is not of type %s"(path[0 .. i + 1].join('.'), targetType));

						if(i + 1 == path.length){
							// Only allow changing the type of the last node in path
							*next = GffValue(targetType);
						}
						else
							enforce!GffPathException(next.type == targetType,
								format!"Type mismatch for node %s of type %s versus provided type %s"(path[0 .. i + 1].join('.'), next.type, targetType)
							);
					}

					node = next;
					nodeType = next.type;
				}
				else if(write && targetType != GffType.Invalid){
					// Insert new value
					final switch(targetType) with(GffType) {
						case Byte:      node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffByte(); break;
						case Char:      node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffChar(); break;
						case Word:      node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffWord(); break;
						case Short:     node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffShort(); break;
						case DWord:     node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffDWord(); break;
						case Int:       node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffInt(); break;
						case DWord64:   node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffDWord64(); break;
						case Int64:     node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffInt64(); break;
						case Float:     node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffFloat(); break;
						case Double:    node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffDouble(); break;
						case String:    node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffString(); break;
						case ResRef:    node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffResRef(); break;
						case LocString: node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffLocString(); break;
						case Void:      node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffVoid(); break;
						case Struct:    node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffStruct(); break;
						case List:      node = &((*gffStruct)[nextName] = GffValue(targetType)).get!GffList(); break;
						case Invalid: assert(0);
					}
					//node = &((*gffStruct)[nextName] = GffValue(targetType));

					assert(nextName in *gffStruct);

					nodeType = targetType;
				}
				else
					throw new GffPathException(format!"Node '%s' does not exist in %s"(nextName, path[0 .. i].join('.')));
			}
			else if(nodeType == GffType.List){
				enforce!GffPathException(targetType == GffType.Invalid || targetType == GffType.Struct,
					format!"Node %s is a list and can only contain struct children"(path[0 .. i].join('.'))
				);
				auto gffList = cast(GffList*)node;

				if(nextName == "$"){
					// Append to list
					(*gffList) ~= GffStruct();
					node = &(*gffList)[$ - 1];
					nodeType = GffType.Struct;
				}
				else{
					size_t index = 0;
					try{
						if(nextName[0] == '$')
							index = (gffList.length + nextName[1 .. $].to!int).to!size_t;
						else
							index += nextName.to!size_t;
					}
					catch(ConvException e){
						e.msg = format!"Node %s is a list, and '%s' is not a valid index: %s"(path[0 .. i].join('.'), nextName, e.msg);
						throw e;
					}

					enforce!GffPathException(index < gffList.length,
						format!"Node %s is a list, and index %d is out of bounds"(path[0 .. i], index)
					);

					node = &(*gffList)[index];
					nodeType = GffType.Struct;
				}
			}
			else
				throw new Exception(format!"Node %s is a %s, and cannot contain any children"(path[0 .. i].join('.'), nodeType.gffTypeToCompatStr()));
		}

		return tuple(nodeType, node);
	}


	//Modifications
	foreach(setValue ; setValuesList){
		auto eq = setValue.indexOf('=');
		assert(eq >= 0, "--set value must contain a '=' character");
		string pathWithType = setValue[0 .. eq];

		string[] path = pathWithType.split(".");
		string value = setValue[eq + 1 .. $];
		bool valueIsJson = false;
		JSONValue jsonValue;

		auto col = path[$ - 1].lastIndexOf(':');
		if(col >= 0){
			// Last path element has a defined type
			if(path[$ - 1][col + 1 .. $] == "json"){
				// set value is in JSON format
				valueIsJson = true;
				jsonValue = value.parseJSON;
				enforce!GffPathException(jsonValue.type == JSON_TYPE.OBJECT, "JSON values must be an objects");
				enforce!GffPathException("type" in jsonValue, "JSON object must contain a \"type\" key");
				const type = jsonValue["type"].str;
				path[$ - 1] = path[$ - 1][0 .. col + 1] ~ type;
			}
		}

		auto node = getGffNode(path, true);
		auto gffType = node[0];
		auto gffNode = node[1];

		if(valueIsJson){
			final switch(gffType) with(GffType) {
				case Byte:      (*cast(GffByte*)      gffNode) = GffValue(jsonValue).get!GffByte;      break;
				case Char:      (*cast(GffChar*)      gffNode) = GffValue(jsonValue).get!GffChar;      break;
				case Word:      (*cast(GffWord*)      gffNode) = GffValue(jsonValue).get!GffWord;      break;
				case Short:     (*cast(GffShort*)     gffNode) = GffValue(jsonValue).get!GffShort;     break;
				case DWord:     (*cast(GffDWord*)     gffNode) = GffValue(jsonValue).get!GffDWord;     break;
				case Int:       (*cast(GffInt*)       gffNode) = GffValue(jsonValue).get!GffInt;       break;
				case DWord64:   (*cast(GffDWord64*)   gffNode) = GffValue(jsonValue).get!GffDWord64;   break;
				case Int64:     (*cast(GffInt64*)     gffNode) = GffValue(jsonValue).get!GffInt64;     break;
				case Float:     (*cast(GffFloat*)     gffNode) = GffValue(jsonValue).get!GffFloat;     break;
				case Double:    (*cast(GffDouble*)    gffNode) = GffValue(jsonValue).get!GffDouble;    break;
				case String:    (*cast(GffString*)    gffNode) = GffValue(jsonValue).get!GffString;    break;
				case ResRef:    (*cast(GffResRef*)    gffNode) = GffValue(jsonValue).get!GffResRef;    break;
				case LocString: (*cast(GffLocString*) gffNode) = GffValue(jsonValue).get!GffLocString; break;
				case Void:      (*cast(GffVoid*)      gffNode) = GffValue(jsonValue).get!GffVoid;      break;
				case Struct:    (*cast(GffStruct*)    gffNode) = GffValue(jsonValue).get!GffStruct;    break;
				case List:      (*cast(GffList*)      gffNode) = GffValue(jsonValue).get!GffList;      break;
				case Invalid: assert(0);
			}
		}
		else{
			final switch(gffType) with(GffType) {
				case Byte:      (*cast(GffByte*)      gffNode) = value.to!GffByte;     break;
				case Char:      (*cast(GffChar*)      gffNode) = value.to!GffChar;     break;
				case Word:      (*cast(GffWord*)      gffNode) = value.to!GffWord;     break;
				case Short:     (*cast(GffShort*)     gffNode) = value.to!GffShort;    break;
				case DWord:     (*cast(GffDWord*)     gffNode) = value.to!GffDWord;    break;
				case Int:       (*cast(GffInt*)       gffNode) = value.to!GffInt;      break;
				case DWord64:   (*cast(GffDWord64*)   gffNode) = value.to!GffDWord64;  break;
				case Int64:     (*cast(GffInt64*)     gffNode) = value.to!GffInt64;    break;
				case Float:     (*cast(GffFloat*)     gffNode) = value.to!GffFloat;    break;
				case Double:    (*cast(GffDouble*)    gffNode) = value.to!GffDouble;   break;
				case String:    (*cast(GffString*)    gffNode) = value;                break;
				case ResRef:    (*cast(GffResRef*)    gffNode) = value;                break;
				case LocString: (*cast(GffLocString*) gffNode) = value;                break;
				case Void:      (*cast(GffVoid*)      gffNode) = Base64.decode(value); break;
				case Struct:    assert(0, "Use JSON format for setting value of type struct");
				case List:      assert(0, "Use JSON format for setting value of type list");
				case Invalid:   assert(0);
			}
		}
	}

	//Value removal
	foreach(rmValue ; removeValuesList){
		string[] path = rmValue.split(".");

		auto parent = getGffNode(path[0 .. $ - 1], false);
		auto parentType = parent[0];
		auto parentNode = parent[1];

		string lastName = path[$ - 1];
		GffType lastType = GffType.Invalid;

		auto col = lastName.lastIndexOf(':');
		if(col >= 0){
			lastType = lastName[col + 1 .. $].compatStrToGffType;
			lastName = lastName[0 .. col];
		}

		switch(parentType) with(GffType) {
			case Struct:
				auto gffStruct = cast(GffStruct*)parentNode;
				enforce!GffPathException(lastName in *gffStruct,
					format!"Node %s cannot be found in struct %s"(lastName, path[0 .. $ - 1])
				);
				if(auto val = lastName in *gffStruct){
					enforce!GffPathException(lastType == Invalid || lastType == val.type,
						format!"Type mismatch: %s is of type %s, not %s"(path.join("."), val.type, lastType)
					);
					gffStruct.remove(lastName);
				}
				else
					throw new GffPathException(format!"Node %s does not exist"(path.join(".")));
				break;
			case List:
				auto gffList = cast(GffList*)parentNode;
				size_t index = 0;
				try{
					if(lastName[0] == '$')
						index = (gffList.length + lastName[1 .. $].to!int).to!size_t;
					else
						index += lastName.to!size_t;
				}
				catch(ConvException e){
					e.msg = format!"Node %s is a list, and '%s' is not a valid index: %s"(path[0 .. $ - 1].join('.'), lastName, e.msg);
					throw e;
				}

				enforce!GffPathException(index < gffList.length,
					format!"Node %s is a list, and index %d is out of bounds"(path[0 .. $ - 1], index)
				);
				enforce!GffPathException(lastType == Invalid || lastType == Struct,
					format!"Type mismatch: %s is of type %s, not %s"(path.join("."), GffType.Struct, lastType)
				);

				gffList.children = gffList.children.remove(index);
				break;
			default:
				throw new GffPathException(format!"Node %s of type %s cannot contain any children"(path[0 .. $ - 1].join("."), parentType));
		}
	}


	if(cleanLocale){

		static void cleanGffLocale(T)(ref T value){
			static if(is(T: GffValue)){
				switch(value.type) with(GffType){
					case LocString:
						with(value.get!GffLocString){
							foreach(k ; strings.keys){
								if(strings[k] == ""){
							 		strings.remove(k);
								}
							}
						}
						break;
					case Struct:
						cleanGffLocale(value.get!GffStruct);
						break;
					case List:
						cleanGffLocale(value.get!GffList);
						break;
					default:
						break;
				}
			}
			else static if(is(T: GffStruct)){
				foreach(ref GffValue innerValue ; value){
					cleanGffLocale(innerValue);
				}
			}
			else static if(is(T: GffList)){
				foreach(ref GffStruct innerStruct ; value){
					cleanGffLocale(innerStruct);
				}
			}
		}

		cleanGffLocale(gff.root);
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


	// Simple modifications
	assert(main(["./nwn-gff","-i",dogePath,"-o",dogePath~"modified.gff",
		"--set","Subrace=1",
		"--set","ACRtHip.Tintable.Tint.3.a=42",
		"--set","SkillList.0.Rank=10",
		"--set","FirstName=Hello",
		"--set","Tag=tag_hello",
		"--remove","LastName",
		"--remove","FeatList.0",
		])==0);
	auto gff = new Gff(dogePath~"modified.gff");
	assert(gff["Subrace"].to!int == 1);
	assert(gff["ACRtHip"]["Tintable"]["Tint"]["3"]["a"].to!int == 42);
	assert(gff["SkillList"][0]["Rank"].to!int == 10);
	assert(gff["FirstName"].to!string == "Hello");
	assert(gff["Tag"].to!string == "tag_hello");
	assert("LastName" !in gff);
	assert(gff["FeatList"][0]["Feat"].get!GffWord == 354);

	// Type mismatch
	assertThrown!GffPathException(main(["./nwn-gff","-i",dogePath,"-o",dogePath~"modified.gff",
		"--set","SkillList:struct.0.Rank=10"]));

	// Cannot create node without type
	assertThrown!GffPathException(main(["./nwn-gff","-i",dogePath,"-o",dogePath~"modified.gff",
		"--set","NewNode=hello"]));

	assertThrown!ArgException(main(["./nwn-gff","-i","nothing.yolo","-o","something.gff"]));
	assert(!"nothing.yolo".exists);
	assert(!"something.gff".exists);


	assert(dogePath.read == dogePathDup.read);


	// set struct / lists operations
	dogePath.writeFile(dogeData);
	assert(main([
		"./nwn-gff","-i",dogePath, "-o",dogePathDup,
		"--set", `VarTable.$:json={"type": "struct","value":{"Name":{"type":"cexostr","value":"tk_item_dropped"},"Type":{"type":"dword","value":1},"Value":{"type":"int","value":1}}}`,
		"--set", `ModelScale.Yolo:int=42`
	])==0);
	gff = new Gff(dogePathDup);
	assert(gff["VarTable"].get!GffList.length == 1);
	assert(gff["VarTable"][0]["Name"].get!GffString == "tk_item_dropped");
	assert(gff["VarTable"][0]["Type"].get!GffDWord == 1);

	assert(gff["ModelScale"]["Yolo"].get!GffInt == 42);

}

