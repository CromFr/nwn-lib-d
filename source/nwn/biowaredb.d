/// Foxpro database format (bioware database)
module nwn.biowaredb;

public import nwn.types;

import std.stdio: File, stderr;
import std.stdint;
import std.conv: to;
import std.datetime;
import std.typecons: Tuple, Nullable;
import std.variant;
import std.string;
import std.array;
import std.range.interfaces;
import std.exception: enforce;
import nwnlibd.parseutils;

debug import std.stdio: writeln;
version(unittest) import std.exception: assertThrown, assertNotThrown;


/// Type of the GFF raw data stored when using StoreCampaignObject
alias BinaryObject = ubyte[];


class BiowareDBException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}


class BiowareDB{

	this(in ubyte[] dbfData, in ubyte[] cdxData, in ubyte[] fptData){
		table.data = dbfData.dup();
		//index.data = cdxData.dup();
		memo.data = fptData.dup();

		buildIndex();
	}



	enum VarType : char{
		Int = 'I',
		Float = 'F',
		String = 'S',
		Vector = 'V',
		Location = 'L',
		BinaryObject = 'O',
	}
	static struct Variable{
		size_t index;
		bool deleted;

		string name;
		string playerid;
		DateTime timestamp;

		VarType type;
	}

	Nullable!size_t getVariableIndex(in string account, in string character, in string variable){
		if(auto i = Key(account~character, variable) in index)
			return Nullable!size_t(*i);
		return Nullable!size_t();
	}


	T getVariableValue(T)(size_t index)
	if(is(T == NWInt) || is(T == NWFloat) || is(T == NWString) || is(T == NWVector) || is(T == NWLocation) || is(T == BinaryObject))
	{
		auto record = table.getRecord(index);
		char type = record[RecOffset.VarType];

		static if(is(T == NWInt)){
			if(type == VarType.Int){
				return (cast(const char[])record[RecOffset.Int .. RecOffset.DBL1]).strip().to!T;
			}
		}
		else static if(is(T == NWFloat)){
			if(type == VarType.Float){
				return (cast(const char[])record[RecOffset.DBL1 .. RecOffset.DBL2]).strip().to!T;
			}
		}
		else static if(is(T == NWString)){
			if(type == VarType.String){
				auto memoIndex = (cast(const char[])record[RecOffset.Memo .. RecOffset.End]).strip().to!ulong;
				return (cast(char[])memo.getBlockContent(memoIndex)).to!string;
			}
		}
		else static if(is(T == NWVector)){
			if(type == VarType.Vector){
				return cast(NWVector)[
						(cast(const char[])record[RecOffset.DBL1 .. RecOffset.DBL2]).strip().to!NWFloat,
						(cast(const char[])record[RecOffset.DBL2 .. RecOffset.DBL3]).strip().to!NWFloat,
						(cast(const char[])record[RecOffset.DBL3 .. RecOffset.DBL4]).strip().to!NWFloat,
					];
			}
		}
		else static if(is(T == NWLocation)){
			if(type == VarType.Location){
				import std.math: atan2, PI;
				auto facing = atan2(
					(cast(const char[])record[RecOffset.DBL5 .. RecOffset.DBL6]).strip().to!double,
					(cast(const char[])record[RecOffset.DBL4 .. RecOffset.DBL5]).strip().to!double);

				return NWLocation(
					(cast(const char[])record[RecOffset.Int .. RecOffset.DBL1]).strip().to!NWObject,
					cast(NWVector)[
						(cast(const char[])record[RecOffset.DBL1 .. RecOffset.DBL2]).strip().to!NWFloat,
						(cast(const char[])record[RecOffset.DBL2 .. RecOffset.DBL3]).strip().to!NWFloat,
						(cast(const char[])record[RecOffset.DBL3 .. RecOffset.DBL4]).strip().to!NWFloat,
					],
					facing * 180.0 / PI
					);
			}
		}
		else static if(is(T == BinaryObject)){
			if(type == VarType.BinaryObject){
				auto memoIndex = (cast(const char[])record[RecOffset.Memo .. RecOffset.End]).strip().to!ulong;
				return memo.getBlockContent(memoIndex);
			}
		}

		throw new BiowareDBException("Variable is not a "~T.stringof);
	}


