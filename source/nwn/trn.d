/// Terrain (trn, trx)
module nwn.trn;

import std.stdint;
import std.string;
import std.conv: to;
import std.traits;
import std.exception: enforce;
import nwnlibd.parseutils;

import std.stdio: write, writeln, writefln;
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

		version(unittest){
			assert(serialize() == rawData);
		}
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

/// Compressed walkmesh (only contained inside TRX files)
struct TrnNWN2WalkmeshPayload{

	string data_type;

	/// ASWM header
	static align(1) struct Header{
		static assert(this.sizeof == 53);
		align(1):
		ubyte[37] unknownA;
		uint32_t vertices_count;
		uint32_t junctions_count;
		uint32_t triangles_count;
		uint32_t unknownB;
	}
	/// ditto
	Header header;

	static align(1) struct Vertex{
		static assert(this.sizeof == 12);
		align(1):
		float[3] position;
	}
	Vertex[] vertices;

	/// Junction between two triangles
	static align(1) struct Junction{
		static assert(this.sizeof == 16);
		align(1):
		uint32_t[2] vertices; /// Vertex indices drawing the junction line
		uint32_t[2] triangles; /// Joined triangles (`uint32_t.max` if none)
	}
	Junction[] junctions;

	/// Mesh Triangle + pre-calculated data + metadata
	static align(1) struct Triangle{
		static assert(this.sizeof == 64);
		align(1):
		uint32_t[3] vertices; /// Vertex indices composing the triangle
		uint32_t[3] linked_junctions; /// Junctions to other triangles (`uint32_t.max` if none, but there should always be 3)
		uint32_t[3] linked_triangles; /// Adjacent triangles (`uint32_t.max` if none)
		float[2] center; /// X / Y coordinates of the center of the triangle. Calculated by avg the 3 vertices coordinates.
		float[3] normal; /// Normal vector
		float dot_product; /// Dot product at plane
		uint16_t island; /// Smaller fraction of a tile. TODO: check if WM helpers create islands?
		uint16_t flags; /// See `Flags`

		enum Flags {
			walkable  = 0x01, /// if the triangle can be walked on. Note the triangle needs path tables to be really walkable
			clockwise = 0x04, /// vertices are wound clockwise and not ccw
			dirt      = 0x08, /// Floor type (for sound effects)
			grass     = 0x10, /// ditto
			stone     = 0x20, /// ditto
			wood      = 0x40, /// ditto
			carpet    = 0x80, /// ditto
			metal     = 0x100, /// ditto
			swamp     = 0x200, /// ditto
			mud       = 0x400, /// ditto
			leaves    = 0x800, /// ditto
			water     = 0x1000, /// ditto
			puddles   = 0x2000, /// ditto
		}
	}
	Triangle[] triangles;

	/// Always 31?
	uint32_t tiles_flags;
	/// Width in meters of a terrain tile (most likely to be 10.0)
	float tiles_width;
	/// Number of tiles along Y axis
	/// TODO: double check height = Y
	uint32_t tiles_grid_height;
	/// Number of tiles along X axis
	/// TODO: double check width = X
	uint32_t tiles_grid_width;
	/// Width of the map borders in tiles (8 means that 8 tiles will be removed on each side)
	uint32_t tiles_border_size;

	/// Tile with its path table
	static struct Tile {

		static align(1) struct Header {
			static assert(this.sizeof == 57);
			align(1):
			char[32] name; /// Last time I checked it was complete garbage
			ubyte owns_data;/// 1 if the tile stores vertices / junctions. Usually 0
			uint32_t vertices_count;
			uint32_t junctions_count;
			uint32_t triangles_count;
			float size_x;/// Always 0 ?
			float size_y;/// Always 0 ?

			/// This value will be added to each triangle index in the PathTable
			uint32_t triangle_offset;
		}
		Header header;

		/// Only used if `header.owns_data == true`
		Vertex[] vertices;

		/// Only used if `header.owns_data == true`
		Junction[] junctions;

		/**
		Tile pathing information

		Notes:
		- "local" refers to the local triangle index. The aswm triangle index
		  can be retrieved by adding Tile.triangle_offset
		- Each triangle referenced here is only referenced once across all the
		  tiles of the ASWM
		*/
		static struct PathTable {

