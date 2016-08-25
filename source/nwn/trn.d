/// Terrain (trn, trx)
module nwn.trn;

import std.stdint;
import std.string;
import std.conv: to;
import std.traits;
import std.exception: enforce;
import nwnlibd.parseutils;

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
char[4] toTrnPacketStr(TrnPacketType type){
	return type.to!(char[])[5..9];
}



struct TrnPacket{

	@property{
		///
		TrnPacketType type()const{return m_type;}
	}
	private TrnPacketType m_type;

	///
	ref TrnPacketTypeToPayload!T as(TrnPacketType T)(){
		if(type != T)
			throw new TrnTypeException("Type mismatch");
		return *cast(TrnPacketTypeToPayload!T*)structData.ptr;
	}

	ubyte[] serialize(){
		final switch(type) with(TrnPacketType){
			foreach(TYPE ; EnumMembers!TrnPacketType){
				case TYPE:
					return as!TYPE.serialize();
			}
		}
	}

package:
	this(TrnPacketType type, in ubyte[] payloadData){
		import std.traits: EnumMembers;

		m_type = type;

		typeswitch:
		final switch(type) with(TrnPacketType){
			foreach(TYPE ; EnumMembers!TrnPacketType){
				case TYPE:
					alias PAYLOAD = TrnPacketTypeToPayload!TYPE;
					structData = cast(ubyte[])([PAYLOAD(payloadData)][0..1]);
					break typeswitch;
			}
		}
	}
	ubyte[] structData;
}






/// UNTESTED WITH NWN1
class Trn{
	this(in string path){
		import std.file: read;
		this(cast(ubyte[])path.read());
	}

	@property string nwnVersion()const{return m_nwnVersion;}
	package string m_nwnVersion;

	@property uint versionMajor()const{return m_versionMajor;}
	package uint m_versionMajor;

	@property uint versionMinor()const{return m_versionMinor;}
	package uint m_versionMinor;

	this(in ubyte[] rawData){
		enforce!TrnParseException(rawData.length>Header.sizeof, "Data is too small to contain the header");

		auto header =        cast(Header*)        rawData.ptr;
		auto packetIndices = cast(PacketIndices*)(rawData.ptr+Header.sizeof);

		m_nwnVersion = header.file_type.charArrayToString;
		m_versionMajor = header.version_major;
		m_versionMinor = header.version_minor;

		foreach(i ; 0..header.resource_count){
			immutable type = packetIndices[i].type.toTrnPacketType(nwnVersion);
			immutable offset = packetIndices[i].offset;

			immutable packet = cast(immutable Packet*)(rawData.ptr+offset);
			immutable packetType = packet.type.toTrnPacketType(nwnVersion);
			immutable packetLength = packet.payload_length;

			enforce!TrnParseException(type==packetType, "Packet type does not match the one referenced in packet indices");

			//writeln(packets.length,": ",type,"   (off=",offset," size=",packetLength,")");
			packets ~= TrnPacket(type, (&packet.payload_start)[0..packetLength]);
		}

		assert(serialize() == rawData);
	}

	ubyte[] serialize(){

		auto header = Header(
			m_nwnVersion.dup[0..4],
			m_versionMajor.to!uint16_t,
			m_versionMinor.to!uint16_t,
			packets.length.to!uint32_t);

		PacketIndices[] indices;
		indices.length = packets.length;

		uint32_t offset = (header.sizeof + PacketIndices.sizeof*indices.length).to!uint32_t;
		ubyte[] packetsData;
		foreach(i, ref packet ; packets){
			auto typeStr = packet.type.toTrnPacketStr();
			//writeln(offset);
			indices[i].type = typeStr;
			indices[i].offset = offset;
			auto packetData = packet.serialize();

			ChunkWriter cw;
			cw.put(typeStr, packetData.length.to!uint32_t, packetData);
			packetsData ~= cw.data;
			offset += cw.data.length;
		}


		ChunkWriter cw;
		cw.put(
			header,
			indices,
			packetsData);
		return cw.data;
	}


	TrnPacket[] packets;

private:
	static align(1) struct Header{
		static assert(this.sizeof == 12);
		char[4] file_type;
		uint16_t version_major;
		uint16_t version_minor;
		uint32_t resource_count;
	}
	static align(1) struct PacketIndices{
		static assert(this.sizeof == 8);
		char[4] type;
		uint32_t offset;
	}
	static align(1) struct Packet{
		static assert(this.sizeof == 8+1);
		char[4] type;
		uint32_t payload_length;
		ubyte payload_start;
	}
}