	Nullable!T getVariableValue(T)(in string account, in string character, in string variable)
	if(is(T == NWInt) || is(T == NWFloat) || is(T == NWString) || is(T == NWVector) || is(T == NWLocation) || is(T == BinaryObject))
	{
		auto idx = getVariableIndex(account, character, variable);
		if(idx.hasValue)
			return Nullable!T(getVariableValue(idx.get));
		return Nullable!T();
	}

	Variable getVariable(size_t index) inout{
		auto record = table.getRecord(index);
		auto ts = cast(const char[])record[RecOffset.Timestamp .. RecOffset.VarType];

		return Variable(
			index,
			record[0] == Table.DeletedFlag.True,
			(cast(const char[])record[RecOffset.VarName .. RecOffset.PlayerID]).strip().to!string,
			(cast(const char[])record[RecOffset.PlayerID .. RecOffset.Timestamp]).strip().to!string,
			DateTime(
				ts[6..8].to!int + 2000,
				ts[0..2].to!int,
				ts[3..5].to!int,
				ts[8..10].to!int,
				ts[11..13].to!int,
				ts[14..16].to!int),
			record[RecOffset.VarType].to!VarType,
			);
	}

	Nullable!T getVariable(T)(in string account, in string character, in string variable){
		auto idx = getVariableIndex(account, character, variable);
		if(idx.hasValue)
			return Nullable!T(getVariable(idx.get));
		return Nullable!T();
	}


	alias opIndex = getVariable;

	@property size_t length() const{
		return table.header.records_count;
	}

	int opApply(scope int delegate(in Variable) dlg) const{
		int res;
		foreach(i ; 0..length){
			res = dlg(getVariable(i));
			if(res != 0) break;
		}
		return res;
	}



private:
	Table table;//dbf
	//Index index;//cdx
	Memo memo;//fpt

	struct Key{
		string pcId;
		string var;
	}
	size_t[Key] index = null;
	void buildIndex(){
		foreach(i ; 0..table.header.records_count){
			auto record = table.getRecord(i);

			if(record[0] == Table.DeletedFlag.False){
				//Not deleted
				index[Key(
					(cast(const char[])record[RecOffset.VarName .. RecOffset.PlayerID]).dup.strip(),
					(cast(const char[])record[RecOffset.PlayerID .. RecOffset.Timestamp]).dup.strip(),
					)] = i;
			}
			index.rehash();
		}
	}


	enum BDBColumn {
		VarName,
		PlayerID,
		Timestamp,
		VarType,
		Int,
		DBL1,
		DBL2,
		DBL3,
		DBL4,
		DBL5,
		DBL6,
		Memo,
	}
	enum RecOffset{
		VarName   = 1,
		PlayerID  = 1 + 32,
		Timestamp = 1 + 32 + 32,
		VarType   = 1 + 32 + 32 + 16,
		Int       = 1 + 32 + 32 + 16 + 1,
		DBL1      = 1 + 32 + 32 + 16 + 1 + 10,
		DBL2      = 1 + 32 + 32 + 16 + 1 + 10 + 20,
		DBL3      = 1 + 32 + 32 + 16 + 1 + 10 + 20 + 20,
		DBL4      = 1 + 32 + 32 + 16 + 1 + 10 + 20 + 20 + 20,
		DBL5      = 1 + 32 + 32 + 16 + 1 + 10 + 20 + 20 + 20 + 20,
		DBL6      = 1 + 32 + 32 + 16 + 1 + 10 + 20 + 20 + 20 + 20 + 20,
		Memo      = 1 + 32 + 32 + 16 + 1 + 10 + 20 + 20 + 20 + 20 + 20 + 20,
		End       = 1 + 32 + 32 + 16 + 1 + 10 + 20 + 20 + 20 + 20 + 20 + 20 + 10,
	}


	static struct Table{
		ubyte[] data;

		enum DeletedFlag: char{
			False = ' ',
			True = '*',
		}

