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

	/// Get/set vector values
	@property{
		NWFloat x() const { return value[0]; }
		void x(NWFloat rhs) { value[0] = rhs; }
		NWFloat y() const { return value[1]; }
		void y(NWFloat rhs) { value[1] = rhs; }
		NWFloat z() const { return value[2]; }
		void z(NWFloat rhs) { value[2] = rhs; }
	}

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
	else static if(is(T == NWItemproperty)) enum NWInitValue = NWItemproperty();
	else static assert(0, "Unknown type");
}

/// itemproperty
struct NWItemproperty {
	uint16_t type = uint16_t.max;
	uint16_t subType = 0;
	uint16_t costValue = 0;
	uint8_t p1 = 0;

	string toString() const{
		return format!"%d.%d(%d, %d)"(type, subType, costValue, p1);
	}
}