			static align(1) struct Header {
				static assert(this.sizeof == 13);
				align(1):

				enum Flags {
					rle       = 0x01,
					zcompress = 0x02,
				}
				uint32_t flags; /// Alsways 0 ?. Probably used to set path table compression
				uint32_t local_to_node_length; /// Length of `local_to_node`
				ubyte node_to_local_length; /// Length of `node_to_local`
				uint32_t rle_table_size; /// Always 0 ?

			}
			Header header;

			/**
			List of node indices for each triangle in the tile

			`local_to_node[triangle_local_index]` represents an index value to
			be used with nodes (see `nodes` for how to use it)

			All triangles (even non walkable) must be represented here.
			Triangle indices that are not used in this tile must have a `0xFF`
			value.
			*/
			ubyte[] local_to_node;

			/**
			Node index to local triangle index

			Values must not be uint32_t.max
			*/
			uint32_t[] node_to_local;

			/**
			Node list

			This is used to determine which triangle a creature should go next
			to reach a destination triangle.

			`nodes[header.node_to_local_length * FromLTNIndex + DestLTNIndex]
			& 0b0111_1111` is an index in `node_to_local` array, containing
			the next triangle to go to in order to reach destination.

			`FromLTNIndex`, `DestLTNIndex` are values found inside the
			`local_to_node` array.
			<ul>
			$(LI `value & 0b0111_1111` is an index in `node_to_local` table)
			$(LI `value & 0b1000_0000` is > 0 if there is a clear line of
			sight between the two triangle. It's not clear what LOS is since
			two linked triangles on flat ground may not have LOS = 1 in game
			files.)
			</ul>

			If FromLTNIndex == DestLTNIndex, the value must be set to 255.

			Note: does not contain any 127 = 0b0111_1111 values
			*/
			ubyte[] nodes;

			/// Always 0b0001_1111 = 31 ?
			uint32_t flags;
		}
		PathTable path_table;


		private void parse(ref ChunkReader wmdata){
			header = wmdata.read!(typeof(header));

			if(header.owns_data){
				vertices = wmdata.readArray!Vertex(header.vertices_count).dup;
				junctions = wmdata.readArray!Junction(header.junctions_count).dup;
			}

			with(path_table){
				header = wmdata.read!(typeof(header));

				enforce!TrnParseException((header.flags & (Header.Flags.rle | Header.Flags.zcompress)) == 0, "Compressed path tables not supported");

				local_to_node = wmdata.readArray!ubyte(header.local_to_node_length).dup;
				node_to_local = wmdata.readArray!uint32_t(header.node_to_local_length).dup;
				nodes = wmdata.readArray!ubyte(header.node_to_local_length ^^ 2).dup;

				flags = wmdata.read!(typeof(flags));
			}
		}
		private void serialize(ref ChunkWriter uncompData){
			uncompData.put(
				header,
				vertices,
				junctions);

			with(path_table){
				// Update header
				header.local_to_node_length = cast(uint32_t)local_to_node.length;

				assert(node_to_local.length <= ubyte.max, "node_to_local is too long");
				header.node_to_local_length = cast(ubyte)node_to_local.length;

				// serialize
				uncompData.put(
					header,
					local_to_node,
					node_to_local,
					nodes,
					flags);
			}
		}

		string dump() const {
			return format!"TILE header: name: %(%s, %)\n"([header.name])
			     ~ format!"        owns_data: %s, vert_cnt: %s, junc_cnt: %s, tri_cnt: %s\n"(header.owns_data, header.vertices_count, header.junctions_count, header.triangles_count)
			     ~ format!"        size_x: %s, size_y: %s\n"(header.size_x, header.size_y)
			     ~ format!"        triangle_offset: %s\n"(header.triangle_offset)
			     ~ format!"     vertices: %s\n"(vertices)
			     ~ format!"     junctions: %s\n"(junctions)
			     ~        "     path_table: \n"
			     ~ format!"       header: flags: %s, ltn_len: %d, ntl_len: %s, rle_len: %s\n"(path_table.header.flags, path_table.header.local_to_node_length, path_table.header.node_to_local_length, path_table.header.rle_table_size)
			     ~ format!"       ltn: %s\n"(path_table.local_to_node)
			     ~ format!"       ntl: %s\n"(path_table.local_to_node)
			     ~ format!"       nodes: %s\n"(path_table.nodes)
			     ~ format!"       flags: %s\n"(path_table.flags);
		}
	}
	/// Map tile list
	/// Non border tiles have `header.vertices_count > 0 || header.junctions_count > 0 || header.triangles_count > 0`
	Tile[] tiles;

