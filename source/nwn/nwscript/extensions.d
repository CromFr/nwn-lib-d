/// Useful functions that are not part of nwscript
module nwn.nwscript.extensions;

import std.conv: to, ConvException;
import std.math;
import std.meta;
import std.traits;

static import nwn.gff;
static import nwn.fastgff;
import nwn.types;
import nwn.nwscript.resources;


/// Checks if T is either a nwn.gff.GffStruct or a nwn.fastgff.GffStruct
template isGffStruct(T){
	enum isGffStruct = is(T: nwn.gff.GffStruct) || is(T: const(nwn.fastgff.GffStruct));
}

/// Imports either nwn.gff or nwn.fastgff, that provide T
package template ImportGffLib(T){
	enum ImportGffLib = "import " ~ moduleName!T ~ ";";
}

/// Calculate an item cost, without taking into account its additional cost
uint calcItemCost(ST)(ref ST oItem) if(isGffStruct!ST) {
	mixin(ImportGffLib!ST);
	// GetItemCost
	// num: malusCost
	// num2: bonusCost
	// num3: chargeCost
	// num4: unitPrice
	// num5: finalPrice
	const baseItemType = oItem["BaseItem"].get!GffInt;

	float malusCost = 0f;
	float bonusCost = 0f;
	float chargeCost = 0f;
	getPropertiesCost(oItem, bonusCost, malusCost, chargeCost);

	float unitPrice = getItemBaseCost(oItem);
	unitPrice += chargeCost;
	unitPrice += 1000f * (bonusCost * bonusCost);
	unitPrice -= 1000f * malusCost * malusCost;
	unitPrice *= getTwoDA("baseitems").get("itemmultiplier", baseItemType, 1f);

	const stack = oItem["StackSize"].get!GffWord;

	int finalPrice = cast(int)(unitPrice) * (stack > 0 ? stack : 1);

	if (finalPrice < 0)
		finalPrice = 0;

	if (finalPrice == 0 && unitPrice > 0f && unitPrice <= 1f)
		finalPrice = 1;

	return finalPrice;
}

unittest{
	import std.meta;
	initTwoDAPaths(["unittest/2da"]);

	foreach(GFF ; AliasSeq!(nwn.gff.Gff, nwn.fastgff.FastGff)){
		auto item = new GFF(cast(ubyte[])import("test_cost_armor.uti")).root;
		assert(calcItemCost(item) == 789_774);

		auto item2 = new GFF(cast(ubyte[])import("test_cost_bow.uti")).root;
		assert(calcItemCost(item2) == 375_303);
	}

}

/// Returns the item additional cost as defined in the blueprint, multiplied by the number of stacked items
int getItemModifyCost(ST)(ref ST oItem) if(isGffStruct!ST) {
	mixin(ImportGffLib!ST);
	const stack = oItem["StackSize"].get!GffWord;
	return oItem["ModifyCost"].to!int * (stack > 0 ? stack : 1);
}


private uint getItemBaseCost(ST)(ref ST oItem) if(isGffStruct!ST) {
	mixin(ImportGffLib!ST);
	const baseItemType = oItem["BaseItem"].get!GffInt;
	if(baseItemType != 16){// != OBJECT_TYPE_ARMOR
		return getTwoDA("baseitems").get("basecost", baseItemType).to!uint;
	}

	auto armor2da = getTwoDA("armorrulestats");
	const armorRulesType = oItem["ArmorRulesType"].get!GffByte;
	if(armorRulesType < armor2da.rows){
		return armor2da.get("cost", armorRulesType).to!uint;
	}
	return 0;
}

private void getPropertiesCost(ST)(ref ST oItem, out float bonusCost, out float malusCost, out float spellChargeCost) if(isGffStruct!ST) {
	mixin(ImportGffLib!ST);
	// A_2: bonusCost
	// A_3: malusCost
	// A_4: spellChargeCost
	// num: highestCastSpellCost
	// num2: secondHighestCastSpellCost
	// num3: totalCastSpellCost
	// num4: specialCostAdjust
	// num5: fTypeCost
	// num6: fSubTypeCost
	// num7: fCostValueCost
	// num8: cost
	// num9: cost
	bonusCost = 0;
	malusCost = 0;
	spellChargeCost = 0;

	float highestCastSpellCost = 0f;
	float secondHighestCastSpellCost = 0f;
	float totalCastSpellCost = 0f;

	foreach(ref prop ; oItem["PropertiesList"].get!GffList){
		auto ip = prop.toNWItemproperty;

		float specialCostAdjust = 0f;
		float fTypeCost = getTwoDA("itempropdef").get("cost", ip.type, 0f);

		float fSubTypeCost = 0.0;
		string sSubTypeTable = getTwoDA("itempropdef").get("subtyperesref", ip.type);
		if(sSubTypeTable !is null)
			fSubTypeCost = getTwoDA(sSubTypeTable).get("cost", ip.subType, 0f);
		float fCostValueCost = getCostValueCost(ip, specialCostAdjust);

		if(ip.type == 15){
			// CastSpell
			float cost = (fTypeCost + fCostValueCost) * fSubTypeCost;
			if (specialCostAdjust >= 1f && oItem["Charges"].get!GffByte >= 1)
			{
				cost = cost * oItem["Charges"].to!float / 50f;
			}
			totalCastSpellCost += cost / 2f;
			if (cost > highestCastSpellCost)
			{
				secondHighestCastSpellCost = highestCastSpellCost;
				highestCastSpellCost = cost;
			}
		}
		else{
			float cost;
			// Either the ip.type has Cost > 0 or ip.subType has Cost > 0
			if (fabs(fTypeCost) > 0f)
				cost = fTypeCost * fCostValueCost;
			else
				cost = fSubTypeCost * fCostValueCost;

			if(isIprpMalus(ip) || cost < 0f)
				malusCost += cost;
			else
				bonusCost += cost;
		}
	}

	foreach(ref red ; oItem["DmgReduction"].get!GffList){
		auto damageRed2da = getTwoDA("iprp_damagereduction");

		bonusCost += damageRed2da.get("Cost", red["DamageAmount"].get!GffInt).toNWFloat;
	}

	if (totalCastSpellCost > 0f)
	{
		spellChargeCost = totalCastSpellCost + highestCastSpellCost / 2f + secondHighestCastSpellCost / 4f;
	}

}

