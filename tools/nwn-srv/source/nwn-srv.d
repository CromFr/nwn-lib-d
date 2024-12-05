/// Authors: Thibaut CHARLES (Crom) cromfr@gmail.com
/// License: GPL-3.0
/// Copyright: Copyright Thibaut CHARLES 2016

module tools.nwnsrv;

import std.stdio;
import std.conv: to, ConvException;
import std.traits;
import std.meta;
import std.string;
import std.file;
import std.typecons: Tuple, Nullable;
import std.exception: enforce;
import std.path;
import std.algorithm;
import core.thread;
alias writeFile = std.file.write;
version(unittest) import std.exception: assertThrown, assertNotThrown;

import tools.common.getopt;
import nwn.constants;
import nwn.nwnserver;


int main(string[] args){
	if(args.length >= 2 && (args[1] == "-h" || args[1] == "--help")){
		writeln("Send requests to NWN2 servers.");
		writefln("Usage: %s (ping|bnes|bnds|bnxi|bnlm)", args[0].baseName);
		writeln("Use '", args[0].baseName, " <subcommand> --help' for details on a specific subcommand.");
		return 0;
	}
	if(args.any!(a => a == "--version")){
		import nwn.ver: NWN_LIB_D_VERSION;
		writeln(NWN_LIB_D_VERSION);
		return 0;
	}

	enforce(args.length > 1, "No subcommand provided");
	immutable command = args[1];
	args = args[0] ~ args[2..$];

	cmdswitch:
	switch(command){
		case "ping":
			{
				int count = 1;
				auto res = getopt(args,
					"n", "Number of pings to issue. 0 for infinite. Default 1", &count);
				if(res.helpWanted){
					improvedGetoptPrinter(
						"Ping server and measure latency\n"
						~"Usage: "~args[0].baseName~" ping [args] hostname[:port]\n"
						~"Example: "~args[0].baseName~" ping lcda-nwn2.fr",
						res.options);
					return 0;
				}
				enforce(args.length > 1, "No hostname provided");
				enforce(args.length <= 2, "Too many arguments provided");

				auto serv = connectServer(args[1]);

				double avg = double.nan;
				double min = double.max;
				double max = 0.0;
				for(auto i = 0 ; i < count || count == 0 ; i++){
					if(i > 0)
						Thread.sleep(1.dur!"seconds");
					auto ping = serv.ping();
					writeln(i, ": ", ping, "ms");
					if(i == 0) avg = ping;
					else       avg = (avg * i + ping) / cast(double)(i + 1);

					if(ping < min) min = ping;
					if(ping > max) max = ping;
				}
				writeln("Average: ", avg, "ms");
				writeln("Min: ", min, "ms");
				writeln("Max: ", max, "ms");
			}
			break;

		foreach(Req ; AliasSeq!("bnes", "bnds", "bnxi", "bnlm")){
			case Req:
				{
					string format = "text";
					auto res = getopt(args,
						"f|format", "Output format. 'text' or 'json'. Default: 'text'.", &format
					);
					if(res.helpWanted){
						improvedGetoptPrinter(
							"Send a "~Req~" request to the server\n"
							~"Usage: "~args[0].baseName~" "~Req~" [args] hostname[:port]\n"
							~"Example: "~args[0].baseName~" "~Req~" lcda-nwn2.fr",
							res.options);
						return 0;
					}
					enforce(args.length > 1, "No hostname provided");
					enforce(args.length <= 2, "Too many arguments provided");

					auto serv = connectServer(args[1]);

					switch(format){
						case "text": writeln(mixin("serv.query"~Req.toUpper~"()").serializeStruct!"text"); break;
						case "json": writeln(mixin("serv.query"~Req.toUpper~"()").serializeStruct!"json"); break;
						default: assert(0, "Bad output format");
					}
				}
				break cmdswitch;
		}

		default:
			writefln("Unknown command '%s'. Try %s --help", command, args[0].baseName);
			return -1;
	}
	return 0;
}

auto connectServer(string url){
	auto urlSplit = url.split(":");
	auto address = urlSplit[0];
	ushort port = urlSplit.length > 1 ? urlSplit[1].to!ushort : 5121;
	return new NWNServer(address, port);
}

string serializeStruct(string format, T)(in T s){
	static if(format == "json"){
		import std.json;
		auto ret = JSONValue();
		ret.object = null;
	}
	else static if(format == "text"){
		string ret;
	}
	else static assert(0);

	static foreach(Member ; FieldNameTuple!T){
		static if(format == "json"){
			ret[Member] = mixin("s."~Member).to!string;
		}
		else static if(format == "text"){
			ret ~= Member ~ ": " ~ mixin("s."~Member).to!string ~ "\n";
		}
	}
	static if(format == "json"){
		return ret.toJSON();
	}
	else{
		return ret;
	}
}

unittest {
	auto stdout_ = stdout;
	auto tmpOut = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__);
	stdout = File(tmpOut, "w");
	scope(success) tmpOut.remove();
	scope(exit) stdout = stdout_;

	assertThrown(main(["nwn-srv"]));
	assert(main(["nwn-srv","--help"]) == 0);
	assert(main(["nwn-srv","--version"]) == 0);

	assertThrown(main(["nwn-srv","bnxi"]));
	assert(main(["nwn-srv","bnxi", "--help"]) == 0);
	assert(main(["nwn-srv", "ping", "--help"]) == 0);
    	assert(main(["nwn-srv", "bnes", "--help"]) == 0);
}
