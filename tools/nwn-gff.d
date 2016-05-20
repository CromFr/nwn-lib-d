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
			off.file.rawWrite(gff.toPrettyString());
			break;
		case Format.json:
			off.file.rawWrite(gffToJson(gff, gff.fileType));
			break;
		default:
			assert(0, iff.format.to!string~" serialization not implemented");
	}
	return 0;
}

enum Format{ gff, json, pretty }
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

	assert(_main(["./nwn-gff","--help"])==0);


	immutable krogarFilePathDup = krogarFilePath~".dup.bic";
	assert(_main(["./nwn-gff","-i",krogarFilePath~":gff","-o",krogarFilePathDup~":gff"])==0);
	assert(krogarFilePath.read == krogarFilePathDup.read);


	assert(_main(["./nwn-gff","-i",krogarFilePath,"-o",krogarFilePathDup~":pretty"])==0);
	assert(_main(["./nwn-gff","-i",krogarFilePath~":gff","-o",krogarFilePathDup~":pretty"])==0);
	assertThrown!Error(_main(["./nwn-gff","-i",krogarFilePath~":pretty"]));
}




//I could not find any Json lib in D that keeps node ordering.
auto ref string gffToJson(ref GffNode node, string fileType, bool rootStruct=true){
	import std.traits;

	string gffTypeToJsonType(GffType type){
		import std.string: toLower;
		switch(type) with(GffType){
			case ExoLocString: return "cexolocstr";
			case ExoString: return "cexostr";
			default: return type.to!string.toLower;
		}
	}
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
	else         ret = `{"type":"`~gffTypeToJsonType(node.type)~`",`;

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

}