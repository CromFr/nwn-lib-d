/// Terrain (trn, trx)
module nwn.trn;

import std.stdint;
import std.string;
import std.conv: to;
import std.traits;
import std.exception: enforce;
import nwnlibd.parseutils;

import nwn.gff : GffNode, GffType, gffTypeToNative;

import std.stdio: writeln, writefln;
version(unittest) import std.exception: assertThrown, assertNotThrown;

class TrnParseException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
class TrnTypeException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
class TrnValueSetException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

///Type of a packet's payload
enum TrnPacketType{
	NWN2_TRWH,/// TerrainWidthHeight
	NWN2_TRRN,/// Main terrain data
	NWN2_WATR,/// Water
	NWN2_ASWM,/// Zipped walkmesh data
}
template TrnPacketTypeToPayload(TrnPacketType type){
	static if(type==TrnPacketType.NWN2_TRWH) alias TrnPacketTypeToPayload = TrnNWN2TerrainDimPayload;
	static if(type==TrnPacketType.NWN2_TRRN) alias TrnPacketTypeToPayload = TrnNWN2MegatilePayload;
	static if(type==TrnPacketType.NWN2_WATR) alias TrnPacketTypeToPayload = TrnNWN2WaterPayload;
	static if(type==TrnPacketType.NWN2_ASWM) alias TrnPacketTypeToPayload = TrnNWN2WalkmeshPayload;
}
TrnPacketType toTrnPacketType(char[4] str, string nwnVersion){
	return (nwnVersion~"_"~str.charArrayToString).to!TrnPacketType;
}



struct TrnPacket{

	@property{
		///
		TrnPacketType type()const{return m_type;}
	}
	package TrnPacketType m_type;

	///
	ref TrnPacketTypeToPayload!T as(TrnPacketType T)(){
		if(type != T)
			throw new TrnTypeException("Type mismatch");
		return *cast(TrnPacketTypeToPayload!T*)payload.ptr;
	}

private:
	this(TrnPacketType type, in void[] payloadData){
		import std.traits: EnumMembers;

		m_type = type;

		typeswitch:
		final switch(type) with(TrnPacketType){
			foreach(TYPE ; EnumMembers!TrnPacketType){
				case TYPE:
					payload.length = TrnPacketTypeToPayload!TYPE.sizeof;
					alias PAYLOAD = TrnPacketTypeToPayload!TYPE;
					*(cast(PAYLOAD*)payload.ptr) = PAYLOAD(payloadData);
					break typeswitch;
			}
		}
	}
	void[] payload;
}






/// UNTESTED WITH NWN1
class Trn{
	this(in string path){
		import std.file: read;
		this(path.read());
	}

	@property string nwnVersion()const{return m_nwnVersion;}
	package string m_nwnVersion;

	@property uint versionMajor()const{return m_versionMajor;}
	package uint m_versionMajor;

	@property uint versionMinor()const{return m_versionMinor;}
	package uint m_versionMinor;

	this(in void[] rawData){
		align(1) struct Header{
			char[4] file_type;
			uint16_t version_major;
			uint16_t version_minor;
			uint32_t resource_count;
		}
		align(1) struct PacketIndices{
			char[4] type;
			uint32_t offset;
		}
		align(1) struct Packet{
			char[4] type;
			uint32_t payload_length;
			ubyte payload_start;
		}

		enforce!TrnParseException(rawData.length>Header.sizeof, "Data is too small to contain the header");

		auto header =        cast(Header*)        rawData.ptr;
		auto packetIndices = cast(PacketIndices*)(rawData.ptr+Header.sizeof);

		m_nwnVersion = header.file_type.charArrayToString;
		m_versionMajor = header.version_major;
		m_versionMinor = header.version_minor;

		foreach(i ; 0..header.resource_count){
			//writeln("=====> ", packetIndices[i]);

			immutable type = packetIndices[i].type.toTrnPacketType(nwnVersion);
			immutable offset = packetIndices[i].offset;

			immutable packet = cast(immutable Packet*)(rawData.ptr+offset);
			immutable packetType = packet.type.toTrnPacketType(nwnVersion);
			immutable packetLength = packet.payload_length;

			enforce!TrnParseException(type==packetType, "Packet type does not match the one referenced in packet indices");

			writeln(packets.length,": ",type);
			packets ~= TrnPacket(type, (&packet.payload_start)[0..packetLength]);
		}
	}


