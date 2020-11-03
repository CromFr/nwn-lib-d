/// NWScript functions and types implemented in D
module nwn.nwscript.functions;

import std.stdint;
import std.array;
import std.string;
import std.conv: to;
import std.meta;

import nwn.tlk;
static import nwn.gff;
static import nwn.fastgff;
import nwn.twoda;
import nwn.nwscript.constants;
import nwn.nwscript.resources;
import nwn.nwscript.extensions;

public import nwn.types;


///
enum OBJECT_INVALID = NWObject.max;


///
NWString GetName(ST)(ref ST objectGff) if(isGffStruct!ST) {
	mixin(ImportGffLib!ST);
	scope resolv = getStrRefResolver();
	if(auto fname = "FirstName" in objectGff){
		auto firstName = fname.get!GffLocString.resolve(resolv);
		auto lastName = objectGff["LastName"].get!GffLocString.resolve(resolv);
		if(lastName != "")
			return [firstName, lastName].join(" ");
		return firstName;
	}
	if(auto localizedName = "LocalizedName" in objectGff)
		return localizedName.get!GffLocString.resolve(resolv);
	else if(auto locName = "LocName" in objectGff)
		return locName.get!GffLocString.resolve(resolv);
	return "";
}
///
NWString GetFirstName(ST)(ref ST objectGff) if(isGffStruct!ST) {
	mixin(ImportGffLib!ST);
	if("FirstName" in objectGff)
		return objectGff["FirstName"].get!GffLocString.resolve(getStrRefResolver());
	else if("LocalizedName" in objectGff)
		return objectGff["LocalizedName"].get!GffLocString.resolve(getStrRefResolver());
	return "";
}
///
NWString GetLastName(ST)(ref ST objectGff) if(isGffStruct!ST) {
	mixin(ImportGffLib!ST);
	if("LastName" in objectGff)
		return objectGff["LastName"].get!GffLocString.resolve(getStrRefResolver());
	return "";
}

///
void SetFirstName(ref nwn.gff.GffStruct objectGff, in NWString name){
	import nwn.gff;
	int32_t language = getStrRefResolver().standartTable.language;
	if("FirstName" in objectGff)
		objectGff["FirstName"].get!GffLocString.strings = [language * 2: name];
	else if("LocalizedName" in objectGff)
		objectGff["LocalizedName"].get!GffLocString.strings = [language * 2: name];
	else assert(0, "No FirstName GFF field");
}
///
void SetLastName(ref nwn.gff.GffStruct objectGff, in NWString name){
	import nwn.gff;
	assert("LastName" in objectGff, "No LastName GFF field");
	int32_t language = 0;
	if(getStrRefResolver() !is null)
		language = getStrRefResolver().standartTable.language;
	objectGff["LastName"].get!GffLocString.strings = [language * 2: name];
}