		align(1) static struct Header{
			align(1):
			static assert(this.sizeof == 32);

			uint8_t file_type;
			uint8_t[3] last_update;// Year+2000, month, day
			uint32_t records_count;//Lines
			uint16_t records_offset;
			uint16_t record_size;

			uint8_t[16] reserved0;

			enum TableFlags: uint8_t{
				HasCDX = 0x01,
				HasMemo = 0x02,
				IsDBC = 0x04,
			}
			TableFlags table_flags;
			uint8_t code_page_mark;

			uint8_t[2] reserved1;
		}
		align(1) static struct FieldSubrecord{
			align(1):
			static assert(this.sizeof == 32);
			char[11] name;
			enum SubrecordType: char{
				Character = 'C',
				Currency = 'Y',
				Numeric = 'N',
				Float = 'F',
				Date = 'D',
				DateTime = 'T',
				Double = 'B',
				Integer = 'I',
				Logical = 'L',
				General = 'G',
				Memo = 'M',
				Picture = 'P',
			}
			SubrecordType field_type;
			uint32_t field_offset;
			uint8_t field_size;
			uint8_t decimal_places;
			enum SubrecordFlags: uint8_t{
				System = 0x01,
				CanStoreNull = 0x02,
				Binary = 0x04,
				AutoIncrement = 0x0C,
			}
			SubrecordFlags field_flags;
			uint32_t autoincrement_next;
			uint8_t autoincrement_step;
			uint8_t[8] reserved0;
		}

		@property{
			inout(Header)* header() inout{
				return cast(inout(Header)*)data.ptr;
			}
			inout(FieldSubrecord[]) fieldSubrecords() inout{

				auto subrecordStart = cast(FieldSubrecord*)(data.ptr + Header.sizeof);
				auto subrecord = subrecordStart;

				size_t subrecordCount = 0;
				while((cast(uint8_t*)subrecord)[0] != 0x0D){
					subrecordCount++;
					subrecord++;
				}
				return cast(inout)subrecordStart[0..subrecordCount];
			}
			inout(ubyte*) records() inout{
				return cast(inout)(data.ptr + header.records_offset);
			}
		}
		inout(ubyte[]) getRecord(size_t i) inout{
			assert(i < header.records_count, "Out of bound");

			inout(ubyte*) record = records + (i * header.record_size);
			return cast(inout)record[0 .. header.record_size];
		}
	}

	version(none)
	static struct Index{
		ubyte[] data;

		enum blockSize = 512;

		align(1) static struct Header{
			align(1):
			static assert(this.sizeof == blockSize);

			uint32_t root_node_index;
			uint32_t free_node_list_index;
			uint32_t node_count_bigendian;

			uint16_t key_length;
			enum IndexFlag: uint8_t{
				UniqueIndex = 1,
				HasForClause = 8,
			}
			IndexFlag index_flags;
			uint8_t signature;
			char[220] key_expression;
			char[220] for_expression;

			ubyte[56] unused0;
		}
		align(1) static struct Node{
			align(1):
			static assert(this.sizeof == blockSize);
			enum Attribute: uint16_t{
				Index = 0,
				Root = 1,
				Leaf = 2,
			}
			Attribute attributes;
			uint16_t key_count;
			uint32_t left_index_bigendian;
			uint32_t right_index_bigendian;
			char[500] key;
		}
		@property{
			Header* header(){
				return cast(Header*)data.ptr;
			}
			Node* nodes(){
				return cast(Node*)(data.ptr + blockSize);
			}
			Node* rootNode(){
				return &nodes[header.root_node_index];
			}
			Node* freeNodeList(){
				return &nodes[header.free_node_list_index];
			}

		}
		Node* getLeft(in Node* node){
			return node.left_index_bigendian != uint32_t.max?
				&nodes[node.left_index_bigendian.bigEndianToNative] : null;
		}
		Node* getRight(in Node* node){
			return node.right_index_bigendian != uint32_t.max?
				&nodes[node.right_index_bigendian.bigEndianToNative] : null;
		}
		Node* findNode(in char[500] key){
			return null;
		}

		void showNode(Index.Node* node, in string name = null){
			import std.string;
			writeln(
				name,":",
				" attr=", leftJustify(node.attributes.to!string, 20),
				//" attr=", cast(Index.Node.Attribute)(cast(uint16_t)node.attributes).bigEndianToNative,
				" nok=", leftJustify(node.key_count.to!string, 4),
				" left=", node.left_index_bigendian.bigEndianToNative, " right=", node.right_index_bigendian.bigEndianToNative,
				" key=", cast(ubyte[])node.key[0..10], " ... ", cast(ubyte[])node.key[$-10 .. $],
				);
		}
	}

	static struct Memo{
		ubyte[] data;

