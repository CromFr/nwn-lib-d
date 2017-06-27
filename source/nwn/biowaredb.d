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
import std.array;
import std.range.interfaces;
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

/// Type of the GFF raw data stored when using StoreCampaignObject
alias BinaryObject = ubyte[];

struct BDBVariable{
	string name;
	string playerid;
	DateTime timestamp;
	Value value;

	alias Value = VariantN!(NWLocation.sizeof, NWInt, NWFloat, NWString, NWVector, NWLocation, BinaryObject);
}

class BiowareDB{

	this(FoxproDB db){
		this.db = db;
	}




	BDBVariable getVariable(size_t index){
		return to!BDBVariable(db.data[index]);
	}
	BDBVariable.Value getVariableValue(size_t index) const{
		return to!(BDBVariable.Value)(db.data[index]);
	}
	BDBVariable.Value getVariableValue(in string playerAccount, in string charName, in string sVarName) const{
		immutable pcId = playerAccount~charName;
		foreach(index, ref entry ; db.data){
			if( entry[Column.VarName] == sVarName
			&& entry[Column.PlayerID] == pcId){
				return getVariableValue(index);
			}
		}
		return BDBVariable.Value();
	}




	bool empty() @property{
		return db.data.empty;
	}


	@property BDBVariable front(){
		return getVariable(0);
	}
	void popFront(){
		db.data.popFront();
	}
	@property BDBVariable back(){
		return getVariable(length-1);
	}
	void popBack(){
		if(db.data.length > 0)
			db.data.length = db.data.length - 1;
	}


	int opApply(scope int delegate(BDBVariable) dlg){
		int res;
		foreach(i ; 0..length){
			res = dlg(getVariable(i));
			if(res != 0) break;
		}
		return res;
	}
	int opApply(scope int delegate(ulong, BDBVariable) dlg){
		int res;
		foreach(i ; 0..length){
			res = dlg(i, getVariable(i));
			if(res != 0) break;
		}
		return res;
	}


	@property BiowareDB save() {
		//TODO: implement and make const
		return this;//return BiowareDB(data.dup);
	}
	BDBVariable opIndex(size_t index){
		return getVariable(index);
	}
	void opIndexAssign(BDBVariable val, size_t index){
		db.data[index] = to!(Variant[])(val);
	}

	@property size_t length() const{
		return db.length;
	}

	alias opDollar = length;

