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
import std.algorithm;
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

template multilineStr(string s){
	enum multilineStr = (){
		auto lines = s.splitLines();
		assert(lines[0].strip == "", "First line must be empty");
		assert(lines.length > 1, "Not enough lines");

		const tabLen = lines[1].length - lines[1].stripLeft.length;
		const tab = lines[1][0 .. tabLen];

		return lines[1 .. $]
			.map!((l){
				if(l.strip.length == 0)
					return "";
				assert(l[0 .. tabLen] == tab, "Tab mismatch on line '" ~ l ~ "'");
				return l[tabLen .. $];
			})
			.join("\n");
	}();
}

int main(string[] args){
	string inputPath, outputPath;
	Format inputFormat = Format.detect, outputFormat = Format.detect;
	string[] setValuesList;
	string[] setLocVars;
	string[] removeValuesList;
	bool cleanLocale = false;
	bool printVersion = false;
	auto res = getopt(args,
		"i|input", "Input file. '-' to read from stdin. Provided for compatibility with Niv GFF tool.", &inputPath,
		"j|input-format", "Input file format ("~EnumMembers!Format.stringof[6..$-1]~")", &inputFormat,
		"o|output", "Output file. Defaults to stdout.", &outputPath,
		"k|output-format", "Output file format ("~EnumMembers!Format.stringof[6..$-1]~")", &outputFormat,
		"s|set", "Set or add nodes in the GFF file. See section 'Setting nodes'.\nEx: 'DayNight.7.SkyDomeModel=my_sky_dome.tga'", &setValuesList,
		"r|remove", "Removes a GFF node with the given node path. See section 'Node paths'.\nEx: 'DayNight.7.SkyDomeModel'", &removeValuesList,
		"clean-locstr", "Remove empty values from localized strings.\n", &cleanLocale,
		"set-locvar", "Sets the local variable to a specific value. ", &setLocVars,
		"version", "Print nwn-lib-d version and exit.\n", &printVersion,
	);
	if(res.helpWanted){
		improvedGetoptPrinter(
			"Parsing and serialization tool for GFF files like ifo, are, bic, uti, ...",
			res.options,
			multilineStr!`
				===== Setting nodes =====
				There are 3 ways to set a GFF value:

				--set <node_path>=<node_value>
				    Sets the value of an existing GFF node, without changing its type
				    Ex: --set 'ItemList.0.Tag=test-tag'
				--set <node_path>:<node_type>=<node_value>
				    Sets the value and type of a GFF node, creating it if does not exist.
				    Structs and Lists cannot be set using this technique.
				    Ex: --set 'ItemList.0.Tag:cexostr=test-tag'
				--set <node_path>:json=<json_value>
				    Sets the value and type of a GFF node using a JSON object.
				    Ex: --set 'ItemList.0.Tag:json={\"type\": \"cexostr\", \"value\": \"test-tag\"}'

				<node_path>    Dot-separated path to the node to set. See section 'Node paths'.
				<node_type>    GFF type. Any of byte, char, word, short, dword, int, dword64, int64, float, double, cexostr, resref, cexolocstr, void, list, struct
				<node_value>   GFF value.
				               'void' values must be encoded in base64.
				               'cexolocstr' values can be either an integer (sets the resref) or a string (sets the english string).
				<json_value>   GFF JSON value, as represented in the json output format.
				               ex: {"type": "struct","value":{"Name":{"type":"cexostr","value":"tk_item_dropped"}}}


				===== Setting local variables =====
				You can set a local variable on the object with this syntax:

				--set-locvar <var_name>:<var_type>=<value>

				<var_name>  The local variable name
				<var_type>  The local variable type. Only 'int', 'float', 'string' are supported.
				<value>     The local variable value to set. It can be either:
				            - A simple value like: 42, hello
				            - A reference to a GFF node using this syntax: gff@<node_path>. See section 'Node paths'.
				            Values are converted to var_type when necessary.

				Examples:
				--set-locvar nAnswer:int=42
				--set-locvar nPVPRules:int=gff@PlayerVsPlayer
				--set-locvar sDescription:string=gff@DescIdentified
				--set-locvar sWeaponName:string=gff@Equip_ItemList.5.LocalizedName


				===== Node paths =====
				A GFF node path is a succession of path elements separated by dots:
				ex: 'VarTable.2.Name', 'DayNight.7.SkyDomeModel', ...

				The path elements can be:
				- Any string: If the parent is a struct, will select the child value with a given label
				- Any integer: If the parent is a list, will select the Nth child struct
				- '$-42': If parent is a list, '$' is replaced by the list length, allowing to access last children of the list with '$-1'
				- '$': Will add a child at the end of the list
				`
		);
		return 0;
	}
	if(printVersion){
		import nwn.ver: NWN_LIB_D_VERSION;
		writeln(NWN_LIB_D_VERSION);
		return 0;
	}

	if(inputPath is null){
		enforce(args.length > 1, "No input file provided");
		enforce(args.length <= 2, "Too many input files provided");
		inputPath = args[1];
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

		File inputFile = inputPath == "-" ? stdin : File(inputPath, "r");
		auto gff = new FastGff(inputFile.readAll);

		File outputFile = outputPath == "-" || outputPath is null ? stdout : File(outputPath, "w");
		outputFile.writeln(gff.toPrettyString());
		return 0;
	}



	//Parsing
	Gff gff;
	File inputFile = inputPath == "-"? stdin : File(inputPath, "r");

	switch(inputFormat){
		case Format.gff:
			gff = new Gff(inputFile);
			break;
		case Format.json, Format.json_minified:
			import nwnlibd.orderedjson;
			gff = new Gff(parseJSON(cast(string)inputFile.readAll.idup));
			break;
		case Format.pretty:
			enforce(0, inputFormat.to!string~" parsing not supported");
			break;
		default:
			enforce(0, inputFormat.to!string~" parsing not implemented");
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
				enforce!GffPathException(targetType != GffType.Invalid,
					format!"Unknown GFF type string: %s. Allowed types are: byte char word short dword int dword64 int64 float double cexostr resref cexolocstr void struct list json"(nextName[col + 1 .. $]));
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
					tswitch: final switch(targetType) {
						static foreach(TYPE ; EnumMembers!GffType){
							case TYPE:
								static if(TYPE != GffType.Invalid){
									node = &((*gffStruct)[nextName] = GffValue(targetType)).get!(gffTypeToNative!TYPE)();
									break tswitch;
								}
								else
									assert(0);
						}
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
		enforce(eq >= 0, "--set value must contain a '=' character");
		enforce(eq + 1 < setValue.length, "No value provided for --set "~setValue);
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
			tswitch: final switch(gffType){
				static foreach(TYPE ; EnumMembers!GffType){
					case TYPE:
						static if(TYPE != GffType.Invalid){
							(*cast(gffTypeToNative!TYPE*)gffNode) = GffValue(jsonValue).get!(gffTypeToNative!TYPE);
							break tswitch;
						}
						else
							assert(0);
				}
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
				case Struct:    throw new Exception("Use 'json' type for setting a value of type struct");
				case List:      throw new Exception("Use 'json' type for setting a value of type list");
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

	// Set local vars
	foreach(ref setlocvar ; setLocVars){
		import nwn.nwscript.functions;

		auto eq = setlocvar.indexOf('=');
		enforce(eq >= 0, "--set-locvar value must contain a '=' character");
		enforce(eq + 1 < setlocvar.length, "No value provided for --set-locvar "~setlocvar);
		const varSpec = setlocvar[0 .. eq];
		const valueSpec = setlocvar[eq + 1 .. $];

		auto colon = varSpec.lastIndexOf(':');
		enforce(colon >= 0 && colon + 1 < varSpec.length, "No variable type provided for --set-locvar "~setlocvar);
		const varName = varSpec[0 .. colon];
		const varType = varSpec[colon + 1 .. $];


		if(valueSpec.length > 4 && valueSpec[0 .. 4] == "gff@"){
			// Value is provided as a reference to a GFF node
			const path = valueSpec[4 .. $].split(".");

			auto node = getGffNode(path, false);
			auto gffType = node[0];
			auto gffNode = node[1];

			switch(varType){
				case "int":
					NWInt value;
					switch(gffType) with(GffType) {
						case Byte:      value = (*cast(GffByte*)      gffNode).to!NWInt; break;
						case Char:      value = (*cast(GffChar*)      gffNode).to!NWInt; break;
						case Word:      value = (*cast(GffWord*)      gffNode).to!NWInt; break;
						case Short:     value = (*cast(GffShort*)     gffNode).to!NWInt; break;
						case DWord:     value = (*cast(GffDWord*)     gffNode).to!NWInt; break;
						case Int:       value = (*cast(GffInt*)       gffNode).to!NWInt; break;
						case DWord64:   value = (*cast(GffDWord64*)   gffNode).to!NWInt; break;
						case Int64:     value = (*cast(GffInt64*)     gffNode).to!NWInt; break;
						case Float:     value = (*cast(GffFloat*)     gffNode).to!NWInt; break;
						case Double:    value = (*cast(GffDouble*)    gffNode).to!NWInt; break;
						case String:    value = (*cast(GffString*)    gffNode).to!NWInt; break;
						case ResRef:    value = (*cast(GffResRef*)    gffNode).to!string.to!NWInt; break;
						case LocString: value = (*cast(GffLocString*) gffNode).to!string.to!NWInt; break;
						default: throw new Exception(format!"Cannot convert %s of type %s to type int"(path.join("."), gffType));
					}
					SetLocalInt(gff.root, varName, value);
					break;
				case "float":
					NWFloat value;
					switch(gffType) with(GffType) {
						case Byte:      value = (*cast(GffByte*)      gffNode).to!NWFloat; break;
						case Char:      value = (*cast(GffChar*)      gffNode).to!NWFloat; break;
						case Word:      value = (*cast(GffWord*)      gffNode).to!NWFloat; break;
						case Short:     value = (*cast(GffShort*)     gffNode).to!NWFloat; break;
						case DWord:     value = (*cast(GffDWord*)     gffNode).to!NWFloat; break;
						case Int:       value = (*cast(GffInt*)       gffNode).to!NWFloat; break;
						case DWord64:   value = (*cast(GffDWord64*)   gffNode).to!NWFloat; break;
						case Int64:     value = (*cast(GffInt64*)     gffNode).to!NWFloat; break;
						case Float:     value = (*cast(GffFloat*)     gffNode).to!NWFloat; break;
						case Double:    value = (*cast(GffDouble*)    gffNode).to!NWFloat; break;
						case String:    value = (*cast(GffString*)    gffNode).to!NWFloat; break;
						case ResRef:    value = (*cast(GffResRef*)    gffNode).to!string.to!NWFloat; break;
						case LocString: value = (*cast(GffLocString*) gffNode).to!string.to!NWFloat; break;
						default: throw new Exception(format!"Cannot convert %s of type %s to type int"(path.join("."), gffType));
					}
					SetLocalFloat(gff.root, varName, value);
					break;
				case "string":
					NWString value;
					switch(gffType) with(GffType) {
						case Byte:      value = (*cast(GffByte*)      gffNode).to!NWString; break;
						case Char:      value = (*cast(GffChar*)      gffNode).to!NWString; break;
						case Word:      value = (*cast(GffWord*)      gffNode).to!NWString; break;
						case Short:     value = (*cast(GffShort*)     gffNode).to!NWString; break;
						case DWord:     value = (*cast(GffDWord*)     gffNode).to!NWString; break;
						case Int:       value = (*cast(GffInt*)       gffNode).to!NWString; break;
						case DWord64:   value = (*cast(GffDWord64*)   gffNode).to!NWString; break;
						case Int64:     value = (*cast(GffInt64*)     gffNode).to!NWString; break;
						case Float:     value = (*cast(GffFloat*)     gffNode).to!NWString; break;
						case Double:    value = (*cast(GffDouble*)    gffNode).to!NWString; break;
						case String:    value = (*cast(GffString*)    gffNode).to!NWString; break;
						case ResRef:    value = (*cast(GffResRef*)    gffNode).to!string.to!NWString; break;
						case LocString: value = (*cast(GffLocString*) gffNode).to!string; break;
						default: throw new Exception(format!"Cannot convert %s of type %s to type int"(path.join("."), gffType));
					}
					SetLocalString(gff.root, varName, value);
					break;
				default: throw new Exception(format!"Unhandled local variable type '%s'"(varType));
			}
		}
		else{
			// Value is provided as string
			switch(varType){
				case "int": SetLocalInt(gff.root, varName, valueSpec.to!NWInt); break;
				case "float": SetLocalFloat(gff.root, varName, valueSpec.to!NWFloat); break;
				case "string": SetLocalString(gff.root, varName, valueSpec.to!NWString); break;
				default: throw new Exception(format!"Unhandled local variable type '%s'"(varType));
			}
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
	File outputFile = outputPath is null || outputPath == "-" ? stdout : File(outputPath, "w");
	switch(outputFormat){
		case Format.gff:
			outputFile.rawWrite(gff.serialize());
			break;
		case Format.pretty:
			outputFile.writeln(gff.toPrettyString());
			break;
		case Format.json, Format.json_minified:
			auto json = gff.toJson;
			outputFile.writeln(outputFormat==Format.json? json.toPrettyString : json.toString);
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
	import std.file;
	import std.path;


	auto stdout_ = stdout;
	auto tmpOut = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__~".out");
	stdout = File(tmpOut, "w");
	scope(success) std.file.remove(tmpOut);
	scope(exit) stdout = stdout_;

	auto krogarData = cast(ubyte[])import("krogar.bic");
	auto krogarFilePath = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__~".krogar.bic");
	scope(success) std.file.remove(krogarFilePath);
	std.file.write(krogarFilePath, krogarData);

	assertThrown(main(["nwn-gff"]));
	assert(main(["nwn-gff","--help"])==0);
	assert(main(["nwn-gff","--version"])==0);

	// binary perfect read / serialization
	immutable krogarFilePathDup = krogarFilePath~".dup.bic";
	scope(success) std.file.remove(krogarFilePathDup);
	assert(main(["nwn-gff",krogarFilePath,"-o",krogarFilePathDup])==0);
	assert(krogarFilePath.read == krogarFilePathDup.read);

	stdout.reopen(null, "w");
	assert(main(["nwn-gff",krogarFilePath,"-o",krogarFilePathDup, "-k","pretty"])==0);
	stdout.flush();
	assert(krogarFilePathDup.readText.splitLines.length == 23067);
	assertThrown(main(["nwn-gff",krogarFilePath, "-j","pretty"]));


	auto dogeData = cast(ubyte[])import("doge.utc");
	immutable dogePath = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__~".doge.utc");
	scope(success) std.file.remove(dogePath);
	std.file.write(dogePath, dogeData);

	immutable dogePathJson = dogePath~".json";
	immutable dogePathDup = dogePath~".dup.utc";


	assert(main(["nwn-gff","-i",dogePath,"-o",dogePathJson])==0);
	assert(main(["nwn-gff","-i",dogePathJson,"-o",dogePathDup])==0);
	assert(main(["nwn-gff",dogePath,"-o",dogePathJson])==0);


	// Simple modifications
	assert(main(["nwn-gff","-i",dogePath,"-o",dogePath~"modified.gff",
		"--set","Subrace=1",
		"--set","ACRtHip.Tintable.Tint.3.a=42",
		"--set","SkillList.0.Rank=10",
		"--set","FirstName=Hello",
		"--set","Tag=tag_hello",
		"--remove","LastName",
		"--remove","FeatList.0",
		"--set-locvar","nAnswer:int=42",
		"--set-locvar","nSpawnHP:int=gff@CurrentHitPoints",
		"--set-locvar","sFirstName:string=gff@FirstName",
		"--set-locvar","sDescription:string=gff@Description",
		"--set-locvar","nCR:int=gff@ChallengeRating",
		"--set-locvar","fNaturalAC:float=gff@NaturalAC",
		])==0);
	auto gff = new Gff(dogePath~"modified.gff");
	assert(gff["Subrace"].to!int == 1);
	assert(gff["ACRtHip"]["Tintable"]["Tint"]["3"]["a"].to!int == 42);
	assert(gff["SkillList"][0]["Rank"].to!int == 10);
	assert(gff["FirstName"].to!string == "Hello");
	assert(gff["Tag"].to!string == "tag_hello");
	assert("LastName" !in gff);
	assert(gff["FeatList"][0]["Feat"].get!GffWord == 354);

	import nwn.nwscript.functions;
	assert(GetLocalInt(gff.root, "nAnswer") == 42);
	assert(GetLocalInt(gff.root, "nSpawnHP") == 13);
	assert(GetLocalString(gff.root, "sDescription") == "Une indicible intelligence pétille dans ses yeux fous...\r\nWow...");
	assert(GetLocalInt(gff.root, "nCR") == 100);
	assert(GetLocalFloat(gff.root, "fNaturalAC") == 2f);
	assert(GetLocalString(gff.root, "sFirstName") == "Hello");

	// Type mismatch
	assertThrown!GffPathException(main(["nwn-gff","-i",dogePath,"-o",dogePath~"modified.gff",
		"--set","SkillList:struct.0.Rank=10"]));

	// Cannot create node without type
	assertThrown!GffPathException(main(["nwn-gff","-i",dogePath,"-o",dogePath~"modified.gff",
		"--set","NewNode=hello"]));

	assertThrown!ArgException(main(["nwn-gff","-i","nothing.yolo","-o","something.gff"]));
	assert(!"nothing.yolo".exists);
	assert(!"something.gff".exists);


	assert(dogePath.read == dogePathDup.read);


	// set struct / lists operations
	assertThrown!GffPathException(main(["nwn-gff","-i",dogePath, "--set", `VarTable.$:notvalidtype=5`]));
	std.file.write(dogePath, dogeData);
	assert(main([
		"nwn-gff","-i",dogePath, "-o",dogePathDup,
		"--set", `VarTable.$:json={"type": "struct","value":{"Name":{"type":"cexostr","value":"tk_item_dropped"},"Type":{"type":"dword","value":1},"Value":{"type":"int","value":1}}}`,
		"--set", `ModelScale.Yolo:int=42`,
		"--set", `DirtyLocStr:json={"type": "cexolocstr", "str_ref": 0, "value": {"0": "", "2": "hello", "3": ""}}`,
		"--clean-locstr"
	])==0);

	gff = new Gff(dogePathDup);
	assert(gff["VarTable"].get!GffList.length == 1);
	assert(gff["VarTable"][0]["Name"].get!GffString == "tk_item_dropped");
	assert(gff["VarTable"][0]["Type"].get!GffDWord == 1);
	assert(gff["ModelScale"]["Yolo"].get!GffInt == 42);
	assert(gff["DirtyLocStr"].get!GffLocString == GffLocString(0, [2: "hello"]));
}

