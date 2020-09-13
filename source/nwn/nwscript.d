/// NWScript functions and types implemented in D
module nwn.nwscript;

import std.stdint;
import std.array;

import nwn.tlk;
import nwn.gff;
import nwn.types;

private StrRefResolver _tlkResolver;

/// Call this function to setup TLK translations for some nwscript functions
void initNWScript(StrRefResolver resolver){
	_tlkResolver = resolver;
}
unittest{
	immutable dialogTlk = cast(immutable ubyte[])import("dialog.tlk");
	immutable userTlk = cast(immutable ubyte[])import("user.tlk");
	initNWScript(new StrRefResolver(new Tlk(dialogTlk), new Tlk(userTlk)));
}


///
enum OBJECT_INVALID = NWObject.max;


///
NWString GetName(ref GffNode objectGff){
	assert(_tlkResolver !is null, "Call initNWScript to setup TLK tables");
	if("FirstName" in objectGff){
		auto firstName = _tlkResolver[objectGff["FirstName"]];
		auto lastName = _tlkResolver[objectGff["LastName"]];
		if(lastName != "")
			return [firstName, lastName].join(" ");
		return firstName;
	}
	if("LocalizedName" in objectGff)
		return _tlkResolver[objectGff["LocalizedName"]];
	else if("LocName" in objectGff)
		return _tlkResolver[objectGff["LocName"]];
	return "";
}
///
NWString GetFirstName(ref GffNode objectGff){
	assert(_tlkResolver !is null, "Call initNWScript to setup TLK tables");
	return _tlkResolver[objectGff["FirstName"]];
}
///
NWString GetLastName(ref GffNode objectGff){
	assert(_tlkResolver !is null, "Call initNWScript to setup TLK tables");
	return _tlkResolver[objectGff["LastName"]];
}

///
void SetFirstName(ref GffNode objectGff, in NWString name){
	int32_t language = 0;
	if(_tlkResolver !is null)
		language = _tlkResolver.standartTable.language;
	objectGff["FirstName"].as!(GffType.ExoLocString).strings[language * 2] = name;
}
///
void SetLastName(ref GffNode objectGff, in NWString name){
	int32_t language = 0;
	if(_tlkResolver !is null)
		language = _tlkResolver.standartTable.language;
	objectGff["LastName"].as!(GffType.ExoLocString).strings[language * 2] = name;
}

unittest{
	immutable dogeUtc = cast(immutable ubyte[])import("doge.utc");
	auto obj = new Gff(dogeUtc);
	assert(GetName(obj) == "Doge");

	SetFirstName(obj, "Sir doge");
	assert(GetName(obj) == "Sir doge");

	SetLastName(obj, "the mighty");
	assert(GetName(obj) == "Sir doge the mighty");
	assert(GetFirstName(obj) == "Sir doge");
	assert(GetLastName(obj) == "the mighty");
}


///
bool GetIsItemPropertyValid(ItemProperty ip){
	return ip.type >= 0;
}



private template TypeToNWTypeConst(T){
	static if     (is(T == NWInt))       enum TypeToNWTypeConst = 1;
	else static if(is(T == NWFloat))     enum TypeToNWTypeConst = 2;
	else static if(is(T == NWString))    enum TypeToNWTypeConst = 3;
	else static if(is(T == NWObject))    enum TypeToNWTypeConst = 4;
	else static if(is(T == NWLocation))  enum TypeToNWTypeConst = 5;
	else static assert(0, "Invalid type");
}


private void SetLocal(T)(ref GffNode oObject, NWString sVarName, T value){
	if("VarTable" in oObject.as!(GffType.Struct)){
		foreach(ref var ; oObject["VarTable"].as!(GffType.List)){
			// TODO: check behaviour when setting two variables with the same name and different types
			if(var["Name"].as!(GffType.ExoString) == sVarName){
				var["Type"].as!(GffType.DWord) = TypeToNWTypeConst!T;
				static if     (is(T == NWInt))       var["Value"].as!(GffType.Int) = value;
				else static if(is(T == NWFloat))     var["Value"].as!(GffType.Float) = value;
				else static if(is(T == NWString))    var["Value"].as!(GffType.ExoString) = value;
				else static if(is(T == NWObject))    var["Value"].as!(GffType.DWord) = value;
				else static if(is(T == NWLocation))  static assert(0, "Not implemented");
				else static assert(0, "Invalid type");
				return;
			}
		}
	}
	else{
		oObject["VarTable"] = GffNode(GffType.List);
	}

	auto var = GffNode(GffType.Struct);
	var["Name"] = GffNode(GffType.ExoString, null, sVarName);
	var["Type"] = GffNode(GffType.DWord, null, TypeToNWTypeConst!T);
	static if     (is(T == NWInt))       var["Value"] = GffNode(GffType.Int, null, value);
	else static if(is(T == NWFloat))     var["Value"] = GffNode(GffType.Float, null, value);
	else static if(is(T == NWString))    var["Value"] = GffNode(GffType.ExoString, null, value);
	else static if(is(T == NWObject))    var["Value"] = GffNode(GffType.DWord, null, value);
	else static if(is(T == NWLocation))  static assert(0, "Not implemented");
	else static assert(0, "Invalid type");

	oObject["VarTable"].as!(GffType.List) ~= var;
}

///
alias SetLocalInt = SetLocal!NWInt;
///
alias SetLocalFloat = SetLocal!NWFloat;
///
alias SetLocalString = SetLocal!NWString;
///
alias SetLocalObject = SetLocal!NWObject;
///
//alias SetLocalLocation = SetLocal!NWLocation;


private T GetLocal(T)(ref GffNode oObject, NWString sVarName){
	if("VarTable" in oObject.as!(GffType.Struct)){
		foreach(ref var ; oObject["VarTable"].as!(GffType.List)){
			if(var["Name"].as!(GffType.ExoString) == sVarName && var["Type"].as!(GffType.DWord) == TypeToNWTypeConst!T){
				static if     (is(T == NWInt))       return var["Value"].as!(GffType.Int);
				else static if(is(T == NWFloat))     return var["Value"].as!(GffType.Float);
				else static if(is(T == NWString))    return var["Value"].as!(GffType.ExoString);
				else static if(is(T == NWObject))    return var["Value"].as!(GffType.DWord);
				else static if(is(T == NWLocation))  static assert(0, "Not implemented");
				else static assert(0, "Invalid type");
			}
		}
	}
	return NWInitValue!T;
}
///
alias GetLocalInt = GetLocal!NWInt;
///
alias GetLocalFloat = GetLocal!NWFloat;
///
alias GetLocalString = GetLocal!NWString;
///
alias GetLocalObject = GetLocal!NWObject;
///
//alias GetLocalLocation = GetLocal!NWLocation;


unittest{
	import std.math;
	immutable dogeUtc = cast(immutable ubyte[])import("doge.utc");
	auto obj = new Gff(dogeUtc);

	SetLocalInt(obj, "TestInt", 5);
	SetLocalFloat(obj, "TestFloat", 5.3);
	SetLocalString(obj, "TestString", "Hello");

	assert(GetLocalInt(obj, "TestInt") == 5);

	assert(approxEqual(GetLocalFloat(obj, "TestFloat"), 5.3f));
	assert(GetLocalString(obj, "TestString") == "Hello");
	assert(GetLocalString(obj, "yolooo") == "");
	assert(GetLocalObject(obj, "TestInt") == OBJECT_INVALID);
}