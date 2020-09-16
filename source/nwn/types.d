// Types compatible with NWN
module nwn.types;

import std.stdint;
import std.string;

/// int
alias NWInt = int32_t;

/// float
alias NWFloat = float;

/// string
alias NWString = string;

/// object
alias NWObject = uint32_t;


/// vector
struct NWVector{
	NWFloat[3] value = [0.0, 0.0, 0.0];

	alias value this;

	string toString() const {
		import std.format: format;
		return format("[%f, %f, %f]", value[0], value[1], value[2]);
	}
	enum NWVector init = NWVector([0.0, 0.0, 0.0]);
}
/// location
///
/// Warning: The area is stored as an onject ID and can change between module runs.
struct NWLocation{
	NWObject area;
	NWVector position;
	NWFloat facing;

	string toString() const {
		import std.format: format;
		return format("%#x %s %f", area, position.toString(), facing);
	}
	enum NWLocation init = NWLocation(NWInitValue!NWObject, NWInitValue!NWVector, NWInitValue!NWFloat);
}


template NWInitValue(T){
	static if(is(T == NWInt))           enum NWInitValue = cast(NWInt)0;
	else static if(is(T == NWFloat))    enum NWInitValue = 0.0f;
	else static if(is(T == NWString))   enum NWInitValue = "";
	else static if(is(T == NWObject))   enum NWInitValue = NWObject.max;
	else static if(is(T == NWVector))   enum NWInitValue = NWVector.init;
	else static if(is(T == NWLocation)) enum NWInitValue = NWLocation.init;
	else static if(is(T == NWItemproperty)) enum NWInitValue = NWItemproperty(-1);
	else static assert(0, "Unknown type");
}

/// itemproperty
struct NWItemproperty {
	int32_t type = -1;
	int32_t subType = -1;
	int32_t costValue = -1;
	int32_t p1 = -1;

	string toString() const{
		return format!"%d.%d(%d, %d)"(type, subType, costValue, p1);
	}

	//string toPrettyString() const{
	//	immutable propNameLabel = getTwoDA("itempropdef").get("Label", type);

	//	immutable subTypeTable = getTwoDA("itempropdef").get("SubTypeResRef", type);
	//	string subTypeLabel;
	//	try subTypeLabel = subTypeTable is null? null : getTwoDA(subTypeTable).get("Label", subType);
	//	catch(TwoDAColumnNotFoundException){
	//		subTypeLabel = subTypeTable is null? null : getTwoDA(subTypeTable).get("NameString", subType);
	//	}

	//	immutable costValueTableIndex = getTwoDA("itempropdef").get("CostTableResRef", type);
	//	immutable costValueTable = costValueTableIndex is null? null : getTwoDA("iprp_costtable").get("Name", costValueTableIndex.to!uint);

	//	immutable costValueLabel = costValueTable is null? null : getTwoDA(costValueTable).get("Label", costValue);

	//	return propNameLabel
	//		~(subTypeLabel is null? null : "."~subTypeLabel)
	//		~(costValueLabel is null? null : "("~costValueLabel~")");
	//}
}