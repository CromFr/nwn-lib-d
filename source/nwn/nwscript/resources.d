/// Resource management required by certain NWScript functions
module nwn.nwscript.resources;

import std.string;
import std.path;
import std.file;
import nwn.tlk;
import nwn.twoda;

private __gshared string[] _twoDAPaths = null;
private TwoDA[string] _twoDAs;


void initTwoDAPaths(in string[] paths){
	_twoDAPaths = paths.dup;
}

TwoDA getTwoDA(in string _name){
	assert(_twoDAPaths !is null, "Call nwn.nwscript.resources.initTwoDAPaths to initialize 2DA search paths");

	auto name = _name.toLower;

	if(name in _twoDAs)
		return _twoDAs[name];

	foreach(p ; _twoDAPaths){
		if(p.baseName.stripExtension.toLower == name){
			_twoDAs[name.toLower] = new TwoDA(p);
			return _twoDAs[name.toLower];
		}
		if(p.isDir){
			foreach(f ; p.dirEntries("*.2da", SpanMode.shallow)){
				if(f.baseName.stripExtension == name){
					_twoDAs[name.toLower] = new TwoDA(f);
					return _twoDAs[name.toLower];
				}
			}
		}
	}
	return null;
}

private __gshared StrRefResolver _tlkResolver;

void initStrRefResolver(StrRefResolver resolver){
	_tlkResolver = resolver;
}

ref StrRefResolver getStrRefResolver(){
	assert(_tlkResolver !is null, "Call nwn.nwscript.resources.initStrRefResolver to initialize TLK translations");
	return _tlkResolver;
}