private bool isIprpMalus(NWItemproperty ip)
{
	switch (ip.type)
	{
		case 10://EnhancementPenalty
		case 21://DamagePenalty
		case 24://Damage_Vulnerability
		case 27://DecreaseAbilityScore
		case 28://DecreaseAC
		case 29://DecreasedSkill
		case 49://ReducedSavingThrows
		case 50://ReducedSpecificSavingThrow
			return true;
		default: return false;
	}
}


private float getCostValueCost(NWItemproperty ip, out float specialCostAdjust){
	specialCostAdjust = 0.0;
	float cost = 0.0;

	auto costTableRef = getTwoDA("itempropdef").get("CostTableResRef", ip.type);
	if(costTableRef !is null){
		auto costTableID = costTableRef.to!uint;
		if(costTableID == 3){ // IPRP_CHARGECOST
			switch (ip.costValue)
			{
				case 2: specialCostAdjust = 5.0; break; // 5_Charges/Use
				case 3: specialCostAdjust = 4.0; break; // 4_Charges/Use
				case 4: specialCostAdjust = 3.0; break; // 3_Charges/Use
				case 5: specialCostAdjust = 2.0; break; // 2_Charges/Use
				case 6: specialCostAdjust = 1.0; break; // 1_Charge/Use
				default: break;
			}
		}

		string costTable = getTwoDA("iprp_costtable").get("Name", costTableID);
		cost = getTwoDA(costTable).get("Cost", ip.costValue, 0f);
	}

	if (fabs(cost) <= float.epsilon)
		cost = cost < 0.0 ? -1.0 : 1.0;

	return cost;
}





// Converts an NWItemproperty into a developer-friendly string (without TLK translations)
string toPrettyString(in NWItemproperty ip){
	immutable propNameLabel = getTwoDA("itempropdef").get("Label", ip.type);

	immutable subTypeTable = getTwoDA("itempropdef").get("SubTypeResRef", ip.type);
	string subTypeLabel;
	if(subTypeTable !is null){
		auto subType2da = getTwoDA(subTypeTable);
		if("label" in subType2da)
			subTypeLabel = subType2da.get("label", ip.subType);
		else
			subTypeLabel = subType2da.get("NameString", ip.subType);
	}

	immutable costValueTableIndex = getTwoDA("itempropdef").get("CostTableResRef", ip.type);
	immutable costValueTable = costValueTableIndex is null? null : getTwoDA("iprp_costtable").get("Name", costValueTableIndex.to!uint);

	immutable costValueLabel = costValueTable is null? null : getTwoDA(costValueTable).get("Label", ip.costValue);

	return propNameLabel
		~(subTypeLabel is null? null : "."~subTypeLabel)
		~(costValueLabel is null? null : "("~costValueLabel~")");
}

/// Converts an itemproperty into its in-game description
string toGameString(in NWItemproperty ip){
	const resolv = getStrRefResolver();
	const props2DA = getTwoDA("itempropdef");
	const costTable2DA = getTwoDA("iprp_costtable");
	const paramTable2DA = getTwoDA("iprp_paramtable");

	string propName;
	string subType;
	string costValue;
	string paramValue;

	propName = resolv[props2DA.get("GameStrRef", ip.type, 0)];

	string subTypeTable = props2DA.get("SubTypeResRef", ip.type, "");
	if(subTypeTable != ""){
		int strref = getTwoDA(subTypeTable).get("Name", ip.subType, 0);
		if(strref > 0)
			subType = resolv[strref];
	}
	string costValueTableId = props2DA.get("CostTableResRef", ip.type, "");
	if(costValueTableId != ""){
		string costValueTable = costTable2DA.get("Name", costValueTableId.to!int);
		int strref = getTwoDA(costValueTable).get("Name", ip.costValue, 0);
		if(strref > 0)
			costValue = resolv[strref];
	}

	string paramTableId = props2DA.get("Param1ResRef", ip.type);
	if(paramTableId != ""){
		string paramTable = paramTable2DA.get("TableResRef", paramTableId.to!int);
		int strref = getTwoDA(paramTable).get("Name", ip.p1, 0);
		if(strref > 0)
			paramValue = resolv[strref];
	}
	return propName
		~ (subType !is null ? " " ~ subType : null)
		~ (costValue !is null ? " " ~ costValue : null)
		~ (paramValue !is null ? " " ~ paramValue : null);
}

// Converts a GFF struct to an item property
NWItemproperty toNWItemproperty(ST)(in ST node) if(isGffStruct!ST) {
	mixin(ImportGffLib!ST);
	return NWItemproperty(
		node["PropertyName"].get!GffWord,
		node["Subtype"].get!GffWord,
		node["CostValue"].get!GffWord,
		node["Param1Value"].get!GffByte,
	);
}

NWFloat toNWFloat(T)(in T value){
	// TODO: not efficient (exception allocation)
	try return value.to!NWFloat;
	catch(ConvException){}
	return 0.0;
}

NWInt toNWInt(T)(in T value){
	// TODO: not efficient (exception allocation)
	try return value.to!NWInt;
	catch(ConvException){}
	return 0;
}
