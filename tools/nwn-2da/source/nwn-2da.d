module tools.nwn2da;

import std;

import nwn.twoda;

import tools.common.getopt;





void usage(in string cmd){
	writeln("2DA tool");
	writeln();
	writeln("Usage: ", cmd.baseName, " command [args]");
	writeln();
	writeln("Commands");
	writeln("  check: Parse the 2da and print found issues");
	writeln("  normalize: Fix issues and re-format 2DA files");
	writeln("  merge: Merge 2da rows together");
}

// Hack for having a full stacktrace when unittest fails (otherwise it stops the stacktrace at main())
int main(string[] args){return _main(args);}
int _main(string[] args)
{
	if(args.any!(a => a == "--version")){
		import nwn.ver: NWN_LIB_D_VERSION;
		writeln(NWN_LIB_D_VERSION);
		return 0;
	}
	if(args.length >= 2 && (args[1] == "--help" || args[1] == "-h")){
		usage(args[0]);
		return 0;
	}

	enforce(args.length > 1, "No subcommand provided");
	immutable command = args[1];
	args = args[0] ~ args[2..$];


	switch(command){
		case "check":
			bool noError, noWarning, noNotice;
			auto res = getopt(args,
				"noerrors", "do not print errors", &noError,
				"nowarnings", "do not print warnings", &noWarning,
				"nonotice", "do not print notice", &noNotice,
			);
			if(res.helpWanted){
				improvedGetoptPrinter(
					multilineStr!`
						Parse the 2da and print found issues

						Usage: nwn-2da check [options] <2da_file> [<2da_file> ...]
						`,
					res.options,
				);
				return 0;
			}

			bool errored = false;
			foreach(file ; args[1 .. $]){
				auto parseRes = TwoDA.recover(file);

				foreach(err ; parseRes.errors){
					if(err.type == "Error" && noError
					|| err.type == "Warning" && noWarning
					|| err.type == "Notice" && noNotice)
						continue;

					errored = true;
					writefln("%s:%d: %s: %s",
						file, err.line, err.type, err.msg
					);
				}
			}

			return errored;

		case "normalize":
			bool noError, noWarning, noNotice;
			auto res = getopt(args);
			if(res.helpWanted){
				improvedGetoptPrinter(
					multilineStr!`
						Fix issues and re-format 2DA files

						Usage: nwn-2da normalize [options] <2da_file> [<2da_file> ...]
						`,
					res.options,
				);
				return 0;
			}

			foreach(file ; args[1 .. $]){
				auto twoda = new TwoDA(file);
				std.file.write(file, twoda.serialize());
			}

			return 0;


		case "merge":
			string[] ranges;
			bool nonInteractive = false;
			auto res = getopt(args,
				"range", "Merge a specific range. Format is: <from>-<to>. Can be provided multiple times.", &ranges,
				"y|yes", "Overwrite existing data without asking", &nonInteractive,
			);
			if(res.helpWanted){
				improvedGetoptPrinter(
					multilineStr!`
						Merge source_2da rows into target_2da

						Usage: nwn-2da merge [options] <target_2da> <source_2da>
						`,
					res.options,
					multilineStr!`
						===============|  Special 2DA merge file format  |===============

						This tool can use the "2DA merge" format for source_2da to specify which rows must be set in target_2da.
						The 2da merge file must start with a line '2DAMV1.0', followed by 2DA rows.

						Example:
						---
						2DAMV1.0
						10    ****          ****     **** **** ****   **** **** **** **** ****
						1000  Aid           16777327 10   2    110533 1    1    1    1    it_s_aid
						1001  Bestow_Curse  16777328 20   3    110533 4    0    1    1    it_s_bestowcurse
						1002  BlindDeaf     16777329 20   2    110533 8    0    1    1    it_s_blinddeaf
						---
						`
				);
				return 0;
			}
			size_t[2][] parsedRanges = ranges.map!((a){
					auto s = a.split('-');
					enforce(s.length == 2, "Bad range '" ~ a ~ "', must be <from>-<to>. Ex: 12-32");
					auto r = s.map!(to!size_t).array;
					enforce(r[0] <= r[1], "Invalid range '" ~ a ~ "'");
					return cast(size_t[2])r[0 .. 2];
				})
				.array;
			bool isInRange(size_t targetIndex){
				if(parsedRanges.length == 0)
					return true;
				foreach(r ; parsedRanges){
					if(r[0] <= targetIndex && targetIndex <= r[1])
						return true;
				}
				return false;
			}

			enforce(args.length == 3, "Need a target and source 2da");
			auto targetPath = args[1];
			auto sourcePath = args[2];

			auto targetTwoDA = new TwoDA(targetPath);

			size_t maxIndex = 0;
			size_t[] sourceRowsIndices;
			string[][] sourceRowsData;
			auto sourceData = std.file.read(sourcePath);
			if(sourceData.length >= 8 && sourceData[0 .. 8] == "2DAMV1.0"){
				// 2da merge format
				foreach(i, line ; (cast(string)sourceData).splitLines){
					if(i == 0)
						continue;
					auto row = TwoDA.extractRowData(line);
					sourceRowsIndices ~= row[0].to!size_t;
					sourceRowsData ~= row[1 .. $];
					maxIndex = max(maxIndex, sourceRowsIndices[$ - 1]);
				}
			}
			else{
				// Standard 2da
				auto sourceTwoDA = new TwoDA(cast(ubyte[])sourceData);
				foreach(i ; 0 .. sourceTwoDA.rows){
					auto row = sourceTwoDA[i];
					if(row.any!"a !is null"){
						sourceRowsIndices ~= i;
						sourceRowsData ~= row.dup;
						maxIndex = max(maxIndex, sourceRowsIndices[$ - 1]);
					}
				}
			}

			if(maxIndex >= targetTwoDA.rows)
				targetTwoDA.rows = maxIndex + 1;

			foreach(i, rowIndex ; sourceRowsIndices){
				if(!isInRange(rowIndex))
					continue;

				auto targetRow = targetTwoDA[rowIndex];
				auto sourceRow = sourceRowsData[i];
				if(targetRow == sourceRow)
					continue;

				if(targetRow.all!"a is null" || nonInteractive)
					targetTwoDA[rowIndex] = sourceRow;
				else{
					writefln("Conflict on row index %d:", rowIndex);
					writefln("Target: ", targetRow);
					writefln("Source: ", sourceRow);
					while(true){
						write("Replace target with source? (y|n|q) ");
						stdout.flush();
						auto ans = stdin.readln();
						switch(ans){
							case "y":
								targetTwoDA[rowIndex] = sourceRow;
								break;
							case "n":
								break;
							case "q":
								return 0;
							default:
								continue;
						}
						break;
					}
				}
			}

			std.file.write(targetPath, targetTwoDA.serialize());


			return 0;

		default:
			writeln("Unknown command ", command);
			return 1;
	}
}



