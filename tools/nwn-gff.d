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
		case Format.json:
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
		case Format.json:
			off.file.rawWrite(gffToJson(gff, gff.fileType));
			break;
		case Format.yaml:
			off.file.rawWrite(gffToYaml(gff));
			break;
		default:
			assert(0, iff.format.to!string~" serialization not implemented");
	}
	return 0;
}

enum Format{ gff, json, yaml, pretty }
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


//I could not find any Json lib in D that keeps node ordering.
auto ref string gffToJson(ref GffNode node, string fileType, bool rootStruct=true){
	import std.traits;

	string escape(in string str){
		string ret;
		foreach(c ; str){
			switch(c){
				case 0x08: ret ~= `\b`; break;
				case 0x0C: ret ~= `\f`; break;
				case '\n': ret ~= `\n`; break;
				case '\r': ret ~= `\r`; break;
				case '\t': ret ~= `\t`; break;
				case '\"': ret ~= `\"`; break;
				case '\\': ret ~= `\\`; break;
				default: ret ~= c;
			}
		}
		return ret;
	}

	if(rootStruct)
		assert(node.type==GffType.Struct);

	string ret;
	if(rootStruct) ret = `{`;
	else         ret = `{"type":"`~gffTypeToStringType(node.type)~`",`;

	typeswitch:
	final switch(node.type) with(GffType){
		foreach(TYPE ; EnumMembers!GffType){
			case TYPE:
			static if(TYPE==Invalid){
				assert(0, "GFF node '"~node.label~"' is of type Invalid and can't be serialized");
			}
			else static if(TYPE==ExoString || TYPE==ResRef){
				ret ~= `"value":"`~escape(node.to!string)~`"`;
				break typeswitch;
			}
			else static if(TYPE==ExoLocString){
				ret ~= `"str_ref":`~node.as!ExoLocString.strref.to!string
						~`,"value":`;

				if(node.as!ExoLocString.strings.length>0){
					ret ~= `{`;
					bool first=true;
					foreach(key, ref value ; node.as!ExoLocString.strings){
						ret ~= (first? null : ",")~`"`~key.to!string~`":"`~escape(value.to!string)~`"`;
						first = false;
					}
					ret ~= `}`;
				}
				else
					ret ~= `{}`;
				break typeswitch;
			}
			else static if(TYPE==Void){
				import std.base64: Base64;
				ret ~= `"value":"`~Base64.encode(cast(ubyte[])node.as!Void)~`"`;
				break typeswitch;
			}
			else static if(TYPE==Struct){
				if(!rootStruct)
					ret ~= `"value":{`;

				size_t index = 0;
				foreach(ref field ; node.as!Struct){
					ret ~= (index++>0? "," : null)~`"`~escape(field.label)~`":`~gffToJson(field, null, false);
				}
				//if(node.structType != typeof(node.structType).max)
					ret ~= (index++>0? "," : null)~`"__struct_id":`~node.structType.to!string;

				if(!rootStruct)
					ret ~= `}`;
				break typeswitch;
			}
			else static if(TYPE==List){
				ret ~= `"value":[`;
				foreach(index, ref field ; node.as!List){
					ret ~= (index>0? "," : null)~gffToJson(field, null, true);
				}
				ret ~= `]`;
				break typeswitch;
			}
			else{
				ret ~= `"value":`~node.to!string;
				break typeswitch;
			}
		}
	}

	if(fileType !is null){
		ret ~= `,"__data_type":"`~fileType~`"`;
	}

	ret ~= `}`;

	return ret;
}