	static struct Island {
		static align(1) struct Header {
			static assert(this.sizeof == 24);
			align(1):
			uint32_t index;
			uint32_t tile;
			Vertex center;
			uint32_t exit_triangles_length;
		}
		Header header;
		uint32_t[] adjacent_islands; /// Adjacent islands
		float[] adjacent_islands_dist; /// Distances between adjacent islands (probably measured between header.center)
		uint32_t[] exit_triangles;

		private void parse(ref ChunkReader wmdata){
			header = wmdata.read!(typeof(header));

			immutable adjLen = wmdata.read!uint32_t;
			adjacent_islands = wmdata.readArray!uint32_t(adjLen).dup;

			immutable adjDistLen = wmdata.read!uint32_t;
			adjacent_islands_dist = wmdata.readArray!float(adjDistLen).dup;

			immutable exitLen = wmdata.read!uint32_t;
			exit_triangles = wmdata.readArray!uint32_t(exitLen).dup;
		}
		private void serialize(ref ChunkWriter uncompData){
			uncompData.put(
				header,
				cast(uint32_t)adjacent_islands.length,
				adjacent_islands,
				cast(uint32_t)adjacent_islands_dist.length,
				adjacent_islands_dist,
				cast(uint32_t)exit_triangles.length,
				exit_triangles);
		}

		string dump() const {
			return format!"ISLA header: index: %s, tile: %s, center: %s, exit_triangles_length: %s\n"(header.index, header.tile, header.center.position, header.exit_triangles_length)
				~ format!"      adjacent_islands: %s\n"(adjacent_islands)
				~ format!"      adjacent_islands_dist: %s\n"(adjacent_islands_dist)
				~ format!"      exit_triangles: %s\n"(exit_triangles);
		}
	}
	Island[] islands;


	static align(1) struct IslandPathNode {
		static assert(this.sizeof == 8);
		uint16_t next;
		uint16_t _padding;
		float weight;
	}
	IslandPathNode[] islands_path_nodes;


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

		tiles_flags      = wmdata.read!(typeof(tiles_flags));
		tiles_width       = wmdata.read!(typeof(tiles_width));
		tiles_grid_height = wmdata.read!(typeof(tiles_grid_height));
		tiles_grid_width  = wmdata.read!(typeof(tiles_grid_width));


		// Tile list
		tiles.length = tiles_grid_height * tiles_grid_width;
		foreach(i, ref tile ; tiles){
			// Path table
			tile.parse(wmdata);
		}

		tiles_border_size = wmdata.read!(typeof(tiles_border_size));

		// Islands list
		islands.length = wmdata.read!uint32_t;
		foreach(ref island ; islands){
			island.parse(wmdata);
		}

		islands_path_nodes = wmdata.readArray!IslandPathNode(islands.length ^^ 2).dup;

		assert(wmdata.bytesLeft == 0, "Remaining " ~ wmdata.bytesLeft.to!string ~ " bytes");

