
module nwn.types;
import std.stdint;

alias NWInt = int32_t;

alias NWFloat = float;

alias NWString = string;

alias NWObject = uint32_t;

struct NWVector{
	float[3] value;

	alias value this;
}

struct NWLocation{
	NWObject area;
	NWVector position;
	NWFloat facing;
}