	TrnPacket[] packets;
}



/// Terrain dimensions
struct TrnNWN2TerrainDimPayload{
	uint32_t width;/// Width in megatiles
	uint32_t height;/// Height in megatiles
	uint32_t unknown;/// Unknown/unused

	package this(in void[] payload){
		width = *(cast(uint32_t*)&payload[0]);
		height = *(cast(uint32_t*)&payload[4]);
		unknown = *(cast(uint32_t*)&payload[8]);
	}
}

/// Megatile information
struct TrnNWN2MegatilePayload{
	string name;///name of the terrain
	///
	static struct Texture{
		string name;
		float[3] color;/// rgb
	}
	Texture[6] textures;/// Textures on the megatile, with their blend color
	///
	static struct Vertex{
		float[3] position;/// x y z
		float[3] normal;  /// normal vector
		ubyte[4] tinting; /// argb
		float[2] xy_0to10;/// ?
		float[2] xy_0to1; /// ?
	}
	Vertex[] vertices;/// Terrain geometry
	///
	static struct Triangle{
		uint16_t[3] vertices;///Triangle vertex indices in $(D TrnNWN2TerrainDimPayload.vertices)
	}
	/// Walkmesh grid triangles positions.
	/// Each uint16_t an index in `vertices` corresponding to a triangle vertex
	Triangle[] triangles;
	ubyte[] dds_a;/// 32 bit DDS bitmap. r,g,b,a defines the intensity of textures 0,1,2,3
	ubyte[] dds_b;/// 32 bit DDS bitmap. r,g defines the intensity of textures 4,5
	static struct Grass{
		char[32] name;
		char[32] texture;
		static struct Blade{
			float[3] position;
			float[3] direction;
			float[3] dimension;
		}
		Blade[] blades;
	}
	Grass[] grass;/// Grass "objects"


	package this(in void[] payload){
		auto data = ChunkReader(payload);

		name = data.read!(char[128]).ptr.fromStringz.idup;

		foreach(ref texture ; textures){
			texture.name = data.read!(char[32]).ptr.fromStringz.idup;
		}
		foreach(ref texture ; textures){
			texture.color = data.read!(float[3]);
		}
		vertices.length  = data.read!uint32_t;
		triangles.length = data.read!uint32_t;

		foreach(ref vertex ; vertices){
			vertex = data.readStruct!Vertex;
		}
		foreach(ref triangle ; triangles){
			triangle = data.read!Triangle;
		}
		immutable dds_a_length = data.read!uint32_t;
		dds_a = data.readArray(dds_a_length).dup;
		immutable dds_b_length = data.read!uint32_t;
		dds_b = data.readArray(dds_b_length).dup;

		immutable grass_count = data.read!uint32_t;
		grass.length = grass_count;
		foreach(ref g ; grass){
			g.name = data.read!(typeof(g.name));
			g.texture = data.read!(typeof(g.texture));
			immutable blades_count = data.read!uint32_t;
			g.blades = data.readArray!(Grass.Blade)(blades_count*Grass.Blade.sizeof).dup;
		}
		assert(data.read_ptr == payload.length, "some bytes were not read");
	}
}

/// Water information
struct TrnNWN2WaterPayload{