unittest {
	auto stdout_ = stdout;
	auto tmpOut = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__~".out");
	stdout = File(tmpOut, "w");
	scope(success) std.file.remove(tmpOut);
	scope(exit) stdout = stdout_;


	assertThrown(_main(["nwn-2da"]));
	assert(_main(["nwn-2da","--help"])==0);
	assert(_main(["nwn-2da","--version"])==0);
	assert(_main(["nwn-2da","yolo"]) != 0);

	immutable targetPath = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__~".target.2da");
	scope(success) std.file.remove(targetPath);
	immutable sourcePath = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__~".source.2dam");
	scope(success) std.file.remove(sourcePath);


	// Checking (most errors are not checked here)
	assert(_main(["nwn-2da","check","--help"])==0);
	stdout.reopen(null, "w");
	std.file.write(targetPath, import("2da/armorrulestats.2da"));
	assert(_main(["nwn-2da","check",targetPath]) == 1);
	stdout.flush();
	assert(tmpOut.readText.splitLines.length == 2);

	// Normalize
	assert(_main(["nwn-2da","normalize","--help"])==0);
	std.file.write(targetPath, import("2da/armorrulestats.2da"));
	assert(_main(["nwn-2da","normalize",targetPath]) == 0);
	assert(_main(["nwn-2da","check",targetPath]) == 0);

	// Merging
	assert(_main(["nwn-2da","merge","--help"])==0);

	auto origTwoDA = new TwoDA(cast(ubyte[])import("2da/iprp_ammocost.2da"));

	// Row data matches, do not change anything
	std.file.write(targetPath, import("2da/iprp_ammocost.2da"));
	std.file.write(sourcePath, multilineStr!`
		2DAMV1.0
		3	1633	1d6Cold	4	NW_WAMMAR005	NW_WAMMBO001	NW_WAMMBU006
		`
	);
	assert(_main(["nwn-2da","merge",targetPath,sourcePath])==0);
	auto res = new TwoDA(targetPath);
	foreach(i ; 0 .. origTwoDA.rows)
		assert(res[i] == origTwoDA[i], i.to!string);

	// Overwrite row data
	std.file.write(targetPath, import("2da/iprp_ammocost.2da"));
	std.file.write(sourcePath, multilineStr!`
		2DAMV1.0
		7	200888	Modified	7	nx1_arrow03	nx1_bolt03	nx1_bullet03
		`
	);
	assert(_main(["nwn-2da","merge","-y",targetPath,sourcePath])==0);
	res = new TwoDA(targetPath);
	assert(res.get("Label", 7) == "Modified");

	// Insert row data
	std.file.write(targetPath, import("2da/iprp_ammocost.2da"));
	std.file.write(sourcePath, multilineStr!`
		2DAMV1.0
		20	1000	NewRow	10	nx1_arrow03	nx1_bolt03	nx1_bullet03
		`
	);
	assert(_main(["nwn-2da","merge",targetPath,sourcePath])==0);
	res = new TwoDA(targetPath);
	assert(res.get("Label", 20) == "NewRow");

	// Insert row data outside of bounds
	std.file.write(targetPath, import("2da/iprp_ammocost.2da"));
	std.file.write(sourcePath, multilineStr!`
		2DAMV1.0
		20	1000	NewRow	10	nx1_arrow03	nx1_bolt03	nx1_bullet03
		`
	);
	assert(_main(["nwn-2da","merge",targetPath,sourcePath])==0);
	res = new TwoDA(targetPath);
	assert(res.get("Label", 20) == "NewRow");


	// Insert a range
	std.file.write(targetPath, import("2da/armorrulestats.2da"));
	std.file.write(sourcePath, multilineStr!`
		2DAMV1.0
		5  Scale-mod        4 3   -4  25 300 50   179905 111250 5438   Medium
		6  Banded-mod       6 1   -6  35 350 250  1733   111251 5439   Heavy
		7  Half-Plate-mod   7 0   -7  40 500 600  1734   111252 5440   Heavy
		8  Full-Plate-mod   8 1   -6  35 500 1500 1736   111253 5441   Heavy
		9  Light_Shield-mod 1 100 -1  5  50  9    2287   179    5443   None
		10 Heavy_Shield-mod 2 100 -2  15 100 20   2286   1550   5458   None
		11 Tower_Shield-mod 4 2   -10 50 450 30   1717   1551   5459   None
		12 Hide-mod         3 4   -3  20 250 15   179882 179878 179886 Medium
		`
	);
	assert(_main(["nwn-2da","merge","-y",targetPath,sourcePath,"--range=6-7","--range=10-11","--range=14-15","--range=100-101"])==0);
	res = new TwoDA(targetPath);
	assert(res.get("Label", 5) == "Scale");
	assert(res.get("Label", 6) == "Banded-mod");
	assert(res.get("Label", 7) == "Half-Plate-mod");
	assert(res.get("Label", 8) == "Full-Plate");
	assert(res.get("Label", 9) == "Light_Shield");
	assert(res.get("Label", 10) == "Heavy_Shield-mod");
	assert(res.get("Label", 11) == "Tower_Shield-mod");
	assert(res.get("Label", 12) == "Hide");
	assert(res.get("Label", 13) == "Chainmail");
	assert(res.get("Label", 14) == "Breastplate");
	assert(res.rows == 47);
}
