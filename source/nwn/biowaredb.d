/// Foxpro database format (bioware database)
module nwn.biowaredb;

public import nwn.types;

import std.stdio: File, stderr;
import std.stdint;
import std.conv: to;
import std.datetime;
import std.typecons: Tuple;
import std.variant;
import std.string;
import std.exception: enforce;
import nwnlibd.parseutils;

debug import std.stdio: writeln;
version(unittest) import std.exception: assertThrown, assertNotThrown;

/// Parsing exception
class FoxproParseException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
class FoxproValueSetException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}


class BiowareDB{

	this(FoxproDB db){
		this.db = db;
	}

	alias VarValue = VariantN!(NWLocation.sizeof, NWInt, NWFloat, NWString, NWVector, NWLocation);

	VarValue getVariableValue(in string playerAccount, in string charName, in string sVarName) const{
		immutable pcId = playerAccount~charName;
		foreach(index, ref entry ; db.data){
			if( entry[Column.VarName] == sVarName
			&& entry[Column.PlayerID] == pcId){
				return getVariableValue(index);
			}
		}
		return VarValue();
	}

	VarValue getVariableValue(size_t index) const{
		auto entry = db.data[index];

		final switch(entry[Column.VarType].get!string[0].to!VarType) with(VarType){
			case Int:    return VarValue(entry[Column.Int].get!double.to!NWInt);
			case Float:  return VarValue(entry[Column.DBL1].get!double.to!NWFloat);
			case String: return VarValue(entry[Column.Memo].get!(ubyte[]).to!NWString);
			case Vector:
				return VarValue(cast(NWVector)[
					entry[Column.DBL1].get!double.to!NWFloat,
					entry[Column.DBL2].get!double.to!NWFloat,
					entry[Column.DBL3].get!double.to!NWFloat]);
			case Location:
				import std.math: atan2, PI;
				auto angle = atan2(entry[Column.DBL5].get!double, entry[Column.DBL4].get!double);
				return VarValue(NWLocation(
					entry[Column.Int].get!double.to!NWObject,
					cast(NWVector)[
						entry[Column.DBL1].get!double.to!NWFloat,
						entry[Column.DBL2].get!double.to!NWFloat,
						entry[Column.DBL3].get!double.to!NWFloat],
					angle*180.0/PI));
		}
	}

	enum VarType : char{
		Int = 'I',
		Float = 'F',
		String = 'S',
		Vector = 'V',
		Location = 'L',
	}
	struct Variable{
		string name;
		string playerid;
		DateTime timestamp;
		VarType type;
		VarValue value;
	}

	Variable getVariable(size_t index){
		auto entry = db.data[index];

		auto timestampstr = entry[Column.Timestamp].get!string;

		auto timestamp = DateTime(
			timestampstr[6..8].to!int + 2000,
			timestampstr[0..2].to!int,
			timestampstr[3..5].to!int,
			timestampstr[8..10].to!int,
			timestampstr[11..13].to!int,
			timestampstr[14..16].to!int);
		return Variable(
			entry[Column.VarName].get!string,
			entry[Column.PlayerID].get!string,
			timestamp,
			entry[Column.VarType].get!string[0].to!VarType,
			getVariableValue(index)
			);
	}


private:
	enum Column {
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



	FoxproDB db;
}
unittest{
	import std.math: fabs;

	auto db = new BiowareDB(new FoxproDB(
		"unittest/testcampaign.dbf",
		"unittest/testcampaign.cdx",
		"unittest/testcampaign.fpt",
		));

	auto var = db.getVariable(0);
	assert(var.name == "ThisIsAFloat");
	assert(var.playerid == "");
	assert(var.timestamp == DateTime(2017,06,24, 19,02,20));
	assert(var.type == BiowareDB.VarType.Float);
	assert(fabs(var.value.get!NWFloat - 13.37) <= 0.001);

	var = db.getVariable(3);
	assert(var.name == "ThisIsALocation");
	assert(var.playerid == "");
	assert(var.timestamp == DateTime(2017,06,24, 19,02,20));
	assert(var.type == BiowareDB.VarType.Location);
	auto loc = var.value.get!NWLocation;
	assert(loc.area == 61031);
	assert(fabs(loc.position[0] - 100.256) <= 0.001);
	assert(fabs(loc.position[1] - 100.259) <= 0.001);
	assert(fabs(loc.position[2] - 0) <= 0.001);
	assert(fabs(loc.facing - 90) <= 0.001);
}






class FoxproDB{