/// Terrain dimensions
struct TrnNWN2TerrainDimPayload{
	uint32_t width;/// Width in megatiles
	uint32_t height;/// Height in megatiles
	uint32_t unknown;/// Unknown/unused

	package this(in ubyte[] payload){
		width = *(cast(uint32_t*)&payload[0]);
		height = *(cast(uint32_t*)&payload[4]);
		unknown = *(cast(uint32_t*)&payload[8]);
	}

	ubyte[] serialize(){
		ChunkWriter cw;
		cw.put(width, height, unknown);
		return cw.data;
	}
}

/// Megatile information
struct TrnNWN2MegatilePayload{
	char[128] name;///name of the terrain
	///
	static align(1) struct Texture{
		static assert(this.sizeof == 44);
		char[32] name;
		float[3] color;/// rgb
	}
	Texture[6] textures;/// Textures on the megatile, with their blend color
	///
	static align(1) struct Vertex{
		static assert(this.sizeof == 44);
		float[3] position;/// x y z
		float[3] normal;  /// normal vector
		ubyte[4] tinting; /// argb
		float[2] xy_0to10;/// ?
		float[2] xy_0to1; /// ?
	}
	align(1) Vertex[] vertices;/// Terrain geometry
	///
	static align(1) struct Triangle{
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
		static align(1) struct Blade{
			static assert(this.sizeof == 36);
			float[3] position;
			float[3] direction;
			float[3] dimension;
		}
		Blade[] blades;
	}
	Grass[] grass;/// Grass "objects"


	package this(in ubyte[] payload){
		auto data = ChunkReader(payload);

		name = data.read!(char[128]);
		//TODO: there is other data than name in this array

		foreach(ref texture ; textures){
			texture.name = data.read!(char[32]);
		}
		foreach(ref texture ; textures){
			texture.color = data.read!(float[3]);
		}
		immutable vertices_length  = data.read!uint32_t;
		immutable triangles_length = data.read!uint32_t;
		vertices = data.readArray!Vertex(vertices_length).dup;
		triangles = data.readArray!Triangle(triangles_length).dup;

		immutable dds_a_length = data.read!uint32_t;
		dds_a = data.readArray(dds_a_length).dup;
		immutable dds_b_length = data.read!uint32_t;
		dds_b = data.readArray(dds_b_length).dup;

		immutable grass_count = data.read!uint32_t;
		grass.length = grass_count;
		foreach(ref g ; grass){
			g.name = data.read!(typeof(g.name)).dup;
			g.texture = data.read!(typeof(g.texture));
			immutable blades_count = data.read!uint32_t;
			g.blades.length = blades_count;
			foreach(ref blade ; g.blades){
				blade = data.readPackedStruct!(Grass.Blade);
			}
		}
		assert(data.read_ptr == payload.length, "some bytes were not read");
	}


