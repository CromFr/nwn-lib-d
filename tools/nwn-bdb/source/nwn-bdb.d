/// Authors: Thibaut CHARLES (Crom) cromfr@gmail.com
/// License: GPL-3.0
/// Copyright: Copyright Thibaut CHARLES 2016

module tools.nwnbdb;

import std.stdio;
import std.conv: to, ConvException;
import std.traits;
import std.string;
import std.path;
import std.file;
import std.exception;
import std.algorithm;
import std.math: log10;
import std.typecons: Tuple, Nullable;
import std.json;
import std.base64: Base64;
import std.regex;
version(unittest) import std.exception: assertThrown, assertNotThrown;

import tools.common.getopt;
import nwn.biowaredb;


class ArgException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

int main(string[] args){
	if(args.length >= 2 && (args[1] == "-h" || args[1] == "--help")){
		writeln("Bioware database (foxpro .dbf) tool");
		writefln("Usage: %s <subcommand>", args[0].baseName);
		writeln("Available subcommands:");
        	writeln("  search    Search specific variables inside a database file");
        	writeln("Use '", args[0].baseName, " <subcommand> --help' for details on a specific subcommand.");
		return args.length <= 1;
	}
	if(args.any!(a => a == "--version")){
		import nwn.ver: NWN_LIB_D_VERSION;
		writeln(NWN_LIB_D_VERSION);
		return 0;
	}
	enforce(args.length >= 2, "No subcommand provided");

	immutable command = args[1];
	args = args[0] ~ args[2..$];

	switch(command){
		default:
			writefln("Unknown sub-command '%s'. See --help", command);
			return 1;
		case "search":{
			string playerid;
			bool moduleOnly = false;
			string name = r".*";
			enum DeletedFlag: int { no = 0, yes = 1, any }
			DeletedFlag deleted = DeletedFlag.any;
			string varTypeStr;
			bool noHeader;
			enum OutputFormat { text, json }
			OutputFormat outputFormat;


			auto res = getopt(args,
				"module", "Search only for module variables (vars not linked to a player character)", &moduleOnly,
				"playerid", "Player ID regex. Player ID is build by appending AccountName + CharacterName, truncated to 32 characters.", &playerid,
				"type", "variable type. Valid values are: Int, Float, String, Vector, Location, Object.", &varTypeStr,
				"name", "Variable name regex", &name,
				"deleted", "Search for either deleted variables or not. Valid values are: any (default), yes, no", &deleted,
				"no-header", "Do not show column header", &noHeader,
				"k|output-format", "Output format. Defaults to text. Valid values are: text, json", &outputFormat,
			);
			if(res.helpWanted || args.length != 2){
				improvedGetoptPrinter(
					"Search specific variables inside a database file\n"
					~"Example: " ~ args[0].baseName ~ " search foxpro-file-basename --name='^VAR_NAME_.*'",
					res.options);
				return 1;
			}

			if(moduleOnly)
				enforce(playerid is null, "--module cannot be used with --playerid");

			if(playerid is null)
				playerid = r".*";

			Nullable!(BiowareDB.VarType) varType;
			if(varTypeStr !is null)
				varType = varTypeStr.to!(BiowareDB.VarType);


			auto dbName = args[1];
			if(dbName.extension.toLower == ".dbf")
				dbName = dbName.stripExtension;

			const db = new BiowareDB(dbName, false);
			auto dbLen = db.length;
			int indexLength = cast(int)log10(cast(double)dbLen) + 1;
			if(indexLength < 3)
				indexLength = 3;

			auto rgxPlayerID = regex(playerid);
			auto rgxName = regex(name);

			if(!noHeader && outputFormat == OutputFormat.text){
				writefln("%s %s %-20s %-32s %-8s %32s   %s",
					"D",
					"Idx".leftJustify(indexLength),
					"Timestamp",
					"Character ID",
					"Type",
					"Variable name",
					"Variable Value",
				);
				writeln("------------------------------------------------------------------------------------------------------------------------");
			}
			auto jsonValue = JSONValue(cast(JSONValue[])null);

			foreach(var ; db){
				if(deleted != DeletedFlag.any && var.deleted != deleted)
					continue;
				if(!varType.isNull && varType.get != var.type)
					continue;

				if(moduleOnly){
					if(var.playerid.toString != "")
						continue;
				}
				else{
					auto playerIDCap = var.playerid.toString.matchFirst(rgxPlayerID);
					if(playerIDCap.empty)
						continue;
				}

				auto nameCap = var.name.matchFirst(rgxName);
				if(nameCap.empty)
					continue;


				if(outputFormat == OutputFormat.text){
					string value;
					final switch(var.type) with(BiowareDB.VarType){
						case Int:      value = db.getVariableValue!NWInt(var.index).to!string;        break;
						case Float:    value = db.getVariableValue!NWFloat(var.index).to!string;      break;
						case String:   value = db.getVariableValue!NWString(var.index).to!string;     break;
						case Vector:   value = db.getVariableValue!NWVector(var.index).to!string;     break;
						case Location: value = db.getVariableValue!NWLocation(var.index).to!string;   break;
						case Object:   value = Base64.encode(db.getVariableValue!(nwn.biowaredb.BinaryObject)(var.index)); break;
					}

					writefln("%s %s %20s %-32s %-8s %32s = %s",
						var.deleted ? "D" : " ",
						var.index.to!string.leftJustify(indexLength),
						var.timestamp.toSimpleString,
						var.playerid.to!string,
						var.type,
						var.name,
						value,
					);
				}
				else if(outputFormat == OutputFormat.json){
					JSONValue varValue;
					varValue["deleted"] = var.deleted;
					varValue["index"] = var.index;
					varValue["timestamp"] = var.timestamp.toISOString;
					varValue["pcid"] = var.playerid.to!string;
					varValue["type"] = var.type;
					varValue["name"] = var.name;
					final switch(var.type) with(BiowareDB.VarType){
						case Int:      varValue["value"] = db.getVariableValue!NWInt(var.index);        break;
						case Float:    varValue["value"] = db.getVariableValue!NWFloat(var.index);      break;
						case String:   varValue["value"] = db.getVariableValue!NWString(var.index);     break;
						case Vector:   varValue["value"] = db.getVariableValue!NWVector(var.index).value;     break;
						case Location: varValue["value"] = db.getVariableValue!NWLocation(var.index).to!string;   break;
						case Object:   varValue["value"] = Base64.encode(db.getVariableValue!(nwn.biowaredb.BinaryObject)(var.index)); break;
					}
					jsonValue.array ~= varValue;
				}
			}

			if(outputFormat == OutputFormat.json){
				writeln(jsonValue.toPrettyString);
			}
		}
		break;
	}
	return 0;
}


