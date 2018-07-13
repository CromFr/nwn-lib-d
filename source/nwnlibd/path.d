/// Case insensitive path functions
module nwnlibd.path;

import std.exception;

///
string buildPathCI(T...)(in string basePath, T subFiles){
	import std.file;
	import std.path;
	import std.string: toUpper;

	enforce(basePath.exists, "basePath '"~basePath~"' does not exist");
	string path = basePath;

	foreach(subFile ; subFiles){
		//Case is correct, cool !
		if(buildPath(path, subFile).exists){
			path = buildPath(path, subFile);
		}
		//Most likely only the extension is fucked up
		else if(buildPath(path, subFile.stripExtension ~ subFile.extension.toUpper).exists){
			path = buildPath(path, subFile.stripExtension ~ subFile.extension.toUpper);
		}
		//Perform full scan of the directory
		else{
			bool bFound = false;
			foreach(file ; path.dirEntries(SpanMode.shallow)){
				if(filenameCmp!(CaseSensitive.no)(file.baseName, subFile) == 0){
					bFound = true;
					path = file.name;
					break;
				}
			}
			if(!bFound)
				path = buildPath(path, subFile);
		}
	}
	return path;
}

///
unittest{
	// First directory must exist and case must be correct
	assertThrown(buildPathCI("UNITTEST", "PLC_MC_BALCONY3.MDB"));

	// Fix case in file paths
	assert(buildPathCI(".", "unittest", "PLC_MC_BALCONY3.MDB") == "./unittest/PLC_MC_BALCONY3.MDB");
	assert(buildPathCI(".", "UNITTEST", "PLC_MC_BALCONY3.mdb") == "./unittest/PLC_MC_BALCONY3.MDB");
	assert(buildPathCI(".", "unittest", "plc_mc_balcony3.mdb") == "./unittest/PLC_MC_BALCONY3.MDB");
	assert(buildPathCI(".", "UNITTEST", "pLc_mc_balConY3.mdB") == "./unittest/PLC_MC_BALCONY3.MDB");

	// Non existing files keep the provided case
	assert(buildPathCI(".", "Unittest", "YoLo.pNg") == "./unittest/YoLo.pNg");
}