		version(unittest){

			auto serialized = serializeUncompressed();
			assert(serialized.length == walkmeshData.length, "mismatch length "~walkmeshData.length.to!string~" -> "~serialized.length.to!string);
			assert(walkmeshData == serialized, "Could not serialize correctly");
		}
	}


	ubyte[] serialize(){
		auto uncompData = serializeUncompressed();

		import std.zlib: compress;
		const compData = compress(uncompData);

		const compLength = compData.length.to!uint32_t;
		const uncompLength = uncompData.length.to!uint32_t;


		ChunkWriter cw;
		cw.put(data_type, compLength, uncompLength, compData);
		return cw.data;
	}

	ubyte[] serializeUncompressed(){
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
			tiles_flags,
			tiles_width,
			tiles_grid_height,
			tiles_grid_width);

		foreach(ref tile ; tiles){
			tile.serialize(uncompData);
		}

		uncompData.put(
			tiles_border_size,
			cast(uint32_t)islands.length);

		foreach(ref island ; islands){
			island.serialize(uncompData);
		}

		uncompData.put(islands_path_nodes);

		return uncompData.data;
	}

	string validate() const {

		foreach(i, ref tile ; tiles){

			immutable nodes_len = tile.path_table.nodes.length;
			immutable node_to_local_len = tile.path_table.node_to_local.length;
			immutable local_to_node_len = tile.path_table.local_to_node.length;

			if(node_to_local_len != tile.path_table.header.node_to_local_length)
				return "In tile "~i.to!string~": Wrong number of node_to_local";
			if(local_to_node_len != tile.path_table.header.local_to_node_length)
				return "In tile "~i.to!string~": Wrong number of local_to_node";

			if(nodes_len != tile.path_table.header.node_to_local_length ^^ 2)
				return "In tile "~i.to!string~": Wrong number of nodes";
			if(nodes_len < 0x7F){
				foreach(j, node ; tile.path_table.nodes){
					if(node == 0xff)
						continue;
					if((node & 0b0111_1111) >= node_to_local_len)
						return "In tile "~i.to!string~", node "~j.to!string~": Illegal value "~node.to!string;
				}
			}
			if(nodes_len < 0xff){
				foreach(j, node ; tile.path_table.local_to_node){
					if(node == 0xff)
						continue;
					if(node >= nodes_len)
						return "In tile "~i.to!string~", local_to_node "~j.to!string~": Illegal value"~node.to!string;
				}
			}

			foreach(j, ntl ; tile.path_table.node_to_local){
				if(ntl >= triangles.length)
					return "In tile "~i.to!string~", node_to_local "~j.to!string~": triangle index "~ntl.to!string~" out of bounds";
			}

		}

		if(islands_path_nodes.length != islands.length ^^ 2)
			return "Wrong number of islands / islands_path_nodes";

		return null;
	}

	string dump() const {
		import std.algorithm;
		import std.array: array;

		string ret;

		ret ~= "==== HEADER ====\n";
		ret ~= "unknownA: " ~ header.unknownA.to!string ~ "\n";
		ret ~= "vertices_count: " ~ header.vertices_count.to!string ~ "\n";
		ret ~= "junctions_count: " ~ header.junctions_count.to!string ~ "\n";
		ret ~= "triangles_count: " ~ header.triangles_count.to!string ~ "\n";
		ret ~= "unknownB: " ~ header.unknownB.to!string ~ "\n";

		ret ~= "==== VERTICES ====\n";
		ret ~= vertices.map!(a => format!"VERT %s\n"(a.position)).join;

		ret ~= "==== JUNCTIONS ====\n";
		ret ~= junctions.map!(a => format!"JUNC line: %s, tri: %s\n"(a.vertices, a.triangles)).join;

		ret ~= "==== TRIANGLES ====\n";
		ret ~= triangles.map!(a =>
				  format!"TRI vert: %s, junc: %s, tri: %s\n"(a.vertices, a.linked_junctions, a.linked_triangles)
				~ format!"    center: %s, normal: %s, dot_product: %s\n"(a.center, a.normal, a.dot_product)
				~ format!"    island: %s, flags: %s\n"(a.island, a.flags)
			).join;

		ret ~= "==== TILES HEADER ====\n";
		ret ~= "tiles_flags: " ~ tiles_flags.to!string ~ "\n";
		ret ~= "tiles_width: " ~ tiles_width.to!string ~ "\n";
		ret ~= "tiles_grid_height: " ~ tiles_grid_height.to!string ~ "\n";
		ret ~= "tiles_grid_width: " ~ tiles_grid_width.to!string ~ "\n";
		ret ~= "tiles_border_size: " ~ tiles_border_size.to!string ~ "\n";

		ret ~= "==== TILES ====\n";
		ret ~= tiles.map!(a => a.dump()).join;

		ret ~= "==== ISLANDS ====\n";
		ret ~= islands.map!(a => a.dump()).join;

		ret ~= "==== ISLAND PATH NODES ====\n";
		ret ~= islands_path_nodes.map!(a => format!"ISPN next: %s, _padding %s, weight: %s\n"(a.next, a._padding, a.weight)).join;

		return ret;
	}
}


unittest {
	auto map = cast(ubyte[])import("eauprofonde-portes.trx");

	auto trn = new Trn(map);
	auto serialized = trn.serialize();
	assert(map.length == serialized.length && map == serialized);
}