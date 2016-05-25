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
			off.file.rawWrite(gffToJson(gff, iff.format==Format.json));
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

string gffTypeToStringType(GffType type){
	import std.string: toLower;
	switch(type) with(GffType){
		case ExoLocString: return "cexolocstr";
		case ExoString: return "cexostr";
		default: return type.to!string.toLower;
	}
}
GffType stringTypeToGffType(string type){
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
		default: assert(0, "Unknown Gff type string: '"~type~"'");
	}
}




string gffToJson(Gff gff, bool pretty){
	import orderedjson;


	auto ref JSONValue buildJsonNode(ref GffNode node, bool topLevelStruct=false){
		JSONValue ret = cast(JSONValue[string])null;

		if(!topLevelStruct)
			ret["type"] = gffTypeToStringType(node.type);

		typeswitch:
		final switch(node.type) with(GffType){
			foreach(TYPE ; EnumMembers!GffType){
				case TYPE:
				static if(TYPE==Invalid){
					assert(0, "GFF node '"~node.label~"' is of type Invalid and can't be serialized");
				}
				else static if(TYPE==ExoLocString){
					ret["str_ref"] = node.as!ExoLocString.strref;
					ret["value"] = JSONValue();
					foreach(strref, str ; node.as!ExoLocString.strings)
						ret["value"][strref.to!string] = str;
					break typeswitch;
				}
				else static if(TYPE==Void){
					import std.base64: Base64;
					ret["value"] = JSONValue(Base64.encode(cast(ubyte[])node.as!Void));
					break typeswitch;
				}
				else static if(TYPE==Struct){
					JSONValue* value;
					ret["__struct_id"] = JSONValue(node.structType);

					if(!topLevelStruct) {
						ret["value"] = JSONValue();
						value = &ret["value"];
					}
					else
						value = &ret;

					foreach(ref child ; node.as!Struct){
						(*value)[child.label] = buildJsonNode(child);
					}
					break typeswitch;
				}
				else static if(TYPE==List){
					auto value = cast(JSONValue[])null;
					foreach(i, ref child ; node.as!List){
						value ~= buildJsonNode(child, true);
					}
					ret["value"] = value;
					break typeswitch;
				}
				else{
					ret["value"] = node.as!TYPE;
					break typeswitch;
				}
			}
		}
		return ret;
	}

	auto json = buildJsonNode(gff.firstNode, true);
	json["__data_type"] = JSONValue(gff.fileType);

	if(pretty)
		return json.toPrettyString;
	return json.toString;
}

Gff jsonToGff(File stream){
	import std.traits: isIntegral, isFloatingPoint;
	import orderedjson;

	GffNode ret = GffNode(GffType.Invalid);
	GffNode*[] nodeStack = [&ret];

	string data;
	char[500] buf;
	char[] dataRead;

	do{
		dataRead = stream.rawRead(buf);
		data ~= dataRead;
	}while(dataRead.length>0);


	auto ref GffNode buildGff(ref JSONValue jsonNode, string label, bool baseStructNode=false){
		GffNode ret;
		if(baseStructNode){
			assert(jsonNode.type == JSON_TYPE.OBJECT);

			ret = GffNode(GffType.Struct);
			ret.structType = -1;
		}
		else{
			assert(jsonNode.type == JSON_TYPE.OBJECT);
			ret = GffNode(stringTypeToGffType(jsonNode["type"].str), label);
		}

		typeswitch:
		final switch(ret.type) with(GffType){
			foreach(TYPE ; EnumMembers!GffType){
				case TYPE:
				static if(TYPE==Invalid)
					assert(0);
				else static if(isIntegral!(gffTypeToNative!TYPE)){
					auto value = &jsonNode["value"];
					if(value.type == JSON_TYPE.UINTEGER)
						ret = value.uinteger;
					else if(value.type == JSON_TYPE.INTEGER)
						ret = value.integer;
					else
						assert(0, "Type "~value.type.to!string~" is not convertible to GffType."~ret.type.to!string);
					break typeswitch;
				}
				else static if(isFloatingPoint!(gffTypeToNative!TYPE)){
					auto value = &jsonNode["value"];
					if(value.type == JSON_TYPE.UINTEGER)
						ret = value.uinteger;
					else if(value.type == JSON_TYPE.INTEGER)
						ret = value.integer;
					else if(value.type == JSON_TYPE.FLOAT)
						ret = value.floating;
					break typeswitch;
				}
				else static if(TYPE==ExoString || TYPE==ResRef){
					ret = jsonNode["value"].str;
					break typeswitch;
				}
				else static if(TYPE==ExoLocString){
					alias Type = gffTypeToNative!ExoLocString;
					ret = jsonNode["str_ref"].integer;

					typeof(Type.strref) strings;
					if(!jsonNode["value"].isNull){
						foreach(string key, ref str ; jsonNode["value"]){

							auto id = key.to!(typeof(Type.strings.keys[0]));
							ret.as!ExoLocString.strings[id] = str.str;
						}
					}
					break typeswitch;
				}
				else static if(TYPE==Void){
					import std.base64: Base64;
					ret = Base64.decode(jsonNode["value"].str);
					break typeswitch;
				}
				else static if(TYPE==Struct){
					JSONValue* jsonValue = baseStructNode? &jsonNode : &jsonNode["value"];

					auto structId = "__struct_id" in *jsonValue;
					if(structId !is null)
						ret.structType = structId.integer.to!(typeof(ret.structType));

					assert(jsonValue.type==JSON_TYPE.OBJECT, "Struct is not a Json Object");

					foreach(ref key ; jsonValue.objectKeyOrder){
						if(key.length<2 || key[0..2]!="__")
							ret.appendField(buildGff((*jsonValue)[key], key));
					}
					ret.updateFieldLabelMap();
					break typeswitch;
				}
				else static if(TYPE==List){
					foreach(ref node ; jsonNode["value"].array){
						assert(node.type==JSON_TYPE.OBJECT, "Array element is not a Json Object");
						ret.as!List ~= buildGff(node, null, true);
					}
					break typeswitch;
				}
			}
		}

		return ret;
	}
	auto json = parseJSON(data);

	auto gff = new Gff;
	gff.firstNode = buildGff(json, null, true);
	gff.fileType = json["__data_type"].str;
	gff.fileVersion = "V3.2";

	return gff;
}


