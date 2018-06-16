/// Terrain (trn, trx)
module nwn.trn;

import std.stdint;
import std.string;
import std.conv: to;
import std.traits;
import std.exception: enforce;
import std.algorithm;
import std.array: array;
import nwnlibd.parseutils;
import nwnlibd.geometry;
import gfm.math.vector;
import gfm.math.box;

import std.stdio: stdout, write, writeln, writefln;
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
	static if(type == TrnPacketType.NWN2_TRWH)      alias TrnPacketTypeToPayload = TrnNWN2TerrainDimPayload;
	else static if(type == TrnPacketType.NWN2_TRRN) alias TrnPacketTypeToPayload = TrnNWN2MegatilePayload;
	else static if(type == TrnPacketType.NWN2_WATR) alias TrnPacketTypeToPayload = TrnNWN2WaterPayload;
	else static if(type == TrnPacketType.NWN2_ASWM) alias TrnPacketTypeToPayload = TrnNWN2WalkmeshPayload;
	else static assert(0, "Type not supported");
}
template TrnPacketPayloadToType(T){
	static if(is(T == TrnNWN2TerrainDimPayload))    alias TrnPacketPayloadToType = TrnPacketType.NWN2_TRWH;
	else static if(is(T == TrnNWN2MegatilePayload)) alias TrnPacketPayloadToType = TrnPacketType.NWN2_TRRN;
	else static if(is(T == TrnNWN2WaterPayload))    alias TrnPacketPayloadToType = TrnPacketType.NWN2_WATR;
	else static if(is(T == TrnNWN2WalkmeshPayload)) alias TrnPacketPayloadToType = TrnPacketType.NWN2_ASWM;
	else static assert(0, "Type not supported");
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
	ref T as(T)() if(is(typeof(TrnPacketPayloadToType!T) == TrnPacketType)) {
		assert(type == TrnPacketPayloadToType!T, "Type mismatch");
		return *cast(T*)structData.ptr;
	}

	ref TrnPacketTypeToPayload!T as(TrnPacketType T)(){
		return as!(TrnPacketTypeToPayload!T);
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
	/// Empty TRN file
	this(){}

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

	/// foreach(i, ref TrnNWN2WalkmeshPayload aswm ; trn){}
	int opApply(T)(scope int delegate(ref T packet) dlg)
	if(is(typeof(TrnPacketPayloadToType!T) == TrnPacketType)) {
		int res = 0;
		foreach(ref packet ; packets){
			if(packet.type == TrnPacketPayloadToType!T){
				if((res = dlg(packet.as!T)) != 0)
					return res;
			}
		}
		return res;
	}

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
		uint32_t edges_count;
		uint32_t triangles_count;
		uint32_t unknownB;
	}
	/// ditto
	Header header;

	static align(1) union Vertex {
		static assert(this.sizeof == 12);
		align(1):

		float[3] position;

		private struct Xyz{ float x, y, z; }
		Xyz _xyz;
		alias _xyz this;
	}
	Vertex[] vertices;

	/// Edge between two triangles
	static align(1) struct Edge{
		static assert(this.sizeof == 16);
		align(1):
		uint32_t[2] vertices; /// Vertex indices drawing the edge line
		uint32_t[2] triangles; /// Joined triangles (`uint32_t.max` if none)
	}
	Edge[] edges;

	/// Mesh Triangle + pre-calculated data + metadata
	static align(1) struct Triangle{
		static assert(this.sizeof == 64);
		align(1):
		uint32_t[3] vertices; /// Vertex indices composing the triangle
		/// Edges to other triangles (`uint32_t.max` if none, but there should always be 3)
		///
		/// Every `linked_edges` should have its associated `linked_triangles` at the same index
		uint32_t[3] linked_edges;
		/// Adjacent triangles (`uint32_t.max` if none)
		///
		/// Every `linked_triangles` should have its associated `linked_edges` at the same index
		uint32_t[3] linked_triangles;
		float[2] center; /// X / Y coordinates of the center of the triangle. Calculated by avg the 3 vertices coordinates.
		float[3] normal; /// Normal vector
		float dot_product; /// Dot product at plane
		uint16_t island; /// Index in the `TrnNWN2WalkmeshPayload.islands` array.
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

	/// Always 31 in TRX files, 15 in TRN files
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
			ubyte owns_data;/// 1 if the tile stores vertices / edges. Usually 0
			uint32_t vertices_count; /// Number of vertices in this tile
			uint32_t edges_count; /// Number of edges in this tile
			uint32_t triangles_count; /// Number of triangles in this tile (walkable + unwalkable)
			float size_x;/// Always 0 ?
			float size_y;/// Always 0 ?

			/// This value will be added to each triangle index in the PathTable
			uint32_t triangles_offset;
		}
		Header header;

		/// Only used if `header.owns_data == true`
		Vertex[] vertices;

		/// Only used if `header.owns_data == true`
		Edge[] edges;

		/**
		Tile pathing information

		Notes:
		- "local" refers to the local triangle index. The aswm triangle index
		  can be retrieved by adding Tile.triangles_offset
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
				uint32_t flags; /// Always 0. Used to set path table compression
				private uint32_t _local_to_node_length; /// use `local_to_node.length` instead
				private ubyte _node_to_local_length; /// use `node_to_local.length` instead
				uint32_t rle_table_size; /// Always 0 ? probably related to Run-Length Encoding

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
				edges = wmdata.readArray!Edge(header.edges_count).dup;
			}

			with(path_table){
				header = wmdata.read!(typeof(header));

				enforce!TrnParseException((header.flags & (Header.Flags.rle | Header.Flags.zcompress)) == 0, "Compressed path tables not supported");

				local_to_node = wmdata.readArray!ubyte(header._local_to_node_length).dup;
				node_to_local = wmdata.readArray!uint32_t(header._node_to_local_length).dup;
				nodes = wmdata.readArray!ubyte(header._node_to_local_length ^^ 2).dup;

				flags = wmdata.read!(typeof(flags));
			}
		}
		private void serialize(ref ChunkWriter uncompData){

			uncompData.put(
				header,
				vertices,
				edges);

			immutable tcount = header.triangles_count;

			with(path_table){
				// Update header
				header._local_to_node_length = local_to_node.length.to!uint32_t;
				header._node_to_local_length = node_to_local.length.to!ubyte;

				assert(nodes.length == node_to_local.length ^^ 2, "Bad number of path table nodes");
				assert(local_to_node.length == tcount, "local_to_node length should match header.triangles_count");

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
			import std.range: chunks;
			return format!"TILE header: name: %(%s, %)\n"([header.name])
			     ~ format!"        owns_data: %s, vert_cnt: %s, edge_cnt: %s, tri_cnt: %s\n"(header.owns_data, header.vertices_count, header.edges_count, header.triangles_count)
			     ~ format!"        size_x: %s, size_y: %s\n"(header.size_x, header.size_y)
			     ~ format!"        triangles_offset: %s\n"(header.triangles_offset)
			     ~ format!"     vertices: %s\n"(vertices)
			     ~ format!"     edges: %s\n"(edges)
			     ~        "     path_table: \n"
			     ~ format!"       header: flags: %s, ltn_len: %d, ntl_len: %s, rle_len: %s\n"(path_table.header.flags, path_table.header._local_to_node_length, path_table.header._node_to_local_length, path_table.header.rle_table_size)
			     ~ format!"       ltn:   %(%3d %)\n"(path_table.local_to_node)
			     ~ format!"       ntl:   %(%3d %)\n"(path_table.node_to_local)
			     ~ format!"       nodes: %(%-(%s%)\n              %)\n"(
			     	path_table.node_to_local.length == 0 ?
			     	[] : path_table.nodes.map!(a => (((a & 128)? "*" : " ") ~ (a & 127).to!string).rightJustify(4)).chunks(path_table.node_to_local.length).array)
			     ~ format!"       flags: %s\n"(path_table.flags);
		}

		ubyte getPathNode(uint32_t fromGTriIndex, uint32_t toGTriIndex) const {
			assert(header.triangles_offset <= fromGTriIndex && fromGTriIndex < path_table.local_to_node.length + header.triangles_offset,
				"From triangle index "~fromGTriIndex.to!string~" is not in tile path table");
			assert(header.triangles_offset <= toGTriIndex && toGTriIndex < path_table.local_to_node.length + header.triangles_offset,
				"To triangle index "~toGTriIndex.to!string~" is not in tile path table");


			immutable nodeFrom = path_table.local_to_node[fromGTriIndex - header.triangles_offset];
			immutable nodeTo = path_table.local_to_node[toGTriIndex - header.triangles_offset];

			if(nodeFrom == 0xff || nodeTo == 0xff)
				return 0xff;

			return path_table.nodes[nodeFrom * path_table.node_to_local.length + nodeTo];
		}

		/**
		Calculate the fastest route between two triangles of a tile. The tile need to be baked, as it uses existing path tables.
		*/
		uint32_t[] findPath(in uint32_t fromGTriIndex, in uint32_t toGTriIndex) const {
			assert(header.triangles_offset <= fromGTriIndex && fromGTriIndex < path_table.local_to_node.length + header.triangles_offset,
				"From triangle index "~fromGTriIndex.to!string~" is not in tile path table");
			assert(header.triangles_offset <= toGTriIndex && toGTriIndex < path_table.local_to_node.length + header.triangles_offset,
				"To triangle index "~toGTriIndex.to!string~" is not in tile path table");

			uint32_t from = fromGTriIndex;

			int iSec = 0;
			uint32_t[] ret;
			while(from != toGTriIndex && iSec++ < 1000){
				auto node = getPathNode(from, toGTriIndex);
				if(node == 0xff)
					return ret;

				from = path_table.node_to_local[node & 0b0111_1111] + header.triangles_offset;
				ret ~= from;

			}
			assert(iSec < 1000, "Tile precalculated paths lead to a loop (from="~fromGTriIndex.to!string~", to="~toGTriIndex.to!string~")");
			return ret;
		}

		/// Check a single tile. You should use `TrnNWN2WalkmeshPayload.validate()` instead
		string validate(in TrnNWN2WalkmeshPayload aswm, uint32_t tileIndex, bool strict = false) const {
			import std.typecons: Tuple;
			alias Ret = Tuple!(bool,"valid", string,"error");
			immutable nodesLen = path_table.nodes.length;
			immutable ntlLen = path_table.node_to_local.length;
			immutable ltnLen = path_table.local_to_node.length;
			immutable offset = header.triangles_offset;


			if(header.triangles_count != ltnLen)
				return "local_to_node: length ("~ltnLen.to!string~") does not match triangles_count ("~header.triangles_count.to!string~")";
			if(offset > aswm.triangles.length)
				return "header.triangles_offset: offset ("~offset.to!string~") points to invalid triangles";
			if(offset + ltnLen > aswm.triangles.length)
				return "local_to_node: contains data for invalid triangles";

			if(strict){
				immutable edgeCnt = aswm.triangles[offset .. offset + header.triangles_count]
					.map!((ref a) => a.linked_edges[])
					.join
					.filter!(a => a != a.max)
					.array.dup
					.sort
					.uniq
					.array.length.to!uint32_t;
				immutable vertCnt = aswm.triangles[offset .. offset + header.triangles_count]
					.map!((ref a) => a.vertices[])
					.join
					.filter!(a => a != a.max)
					.array.dup
					.sort
					.uniq
					.array.length.to!uint32_t;

				if(edgeCnt != header.edges_count)
					return "header.edges_count: Wrong number of edges: got "~header.edges_count.to!string~", counted "~edgeCnt.to!string;
				if(vertCnt != header.vertices_count)
					return "header.vertices_count: Wrong number of vertices: got "~header.vertices_count.to!string~", counted "~vertCnt.to!string;
			}

			if(strict){
				uint32_t tileX = tileIndex % aswm.tiles_grid_width;
				uint32_t tileY = tileIndex / aswm.tiles_grid_width;
				auto tileAABB = box2f(
					vec2f(tileX * aswm.tiles_width,       tileY * aswm.tiles_width),
					vec2f((tileX + 1) * aswm.tiles_width, (tileY + 1) * aswm.tiles_width));

				foreach(i ; offset .. offset + header.triangles_count){
					if(!tileAABB.contains(vec2f(aswm.triangles[i].center)))
						return "Triangle "~i.to!string~" is outside of the tile AABB";
				}
			}

			// Path table
			if(nodesLen != ntlLen ^^ 2)
				return "Wrong number of nodes";
			if(nodesLen < 0x7f){
				foreach(j, node ; path_table.nodes){
					if(node == 0xff)
						continue;
					if((node & 0b0111_1111) >= ntlLen)
						return "nodes["~j.to!string~"]: Illegal value "~node.to!string;
				}
			}
			if(nodesLen < 0xff){
				foreach(j, node ; path_table.local_to_node){
					if(node == 0xff)
						continue;
					if(node >= nodesLen)
						return "local_to_node["~j.to!string~"]: Illegal value"~node.to!string;
				}
			}

			foreach(j, ntl ; path_table.node_to_local){
				if(ntl + offset >= aswm.triangles.length)
					return "node_to_local["~j.to!string~"]: triangle index "~ntl.to!string~" out of bounds";
			}

			return null;
		}
	}
	/// Map tile list
	/// Non border tiles have `header.vertices_count > 0 || header.edges_count > 0 || header.triangles_count > 0`
	Tile[] tiles;

	/**
	Tile or fraction of a tile used for pathfinding through large distances.

	<ul>
	<li>The island boundaries match exactly the tile boundaries</li>
	<li>Generally you have one island per tile.</li>
	<li>You can have multiple islands for one tile, like if one side of the tile is not accessible from the other side</li>
	</ul>
	*/
	static struct Island {
		static align(1) struct Header {
			static assert(this.sizeof == 24);
			align(1):
			uint32_t index; /// Index of the island in the aswm.islands array. TODO: weird
			uint32_t tile; /// Value looks pretty random, but is identical for all islands
			Vertex center; /// Center of the island. Z is always 0. TODO: find how it is calculated
			uint32_t triangles_count; /// Number of triangles in this island
		}
		Header header;
		uint32_t[] adjacent_islands; /// Adjacent islands
		float[] adjacent_islands_dist; /// Distances between adjacent islands (probably measured between header.center)

		/**
		List of triangles that are on the island borders, and which linked_edges
		can lead to a triangle that have another triangle.island value.

		<ul>
		<li>There is no need to register all possible exit triangles. Only one per adjacent island is enough.</li>
		<li>Generally it is 4 walkable triangles: 1 top left, 2 bot left and 1 bot right</li>
		</ul>
		*/
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
			return format!"ISLA header: index: %s, tile: %s, center: %s, triangles_count: %s\n"(header.index, header.tile, header.center.position, header.triangles_count)
			     ~ format!"      adjacent_islands: %s\n"(adjacent_islands)
			     ~ format!"      adjacent_islands_dist: %s\n"(adjacent_islands_dist)
			     ~ format!"      exit_triangles: %s\n"(exit_triangles);
		}
	}

	/// Islands list. See `Island`
	Island[] islands;


	static align(1) struct IslandPathNode {
		static assert(this.sizeof == 8);
		uint16_t next; /// Next island index to go to
		uint16_t _padding;
		float weight; /// Distance to `next` island.
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
		edges      = wmdata.readArray!Edge(header.edges_count).dup;
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


	/**
	Serialize TRN packet data
	*/
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

	/**
	Serialize the aswm data without compressing it. Useful for debugging raw data.
	*/
	ubyte[] serializeUncompressed(){
		//update header values
		header.vertices_count  = vertices.length.to!uint32_t;
		header.edges_count = edges.length.to!uint32_t;
		header.triangles_count = triangles.length.to!uint32_t;

		//build uncompressed data
		ChunkWriter uncompData;
		uncompData.put(
			header,
			vertices,
			edges,
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

	/**
	Check if the ASWM contains legit data

	Args:
	strict = false to allow some data inconsistencies that does not cause issues with nwn2
	Returns: Error string. `null` if there is no errors.
	*/
	string validate(bool strict = false) const {

		immutable vertLen = vertices.length;
		immutable edgeLen = edges.length;
		immutable triLen = triangles.length;
		immutable islLen = islands.length;

		// Edges
		foreach(iedge, ref edge ; edges){
			foreach(v ; edge.vertices){
				if(v >= vertLen)
					return "edges["~iedge.to!string~"]: Invalid vertex index "~v.to!string;
			}
			foreach(t ; edge.triangles){
				if(t != uint32_t.max && t >= triLen)
					return "edges["~iedge.to!string~"]: Invalid triangle index "~t.to!string;
			}
		}

		// Triangles
		foreach(itri, ref tri ; triangles){
			foreach(v ; tri.vertices){
				if(v >= vertLen)
					return "triangles["~itri.to!string~"]: Invalid vertex index "~v.to!string;
			}

			foreach(i ; 0 .. 3){
				immutable lj = tri.linked_edges[i];
				immutable lt = tri.linked_triangles[i];
				if(lj >= edgeLen)
					return "triangles["~itri.to!string~"].linked_edges["~i.to!string~"]: invalid edge index "~lj.to!string;
				if(lt != uint32_t.max && lt >= triLen)
					return "triangles["~itri.to!string~"].linked_triangles["~i.to!string~"]: invalid triangle index "~lt.to!string;

				if((edges[lj].triangles[0] != itri || edges[lj].triangles[1] != lt)
					&& (edges[lj].triangles[1] != itri || edges[lj].triangles[0] != lt))
					return "triangles["~itri.to!string~"].linked_xxx["~i.to!string~"]: linked edge does not match linked triangle";
			}

			if(tri.island != uint16_t.max && tri.island >= islLen)
				return "triangles["~itri.to!string~"].island: Invalid island index "~tri.island.to!string;
		}

		// Tiles
		if(tiles.length != tiles_grid_width * tiles_grid_height)
			return "Wrong number of tiles (should be tiles_grid_width * tiles_grid_height)";

		if(tiles_width <= 0.0)
			return "tiles_width: must be > 0";

		foreach(i, ref tile ; tiles){
			auto err = tile.validate(this, cast(uint32_t)i, strict);
			if(err !is null)
				return "tiles["~i.to!string~"]: "~err;
		}

		uint32_t[] overlapingTri;
		overlapingTri.length = triangles.length;
		overlapingTri[] = uint32_t.max;
		foreach(i, ref tile ; tiles){
			foreach(t ; tile.header.triangles_offset .. tile.header.triangles_offset + tile.header.triangles_count){
				if(overlapingTri[t] != uint32_t.max)
					return "tiles["~i.to!string~"]: triangle "~t.to!string~" (center="~triangles[t].center.to!string~") is already owned by tile "~overlapingTri[t].to!string;
				overlapingTri[t] = cast(uint32_t)i;
			}
		}

		// Islands
		foreach(isli, ref island ; islands){
			if(island.header.index != isli)
				return "islands["~isli.to!string~"].header.index: does not match island index in islands array";


			if(island.adjacent_islands.length != island.adjacent_islands_dist.length
			|| island.adjacent_islands.length != island.exit_triangles.length)
				return "islands["~isli.to!string~"]: adjacent_islands/adjacent_islands_dist/exit_triangles length mismatch";

			foreach(i ; 0 .. island.adjacent_islands.length){
				if(island.adjacent_islands[i] >= islLen)// Note: Skywing allows uint16_t.max value
					return "islands["~isli.to!string~"].adjacent_islands["~i.to!string~"]: Invalid island index";
				if(island.exit_triangles[i] >= triLen)
					return "islands["~isli.to!string~"].exit_triangles["~i.to!string~"]: Invalid triangle index";

				foreach(exitIdx, t ; island.exit_triangles){
					if(triangles[t].island != isli)
						return "islands["~isli.to!string~"].exit_triangles["~exitIdx.to!string~"]: triangle is outside of the island";

					bool found = false;
					foreach(lt ; triangles[t].linked_triangles){
						if(lt != uint32_t.max
						&& triangles[lt].island == island.adjacent_islands[exitIdx]){
							found = true;
							break;
						}
					}
					if(!found)
						return "islands["~isli.to!string~"].linked_triangles["~exitIdx.to!string~"]: triangle is not linked to island "~island.adjacent_islands[exitIdx].to!string;
				}

			}
		}

		// Island path nodes
		if(islands_path_nodes.length != islands.length ^^ 2)
			return "Wrong number of islands / islands_path_nodes";
		foreach(i, ipn ; islands_path_nodes){
			if(ipn.next != uint16_t.max && ipn.next >= islLen)
				return "islands_path_nodes["~i.to!string~"]: Invalid next island index "~ipn.next.to!string;
		}

		return null;
	}

	/**
	Dump trn data as text
	*/
	string dump() const {
		import std.algorithm;
		import std.array: array;

		string ret;

		ret ~= "==== HEADER ====\n";
		ret ~= "unknownA: " ~ header.unknownA.to!string ~ "\n";
		ret ~= "vertices_count: " ~ header.vertices_count.to!string ~ "\n";
		ret ~= "edges_count: " ~ header.edges_count.to!string ~ "\n";
		ret ~= "triangles_count: " ~ header.triangles_count.to!string ~ "\n";
		ret ~= "unknownB: " ~ header.unknownB.to!string ~ "\n";

		ret ~= "==== VERTICES ====\n";
		ret ~= vertices.map!(a => format!"VERT %s\n"(a.position)).join;

		ret ~= "==== EDGES ====\n";
		ret ~= edges.map!(a => format!"EDGE line: %s, tri: %s\n"(a.vertices, a.triangles)).join;

		ret ~= "==== TRIANGLES ====\n";
		ret ~= triangles.map!(a =>
				  format!"TRI vert: %s, edge: %s, tri: %s\n"(a.vertices, a.linked_edges, a.linked_triangles)
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



	// Each entry is one triangle index from every separate island on this tile
	private static struct IslandMeta{
		uint32_t tile;
		uint32_t islandTriangle;
		// This will store all edges that can lead to other tiles
		uint32_t[] edges;
	}

	/**
	Removes triangles from the mesh, and removes unused vertices and edges accordingly.

	Also updates vertex / edge / triangle indices to match new indices.

	Does not updates path tables. You need to run `bake()` to re-generate path tables.

	Params:
	removeFunc = Delegate to check is triangle must be removed.
	*/
	void removeTriangles(bool delegate(in Triangle) removeFunc){
		uint32_t[] vertTransTable, edgeTransTable, triTransTable;
		vertTransTable.length = vertices.length;
		edgeTransTable.length = edges.length;
		triTransTable.length = triangles.length;
		vertTransTable[] = uint32_t.max;
		edgeTransTable[] = uint32_t.max;
		triTransTable[] = uint32_t.max;

		bool[] usedEdges, usedVertices;
		usedVertices.length = vertices.length;
		usedEdges.length = edges.length;
		usedVertices[] = false;
		usedEdges[] = false;

		// Reduce triangle list & flag used edges
		uint32_t newIndex = 0;
		foreach(i, ref triangle ; triangles){
			if(removeFunc(triangle)){

				// Flag used / unused vertices & edges
				foreach(vert ; triangle.vertices){
					usedVertices[vert] = true;
				}
				foreach(edge ; triangle.linked_edges){
					if(edge != uint32_t.max)
						usedEdges[edge] = true;
				}

				// Reduce triangle list in place
				triangles[newIndex] = triangle;
				triTransTable[i] = newIndex++;
			}
			else
				triTransTable[i] = uint32_t.max;
		}
		triangles.length = newIndex;

		// Reduce vertices list
		newIndex = 0;
		foreach(i, used ; usedVertices){
			if(used){
				vertices[newIndex] = vertices[i];
				vertTransTable[i] = newIndex++;
			}
			else
				vertTransTable[i] = uint32_t.max;
		}
		vertices.length = newIndex;

		// Reduce edges list
		newIndex = 0;
		foreach(i, used ; usedEdges){
			if(used){
				edges[newIndex] = edges[i];
				edgeTransTable[i] = newIndex++;
			}
			else
				edgeTransTable[i] = uint32_t.max;
		}
		edges.length = newIndex;

		translateIndices(triTransTable, edgeTransTable, vertTransTable);
	}

	/**
	Translate triangle / edge / vertex indices stored in mesh data.

	Each argument is a table of the length of the existing list where:
	<ul>
	<li>The index is the index of the current triangle</li>
	<li>The value is the index of the translated triangle</li>
	</ul>
	If the argument is an empty array, no translation is done. Does NOT update path tables & islands data.
	*/
	void translateIndices(uint32_t[] triTransTable, uint32_t[] edgeTransTable, uint32_t[] vertTransTable){
		immutable ttrans = triTransTable.length > 0;
		immutable jtrans = edgeTransTable.length > 0;
		immutable vtrans = vertTransTable.length > 0;

		// Adjust indices in edges data
		foreach(ref edge ; edges){
			if(vtrans){
				foreach(ref vert ; edge.vertices){
					vert = vertTransTable[vert];
					assert(vert != uint32_t.max && vert < vertices.length, "Invalid vertex index");
				}
			}
			if(ttrans){
				foreach(ref tri ; edge.triangles){
					if(tri != uint32_t.max){
						tri = triTransTable[tri];
						assert(tri == uint32_t.max || tri < triangles.length, "Invalid triangle index");
					}
				}

			}
			// Pack triangle indices (may be overkill)
			if(edge.triangles[0] == uint32_t.max && edge.triangles[1] != uint32_t.max){
				edge.triangles[0] = edge.triangles[1];
				edge.triangles[1] = uint32_t.max;
			}
		}

		// Adjust indices in triangles data
		foreach(ref triangle ; triangles){
			if(vtrans){
				foreach(ref vert ; triangle.vertices){
					vert = vertTransTable[vert];
					assert(vert != uint32_t.max && vert < vertices.length, "Invalid vertex index");
				}
			}
			if(jtrans){
				foreach(ref edge ; triangle.linked_edges){
					edge = edgeTransTable[edge];//All triangles should have 3 edges
					assert(edge < edges.length, "Invalid edge index");
				}
			}
			if(ttrans){
				foreach(ref tri ; triangle.linked_triangles){
					if(tri != uint32_t.max){
						tri = triTransTable[tri];
					}
				}
			}
		}

	}

	/// Reorder triangles and prepare tile triangles associations
	private
	void splitTiles(){
		uint32_t[] triTransTable;
		triTransTable.length = triangles.length;
		triTransTable[] = uint32_t.max;


		Triangle[] newTriangles;
		newTriangles.length = triangles.length;
		uint32_t newTrianglesPtr = 0;

		foreach(y ; 0 .. tiles_grid_height){
			foreach(x ; 0 .. tiles_grid_width){
				auto tileAABB = box2f(
					vec2f(x * tiles_width,       y * tiles_width),
					vec2f((x + 1) * tiles_width, (y + 1) * tiles_width));

				auto tile = &tiles[y * tiles_grid_width + x];
				tile.header.triangles_offset = newTrianglesPtr;

				foreach(i, ref tri ; triangles){
					if(tileAABB.contains(vec2f(tri.center))){
						newTriangles[newTrianglesPtr] = tri;
						triTransTable[i] = newTrianglesPtr;
						newTrianglesPtr++;
					}
				}
				tile.header.triangles_count = newTrianglesPtr - tile.header.triangles_offset;
			}
		}

		triangles = newTriangles[0 .. newTrianglesPtr];

		translateIndices(triTransTable, [], []);
	}

	/**
	Bake the existing walkmesh by re-creating tiles, islands, path tables, ...

	Does not modify the current walkmesh like what you would expect with
	placeable walkmesh / walkmesh cutters.

	Params:
	removeBorders = true to remove unwalkable map borders from the walkmesh.
	*/
	void bake(bool removeBorders = true){
		// Reset island associations
		triangles.each!((ref a) => a.island = 0xffff);

		// Remove border triangles
		if(removeBorders){
			auto terrainAABB = box2f(
				vec2f(tiles_border_size * tiles_width, tiles_border_size * tiles_width),
				vec2f((tiles_grid_width - tiles_border_size) * tiles_width, (tiles_grid_height - tiles_border_size) * tiles_width));

			removeTriangles(a => terrainAABB.contains(vec2f(a.center)));
		}

		// Reorder triangles to have consecutive triangles for each tile
		splitTiles();

		IslandMeta[] islandsMeta;
		islandsMeta.reserve(tiles.length * 2);

		// Bake tiles
		foreach(i ; 0 .. tiles.length){
			//removeBorders
			islandsMeta ~= bakeTile(i.to!uint32_t);
		}

		// islandTileID looks random-ish in TRX files. Here we generate by
		// calculating a 32bit CRC with islandsMeta data, so bake() result is
		// reproducible
		import std.digest.crc: crc32Of;
		auto islandTileID = *cast(uint32_t*)crc32Of(islandsMeta).ptr;

		islands.length = islandsMeta.length;
		foreach(i, ref island ; islands){
			// Set island index
			island.header.index = i.to!uint32_t;

			// Set island associated tile
			//island.header.tile = islandsMeta[i].tile;
			island.header.tile = islandTileID;

			auto tile = &tiles[islandsMeta[i].tile];
			auto tileTriangleOffset = tile.header.triangles_offset;
			auto firstLTri = islandsMeta[i].islandTriangle - tileTriangleOffset;
			auto tileNTLLen = tile.path_table.node_to_local.length;
			auto nodeIndex = tile.path_table.local_to_node[firstLTri];

			assert(nodeIndex != 0xff, "BakeTile returned a non walkable islandTriangle");

			//writeln("len=", tile.path_table.nodes.length, " [", tileNTLLen * nodeIndex, " .. ", tileNTLLen * (nodeIndex + 1), "], ntllen=", tileNTLLen);
			auto nodes = tile.path_table.nodes[tileNTLLen * nodeIndex .. tileNTLLen * (nodeIndex + 1)];

			// Retrieve island triangle list
			uint32_t[] islandTriangles;
			islandTriangles.reserve(nodes.length);

			islandTriangles ~= islandsMeta[i].islandTriangle;
			foreach(j, node ; nodes){
				// TODO: o(n^^2)
				if(node != 0xff)
					islandTriangles ~= (tile.path_table.local_to_node.countUntil(j) + tileTriangleOffset).to!uint32_t;
			}

			// Set island triangle count
			island.header.triangles_count = islandTriangles.length.to!uint32_t;

			// Set island center (calculated by avg all triangle centers)
			island.header.center.position = [0,0,0];
			foreach(t ; islandTriangles)
				island.header.center.position[0 .. 2] += triangles[t].center[];
			island.header.center.position[] /= cast(double)islandTriangles.length;

			// Set triangle associated island index
			foreach(t ; islandTriangles)
				triangles[t].island = i.to!uint16_t;
		}

		// Set island connections
		foreach(i, ref island ; islands){

			island.adjacent_islands.length = 0;
			island.adjacent_islands_dist.length = 0;
			island.exit_triangles.length = 0;

			foreach(edge ; islandsMeta[i].edges){

				uint32_t exitTriangle = uint32_t.max;
				uint32_t exitIsland = uint32_t.max;

				foreach(t ; edges[edge].triangles){
					immutable islandIdx = triangles[t].island;
					if(islandIdx == i)
						exitTriangle = t;
					else
						exitIsland = islandIdx;
				}

				if(exitTriangle != uint32_t.max && exitIsland != uint32_t.max
				&& island.adjacent_islands.find(exitIsland).empty){
					island.adjacent_islands ~= exitIsland;
					island.exit_triangles ~= exitTriangle;

					// Calculate island distance
					import std.math: sqrt;
					auto dist = islands[exitIsland].header.center.position.dup;
					dist[] -= island.header.center.position[];
					island.adjacent_islands_dist ~= sqrt(dist[0] ^^ 2 + dist[1] ^^ 2);
				}

			}
		}

		// Rebuild island path tables
		islands_path_nodes.length = islands.length ^^ 2;
		islands_path_nodes[] = IslandPathNode(uint16_t.max, 0, 0.0);


		foreach(uint32_t fromIslandIdx, ref fromIsland ; islands){

			bool[] visitedIslands;
			visitedIslands.length = islands.length;
			visitedIslands[] = false;


			static struct NextToExplore{
				uint16_t[] list;
				uint16_t target = uint16_t.max;
				float distance = 0.0;
			}
			auto getIslandPathNode(uint32_t from, uint32_t to){
				return &islands_path_nodes[from * islands.length + to];
			}

			NextToExplore[] explore(uint16_t islandIdx, uint16_t targetIsland = uint16_t.max, float distance = 0.0){
				NextToExplore[] ret;
				if(targetIsland != uint16_t.max)
					ret ~= NextToExplore([], targetIsland, distance);


				foreach(j, linkedIslIdx ; islands[islandIdx].adjacent_islands){

					if(linkedIslIdx == fromIslandIdx)
						continue;// We must not visit initial island (node value must stay as 0xff)

					auto linkedIsl = &islands[linkedIslIdx];

					auto node = getIslandPathNode(fromIslandIdx, linkedIslIdx);
					if(node.next == uint16_t.max){
						// This is the first time we visit the island from this fromTriIdx

						if(targetIsland == uint16_t.max){
							ret ~= NextToExplore([], linkedIslIdx.to!uint16_t, islands[islandIdx].adjacent_islands_dist[j]);
						}

						ret[$-1].list ~= linkedIslIdx.to!uint16_t;

						node.next = ret[$-1].target;
						node.weight = ret[$-1].distance;
					}
				}
				return ret;
			}

			NextToExplore[] nextToExplore = [ NextToExplore([fromIslandIdx.to!uint16_t]) ];
			NextToExplore[] newNextToExplore;
			while(nextToExplore.length > 0 && nextToExplore.map!(a => a.list.length).sum > 0){
				foreach(ref nte ; nextToExplore){
					foreach(t ; nte.list){
						newNextToExplore ~= explore(t, nte.target, nte.distance);
					}
				}
				nextToExplore = newNextToExplore;
				newNextToExplore.length = 0;
			}

		}

		debug{
			auto err = validate();
			assert(err is null, err);
		}

	}

	private IslandMeta[] bakeTile(uint32_t tileIndex){
		//writeln("bakeTile: ", tileIndex);

		auto tile = &tiles[tileIndex];
		uint32_t tileX = tileIndex % tiles_grid_width;
		uint32_t tileY = tileIndex / tiles_grid_width;

		// Get tile bounding box
		auto tileAABB = box2f(
			vec2f(tileX * tiles_width, tileY * tiles_width),
			vec2f((tileX + 1) * tiles_width, (tileY + 1) * tiles_width));

		// Build tile triangle list
		immutable trianglesOffset = tile.header.triangles_offset;
		uint32_t[] tileTriangles;
		tileTriangles.length = tile.header.triangles_count;
		foreach(i, ref t ; tileTriangles)
			t = (i + trianglesOffset).to!uint32_t;

		// Recalculate edge & vert count
		tile.header.edges_count = triangles[trianglesOffset .. trianglesOffset + tile.header.triangles_count]
			.map!((ref a) => a.linked_edges[])
			.join
			.filter!(a => a != a.max)
			.array
			.sort
			.uniq
			.array.length.to!uint32_t;
		tile.header.vertices_count = triangles[trianglesOffset .. trianglesOffset + tile.header.triangles_count]
			.map!((ref a) => a.vertices[])
			.join
			.filter!(a => a != a.max)
			.array
			.sort
			.uniq
			.array.length.to!uint32_t;


		// Find walkable triangles to deduce NTL length & LTN content
		const walkableTriangles = tileTriangles.filter!(a => triangles[a].flags & Triangle.Flags.walkable).array;
		immutable walkableTrianglesLen = walkableTriangles.length.to!uint32_t;

		// node_to_local indices are stored on 7 bits
		enforce(walkableTrianglesLen < 0b0111_1111, "Too many walkable triangles on a single tile");

		// Fill NTL with walkable triangles local indices
		tile.path_table.node_to_local = walkableTriangles.dup;
		tile.path_table.node_to_local[] -= trianglesOffset;
		ubyte getNtlIndex(uint32_t destTriangle){
			destTriangle -= trianglesOffset;
			// insert destTriangle inside ntl and return its index
			foreach(i, t ; tile.path_table.node_to_local){
				if(t == destTriangle)
					return i.to!ubyte;
			}
			assert(0, "Triangle local idx="~destTriangle.to!string~" not found in NTL array "~tile.path_table.node_to_local.to!string);
		}

		// Set LTN content: 0xff if the triangle is unwalkable, otherwise an
		// index in walkableTriangles
		tile.path_table.local_to_node.length = tile.header.triangles_count;

		tile.path_table.local_to_node[] = 0xff;
		foreach(i, triIdx ; walkableTriangles)
			tile.path_table.local_to_node[triIdx - trianglesOffset] = i.to!ubyte;

		// Resize nodes table
		tile.path_table.nodes.length = (walkableTrianglesLen * walkableTrianglesLen).to!uint32_t;
		tile.path_table.nodes[] = 0xff;// 0xff means inaccessible.


		ubyte* getNode(uint32_t fromGIdx, uint32_t toGIdx) {
			return &tile.path_table.nodes[
				tile.path_table.local_to_node[fromGIdx - trianglesOffset] * walkableTrianglesLen
				+ tile.path_table.local_to_node[toGIdx - trianglesOffset]
			];
		}


		// Visited triangles. Not used for pathfinding, but for island detection.
		bool[] visitedTriangles;
		visitedTriangles.length = tile.path_table.local_to_node.length;
		visitedTriangles[] = false;


		IslandMeta[] islandsMeta;
		bool islandRegistration = false;


		// Calculate pathfinding
		foreach(i, fromTriIdx ; walkableTriangles){

			// If the triangle has not been visited before, we add a new
			// island All triangles accessible from this one will be marked as
			// visited, so we don't add more than once the same island
			if(visitedTriangles[fromTriIdx - trianglesOffset] == false){
				islandsMeta ~= IslandMeta(tileIndex, fromTriIdx, []);
				islandRegistration = true;
			}
			else
				islandRegistration = false;

			static struct NextToExplore{
				uint32_t[] list;
				ubyte ntlTarget = ubyte.max;
			}

			NextToExplore[] explore(uint32_t currTriIdx, ubyte ntlTarget = ubyte.max){
				NextToExplore[] ret;
				if(ntlTarget != ubyte.max)
					ret ~= NextToExplore([], ntlTarget);

				foreach(j, linkedTriIdx ; triangles[currTriIdx].linked_triangles){
					if(linkedTriIdx == uint32_t.max)
						continue;// there is no linked triangle

					if(fromTriIdx == linkedTriIdx)
						continue;// We must not visit initial triangle (node value must stay as 0xff)

					auto linkedTri = &triangles[linkedTriIdx];

					if(!(linkedTri.flags & linkedTri.Flags.walkable))
						continue;// non walkable triangle

					if(tileAABB.contains(vec2f(linkedTri.center))){
						// linkedTri is inside the tile

						// Mark the triangle as visited (only for island detection)
						visitedTriangles[linkedTriIdx - trianglesOffset] = true;

						auto node = getNode(fromTriIdx, linkedTriIdx);
						if(*node == 0xff){
							// This is the first time we visit the triangle from this fromTriIdx

							if(ntlTarget == ubyte.max){
								ret ~= NextToExplore([], getNtlIndex(linkedTriIdx));
							}

							ret[$-1].list ~= linkedTriIdx;

							assert(ret[$-1].ntlTarget < 0b0111_1111);
							*node = ret[$-1].ntlTarget;// TODO: do VISIBLE / LOS calculation
						}
					}
					else{
						// linkedTri is outside the tile
						if(islandRegistration){
							immutable edgeIdx = triangles[currTriIdx].linked_edges[j];
							assert(edges[edgeIdx].triangles[0] == currTriIdx && edges[edgeIdx].triangles[1] == linkedTriIdx
								|| edges[edgeIdx].triangles[1] == currTriIdx && edges[edgeIdx].triangles[0] == linkedTriIdx,
								"Incoherent edge "~edgeIdx.to!string~": "~edges[edgeIdx].to!string);
							islandsMeta[$-1].edges ~= edgeIdx;
						}
					}
				}
				return ret;
			}

			NextToExplore[] nextToExplore = [ NextToExplore([fromTriIdx]) ];
			NextToExplore[] newNextToExplore;
			while(nextToExplore.length > 0 && nextToExplore.map!(a => a.list.length).sum > 0){
				foreach(ref nte ; nextToExplore){
					foreach(t ; nte.list){
						newNextToExplore ~= explore(t, nte.ntlTarget);
					}
				}
				nextToExplore = newNextToExplore;
				newNextToExplore.length = 0;
			}
		}

		//if(walkableTrianglesLen > 0)
		//	writeln("Tile ", tileIndex, ": ", walkableTrianglesLen, " walkable triangles in ", islandsMeta.length, " islands");

		return islandsMeta;
	}

	/**
	Calculate the fastest route between two islands. The area need to be baked, as it uses existing path tables.
	*/
	uint16_t[] findIslandsPath(in uint16_t fromIslandIndex, in uint16_t toIslandIndex) const {
		uint16_t from = fromIslandIndex;
		int iSec = 0;
		uint16_t[] ret;
		while(fromIslandIndex != toIslandIndex && iSec++ < 1000){
			auto node = &islands_path_nodes[from * islands.length + toIslandIndex];
			if(node.next == uint16_t.max)
				return ret;

			from = node.next;
			ret ~= from;
		}
		assert(iSec < 1000, "Islands precalculated paths lead to a loop (from="~fromIslandIndex.to!string~", to="~toIslandIndex.to!string~")");
		return ret;
	}

	/**
	Set 3d mesh geometry
	*/
	void setGenericMesh(in GenericASWMMesh mesh){
		// Copy vertices
		vertices.length = mesh.vertices.length;
		foreach(i, ref v ; vertices)
			v.position = mesh.vertices[i].v;

		// Copy triangles
		triangles.length = mesh.triangles.length;
		foreach(i, ref t ; triangles){
			t.vertices = mesh.triangles[i].vertices.dup[0 .. 3];

			t.linked_edges[] = uint32_t.max;
			t.linked_triangles[] = uint32_t.max;

			t.center = vertices[t.vertices[0]].position[0 .. 2];
			t.center[] += vertices[t.vertices[1]].position[0 .. 2];
			t.center[] += vertices[t.vertices[2]].position[0 .. 2];
			t.center[] /= 3.0;

			t.normal = vertices[t.vertices[0]].x * vertices[t.vertices[1]].x
				+ vertices[t.vertices[0]].y * vertices[t.vertices[1]].y
				+ vertices[t.vertices[0]].z * vertices[t.vertices[1]].z;

			t.dot_product = vertices[t.vertices[0]].x * vertices[t.vertices[1]].x * vertices[t.vertices[2]].x
				+ vertices[t.vertices[0]].y * vertices[t.vertices[1]].y * vertices[t.vertices[2]].y
				+ vertices[t.vertices[0]].z * vertices[t.vertices[1]].z * vertices[t.vertices[2]].z;

			t.island = uint16_t.max;

			t.flags = mesh.triangles[i].flags;
			if(isTriangleClockwise(t.vertices[].map!(a => vec2f(vertices[a].position[0 .. 2])).array[0 .. 3]))
				t.flags |= t.Flags.clockwise;
			else
				t.flags &= t.flags.max ^ t.Flags.clockwise;
		}

		// Rebuild edge list
		buildEdges();
	}

	/**
	Converts terrain mesh data to a more generic format.
	*/
	GenericASWMMesh toGenericMesh() const {
		GenericASWMMesh ret;
		ret.vertices.length = vertices.length;
		ret.triangles.length = triangles.length;

		foreach(i, ref v ; vertices){
			ret.vertices[i] = vec3f(v.position);
		}
		foreach(i, ref t ; triangles){
			ret.triangles[i] = ret.Triangle(t.vertices, t.flags);
		}
		return ret;
	}

	/**
	Rebuilds edge data by going through every triangle / vertices

	Warning: NWN2 official baking tool often produces duplicated triangles and
	edges around placeable walkmeshes.
	*/
	void buildEdges(){
		uint32_t[uint32_t[2]] edgeMap;
		uint32_t findEdge(uint32_t[2] vertices){
			if(auto j = vertices in edgeMap)
				return *j;
			return uint32_t.max;
		}

		edges.length = 0;

		foreach(i, ref t ; triangles){
			// Create edges as needed
			foreach(j ; 0 .. 3){
				auto vrt = [t.vertices[j], t.vertices[(j+1) % 3]].sort.array;
				auto edgeIdx = findEdge(vrt[0 .. 2]);

				if(edgeIdx == uint32_t.max){
					// Add new edge
					edgeMap[vrt[0 .. 2]] = edges.length.to!uint32_t;
					edges ~= Edge(vrt[0 .. 2], [i.to!uint32_t, uint32_t.max]);
				}
				else{
					// Add triangle to existing edge
					enforce(edges[edgeIdx].triangles[1] == uint32_t.max,
						"Edge "~edgeIdx.to!string~" = "~edges[edgeIdx].to!string~" cannot be linked to more than 2 triangles (cannot add triangle "~i.to!string~")");
					edges[edgeIdx].triangles[1] = i.to!uint32_t;
				}
			}
		}

		// update triangles[].linked_edge & triangles[].linked_triangles
		foreach(edgeIdx, ref edge ; edges){
			assert(edge.triangles[0] != uint32_t.max);

			foreach(j, tIdx ; edge.triangles){
				if(tIdx == uint32_t.max)
					continue;

				size_t slot;
				for(slot = 0 ; slot < 3 ; slot++)
					if(triangles[tIdx].linked_edges[slot] == uint32_t.max)
						break;
				assert(slot < 3, "Triangle "~tIdx.to!string~" is already linked to 3 triangles");

				triangles[tIdx].linked_edges[slot] = edgeIdx.to!uint32_t;
				triangles[tIdx].linked_triangles[slot] = edge.triangles[(j + 1) % 2];
			}
		}

	}

}

unittest {
	auto epportesTrx = cast(ubyte[])import("eauprofonde-portes.trx");

	auto trn = new Trn(epportesTrx);
	auto serialized = trn.serialize();
	assert(epportesTrx.length == serialized.length && epportesTrx == serialized);

	foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
		assert(aswm.validate() is null, aswm.validate());

		aswm.bake();
		assert(aswm.validate() is null, aswm.validate());

		aswm.removeTriangles((in t) => (t.flags & t.Flags.walkable) == 0);
		aswm.bake();
		assert(aswm.validate() is null, aswm.validate());
	}


	trn = new Trn(cast(ubyte[])import("IslandsTest.trn"));
	foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
		assert(aswm.validate() is null, aswm.validate());

		auto mesh = aswm.toGenericMesh;

		// Shuffle mesh
		mesh.shuffle();
		aswm.setGenericMesh(mesh);
		aswm.bake();

		assert(aswm.validate() is null, aswm.validate());

		// Values taken from trx file baked with the toolset
		assert(aswm.triangles.length == 1152);
		assert(aswm.edges.length == 1776);
		assert(aswm.islands.length == 25);
	}
}








struct GenericASWMMesh {
	vec3f[] vertices;

	static struct Triangle{
		uint32_t[3] vertices; /// Vertex indices composing the triangle
		uint16_t flags; /// See `Flags`
		enum Flags {
			walkable  = 0x01, /// if the triangle can be walked on. Note the triangle needs path tables to be really walkable
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

	/// Throw an exception if mesh contains invalid indices
	void validate(){
		foreach(i, ref t ; triangles)
			foreach(vi ; t.vertices)
				enforce(vi < vertices.length,
					"Triangle "~i.to!string~" contains invalid vertex index ("~vi.to!string~")");
	}

	/// Shuffle all data, while keeping the same 3d model
	void shuffle(){
		// Shuffle all triangles & vertices
		uint32_t[] vertTransTable, triTransTable;
		vertTransTable.length = vertices.length;
		triTransTable.length = triangles.length;
		foreach(uint32_t i, ref val ; vertTransTable) val = i;
		foreach(uint32_t i, ref val ; triTransTable) val = i;

		import std.random: randomShuffle;
		vertTransTable.randomShuffle();
		triTransTable.randomShuffle();

		auto oldVertices = this.vertices.idup;
		auto oldTriangles = this.triangles.idup;

		foreach(oldVIdx, newVIdx ; vertTransTable)
			vertices[newVIdx] = vec3f(oldVertices[oldVIdx]);

		foreach(oldTIdx, newTIdx ; triTransTable){
			auto oldTri = &oldTriangles[oldTIdx];
			triangles[newTIdx] = Triangle(oldTri.vertices, oldTri.flags);

			foreach(ref v ; triangles[newTIdx].vertices[].randomShuffle)
				v = vertTransTable[v];
		}
	}

}