	this(in string dbfPath, in string cdxPath, in string fptPath){
		import std.file: read;
		this(cast(ubyte[])dbfPath.read(), cast(ubyte[])cdxPath.read(), cast(ubyte[])fptPath.read());
	}

	this(in ubyte[] dbfRawData, in ubyte[] cdxRawData, in ubyte[] fptRawData){
		import nwnlibd.parseutils;

		auto memo = MemoFinder(fptRawData);

		loadMainData(dbfRawData, memo);
	}

	enum FoxProFileType : uint8_t{
		FoxBASE = 0x02,
		FoxBASE_DbaseIIIplus_nomemo = 0x03,
		VisualFoxPro = 0x30,
		VisualFoxPro_autoincrement = 0x31,
		dBASEIV_SQLTableFiles_nomemo = 0x43,
		dBASEIV_SQLSystemFiles_nomemo = 0x63,
		FoxBASEPlus_dBASEIIIplus_withmemo = 0x83,
		dBASEIV_withmemo = 0x8B,
		dBASEIV_SQLTableFiles_withmemo = 0xCB,
		FoxPro2x_withmemo = 0xF5,
		FoxBASEBis = 0xFB,
	}
	FoxProFileType fileType;


	@property{
		/// Date when the file has been modified
		Date modifiedDate()const{return m_modifiedDate;}
		/// ditto
		void modifiedDate(Date value){
			if(value.year<2000 || value.year > 2000+uint8_t.max)
				throw new FoxproValueSetException("modifiedDate year must be between 2000 and 2255");
			m_modifiedDate = value;
		}
	}
	private Date m_modifiedDate = Date(2000, 1, 1);

	@property{
		size_t length() const{return data.length;}
	}
	@property{
		size_t columnCount() const {return m_columnInfo.length;}
	}

	static struct ColumnInfo{
		string name;
		enum Type: char{
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
		Type type;

		enum Flags{
			System = 0x01,
			CanStoreNull = 0x02,
			Binary = 0x04,
			AutoIncrement = 0x0C,
		}
		uint8_t flags;

		uint8_t size;
	}
	@property{
		auto columnInfo() const {return m_columnInfo;}
	}


	Variant[][] data;


private:
	ColumnInfo[] m_columnInfo;



	align(1) static struct TableFileStructHeader{
		align(1):
		static assert(this.sizeof == 32);

		FoxProFileType file_type;
		uint8_t[3] last_update;// Year+2000, month, day
		uint32_t records_count;//Lines
		uint16_t records_offset;
		uint16_t records_size;

		uint8_t[16] reserved0;

		enum TableFlags{
			HasCDX = 0x01,
			HasMemo = 0x02,
			IsDBC = 0x04,
		}
		uint8_t table_flags;
		uint8_t code_page_mark;

		uint8_t[2] reserved1;
	}
	align(1) static struct FieldSubrecord{
		align(1):
		static assert(this.sizeof == 32);
		char[11] name;
		ColumnInfo.Type field_type;
		uint32_t field_offset;
		uint8_t field_size;
		uint8_t decimal_places;
		uint8_t field_flags;//ColumnInfo.Flags
		uint32_t autoincrement_next;
		uint8_t autoincrement_step;
		uint8_t[8] reserved0;
	}
	void loadMainData(in ubyte[] rawData, in MemoFinder memo){

		enforce!FoxproParseException(rawData.length >= 32+264,
			"TableFile data length is too small");

		auto header = cast(immutable TableFileStructHeader*)rawData.ptr;

		fileType = header.file_type;
		m_modifiedDate = Date(
			header.last_update[0] + 2000,
			header.last_update[1],
			header.last_update[2]);

		auto columns_start = cast(FieldSubrecord*)(rawData.ptr + TableFileStructHeader.sizeof);
		auto columnsPtr = columns_start;
		while((cast(uint8_t*)columnsPtr)[0] != 0x0D){
			m_columnInfo ~= ColumnInfo(
				charArrayToString(columnsPtr.name),
				columnsPtr.field_type,
				columnsPtr.field_flags,
				columnsPtr.field_size,
				);

			columnsPtr++;
		}

		assert((cast(uint8_t*)columnsPtr)[0] == 0x0D);

		if(header.table_flags & TableFileStructHeader.TableFlags.IsDBC){
			assert(0, "DBC Not handled");
			// char[263] cdxPath = (cast(char*)subrec)[1..264];
		}


		const(uint8_t)* firstRecord = &rawData[header.records_offset+1];
		immutable record_size = header.records_size;
		foreach(recordIdx ; 0..header.records_count){

			Variant[] record;


			const(uint8_t)* recordPtr = firstRecord + recordIdx * record_size;

			//writeln("New record offset=", recordPtr - rawData.ptr, "    size=",record_size);

			uint8_t fieldOffset = 0;
			foreach(colIdx, ref col ; columnInfo){


				const(uint8_t)[] value = recordPtr[fieldOffset .. fieldOffset + col.size];
				string valueStr = charArrayToString(cast(char[])value, col.size).strip;

				//writeln("New field ",col.type,": record=",recordIdx," col=", colIdx," offset=",recordPtr+fieldOffset - rawData.ptr," ======> ", value);

				switch(col.type) with(ColumnInfo.Type){
					case Character:
						record ~= Variant(valueStr);
						break;
					case Numeric:
					case Float:
					case Double:
					case Integer:
						if(valueStr == "")
							record ~= Variant();
						else
							record ~= Variant(valueStr.to!double);
						break;
					case Memo:
						if(valueStr == "")
							record ~= Variant();
						else{
							auto entry = valueStr.to!size_t;
							record ~= Variant(memo.get(entry));
						}
						break;
					case Currency:
					case Date:
					case DateTime:
					case Logical:
					case General:
					case Picture:
						throw new FoxproParseException("Type "~col.type.to!string~" not handled");
					default: assert(0);
				}

				fieldOffset += col.size;
			}

			//writeln("++++>",record);
			data ~= record;

		}

	}






