/// Useful functions that are not part of NWScript
module nwn.nwscript.tooling;

import std.conv: to;

import nwn.twoda;
import nwn.nwscript.functions;
import nwn.nwscript.resources;

// Converts an NWItemproperty into a user friendly string
string toPrettyString(in NWItemproperty ip){
	immutable propNameLabel = getTwoDA("itempropdef").get("Label", ip.type);

	immutable subTypeTable = getTwoDA("itempropdef").get("SubTypeResRef", ip.type);
	string subTypeLabel;
	try subTypeLabel = subTypeTable is null? null : getTwoDA(subTypeTable).get("Label", ip.subType);
	catch(TwoDAColumnNotFoundException){
		subTypeLabel = subTypeTable is null? null : getTwoDA(subTypeTable).get("NameString", ip.subType);
	}

	immutable costValueTableIndex = getTwoDA("itempropdef").get("CostTableResRef", ip.type);
	immutable costValueTable = costValueTableIndex is null? null : getTwoDA("iprp_costtable").get("Name", costValueTableIndex.to!uint);

	immutable costValueLabel = costValueTable is null? null : getTwoDA(costValueTable).get("Label", ip.costValue);

	return propNameLabel
		~(subTypeLabel is null? null : "."~subTypeLabel)
		~(costValueLabel is null? null : "("~costValueLabel~")");
}
