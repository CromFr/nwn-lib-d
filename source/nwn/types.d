
module nwn.types;
import std.stdint;

alias NWInt = int32_t;

alias NWFloat = float;

alias NWString = string;

alias NWObject = uint32_t;

alias NWVector = float[3];

struct NWLocation{
	NWObject area;
	NWVector position;
	NWFloat facing;
}

