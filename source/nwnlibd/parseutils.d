/// Authors: Thibaut CHARLES (Crom) cromfr@gmail.com
/// License: GPL-3.0
/// Copyright: Copyright Thibaut CHARLES 2016

/// Internal parsing tools
module nwnlibd.parseutils;

import std.traits;

/// Converts a static char array to string.
/// The fixed char array may or may not be null terminated
auto ref string charArrayToString(T)(in T str) if(isStaticArray!T && isSomeChar!(ForeachType!T)){
	import std.string: fromStringz;
	if(str[$-1]=='\0')
		return str.ptr.fromStringz.idup;
	else
		return str.idup;
}

/// Formats a binary array to something readable
string dumpByteArray(in void[] byteArray){
	import std.string: rightJustify;
	import std.conv: to;
	string ret;
	foreach(i ; 0..20){
		if(i==0)ret ~= "    / ";
		ret ~= i.to!string.rightJustify(4, '_');
	}
	ret ~= "\n";
	foreach(i ; 0..byteArray.length){
		auto ptr = byteArray.ptr + i;
		if(i%20==0)ret ~= (i/10).to!string.rightJustify(3)~" > ";
		ret ~= (*cast(ubyte*)ptr).to!string.rightJustify(4);
		if(i%20==19)ret ~= "\n";
	}
	ret ~= "\n";
	return ret;
}