unittest{
	immutable dogeUtc = cast(immutable ubyte[])import("doge.utc");

	immutable dialogTlk = cast(immutable ubyte[])import("dialog.tlk");
	immutable userTlk = cast(immutable ubyte[])import("user.tlk");
	initStrRefResolver(new StrRefResolver(
		new Tlk(dialogTlk),
		new Tlk(userTlk)
	));

	{
		auto obj = new nwn.gff.Gff(dogeUtc).root;

		assert(GetName(obj) == "Doge");

		SetFirstName(obj, "Sir doge");
		assert(GetName(obj) == "Sir doge");

		SetLastName(obj, "the mighty");
		assert(GetName(obj) == "Sir doge the mighty");
		assert(GetFirstName(obj) == "Sir doge");
		assert(GetLastName(obj) == "the mighty");
	}
	{
		auto obj = new nwn.fastgff.FastGff(dogeUtc).root;
		assert(GetName(obj) == "Doge");
	}

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


private void SetLocal(T)(ref nwn.gff.GffStruct oObject, NWString sVarName, T value){
	import nwn.gff;
	if("VarTable" in oObject){
		foreach(ref var ; oObject["VarTable"].get!GffList){
			// TODO: check behaviour when setting two variables with the same name and different types
			if(var["Name"].get!GffString == sVarName){
				var["Type"].get!GffDWord = TypeToNWTypeConst!T;
				static if     (is(T == NWInt))       var["Value"].get!GffInt = value;
				else static if(is(T == NWFloat))     var["Value"].get!GffFloat = value;
				else static if(is(T == NWString))    var["Value"].get!GffString = value;
				else static if(is(T == NWObject))    var["Value"].get!GffDWord = value;
				else static if(is(T == NWLocation))  static assert(0, "Not implemented");
				else static assert(0, "Invalid type");
				return;
			}
		}
	}
	else{
		oObject["VarTable"] = GffList();
	}

	auto var = nwn.gff.GffStruct();
	var["Name"] = sVarName;
	var["Type"] = GffDWord(TypeToNWTypeConst!T);
	static if     (is(T == NWInt))       var["Value"] = GffInt(value);
	else static if(is(T == NWFloat))     var["Value"] = GffFloat(value);
	else static if(is(T == NWString))    var["Value"] = value;
	else static if(is(T == NWObject))    var["Value"] = GffDWord(value);
	else static if(is(T == NWLocation))  static assert(0, "Not implemented");
	else static assert(0, "Invalid type");

	oObject["VarTable"].get!GffList ~= var;
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


private T GetLocal(T, ST)(ref ST oObject, NWString sVarName) if(isGffStruct!ST) {
	mixin(ImportGffLib!ST);
	if("VarTable" in oObject){
		foreach(var ; oObject["VarTable"].get!GffList){
			if(var["Name"].get!GffString == sVarName && var["Type"].get!GffDWord == TypeToNWTypeConst!T){
				static if     (is(T == NWInt))       return var["Value"].get!GffInt;
				else static if(is(T == NWFloat))     return var["Value"].get!GffFloat;
				else static if(is(T == NWString))    return var["Value"].get!GffString;
				else static if(is(T == NWObject))    return var["Value"].get!GffDWord;
				else static if(is(T == NWLocation))  static assert(0, "Not implemented");
				else static assert(0, "Invalid type");
			}
		}
	}
	return NWInitValue!T;
}
///
NWInt GetLocalInt(ST)(ref ST oObject, NWString sVarName){ return GetLocal!NWInt(oObject, sVarName); };
///
NWFloat GetLocalFloat(ST)(ref ST oObject, NWString sVarName){ return GetLocal!NWFloat(oObject, sVarName); };
///
NWString GetLocalString(ST)(ref ST oObject, NWString sVarName){ return GetLocal!NWString(oObject, sVarName); };
///
NWObject GetLocalObject(ST)(ref ST oObject, NWString sVarName){ return GetLocal!NWObject(oObject, sVarName); };
///
//alias GetLocalLocation = GetLocal!NWLocation;


unittest{
	import std.math;
	immutable dogeUtc = cast(immutable ubyte[])import("doge.utc");
	{
		auto obj = new nwn.gff.Gff(dogeUtc).root;

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
	{
		auto obj = new nwn.fastgff.FastGff(dogeUtc).root;
		assert(GetLocalInt(obj, "aaabbb") == 0);
	}

}

private void DeleteLocal(T)(ref nwn.gff.GffStruct oObject, NWString sVarName){
	import nwn.gff;
	import std.algorithm: remove;
	if("VarTable" in oObject){
		foreach(i, ref var ; oObject["VarTable"].get!GffList){
			if(var["Name"].get!GffString == sVarName && var["Type"].get!GffDWord == TypeToNWTypeConst!T){
				oObject["VarTable"].get!GffList.children = oObject["VarTable"].get!GffList.children.remove(i);
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


private static nwn.gff.GffStruct[] currentGetItemPropertyRangeGff;
private static const(nwn.fastgff.GffStruct)[] currentGetItemPropertyRangeFastGff;

///
NWItemproperty GetFirstItemProperty(ST)(ref ST oItem) if(isGffStruct!ST) {
	mixin(ImportGffLib!ST);
	static if(is(ST: nwn.gff.GffStruct))
		alias currentGetItemPropertyRange = currentGetItemPropertyRangeGff;
	else
		alias currentGetItemPropertyRange = currentGetItemPropertyRangeFastGff;

	if(auto val = "PropertiesList" in oItem)
		currentGetItemPropertyRange = val.get!GffList;
	else
		return NWInitValue!NWItemproperty;

	if(currentGetItemPropertyRange.empty)
		return NWInitValue!NWItemproperty;

	return currentGetItemPropertyRange.front.toNWItemproperty;
}

///
NWItemproperty GetNextItemProperty(ST)(ref ST oItem) if(isGffStruct!ST) {
	mixin(ImportGffLib!ST);
	static if(is(ST: nwn.gff.GffStruct))
		alias currentGetItemPropertyRange = currentGetItemPropertyRangeGff;
	else
		alias currentGetItemPropertyRange = currentGetItemPropertyRangeFastGff;

	if(currentGetItemPropertyRange.empty)
		return NWInitValue!NWItemproperty;

	currentGetItemPropertyRange.popFront();

	if(currentGetItemPropertyRange.empty)
		return NWInitValue!NWItemproperty;

	return currentGetItemPropertyRange.front.toNWItemproperty;
}

unittest{
	immutable itemData = cast(immutable ubyte[])import("ceinturedeschevaliersquidisentni.uti");

	foreach(GFF ; AliasSeq!(nwn.gff.Gff, nwn.fastgff.FastGff)){
		auto item = new GFF(itemData).root;

		size_t index = 0;
		auto ip = GetFirstItemProperty(item);
		while(GetIsItemPropertyValid(ip)){
			assert(ip == item["PropertiesList"][index].toNWItemproperty, "Mismatch on ip " ~ index.to!string);
			index++;
			ip = GetNextItemProperty(item);
		}
		assert(index == 2);
	}
}

///
NWInt GetBaseItemType(ST)(in ST oItem) if(isGffStruct!ST) {
	mixin(ImportGffLib!ST);
	return oItem["BaseItem"].to!NWInt;
}

///
void AddItemProperty(NWInt nDurationType, NWItemproperty ipProperty, ref nwn.gff.GffStruct oItem, NWFloat fDuration=0.0f){
	import nwn.gff;
	assert(nDurationType == DURATION_TYPE_PERMANENT, "Only permanent is supported");
	if("PropertiesList" !in oItem){
		oItem["PropertiesList"] = GffList();
	}

	static nwn.gff.GffStruct buildPropStruct(in NWItemproperty iprp){
		nwn.gff.GffStruct ret;
		with(ret){
			assert(iprp.type < getTwoDA("itempropdef").rows);

			ret["PropertyName"] = GffWord(iprp.type);

			immutable subTypeTable = getTwoDA("itempropdef").get("SubTypeResRef", iprp.type);
			if(subTypeTable is null)
				assert(iprp.subType==uint16_t.max || iprp.subType == 0, format!"subType=%d is pointing to non-existent SubTypeTable (for iprp=%s)"(iprp.subType, iprp));
			else
				assert(iprp.subType!=uint16_t.max, "iprp.subType must be defined");

			ret["Subtype"] = GffWord(iprp.subType);

			string costTableResRef = getTwoDA("itempropdef").get("CostTableResRef", iprp.type);
			if(costTableResRef is null)
				assert(iprp.costValue==uint16_t.max || iprp.costValue == 0, format!"costValue=%d is pointing to non-existent CostTableResRef (for iprp=%s)"(iprp.costValue, iprp));
			else
				assert(iprp.costValue!=uint16_t.max, "iprp.costValue must be defined");

			ret["CostTable"] = GffByte(costTableResRef !is null? costTableResRef.to!ubyte : 0);
			ret["CostValue"] = GffWord(iprp.costValue);

			immutable paramTableResRef = getTwoDA("itempropdef").get("Param1ResRef", iprp.type);
			if(paramTableResRef !is null){
				assert(iprp.p1!=uint8_t.max, "iprp.p1 must be defined for IPRP " ~ iprp.to!string);
				ret["Param1"] = GffByte(paramTableResRef.to!ubyte);
				ret["Param1Value"] = GffByte(iprp.p1);
			}
			else{
				assert(iprp.p1==uint8_t.max || iprp.p1==0, format!"iprp.p1 pointing to non-existent Param1ResRef (for iprp=%s)"(iprp.to!string));
				ret["Param1"] = GffByte(0);
				ret["Param1Value"] = GffByte(0);
			}

			//ret["Param2"] = GffByte(0);
			//ret["Param2Value"] = GffByte(0);
			ret["ChanceAppear"] = GffByte(100);
			ret["UsesPerDay"] = GffByte(255);
			ret["Useable"] = GffByte(1);
		}
		return ret;
	}

	oItem["PropertiesList"].get!GffList ~= buildPropStruct(ipProperty);
}

///
void RemoveItemProperty(ref nwn.gff.GffStruct oItem, NWItemproperty ipProperty){
	import nwn.gff;
	import std.algorithm;

	auto subTypeTable = getTwoDA("itempropdef").get("SubTypeResRef", ipProperty.type);
	bool hasSubType = subTypeTable !is null && subTypeTable != "";
	auto costValueTable = getTwoDA("itempropdef").get("CostTableResRef", ipProperty.type);
	bool hasCostValue = costValueTable !is null && costValueTable != "" && costValueTable.to!int > 0;
	auto param1Table = getTwoDA("itempropdef").get("Param1ResRef", ipProperty.type);
	bool hasParam1 = param1Table !is null && param1Table != "" && param1Table.to!int >= 0;

	oItem["PropertiesList"].get!GffList.children = oItem["PropertiesList"].get!GffList.children.remove!((node){
		auto ip = node.toNWItemproperty;

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
	import nwn.gff;
	immutable itemData = cast(immutable ubyte[])import("ceinturedeschevaliersquidisentni.uti");
	auto item = new Gff(itemData).root;

	initTwoDAPaths(["unittest/2da"]);

	auto ipRegen10 = NWItemproperty(51, 0, 10);

	AddItemProperty(DURATION_TYPE_PERMANENT, ipRegen10, item);
	assert(item["PropertiesList"].get!GffList.length == 3);

	auto addedProp = item["PropertiesList"].get!GffList[$-1];
	assert(addedProp["PropertyName"].get!GffWord == 51);
	assert(addedProp["Subtype"].get!GffWord == 0);
	assert(addedProp["CostValue"].get!GffWord == 10);
	assert(addedProp["CostTable"].get!GffByte == 2);
	assert(addedProp["Param1"].get!GffByte == 0);
	assert(addedProp["Param1Value"].get!GffByte == 0);
	//assert(addedProp["Param2"].get!GffByte == 0);
	//assert(addedProp["Param2Value"].get!GffByte == 0);
	assert(addedProp["ChanceAppear"].get!GffByte == 100);
	assert(addedProp["UsesPerDay"].get!GffByte == 255);
	assert(addedProp["Useable"].get!GffByte == 1);

	auto ipRegen5 = NWItemproperty(51, 0, 5);
	RemoveItemProperty(item, ipRegen5);
	assert(item["PropertiesList"].get!GffList.length == 3);

	RemoveItemProperty(item, ipRegen10);
	assert(item["PropertiesList"].get!GffList.length == 2);
}

///
NWInt GetItemPropertyDurationType(NWItemproperty iprp){
	// duration is not stored in the struct
	return DURATION_TYPE_PERMANENT;
}

///
NWInt GetItemPropertyCostTable(NWItemproperty iProp){
	return getTwoDA("itempropdef").get!NWInt("CostTableResRef", iProp.type, -1);
}



///
NWString Get2DAString(NWString s2DA, NWString sColumn, NWInt nRow){
	return getTwoDA(s2DA).get!NWString(sColumn, nRow, "");
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