	ubyte[] serialize(){
		ChunkWriter cw;
		cw.put(name);
		foreach(ref texture ; textures)
			cw.put(texture.name);
		foreach(ref texture ; textures)
			cw.put(texture.color);

		cw.put(
			vertices.length.to!uint32_t,
			triangles.length.to!uint32_t,
			vertices,
			triangles,
			dds_a.length.to!uint32_t, dds_a,
			dds_b.length.to!uint32_t, dds_b,
			grass.length.to!uint32_t);

		foreach(ref g ; grass){
			cw.put(
				g.name,
				g.texture,
				g.blades.length.to!uint32_t, g.blades);
		}

		return cw.data;
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
	static align(1) struct Texture{
		static assert(this.sizeof == 48);
		char[32] name;/// Texture name
		float[2] direction;/// Scrolling direction
		float rate;/// Scrolling speed
		float angle;/// Scrolling angle in radiant
	}
	Texture[3] textures;/// Water textures
	float[2] offset;/// x,y offset in water-space <=> megatile_coordinates/8
	///
	static align(1) struct Vertex{
		static assert(this.sizeof == 28);
		float[3] position;/// x y z
		float[2] xy_0to5;/// ?
		float[2] xy_0to1;/// ?
	}
	Vertex[] vertices;
	///
	static align(1) struct Triangle{
		static assert(this.sizeof == 6);
		uint16_t[3] vertices;///Triangle vertex indices in $(D TrnNWN2WaterPayload.vertices)
	}
	/// Walkmesh grid triangles positions.
	/// Each uint16_t an index in `vertices` corresponding to a triangle vertex
	Triangle[] triangles;
	uint32_t[] triangles_flags;/// 0 = has water, 1 = no water
	ubyte[] dds;/// DDS bitmap
	uint32_t[2] megatile_position;/// Position of the associated megatile in the terrain


	package this(in ubyte[] payload){
		auto data = ChunkReader(payload);

		unknown       = data.read!(typeof(unknown));
		color         = data.read!(typeof(color));
		ripple         = data.read!(typeof(ripple));
		smoothness    = data.read!(typeof(smoothness));
		reflect_bias  = data.read!(typeof(reflect_bias));
		reflect_power = data.read!(typeof(reflect_power));
		unknown2      = data.read!(typeof(unknown2));
		unknown3      = data.read!(typeof(unknown3));

		foreach(ref texture ; textures){
			texture.name      = data.read!(char[32]);
			texture.direction = data.read!(typeof(texture.direction));
			texture.rate      = data.read!(typeof(texture.rate));
			texture.angle     = data.read!(typeof(texture.angle));
		}


		offset = data.read!(typeof(offset));
		immutable vertices_length  = data.read!uint32_t;
		immutable triangles_length = data.read!uint32_t;

		vertices = data.readArray!Vertex(vertices_length).dup;
		triangles = data.readArray!Triangle(triangles_length).dup;

		triangles_flags = data.readArray!uint32_t(triangles_length).dup;

		immutable dds_length = data.read!uint32_t;
		dds = data.readArray(dds_length).dup;

		megatile_position = data.read!(typeof(megatile_position));

		assert(data.read_ptr == payload.length, "some bytes were not read");
	}


	ubyte[] serialize(){
		ChunkWriter cw;
		cw.put(
			unknown,
			color,
			ripple,
			smoothness,
			reflect_bias,
			reflect_power,
			unknown2,
			unknown3,
			textures,
			offset,
			vertices.length.to!uint32_t,
			triangles.length.to!uint32_t,
			vertices,
			triangles,
			triangles_flags,
			dds.length.to!uint32_t, dds,
			megatile_position);
		return cw.data;
	}
}
struct TrnNWN2WalkmeshPayload{

	string data_type;

	static align(1) struct Header{
		static assert(this.sizeof==53);
		align(1):
		ubyte[37] unknownA;
		uint32_t vertices_count;
		uint32_t junctions_count;
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

	static align(1) struct Junction{
		static assert(this.sizeof==16);
		align(1):
		uint32_t[2] vertices;
		uint32_t[2] triangles;
	}
	Junction[] junctions;

	static align(1) struct Triangle{
		static assert(this.sizeof==64);
		align(1):
		uint32_t[3] vertices;
		uint32_t[3] linked_junctions;
		uint32_t[3] linked_triangles;
		float[2] center;
		float[3] normal;
		float unknownA;
		uint16_t microtileId;
		uint16_t flags;
	}
	Triangle[] triangles;


	ubyte[] remaining_data;





	package this(in ubyte[] payload){
		auto data = ChunkReader(payload);

		data_type               = data.read!(char[4]).charArrayToString;
		immutable comp_length   = data.read!uint32_t;
		immutable uncomp_length = data.read!uint32_t;
		auto comp_wm            = data.readArray(comp_length);

		// zlib deflate
		import std.zlib: uncompress;
		auto walkmeshData = cast(ubyte[])uncompress(comp_wm, uncomp_length);
		assert(walkmeshData.length == uncomp_length, "Length mismatch");

		auto wmdata = ChunkReader(walkmeshData);

		header = wmdata.read!Header;
		assert(wmdata.read_ptr==0x35);

		vertices       = wmdata.readArray!Vertex(header.vertices_count).dup;
		junctions      = wmdata.readArray!Junction(header.junctions_count).dup;
		triangles      = wmdata.readArray!Triangle(header.triangles_count).dup;

		//import std.file: writeFile=write;
		//writeFile("walkmesh.wm", walkmeshData);
		//writeln("offset: ", wmdata.read_ptr, ", ",wmdata.bytesLeft," remaining bytes");

		remaining_data = wmdata.readArray(wmdata.bytesLeft).dup;
	}


	ubyte[] serialize(){
		//update header values
		header.vertices_count  = vertices.length.to!uint32_t;
		header.junctions_count = junctions.length.to!uint32_t;
		header.triangles_count = triangles.length.to!uint32_t;

		//build uncompressed data
		ChunkWriter uncompData;
		uncompData.put(
			header,
			vertices,
			junctions,
			triangles,
			remaining_data);

		import std.zlib: compress;
		const compData = compress(uncompData.data);

		const compLength = compData.length.to!uint32_t;
		const uncompLength = uncompData.data.length.to!uint32_t;


		ChunkWriter cw;
		cw.put(data_type, compLength, uncompLength, compData);
		return cw.data;
	}
}
