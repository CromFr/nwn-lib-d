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
import nwn.nwscript.extensions;

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
	if("FirstName" in objectGff)
		return getStrRefResolver()[objectGff["FirstName"]];
	else if("LocalizedName" in objectGff)
		return getStrRefResolver()[objectGff["LocalizedName"]];
	return "";
}
///
NWString GetLastName(ref GffStruct objectGff){
	if("LastName" in objectGff)
		return getStrRefResolver()[objectGff["LastName"]];
	return "";
}

///
void SetFirstName(ref GffStruct objectGff, in NWString name){
	int32_t language = getStrRefResolver().standartTable.language;
	if("FirstName" in objectGff)
		objectGff["FirstName"].as!(GffType.ExoLocString).strings = [language * 2: name];
	else if("LocalizedName" in objectGff)
		objectGff["LocalizedName"].as!(GffType.ExoLocString).strings = [language * 2: name];
	else assert(0, "No FirstName GFF field");
}
///
void SetLastName(ref GffStruct objectGff, in NWString name){
	assert("LastName" in objectGff, "No LastName GFF field");
	int32_t language = 0;
	if(getStrRefResolver() !is null)
		language = getStrRefResolver().standartTable.language;
	objectGff["LastName"].as!(GffType.ExoLocString).strings = [language * 2: name];
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
	return ip.type != uint16_t.max;
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

	DeleteLocalInt(obj, "TestString");
	assert(GetLocalString(obj, "TestString") == "Hello");
	DeleteLocalString(obj, "TestString");
	assert(GetLocalString(obj, "TestString") == "");

}

private void DeleteLocal(T)(ref GffStruct oObject, NWString sVarName){
	import std.algorithm: remove;
	if("VarTable" in oObject){
		foreach(i, ref var ; oObject["VarTable"].as!(GffType.List)){
			if(var["Name"].as!(GffType.ExoString) == sVarName && var["Type"].as!(GffType.DWord) == TypeToNWTypeConst!T){
				oObject["VarTable"].as!(GffType.List) = oObject["VarTable"].as!(GffType.List).remove(i);
				return;
			}
		}
	}
}
///
alias DeleteLocalInt = DeleteLocal!NWInt;
///
alias DeleteLocalFloat = DeleteLocal!NWFloat;
///
alias DeleteLocalString = DeleteLocal!NWString;
///
alias DeleteLocalObject = DeleteLocal!NWObject;
///
alias DeleteLocalLocation = DeleteLocal!NWLocation;



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



private static GffNode[] currentGetItemPropertyRange;
///
NWItemproperty GetFirstItemProperty(ref GffStruct oItem){
	if("PropertiesList" !in oItem)
		return NWInitValue!NWItemproperty;

	currentGetItemPropertyRange = oItem["PropertiesList"].as!(GffType.List);

	if(currentGetItemPropertyRange.empty)
		return NWInitValue!NWItemproperty;

	return currentGetItemPropertyRange.front.as!(GffType.Struct).toNWItemproperty;
}

///
NWItemproperty GetNextItemProperty(ref GffStruct oItem){
	if(currentGetItemPropertyRange.empty)
		return NWInitValue!NWItemproperty;

	currentGetItemPropertyRange.popFront();

	if(currentGetItemPropertyRange.empty)
		return NWInitValue!NWItemproperty;

	return currentGetItemPropertyRange.front.as!(GffType.Struct).toNWItemproperty;
}

unittest{
	immutable itemData = cast(immutable ubyte[])import("ceinturedeschevaliersquidisentni.uti");
	auto item = new Gff(itemData).as!(GffType.Struct);

	size_t index = 0;
	auto ip = GetFirstItemProperty(item);
	while(GetIsItemPropertyValid(ip)){
		assert(ip == item["PropertiesList"][index].as!(GffType.Struct).toNWItemproperty, "Mismatch on ip " ~ index.to!string);
		index++;
		ip = GetNextItemProperty(item);
	}
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

			ret["PropertyName"] = GffNode(GffType.Word, "PropertyName", iprp.type);

			immutable subTypeTable = getTwoDA("itempropdef").get("SubTypeResRef", iprp.type);
			if(subTypeTable is null)
				assert(iprp.subType==uint16_t.max || iprp.subType == 0, format!"subType=%d is pointing to non-existent SubTypeTable (for iprp=%s)"(iprp.subType, iprp));
			else
				assert(iprp.subType!=uint16_t.max, "iprp.subType must be defined");

			ret["Subtype"] = GffNode(GffType.Word, "Subtype", iprp.subType);

			string costTableResRef = getTwoDA("itempropdef").get("CostTableResRef", iprp.type);
			if(costTableResRef is null)
				assert(iprp.costValue==uint16_t.max || iprp.costValue == 0, format!"costValue=%d is pointing to non-existent CostTableResRef (for iprp=%s)"(iprp.costValue, iprp));
			else
				assert(iprp.costValue!=uint16_t.max, "iprp.costValue must be defined");

			ret["CostTable"] = GffNode(GffType.Byte, "CostTable", costTableResRef !is null? costTableResRef.to!ubyte : 0);
			ret["CostValue"] = GffNode(GffType.Word, "CostValue", iprp.costValue);

			immutable paramTableResRef = getTwoDA("itempropdef").get("Param1ResRef", iprp.type);
			if(paramTableResRef !is null){
				assert(iprp.p1!=uint8_t.max, "iprp.p1 must be defined for IPRP " ~ iprp.to!string);
				ret["Param1"] = GffNode(GffType.Byte, "Param1", paramTableResRef.to!ubyte);
				ret["Param1Value"] = GffNode(GffType.Byte, "Param1Value", iprp.p1);
			}
			else{
				assert(iprp.p1==uint8_t.max || iprp.p1==0, format!"iprp.p1 pointing to non-existent Param1ResRef (for iprp=%s)"(iprp.to!string));
				ret["Param1"] = GffNode(GffType.Byte, "Param1", 0);
				ret["Param1Value"] = GffNode(GffType.Byte, "Param1Value", 0);
			}

			//ret["Param2"] = GffNode(GffType.Byte, "Param2", 0);
			//ret["Param2Value"] = GffNode(GffType.Byte, "Param2Value", 0);
			ret["ChanceAppear"] = GffNode(GffType.Byte, "ChanceAppear", 100);
			ret["UsesPerDay"] = GffNode(GffType.Byte,"UsesPerDay", 255);
			ret["Useable"] = GffNode(GffType.Byte, "Useable", 1);
		}
		return ret;
	}

	oItem["PropertiesList"].as!(GffType.List) ~= GffNode(GffType.Struct, null, buildPropStruct(ipProperty));
}