	align(1) static struct MemoHeader{
		align(1):
		static assert(this.sizeof == 512);

		uint32_t next_free_block;
		uint16_t unused0;
		uint16_t block_size;
		uint8_t[504] unused1;
	}

	align(1) static struct MemoBlockHeader{
		align(1):
		static assert(this.sizeof == 8);

		uint32_t signature;//bit field with 0: picture, 1: text
		uint32_t size;
	}

	static struct MemoFinder{
		import std.bitmanip;
		this(in ubyte[] rawData){
			enforce!FoxproParseException(rawData.length >= MemoHeader.sizeof,
				"TableFile data length is too small");

			auto header = cast(immutable MemoHeader*)rawData.ptr;

			memoData = rawData;
			blockSize = bigEndianToNative!uint16_t(cast(ubyte[2])((&header.block_size)[0..1]));
		}

		ubyte[] get(size_t id) const{
			immutable offset = 512 + (id-1) * blockSize;
			enforce(offset + blockSize <= memoData.length);

			auto header = cast(MemoBlockHeader*)(&memoData[offset]);
			immutable contentSize = bigEndianToNative!uint32_t(cast(ubyte[4])(&header.size)[0..1]);
			return memoData[offset + MemoBlockHeader.sizeof .. offset + MemoBlockHeader.sizeof + contentSize].dup;
		}

		const ubyte[] memoData;
		uint16_t blockSize;
	}
}



unittest{

	{
		auto db = new BiowareDB(new FoxproDB(
			"/home/crom/Documents/Neverwinter Nights 2/database/pctools--crom29_aoroducormyr.dbf",
			"/home/crom/Documents/Neverwinter Nights 2/database/pctools--crom29_aoroducormyr.cdx",
			"/home/crom/Documents/Neverwinter Nights 2/database/pctools--crom29_aoroducormyr.fpt",
			));
	}

	//auto db = new BiowareDB(
	//	"/home/crom/Documents/Neverwinter Nights 2/database/a.dbf",
	//	"/home/crom/Documents/Neverwinter Nights 2/database/a.cdx",
	//	"/home/crom/Documents/Neverwinter Nights 2/database/a.fpt",
	//	);

	//{
	//	auto db = new BiowareDB(
	//		"/home/crom/Documents/Neverwinter Nights 2/database/xp_craftkaf3j6u4.dbf",
	//		"/home/crom/Documents/Neverwinter Nights 2/database/xp_craftkaf3j6u4.cdx",
	//		"/home/crom/Documents/Neverwinter Nights 2/database/xp_craftkaf3j6u4.fpt",
	//		);
	//}



}