Gff jsonToGff(File stream){
	import std.ascii: isWhite;
	import orderedjson;
	//import std.json;

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
			ret = GffNode(GffType.Struct);
			ret.structType = -1;

			assert(jsonNode.type == JSON_TYPE.OBJECT);
		}
		else
			ret = GffNode(stringTypeToGffType(jsonNode["type"].str), label);


		final switch(ret.type) with(GffType){
			case Invalid: assert(0);

			case Byte,Char,Word,Short,DWord,Int,DWord64,Int64:
				auto value = &jsonNode["value"];
				if(value.type == JSON_TYPE.UINTEGER)
					ret = value.uinteger;
				else if(value.type == JSON_TYPE.INTEGER)
					ret = value.integer;
				else
					assert(0, "Type "~value.type.to!string~" is not convertible to GffType."~ret.type.to!string);
				break;

			case Float,Double:
				auto value = &jsonNode["value"];
				if(value.type == JSON_TYPE.UINTEGER)
					ret = value.uinteger;
				else if(value.type == JSON_TYPE.INTEGER)
					ret = value.integer;
				else if(value.type == JSON_TYPE.FLOAT)
					ret = value.floating;
				break;

			case ExoString,ResRef:
				ret = jsonNode["value"].str;
				break;

			case ExoLocString:
				alias Type = gffTypeToNative!ExoLocString;
				ret = jsonNode["str_ref"].integer;

				typeof(Type.strref) strings;
				foreach(string key, ref str ; jsonNode["value"]){

					auto id = key.to!(typeof(Type.strings.keys[0]));
					ret.as!ExoLocString.strings[id] = str.str;
				}
				break;

			case Void:
				import std.base64: Base64;
				ret = Base64.decode(jsonNode["value"].str);
				break;

			case Struct:
				JSONValue* jsonValue;
				if(baseStructNode) jsonValue = &jsonNode;
				else               jsonValue = &jsonNode["value"];

				auto structId = "__struct_id" in *jsonValue;
				if(structId !is null)
					ret.structType = cast(typeof(ret.structType))structId.integer;

				assert(jsonValue.type==JSON_TYPE.OBJECT, "Struct is not a Json Object");

				foreach(ref key ; jsonValue.objectKeyOrder){
					if(key.length<2 || key[0..2]!="__")
						ret.appendField(buildGff((*jsonValue)[key], key));
				}
				ret.updateFieldLabelMap();
				break;
			case List:
				foreach(ref node ; jsonNode["value"].array){
					assert(node.type==JSON_TYPE.OBJECT, "Array element is not a Json Object");
					ret.as!List ~= buildGff(node, null, true);
				}
				break;
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



string gffToYaml(Gff gff){

	import yaml;

	Node gffNodeToYaml(ref GffNode gffNode){

		Node ret;

		typeswitch:
		final switch(gffNode.type) with(GffType){
			foreach(TYPE ; EnumMembers!GffType){
				case TYPE:
				static if(TYPE==Invalid)
					assert(0);
				else static if(TYPE==ExoLocString){
					ret = Node([
							"strref": Node(gffNode.as!ExoLocString.strref),
							"strings": Node(gffNode.as!ExoLocString.strings),
						], gffTypeToStringType(TYPE));
					break typeswitch;
				}
				else static if(TYPE==Void){
					import std.base64: Base64;
					string value = Base64.encode(cast(ubyte[])gffNode.as!Void);
					ret = Node(value, gffTypeToStringType(TYPE));
					break typeswitch;
				}
				else static if(TYPE==Struct){
					Node[string] map;
					foreach(ref node ; gffNode.as!Struct){
						map[node.label] = gffNodeToYaml(node);
					}
					ret = Node(map, gffTypeToStringType(TYPE)~":"~gffNode.structType.to!string);
					break typeswitch;
				}
				else static if(TYPE==List){
					ret = Node(0, gffTypeToStringType(TYPE));
					//Node[] list;
					//foreach(ref node ; gffNode.as!List){
					//	list ~= gffNodeToYaml(node);
					//}
					//ret = Node(list, gffTypeToStringType(TYPE));
					break typeswitch;
				}
				else{
					ret = Node(gffNode.as!TYPE, gffTypeToStringType(TYPE));
					break typeswitch;
				}

			}
		}

		return ret;
	}

	import dyaml.stream: YMemoryStream;
	auto stream = new YMemoryStream();

	Dumper(stream).dump(gffNodeToYaml(gff.firstNode));



	return (cast(char[])stream.data).to!string;
}