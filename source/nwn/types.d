
module nwn.types;
import std.stdint;

alias NWInt = int32_t;

alias NWFloat = float;

alias NWString = string;

alias NWObject = uint32_t;

struct NWVector{
	float[3] value;

	alias value this;

	string toString() const {
		import std.format: format;
		return format("[%f, %f, %f]", value[0], value[1], value[2]);
	}
}

struct NWLocation{
	NWObject area;
	NWVector position;
	NWFloat facing;

	string toString() const {
		import std.format: format;
		return format("%#x %s %f", area, position.toString(), facing);
	}
}

