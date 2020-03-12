module nwn.mdb;

import std.stdint;
import std.typecons;
import nwnlibd.parseutils;

class Mdb {



	static align(1) struct Header {
		static assert(this.sizeof == 12);
		align(1):
		char[4] type;
		uint16_t majorVersion;
		uint16_t minorVersion;
		uint32_t packets_length;
	}
	Header header;

	enum PacketType: char[4] {
		RIGD = "RIGD", /// Rigid body
		SKIN = "SKIN", /// Skin Vertex
		COL2 = "COL2", /// Coarse collision mesh
		COL3 = "COL3", /// Precise collision mesh
		HOOK = "HOOK", /// Hook point
		WALK = "WALK", /// Walk Mesh
		COLS = "COLS",
		TRRN = "TRRN",
		HELM = "HELM",
		HAIR = "HAIR"
	}

	static align(1) struct PacketKey {
		static assert(this.sizeof == 8);
		align(1):
		PacketType type;
		uint32_t offset;
	}
	PacketKey[] packet_keys;

	static struct Packet {
		PacketType type;
		package ubyte[] rawData;

		package this(PacketType type, in ubyte[] rawData){
			this.type = type;
			this.rawData = rawData.dup;
		}

		auto get(PacketType type)(){
			assert(type == this.type, "Wrong packet type");

			scope(exit) rawData = null;

			static if(type == PacketType.WALK) return MdbWALK(rawData);
			else static assert(0, "MDB packet "~type~" not implemented");
		}
	}
	Packet[] packets;



	this(in ubyte[] data){
		auto cr = new ChunkReader(data);
		header = cr.read!Header;

		packet_keys = cr.readArray!PacketKey(header.packets_length).dup;

		packets.length = header.packets_length;
		foreach(ref packet ; packets){
			auto type = cr.read!PacketType;
			auto size = cr.read!uint32_t;

			packet = Packet(type, cr.readArray(size));
		}

		assert(cr.bytesLeft == 0, "Remaining data");
	}

}

private align(1) union MdbVertex {
	static assert(this.sizeof == 12);
	align(1):
	float[3] position;

	private struct Xyz{ float x, y, z; }
	Xyz _xyz;
	alias _xyz this;
}

private align(1) struct MdbTriangle {
	static assert(this.sizeof == 6);
	align(1):
	uint16_t[3] vertices;
}


struct MdbWALK {

	static align(1) struct Header {
		char[32] name;
		uint32_t ui_flags;
		uint32_t vertices_length;
		uint32_t triangles_length;
	}
	Header header;
	MdbVertex[] vertices;

	static align(1) struct MdbWalkTriangle {
		align(1):
		MdbTriangle tri;
		alias tri this;

		enum Flags : uint32_t {
			walkable = 0b00000000_00000000_00000000_00000001,
			_res1    = 0b00000000_00000000_00000000_00000010,
			_res2    = 0b00000000_00000000_00000000_00000100,
			dirt     = 0b00000000_00000000_00000000_00001000,
			grass    = 0b00000000_00000000_00000000_00010000,
			stone    = 0b00000000_00000000_00000000_00100000,
			wood     = 0b00000000_00000000_00000000_01000000,
			carpet   = 0b00000000_00000000_00000000_10000000,
			metal    = 0b00000000_00000000_00000001_00000000,
			swamp    = 0b00000000_00000000_00000010_00000000,
			mud      = 0b00000000_00000000_00000100_00000000,
			leaves   = 0b00000000_00000000_00001000_00000000,
			water    = 0b00000000_00000000_00010000_00000000,
			puddles  = 0b00000000_00000000_00100000_00000000,
			_res3    = 0b11111111_11111111_11000000_00000000,
		}
		uint32_t flags;
	}
	MdbWalkTriangle[] triangles;

	this(in ubyte[] rawData){
		auto cr = ChunkReader(rawData);

		header = cr.read!Header;
		vertices = cr.readArray!MdbVertex(header.vertices_length).dup;
		triangles = cr.readArray!MdbWalkTriangle(header.triangles_length).dup;

		assert(cr.bytesLeft == 0, "Remaining data");
	}

	void toObj(string filePath) const {
		import std.stdio;
		auto obj = File(filePath, "w");
		obj.writeln("o ", filePath);

		foreach(ref v ; vertices){
			writeln("z=", *cast(uint16_t*)&v.z);
			obj.writefln("v %(%f %)", v.position);
		}
		foreach(ref t ; triangles){
			obj.writefln("f %s %s %s", t.vertices[0] + 1, t.vertices[1] + 1, t.vertices[2] + 1);
		}
	}

}


version(None) unittest {
	const balcony = cast(ubyte[])import("PLC_MC_BALCONY3.MDB");

	auto mdb = new Mdb(balcony);
	foreach(ref packet ; mdb.packets){
		if(packet.type == Mdb.PacketType.WALK){
			auto wm = packet.get!(Mdb.PacketType.WALK);
		}
	}
}