		align(1) static struct Header{
			align(1):
			static assert(this.sizeof == 512);

			uint32_t next_free_block_bigendian;
			uint16_t unused0;
			uint16_t block_size_bigendian;
			uint8_t[504] unused1;
		}
		align(1) static struct Block{
			align(1):
			static assert(this.sizeof == 8);

			uint32_t signature_bigendian;//bit field with 0: picture, 1: text
			uint32_t size_bigendian;
			ubyte[0] data;
		}
		@property{
			inout(Header)* header() inout{
				return cast(inout(Header)*)data.ptr;
			}
			size_t blockCount() const{
				return (data.length - Header.sizeof) / header.block_size_bigendian.bigEndianToNative;
			}
		}

		inout(Block)* getBlock(size_t i) inout{
			assert(i >= 1, "Memo indices starts at 1");
			assert(i < blockCount+1, "Out of bound");

			return cast(inout(Block)*)
				(data.ptr + Header.sizeof
				+ (i-1) * header.block_size_bigendian.bigEndianToNative);
		}
		inout(ubyte[]) getBlockContent(size_t i) inout{
			auto block = getBlock(i);
			return cast(inout)block.data.ptr[0 .. block.size_bigendian.bigEndianToNative];
		}
	}



}


unittest{
	import std.range.primitives;
	import std.math: fabs;

	auto db = new BiowareDB(
		cast(immutable ubyte[])import("testcampaign.dbf"),
		cast(immutable ubyte[])import("testcampaign.cdx"),
		cast(immutable ubyte[])import("testcampaign.fpt"),
		);


	//Read checks
	auto var = db[0];
	assert(var.deleted == false);
	assert(var.name == "ThisIsAFloat");
	assert(var.playerid == "");
	assert(var.timestamp == DateTime(2017,06,25, 23,19,26));
	assert(var.type == 'F');
	assert(db.getVariableValue!NWFloat(var.index) == 13.37f);

	var = db[1];
	assert(var.deleted == false);
	assert(var.name == "ThisIsAnInt");
	assert(var.playerid == "");
	assert(var.timestamp == DateTime(2017,06,25, 23,19,27));
	assert(var.type == 'I');
	assert(db.getVariableValue!NWInt(var.index) == 42);

	var = db[2];
	assert(var.deleted == false);
	assert(var.name == "ThisIsAVector");
	assert(var.playerid == "");
	assert(var.timestamp == DateTime(2017,06,25, 23,19,28));
	assert(var.type == 'V');
	assert(db.getVariableValue!NWVector(var.index) == [1.1f, 2.2f, 3.3f]);

	var = db[3];
	assert(var.deleted == false);
	assert(var.name == "ThisIsALocation");
	assert(var.playerid == "");
	assert(var.timestamp == DateTime(2017,06,25, 23,19,29));
	assert(var.type == 'L');
	auto loc = db.getVariableValue!NWLocation(var.index);
	assert(loc.area == 61031);
	assert(fabs(loc.position[0] - 103.060) <= 0.001);
	assert(fabs(loc.position[1] - 104.923) <= 0.001);
	assert(fabs(loc.position[2] - 40.080) <= 0.001);
	assert(fabs(loc.facing - 62.314) <= 0.001);

	var = db[4];
	assert(var.deleted == false);
	assert(var.name == "ThisIsAString");
	assert(var.playerid == "");
	assert(var.timestamp == DateTime(2017,06,25, 23,19,30));
	assert(var.type == 'S');
	assert(db.getVariableValue!NWString(var.index) == "Hello World");

	var = db[5];
	assert(var.deleted == false);
	assert(var.name == "StoredObjectName");
	assert(var.type == 'S');
	assert(var.playerid == "Crom 29Adaur Harbor");

	var = db[6];
	assert(var.deleted == false);
	assert(var.type == 'O');
	import nwn.gff;
	auto gff = new Gff(db.getVariableValue!BinaryObject(var.index));
	assert(gff["LocalizedName"].as!(GffType.ExoLocString).strref == 162153);

	var = db[7];
	assert(var.deleted == true);
	assert(var.name == "DeletedVarExample");

}




private T bigEndianToNative(T)(inout T i){
	import std.bitmanip: bigEndianToNative;
	return bigEndianToNative!T(cast(inout ubyte[T.sizeof])(&i)[0 .. 1]);
}