/// Authors: Thibaut CHARLES (Crom) cromfr@gmail.com
/// License: GPL-3.0
/// Copyright: Copyright Thibaut CHARLES 2016

module nwnbdb;

import std.stdio;
import std.conv: to, ConvException;
import std.getopt;
import std.traits;
import std.string;
import std.math: log10;
import std.typecons: Tuple, Nullable;
version(unittest) import std.exception: assertThrown, assertNotThrown;

import nwn.biowaredb;

version(unittest){}
else{
	int main(string[] args){return _main(args);}
}

class ArgException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

void usage(in string cmd){
	writeln("Bioware database (foxpro .dbf) tool");
	writeln("Usage: ", cmd, " (search)");
}

int _main(string[] args){
	if(args.length <= 1 || (args.length > 1 && (args[1] == "--help" || args[1] == "-h"))){
		usage(args[0]);
		return 1;
	}

	if(args.length > 2){
		immutable command = args[1];
		args = args[0] ~ args[2..$];

		switch(command){
			default:
				usage(args[0]);
				return 1;
			case "search":{
				string playerid = r".*";
				string name = r".*";
				enum DeletedFlag: int { no = 0, yes = 1, any }
				DeletedFlag deleted = DeletedFlag.any;
				version(Windows) bool colors = false;
				else             bool colors = true;

				auto res = getopt(args,
					"playerid", "Player ID regex. Player ID is build by appending AccountName + CharacterName, up to 32 characters.", &playerid,
					"name", "Variable name regex", &name,
					"deleted", "Search for either deleted variables or not. Valid values are: any (default), yes, no", &deleted,
					"colors", "Enable/disable ANSI colors (default to 0 on Windows)", &colors);
				if(res.helpWanted || args.length != 2){
					defaultGetoptPrinter(
						"Search specific variables inside a database file\n"
						~"Example: " ~ args[0] ~ " search foxpro-file-basename --name='^VAR_NAME_.*'",
						res.options);
					return 0;
				}

				const db = new BiowareDB(args[1]);
				auto dbLen = db.length;
				int indexLength = cast(int)log10(dbLen) + 1;


				import std.regex;
				auto rgxPlayerID = regex(playerid);
				auto rgxName = regex(name);

				foreach(var ; db){
					if(deleted != DeletedFlag.any && var.deleted != deleted)
						continue;

					auto playerIDCap = var.playerid.toString.matchFirst(rgxPlayerID);
					if(playerIDCap.empty)
						continue;

					auto nameCap = var.name.matchFirst(rgxName);
					if(nameCap.empty)
						continue;

					import std.base64;

					string value;
					final switch(var.type) with(BiowareDB.VarType){
						case Int:          value = db.getVariableValue!NWInt(var.index).to!string;        break;
						case Float:        value = db.getVariableValue!NWFloat(var.index).to!string;      break;
						case String:       value = db.getVariableValue!NWString(var.index).to!string;     break;
						case Vector:       value = db.getVariableValue!NWVector(var.index).to!string;     break;
						case Location:     value = db.getVariableValue!NWLocation(var.index).to!string;   break;
						case BinaryObject: value = Base64.encode(db.getVariableValue!(nwn.biowaredb.BinaryObject)(var.index)); break;
					}

					if(colors){
						writeln(
							(var.deleted? colfg.red ~ "D" ~ colfg.def ~ colvar.faded : " ")
							~ " " ~ var.index.to!string.leftJustify(indexLength)
							~ " " ~ colvar.italic ~ var.timestamp.toSimpleString ~ colvar.noitalic
							~ " " ~ (playerIDCap.pre ~ colvar.ulined ~ playerIDCap.hit ~ colvar.noulined ~ playerIDCap.post).leftJustify(32 + 9)
							~ " " ~ (nameCap.pre ~ colvar.ulined ~ nameCap.hit ~ colvar.noulined ~ nameCap.post).leftJustify(32 + 9)
							~ " " ~ var.type.to!string ~ " = " ~ value ~ colvar.end);
					}
					else{

					}
				}


			}
			break;
		}
	}
	return 0;
}







enum colfg : string{
	def =          "\x1b[39m",
	black =        "\x1b[30m",
	lightblack =   "\x1b[90m",
	red =          "\x1b[31m",
	lightred =     "\x1b[91m",
	green =        "\x1b[32m",
	lightgreen =   "\x1b[92m",
	yellow =       "\x1b[33m",
	lightyellow =  "\x1b[93m",
	blue =         "\x1b[34m",
	lightblue =    "\x1b[94m",
	magenta =      "\x1b[35m",
	lightmagenta = "\x1b[95m",
	cyan =         "\x1b[36m",
	lightcyan =    "\x1b[96m",
	white =        "\x1b[37m",
	lightwhite =   "\x1b[97m"
}
enum colbg : string{
	def =          "\x1b[49m",
	black =        "\x1b[40m",
	lightblack =   "\x1b[100m",
	red =          "\x1b[41m",
	lightred =     "\x1b[101m",
	green =        "\x1b[42m",
	lightgreen =   "\x1b[102m",
	yellow =       "\x1b[43m",
	lightyellow =  "\x1b[103m",
	blue =         "\x1b[44m",
	lightblue =    "\x1b[104m",
	magenta =      "\x1b[45m",
	lightmagenta = "\x1b[105m",
	cyan =         "\x1b[46m",
	lightcyan =    "\x1b[106m",
	white =        "\x1b[47m",
	lightwhite =   "\x1b[107m"
}

enum colvar : string{
	none =      "\x1b[0m",
	bold =      "\x1b[1m",
	faded =     "\x1b[2m",
	italic =    "\x1b[3m",
	ulined =    "\x1b[4m",
	striked =   "\x1b[9m",
	inverted =  "\x1b[7m",
	nobold =    "\x1b[21m",
	nofaded =   "\x1b[22m",
	noitalic =  "\x1b[23m",
	noulined =  "\x1b[24m",
	nostriked = "\x1b[29m",
	end =       "\x1b[m"
}