	ubyte[128] unknown;/// Probably a name
	float[3] color;/// R,G,B
	float[2] ripple;/// Ripples
	float smoothness;/// Smoothness
	float reflect_bias;/// Reflection bias
	float reflect_power;/// Reflection power
	float unknown2;/// Always 180.0
	float unknown3;/// Always 0.5
	///
	static struct Texture{
		string name;/// Texture name
		float[2] direction;/// Scrolling direction
		float rate;/// Scrolling speed
		float angle;/// Scrolling angle in radiant
	}
	Texture[3] textures;/// Water textures
	float[2] offset;/// x,y offset in water-space <=> megatile_coordinates/8
	///
	static struct Vertex{
		float[3] position;/// x y z
		float[2] xy_0to5;/// ?
		float[2] xy_0to1;/// ?
	}
	Vertex[] vertices;
	///
	static struct Triangle{
		uint16_t[3] vertices;///Triangle vertex indices in $(D TrnNWN2WaterPayload.vertices)
	}
	/// Walkmesh grid triangles positions.
	/// Each uint16_t an index in `vertices` corresponding to a triangle vertex
	Triangle[] triangles;
	uint32_t[] triangles_flags;/// 0 = has water, 1 = no water
	ubyte[] dds;/// DDS bitmap
	uint32_t[2] megatile_position;/// Position of the associated megatile in the terrain


	package this(in void[] payload){
		auto data = ChunkReader(payload);

		unknown       = data.read!(typeof(unknown));
		color         = data.read!(typeof(color));
		smoothness    = data.read!(typeof(smoothness));
		reflect_bias  = data.read!(typeof(reflect_bias));
		reflect_power = data.read!(typeof(reflect_power));
		unknown2      = data.read!(typeof(unknown2));
		unknown3      = data.read!(typeof(unknown3));

		foreach(ref texture ; textures){
			texture.name      = data.read!(char[32]).ptr.fromStringz.idup;
			texture.direction = data.read!(typeof(texture.direction));
			texture.rate      = data.read!(typeof(texture.rate));
			texture.angle     = data.read!(typeof(texture.angle));
		}

		offset           = data.read!(typeof(offset));
		vertices.length  = data.read!uint32_t;
		triangles.length = data.read!uint32_t;

		foreach(ref vertex ; vertices){
			vertex = data.readStruct!Vertex;
		}
		foreach(ref triangle ; triangles){
			triangle = data.readStruct!Triangle;
		}
		triangles_flags = data.readArray!uint32_t(triangles.length).dup;

		immutable dds_length = data.read!uint32_t;
		dds = data.readArray(dds_length).dup;

		megatile_position = data.read!(typeof(megatile_position));

		//writeln(data.read_ptr, "=====", payload.length);
		assert(data.read_ptr == payload.length, "some bytes were not read");
	}
}
struct TrnNWN2WalkmeshPayload{

	string data_type;

	static align(1) struct Header{
		static assert(this.sizeof==53);
		align(1):
		void[37] unknownA;
		uint32_t terrain_vertices_count;
		uint32_t unknown0_count;
		uint32_t triangles_count;
		uint32_t unknownB;
	}
	Header header;
	static align(1) struct Vertex{
		static assert(this.sizeof==12);
		align(1):
		float[3] position;
	}
	Vertex[] vertices;

	static align(1) struct Unknown0{
		static assert(this.sizeof==16);
		align(1):
		uint32_t[4] data;
	}
	Unknown0[] unknown0_block;

	static align(1) struct Triangle{
		static assert(this.sizeof==64);
		align(1):
		uint32_t[3] vertices;
		uint32_t[6] dataA;
		float[6] dataB;
		uint16_t[2] flags;
	}
	Triangle[] triangles;


	ubyte[] remaining_data;





	package this(in void[] payload){
		auto data = ChunkReader(payload);

		data_type               = data.read!(char[4]).charArrayToString;
		immutable comp_length   = data.read!uint32_t;
		immutable uncomp_length = data.read!uint32_t;
		auto comp_wm            = data.readArray(comp_length);

		// zlib deflate
		import std.zlib: uncompress;
		auto walkmeshData = uncompress(comp_wm, uncomp_length);
		assert(walkmeshData.length == uncomp_length, "Length mismatch");

		auto wmdata = ChunkReader(walkmeshData);

		header = wmdata.read!Header;
		assert(wmdata.read_ptr==0x35);

		vertices       = wmdata.readArray!Vertex(header.terrain_vertices_count).dup;
		unknown0_block = wmdata.readArray!Unknown0(header.unknown0_count).dup;
		triangles      = wmdata.readArray!Triangle(header.triangles_count).dup;

		remaining_data = wmdata.readArray(wmdata.bytesLeft).dup;
	}
}
