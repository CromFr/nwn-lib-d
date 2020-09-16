/// NWScript functions and types implemented in D
module nwn.nwscript.functions;

import std.stdint;
import std.array;
import std.string;
import std.conv: to;

import nwn.tlk;
import nwn.gff;
import nwn.twoda;
import nwn.nwscript.constants;
import nwn.nwscript.resources;

public import nwn.types;


///
enum OBJECT_INVALID = NWObject.max;


///
NWString GetName(ref GffStruct objectGff){
	scope resolv = getStrRefResolver();
	if("FirstName" in objectGff){
		auto firstName = resolv[objectGff["FirstName"]];
		auto lastName = resolv[objectGff["LastName"]];
		if(lastName != "")
			return [firstName, lastName].join(" ");
		return firstName;
	}
	if("LocalizedName" in objectGff)
		return resolv[objectGff["LocalizedName"]];
	else if("LocName" in objectGff)
		return resolv[objectGff["LocName"]];
	return "";
}
///
NWString GetFirstName(ref GffStruct objectGff){
	return getStrRefResolver()[objectGff["FirstName"]];
}
///
NWString GetLastName(ref GffStruct objectGff){
	return getStrRefResolver()[objectGff["LastName"]];
}

///
void SetFirstName(ref GffStruct objectGff, in NWString name){
	int32_t language = getStrRefResolver().standartTable.language;
	objectGff["FirstName"].as!(GffType.ExoLocString).strings[language * 2] = name;
}
///
void SetLastName(ref GffStruct objectGff, in NWString name){
	int32_t language = 0;
	if(getStrRefResolver() !is null)
		language = getStrRefResolver().standartTable.language;
	objectGff["LastName"].as!(GffType.ExoLocString).strings[language * 2] = name;
}

unittest{
	immutable dogeUtc = cast(immutable ubyte[])import("doge.utc");
	auto obj = new Gff(dogeUtc).as!(GffType.Struct);

	immutable dialogTlk = cast(immutable ubyte[])import("dialog.tlk");
	immutable userTlk = cast(immutable ubyte[])import("user.tlk");
	initStrRefResolver(new StrRefResolver(
		new Tlk(dialogTlk),
		new Tlk(userTlk)
	));

	assert(GetName(obj) == "Doge");

	SetFirstName(obj, "Sir doge");
	assert(GetName(obj) == "Sir doge");

	SetLastName(obj, "the mighty");
	assert(GetName(obj) == "Sir doge the mighty");
	assert(GetFirstName(obj) == "Sir doge");
	assert(GetLastName(obj) == "the mighty");
}