	BDBVariable[] opSlice(size_t start, size_t end){
		import std.array: array;
		import std.algorithm: map;

		BDBVariable[] res;
		foreach(i ; start..end){
			res ~= getVariable(i);
		}
		return res;
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
	enum VarType : char{
		Int = 'I',
		Float = 'F',
		String = 'S',
		Vector = 'V',
		Location = 'L',
		BinObject = 'O',
	}


	static auto to(T: BDBVariable)(in Variant[] entry){
		immutable ts = entry[Column.Timestamp].get!string;
		return BDBVariable(
			entry[Column.VarName].get!string,
			entry[Column.PlayerID].get!string,
			DateTime(
				ts[6..8].to!int + 2000,
				ts[0..2].to!int,
				ts[3..5].to!int,
				ts[8..10].to!int,
				ts[11..13].to!int,
				ts[14..16].to!int),
			to!(BDBVariable.Value)(entry)
			);
	}
	static auto to(T: BDBVariable.Value)(in Variant[] entry){
		final switch(entry[Column.VarType].get!string[0].to!VarType) with(VarType){
			case Int:    return BDBVariable.Value(entry[Column.Int].get!double.to!NWInt);
			case Float:  return BDBVariable.Value(entry[Column.DBL1].get!double.to!NWFloat);
			case String: return BDBVariable.Value((cast(char[])entry[Column.Memo].get!(ubyte[])).to!NWString);
			case Vector:
				return BDBVariable.Value(cast(NWVector)[
					entry[Column.DBL1].get!double.to!NWFloat,
					entry[Column.DBL2].get!double.to!NWFloat,
					entry[Column.DBL3].get!double.to!NWFloat]);
			case Location:
				import std.math: atan2, PI;
				auto angle = atan2(entry[Column.DBL5].get!double, entry[Column.DBL4].get!double);

				return BDBVariable.Value(NWLocation(
					entry[Column.Int].get!double.to!NWObject,
					cast(NWVector)[
						entry[Column.DBL1].get!double.to!NWFloat,
						entry[Column.DBL2].get!double.to!NWFloat,
						entry[Column.DBL3].get!double.to!NWFloat],
					angle*180.0/PI));
			case BinObject:
				return BDBVariable.Value(entry[Column.Memo].get!(ubyte[]).to!BinaryObject);
		}
	}

	static auto to(T: Variant[])(in BDBVariable var){
		Variant[] entry;
		entry.length = 12;

		import std.string: format;
		entry[Column.VarName] = Variant(var.name);
		entry[Column.PlayerID] = Variant(var.playerid);
		entry[Column.Timestamp] = Variant(format("%02d/%02d/%02d%02d:%02d:%02d",
			var.timestamp.month,
			var.timestamp.day,
			var.timestamp.year-2000,
			var.timestamp.hour,
			var.timestamp.minute,
			var.timestamp.second,
			));

		if(var.value.type == typeid(NWInt)){
			entry[Column.VarType] = "I";
			entry[Column.Int] = var.value.get!NWInt.to!double;
		}
		else if(var.value.type == typeid(NWFloat)){
				entry[Column.VarType] = "F";
				entry[Column.DBL1] = var.value.get!NWFloat.to!double;
		}
		else if(var.value.type == typeid(NWString)){
				entry[Column.VarType] = "S";
				entry[Column.Memo] = cast(ubyte[])var.value.get!NWString;
		}
		else if(var.value.type == typeid(NWVector)){
				entry[Column.VarType] = "V";
				auto value = var.value.get!NWVector;
				entry[Column.DBL1] = value[0].to!double;
				entry[Column.DBL2] = value[1].to!double;
				entry[Column.DBL3] = value[2].to!double;
		}
		else if(var.value.type == typeid(NWLocation)){
				entry[Column.VarType] = "L";
				auto value = var.value.get!NWLocation;
				entry[Column.Int] = value.area.to!double;
				entry[Column.DBL1] = value.position[0].to!double;
				entry[Column.DBL2] = value.position[1].to!double;
				entry[Column.DBL3] = value.position[2].to!double;

				import std.math: cos, sin, PI;
				auto facing = value.facing * PI / 180.0;
				entry[Column.DBL4] = cos(facing).to!NWFloat;
				entry[Column.DBL5] = sin(facing).to!NWFloat;
				entry[Column.DBL6] = 0f;
		}
		else if(var.value.type == typeid(BinaryObject)){
				entry[Column.VarType] = "O";
				entry[Column.Memo] = var.value.get!BinaryObject.to!(ubyte[]);
		}
		else
			assert(0);
		return entry;
	}


	FoxproDB db;
}
unittest{
	import std.range.primitives;

	static assert(isInputRange!BiowareDB);
	static assert(isInfinite!BiowareDB == false);
	static assert(isForwardRange!BiowareDB);
	static assert(isBidirectionalRange!BiowareDB);
	static assert(isRandomAccessRange!BiowareDB);


	import std.math: fabs;

	auto db = new BiowareDB(new FoxproDB(
		"unittest/testcampaign.dbf",
		"unittest/testcampaign.cdx",
		"unittest/testcampaign.fpt",
		));

	//Read checks
	auto var = db[0];
	assert(var.name == "ThisIsAFloat");
	assert(var.playerid == "");
	assert(var.timestamp == DateTime(2017,06,25, 23,19,26));
	assert(fabs(var.value.get!NWFloat - 13.37) <= 0.001);

	var = db[1];
	assert(var.name == "ThisIsAnInt");
	assert(var.playerid == "");
	assert(var.timestamp == DateTime(2017,06,25, 23,19,27));
	assert(var.value.get!NWInt == 42);

	var = db[2];
	assert(var.name == "ThisIsAVector");
	assert(var.playerid == "");
	assert(var.timestamp == DateTime(2017,06,25, 23,19,28));
	assert(var.value.get!NWVector == [1.1f, 2.2f, 3.3f]);

	var = db[3];
	assert(var.name == "ThisIsALocation");
	assert(var.playerid == "");
	assert(var.timestamp == DateTime(2017,06,25, 23,19,29));
	auto loc = var.value.get!NWLocation;
	assert(loc.area == 61031);
	assert(fabs(loc.position[0] - 103.060) <= 0.001);
	assert(fabs(loc.position[1] - 104.923) <= 0.001);
	assert(fabs(loc.position[2] - 40.080) <= 0.001);
	assert(fabs(loc.facing - 62.314) <= 0.001);

	var = db[4];
	assert(var.name == "ThisIsAString");
	assert(var.playerid == "");
	assert(var.timestamp == DateTime(2017,06,25, 23,19,30));
	assert(var.value.get!NWString == "Hello World");

	var = db[5];
	assert(var.playerid == "Crom 29Adaur Harbor");

	var = db[6];
	import nwn.gff;
	auto gff = new Gff(var.value.get!BinaryObject);
	assert(gff["LocalizedName"].as!(GffType.ExoLocString).strref == 162153);


	//Internal conversions
	foreach(entry ; db)
		assert(entry == BiowareDB.to!(BDBVariable)(BiowareDB.to!(Variant[])(entry)));
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