///
void RemoveItemProperty(ref GffStruct oItem, NWItemproperty ipProperty){
	import std.algorithm;

	auto subTypeTable = getTwoDA("itempropdef").get("SubTypeResRef", ipProperty.type);
	bool hasSubType = subTypeTable !is null && subTypeTable != "";
	auto costValueTable = getTwoDA("itempropdef").get("CostTableResRef", ipProperty.type);
	bool hasCostValue = costValueTable !is null && costValueTable != "" && costValueTable.to!int > 0;
	auto param1Table = getTwoDA("itempropdef").get("Param1ResRef", ipProperty.type);
	bool hasParam1 = param1Table !is null && param1Table != "" && param1Table.to!int >= 0;

	oItem["PropertiesList"].as!(GffType.List) = oItem["PropertiesList"].as!(GffType.List).remove!((node){
		auto ip = node.as!(GffType.Struct).toNWItemproperty;

		if(ip.type != ipProperty.type)
			return false;
		if(hasSubType && ip.subType != ipProperty.subType)
			return false;
		if(hasCostValue && ip.costValue != ipProperty.costValue)
			return false;
		if(hasParam1 && ip.p1 != ipProperty.p1)
			return false;
		return true;
	});
}

unittest{
	immutable itemData = cast(immutable ubyte[])import("ceinturedeschevaliersquidisentni.uti");
	auto item = new Gff(itemData).as!(GffType.Struct);

	initTwoDAPaths(["unittest/2da"]);

	auto ipRegen10 = NWItemproperty(51, 0, 10);

	AddItemProperty(DURATION_TYPE_PERMANENT, ipRegen10, item);
	assert(item["PropertiesList"].as!(GffType.List).length == 3);

	auto addedProp = item["PropertiesList"].as!(GffType.List)[$-1].as!(GffType.Struct);
	assert(addedProp["PropertyName"].as!(GffType.Word) == 51);
	assert(addedProp["Subtype"].as!(GffType.Word) == 0);
	assert(addedProp["CostValue"].as!(GffType.Word) == 10);
	assert(addedProp["CostTable"].as!(GffType.Byte) == 2);
	assert(addedProp["Param1"].as!(GffType.Byte) == 0);
	assert(addedProp["Param1Value"].as!(GffType.Byte) == 0);
	//assert(addedProp["Param2"].as!(GffType.Byte) == 0);
	//assert(addedProp["Param2Value"].as!(GffType.Byte) == 0);
	assert(addedProp["ChanceAppear"].as!(GffType.Byte) == 100);
	assert(addedProp["UsesPerDay"].as!(GffType.Byte) == 255);
	assert(addedProp["Useable"].as!(GffType.Byte) == 1);

	auto ipRegen5 = NWItemproperty(51, 0, 5);
	RemoveItemProperty(item, ipRegen5);
	assert(item["PropertiesList"].as!(GffType.List).length == 3);

	RemoveItemProperty(item, ipRegen10);
	assert(item["PropertiesList"].as!(GffType.List).length == 2);
}

///
NWInt GetItemPropertyDurationType(NWItemproperty iprp){
	// duration is not stored in the struct
	return DURATION_TYPE_PERMANENT;
}

///
NWInt GetItemPropertyCostTable(NWItemproperty iProp){
	string sCostTableID = getTwoDA("itempropdef")[iProp.type, "CostTableResRef"];
	if(sCostTableID.length > 0)
		return sCostTableID.to!NWInt;
	return -1;
}



///
NWString Get2DAString(NWString s2DA, NWString sColumn, NWInt nRow){
	return getTwoDA(s2DA)[nRow, sColumn];
}



///
NWString IntToString(NWInt nInteger){
	return nInteger.to!NWString;
}
///
NWFloat IntToFloat(NWInt nInteger){
	return nInteger.to!NWFloat;
}
///
NWInt FloatToInt(NWFloat fFloat){
	return fFloat.to!NWInt;
}
///
NWString FloatToString(NWFloat fFloat, NWInt nWidth=18, NWInt nDecimals=9){
	return format("%" ~ nWidth.to!string ~ "." ~ nDecimals.to!string ~ "f", fFloat);
}
///
NWInt StringToInt(NWString sNumber){
	return sNumber.to!NWInt;
}
///
NWFloat StringToFloat(NWString sNumber){
	return sNumber.to!NWFloat;
}