///
bool GetIsItemPropertyValid(NWItemproperty ip){
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


private void SetLocal(T)(ref GffStruct oObject, NWString sVarName, T value){
	if("VarTable" in oObject){
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


private T GetLocal(T)(ref GffStruct oObject, NWString sVarName){
	if("VarTable" in oObject){
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
	auto obj = new Gff(dogeUtc).as!(GffType.Struct);

	SetLocalInt(obj, "TestInt", 5);
	SetLocalFloat(obj, "TestFloat", 5.3);
	SetLocalString(obj, "TestString", "Hello");

	assert(GetLocalInt(obj, "TestInt") == 5);

	assert(approxEqual(GetLocalFloat(obj, "TestFloat"), 5.3f));
	assert(GetLocalString(obj, "TestString") == "Hello");
	assert(GetLocalString(obj, "yolooo") == "");
	assert(GetLocalObject(obj, "TestInt") == OBJECT_INVALID);
}



///
NWInt GetItemPropertyType(NWItemproperty ip){
	return ip.type;
}
///
NWInt GetItemPropertySubType(NWItemproperty ip){
	return ip.subType;
}
///
NWInt GetItemPropertyCostTableValue(NWItemproperty ip){
	return ip.costValue;
}
///
NWInt GetItemPropertyParam1Value(NWItemproperty ip){
	return ip.p1;
}



private NWItemproperty gffStructToIPRP(in gffTypeToNative!(GffType.Struct) node){
	return NWItemproperty(
		node["PropertyName"].as!(GffType.Word),
		node["Subtype"].as!(GffType.Word),
		node["CostValue"].as!(GffType.Word),
		node["Param1"].as!(GffType.Byte),
	);
}

private static GffNode[] currentGetItemPropertyRange;
///
NWItemproperty GetFirstItemProperty(ref GffStruct oItem){
	if("PropertiesList" !in oItem){
		return NWInitValue!NWItemproperty;
	}

	currentGetItemPropertyRange = oItem["PropertiesList"].as!(GffType.List);

	return gffStructToIPRP(currentGetItemPropertyRange.front.as!(GffType.Struct));
}

///
NWItemproperty GetNextItemProperty(ref GffStruct oItem){
	currentGetItemPropertyRange.popFront();

	if(currentGetItemPropertyRange.empty)
		return NWInitValue!NWItemproperty;
	return gffStructToIPRP(currentGetItemPropertyRange.front.as!(GffType.Struct));
}

///
NWInt GetBaseItemType(in GffStruct oItem){
	return oItem["BaseItem"].to!NWInt;
}

///
void AddItemProperty(NWInt nDurationType, NWItemproperty ipProperty, ref GffStruct oItem, NWFloat fDuration=0.0f){
	assert(nDurationType == DURATION_TYPE_PERMANENT, "Only permanent is supported");
	if("PropertiesList" !in oItem){
		oItem["PropertiesList"] = GffNode(GffType.List);
	}

	static GffStruct buildPropStruct(in NWItemproperty iprp){
		GffStruct ret;
		with(ret){
			assert(iprp.type < getTwoDA("itempropdef").rows);

			ret["PropertyName"] = GffNode(GffType.Word, null, iprp.type);

			immutable subTypeTable = getTwoDA("itempropdef").get("SubTypeResRef", iprp.type);
			if(subTypeTable is null)
				assert(iprp.subType==uint16_t.max, "iprp.subType pointing to non-existent SubTypeTable");
			else
				assert(iprp.subType!=uint16_t.max, "iprp.subType must be defined");

			ret["Subtype"] = GffNode(GffType.Word, null, iprp.subType);

			string costTableResRef = getTwoDA("itempropdef").get("CostTableResRef", iprp.type);
			if(costTableResRef is null)
				assert(iprp.costValue==uint16_t.max, "iprp.costValue pointing to non-existent CostTableResRef");
			else
				assert(iprp.costValue!=uint16_t.max, "iprp.costValue must be defined");

			ret["CostTable"] = GffNode(GffType.Byte, null, costTableResRef !is null? costTableResRef.to!ubyte : ubyte.max);
			ret["CostValue"] = GffNode(GffType.Word, null, iprp.costValue);


			immutable paramTableResRef = getTwoDA("itempropdef").get("Param1ResRef", iprp.type);
			if(paramTableResRef !is null){
				assert(iprp.p1!=uint8_t.max, "iprp.p1 must be defined");
				ret["Param1"] = GffNode(GffType.Byte, null, paramTableResRef.to!ubyte);
				ret["iprp.p1"] = GffNode(GffType.Byte, null, iprp.p1);
			}
			else{
				assert(iprp.p1==uint8_t.max, "iprp.p1 pointing to non-existent Param1ResRef");
				ret["Param1"] = GffNode(GffType.Byte, null, uint8_t.max);
				ret["Param1Value"] = GffNode(GffType.Byte, null, uint8_t.max);
			}

			ret["ChanceAppear"] = GffNode(GffType.Byte, null, 100);
			ret["UsesPerDay"] = GffNode(GffType.Byte, null, 255);
			ret["Useable"] = GffNode(GffType.Byte, null, 1);
		}
		return ret;
	}

	oItem["PropertiesList"].as!(GffType.List) ~= GffNode(GffType.Struct, null, buildPropStruct(ipProperty));

}

///
int GetItemPropertyDurationType(NWItemproperty iprp){
	// duration is not stored in the struct
	return DURATION_TYPE_PERMANENT;
}

///
void RemoveItemProperty(ref GffStruct oItem, NWItemproperty ipProperty){
	import std.algorithm;

	oItem["PropertiesList"].as!(GffType.List).remove!(prop => {
		auto ip = gffStructToIPRP(prop.as!(GffType.Struct));
		return ip == ipProperty;
	});
}