unittest {
	auto stdout_ = stdout;
	auto tmpOut = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__);
	stdout = File(tmpOut, "w");
	scope(success) tmpOut.remove();
	scope(exit) stdout = stdout_;


	assertThrown(main(["nwn-bdb"]) != 0);
	assert(main(["nwn-bdb","--help"]) == 0);
	assert(main(["nwn-bdb","--version"]) == 0);

	// List everything
	stdout.reopen(null, "w");
	assert(main(["nwn-bdb", "search", "../../unittest/testcampaign", "--no-header"]) == 0);
	stdout.flush();
	assert(tmpOut.readText.splitLines.length == 8);

	// List module vars
	stdout.reopen(null, "w");
	assert(main(["nwn-bdb", "search", "../../unittest/testcampaign", "--no-header", "--module"]) == 0);
	stdout.flush();
	assert(tmpOut.readText.splitLines.length == 6);

	// Search player vars
	stdout.reopen(null, "w");
	assert(main(["nwn-bdb", "search", "../../unittest/testcampaign", "--no-header", "--playerid", "Crom 2"]) == 0);
	stdout.flush();
	assert(tmpOut.readText.splitLines.length == 2);

	// Search var names
	stdout.reopen(null, "w");
	assert(main(["nwn-bdb", "search", "../../unittest/testcampaign", "--no-header", "--name", "ThisIs"]) == 0);
	stdout.flush();
	assert(tmpOut.readText.splitLines.length == 5);

	// Output json
	stdout.reopen(null, "w");
	assert(main(["nwn-bdb", "search", "../../unittest/testcampaign", "--output-format", "json"]) == 0);
	stdout.flush();
	assert(tmpOut.readText.parseJSON.array.length == 8);
}
