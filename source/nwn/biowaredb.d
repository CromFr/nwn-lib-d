/** Bioware campaign database (Foxpro db)
* Macros:
*   INDEX = Index of the variable in the table
*   VARNAME = Campaign variable name
*   TYPE = Type of the variable. Must match the stored variable type.
*   PCID = player character identifier<br/>
*          Should be his account name concatenated with his character name<br/>
*          $(D null) for module variables
*
*   ACCOUNT = Player account name<br/>
*            $(D null) for module variables
*   CHARACTER = Character name.<br/>
*            $(D null) for module variables
*
* Examples:
* --------------------
* // Open ./yourdatabasename.dbf, ./yourdatabasename.cdx, ./yourdatabasename.fpt
* auto db = new BiowareDB("./yourdatabasename");
*
* // Set a campaign variable associated to a character
* db.setVariableValue("YourAccount", "YourCharName", "TestFloat", 42.0f);
*
* // Set a campaign variable associated with the module
* db.setVariableValue(null, null, "TestVector", NWVector([1.0f, 2.0f, 3.0f]));
*
* // Retrieve variable information
* auto var = db.getVariable("YourAccount", "YourCharName", "TestFloat").get();
*
* // Retrieve variable value using its index (fast)
* float f = db.getVariableValue!NWFloat(var.index);
*
* // Retrieve variable value by searching it
* NWVector v = db.getVariableValue!NWVector(null, null, "TestVector").get();
*
* // Iterate over all variables (using variable info)
* foreach(varinfo ; db){
* 	if(varinfo.deleted == false)
* 		// Variable exists
* 	}
* 	else{
* 		// Variable has been deleted, skip it
* 		continue;
* 	}
* }
*
* // Save changes
* auto serialized = db.serialize();
* std.file.write("./yourdatabasename.dbf", serialized.dbf);
* std.file.write("./yourdatabasename.fpt", serialized.fpt);
*
* --------------------
*/
module nwn.biowaredb;

public import nwn.types;

import std.stdio: File, stderr;
import std.stdint;
import std.conv: to;
import std.datetime: Clock, DateTime;
import std.typecons: Tuple, Nullable;
import std.string;
import std.exception: enforce;
import std.json;
import nwnlibd.parseutils;

debug import std.stdio: writeln;
version(unittest) import std.exception: assertThrown, assertNotThrown;


/// Type of the GFF raw data stored when using StoreCampaignObject
alias BinaryObject = ubyte[];


///
class BiowareDBException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

/// ID used by Bioware Database to 'uniquely' identify a specific character. Can be used as a char[32].
struct PCID {
	/// Standard way to create a PCID.
	///
	/// Will create a char[32] containing at most 16 chars from the account and 16 chars from the char name, right-filled with spaces.
	this(in string accountName, in string charName){
		string pcidTmp;
		pcidTmp ~= accountName[0 .. accountName.length <= 16? $ : 16];
		pcidTmp ~= charName[0 .. charName.length <= 16? $ : 16];

		if(pcidTmp.length < 32){
			pcid[0 .. pcidTmp.length] = pcidTmp;
			pcid[pcidTmp.length .. $] = ' ';
		}
		else
			pcid = pcidTmp[0 .. 32];
	}

	/// Create with existing PCID
	this(in char[32] pcid){
		this.pcid = pcid;
	}


	/// Easily readable PCID, with spaces stripped
	string toString() const {
		import std.string: stripRight;
		return pcid.stripRight.idup();
	}

	alias pcid this;
	char[32] pcid = "                                ";
}


/// Bioware database (in FoxPro format, ie dbf, cdx and ftp files)
class BiowareDB{

	/// Constructor with raw data
	/// Note: data will be copied inside the class
	this(in ubyte[] dbfData, in ubyte[] cdxData, in ubyte[] fptData, bool buildIndex = true){
		table.data = dbfData.dup();
		//index.data = null;//Not used
		memo.data = fptData.dup();

		if(buildIndex)
			buildTableIndex();
	}

	/// Constructor with file paths
	this(in string dbfPath, in string cdxPath, in string fptPath, bool buildIndex = true){
		import std.stdio: File;

		auto dbf = File(dbfPath, "r");
		table.data.length = dbf.size.to!size_t;
		table.data = dbf.rawRead(table.data);

		auto fpt = File(fptPath, "r");
		memo.data.length = fpt.size.to!size_t;
		memo.data = fpt.rawRead(memo.data);

		if(buildIndex)
			buildTableIndex();
	}

	/// Constructor with file path without its extension. It will try to open the dbf and ftp files.
	this(in string dbFilesPath){
		this(
			dbFilesPath~".dbf",
			null,//Not used
			dbFilesPath~".fpt",
		);
	}

	/// Returns a tuple with dbf and fpt raw data (accessible with .dbf and .fpt)
	/// Warning: Does not serialize cdx file
	auto serialize(){
		//TODO: check if serialization does not break nwn2 since CDX isn't generated
		return Tuple!(const ubyte[], "dbf", const ubyte[], "fpt")(table.data, memo.data);
	}


	/// Type of a stored variable
	enum VarType : char{
		Int = 'I',
		Float = 'F',
		String = 'S',
		Vector = 'V',
		Location = 'L',
		Object = 'O',
	}
	/// Convert a BiowareDB.VarType into the associated native type
	template toVarType(T){
		static if(is(T == NWInt))             alias toVarType = VarType.Int;
		else static if(is(T == NWFloat))      alias toVarType = VarType.Float;
		else static if(is(T == NWString))     alias toVarType = VarType.String;
		else static if(is(T == NWVector))     alias toVarType = VarType.Vector;
		else static if(is(T == NWLocation))   alias toVarType = VarType.Location;
		else static if(is(T == BinaryObject)) alias toVarType = VarType.Object;
		else static assert(0);
	}
	/// Representation of a stored variable
	static struct Variable{
		size_t index;
		bool deleted;

		string name;
		PCID playerid;
		DateTime timestamp;

		VarType type;
	}

	/// Search and return the index of a variable
	///
	/// Expected O(1).
	/// Params:
	///   pcid = $(PCID)
	///   varName = $(VARNAME)
	/// Returns: `null` if not found
	Nullable!size_t getVariableIndex(in PCID pcid, in string varName) const{
		if(auto i = Key(pcid, varName) in index)
			return Nullable!size_t(*i);
		return Nullable!size_t();
	}

	/// Search and return the index of a variable
	///
	/// Expected O(1).
	/// Params:
	///   account = $(ACCOUNT)
	///   character = $(CHARACTER)
	///   varName = $(VARNAME)
	/// Returns: `null` if not found
	Nullable!size_t getVariableIndex(in string account, in string character, in string varName) const{
		return getVariableIndex(PCID(account, character), varName);
	}

	/// Get the variable value at `index`
	/// Note: Can be used to retrieve deleted variable values.
	/// Params:
	///   T = $(TYPE)
	///   index = $(INDEX)
	/// Returns: the variable value
	/// Throws: BiowareDBException if stored type != requested type
	const(T) getVariableValue(T)(size_t index) const
	if(is(T == NWInt) || is(T == NWFloat) || is(T == NWString) || is(T == NWVector) || is(T == NWLocation) || is(T == BinaryObject))
	{
		auto record = table.getRecord(index);
		char type = record[RecOffset.VarType];

		enforce!BiowareDBException(type == toVarType!T,
			"Variable is not a "~T.stringof);

		static if(is(T == NWInt)){
			return (cast(const char[])record[RecOffset.Int .. RecOffset.IntEnd]).strip().to!T;
		}
		else static if(is(T == NWFloat)){
			return (cast(const char[])record[RecOffset.DBL1 .. RecOffset.DBL1End]).strip().to!T;
		}
		else static if(is(T == NWString)){
			auto memoIndexStr = (cast(const char[])record[RecOffset.Memo .. RecOffset.MemoEnd]).strip();
			if(memoIndexStr.length == 0)
				return null;
			return (cast(const char[])memo.getBlockContent(memoIndexStr.to!size_t)).to!string;
		}
		else static if(is(T == NWVector)){
			return NWVector([
				(cast(const char[])record[RecOffset.DBL1 .. RecOffset.DBL1End]).strip().to!NWFloat,
				(cast(const char[])record[RecOffset.DBL2 .. RecOffset.DBL2End]).strip().to!NWFloat,
				(cast(const char[])record[RecOffset.DBL3 .. RecOffset.DBL3End]).strip().to!NWFloat,
			]);
		}
		else static if(is(T == NWLocation)){
			import std.math: atan2, PI;
			auto facing = atan2(
				(cast(const char[])record[RecOffset.DBL5 .. RecOffset.DBL5End]).strip().to!double,
				(cast(const char[])record[RecOffset.DBL4 .. RecOffset.DBL4End]).strip().to!double);

			return NWLocation(
				(cast(const char[])record[RecOffset.Int .. RecOffset.IntEnd]).strip().to!NWObject,
				NWVector([
					(cast(const char[])record[RecOffset.DBL1 .. RecOffset.DBL1End]).strip().to!NWFloat,
					(cast(const char[])record[RecOffset.DBL2 .. RecOffset.DBL2End]).strip().to!NWFloat,
					(cast(const char[])record[RecOffset.DBL3 .. RecOffset.DBL3End]).strip().to!NWFloat,
				]),
				facing * 180.0 / PI
			);
		}
		else static if(is(T == BinaryObject)){
			auto memoIndexStr = (cast(const char[])record[RecOffset.Memo .. RecOffset.MemoEnd]).strip();
			if(memoIndexStr.length == 0)
				return null;
			return memo.getBlockContent(memoIndexStr.to!size_t);
		}
		else static assert(0);
	}

	const(string) getVariableValueString(size_t index) const{
		const record = table.getRecord(index);
		const type = record[RecOffset.VarType].to!VarType;

		final switch(type) with(VarType){
			case Int:
				return getVariableValue!NWInt(index).to!string;
			case Float:
				return getVariableValue!NWFloat(index).to!string;
			case String:
				return getVariableValue!NWString(index).to!string;
			case Vector:
				return getVariableValue!NWVector(index).toString;
			case Location:
				return getVariableValue!NWLocation(index).toString;
			case Object:
				import std.base64: Base64;
				return Base64.encode(getVariableValue!BinaryObject(index));
		}
	}

	JSONValue getVariableValueJSON(size_t index) const{
		JSONValue ret = cast(JSONValue[string])null;

		const record = table.getRecord(index);
		const type = record[RecOffset.VarType].to!VarType;

		final switch(type) with(VarType){
			case Int:
				return JSONValue(getVariableValue!NWInt(index));
			case Float:
				return JSONValue(getVariableValue!NWFloat(index));
			case String:
				return JSONValue(getVariableValue!NWString(index));
			case Vector:
				const v = getVariableValue!NWVector(index);
				return JSONValue(v.value);
			case Location:
				const l = getVariableValue!NWLocation(index);
				return JSONValue([
					"area": JSONValue(l.area),
					"position": JSONValue(l.position.value),
					"facing": JSONValue(l.facing),
				]);
			case Object:
				import std.base64: Base64;
				return JSONValue(Base64.encode(getVariableValue!BinaryObject(index)));
		}
	}


	/// Search and return the value of a variable
	///
	/// Expected O(1).
	/// Params:
	///   T = $(TYPE)
	///   pcid = $(PCID)
	///   varName = $(VARNAME)
	/// Returns: the variable value, or null if not found
	Nullable!(const(T)) getVariableValue(T)(in PCID pcid, in string varName) const
	if(is(T == NWInt) || is(T == NWFloat) || is(T == NWString) || is(T == NWVector) || is(T == NWLocation) || is(T == BinaryObject))
	{
		auto idx = getVariableIndex(pcid, varName);
		if(idx.isNull == false)
			return Nullable!(const(T))(getVariableValue!T(idx.get));
		return Nullable!(const(T))();
	}

	/// Search and return the value of a variable
	///
	/// Expected O(1).
	/// Params:
	///   T = $(TYPE)
	///   account = $(ACCOUNT)
	///   character = $(CHARACTER)
	///   varName = $(VARNAME)
	/// Returns: the variable value, or null if not found
	Nullable!(const(T)) getVariableValue(T)(in string account, in string character, in string varName) const
	if(is(T == NWInt) || is(T == NWFloat) || is(T == NWString) || is(T == NWVector) || is(T == NWLocation) || is(T == BinaryObject))
	{
		return getVariableValue(PCID(account, character), varName);
	}

	/// Get variable information using its index
	///
	/// Note: Be sure to check `Variable.deleted` value
	/// Params:
	///   index = $(INDEX)
	/// Returns: the variable information
	Variable getVariable(size_t index) const{
		auto record = table.getRecord(index);
		auto ts = cast(const char[])record[RecOffset.Timestamp .. RecOffset.TimestampEnd];

		return Variable(
			index,
			record[0] == Table.DeletedFlag.True,
			(cast(const char[])record[RecOffset.VarName .. RecOffset.VarNameEnd]).strip().to!string,
			PCID(cast(char[32])record[RecOffset.PlayerID .. RecOffset.PlayerIDEnd]),
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

	/// Search and return variable information
	///
	/// Expected O(1).
	/// Params:
	///   pcid = $(PCID)
	///   varName = $(VARNAME)
	/// Returns: the variable information, or null if not found
	Nullable!Variable getVariable(in PCID pcid, in string varName) const{
		auto idx = getVariableIndex(pcid, varName);
		if(idx.isNull == false)
			return Nullable!Variable(getVariable(idx.get));
		return Nullable!Variable();
	}

	/// Search and return variable information
	///
	/// Expected O(1).
	/// Params:
	///   account = $(ACCOUNT)
	///   character = $(CHARACTER)
	///   varName = $(VARNAME)
	/// Returns: the variable information, or null if not found
	Nullable!Variable getVariable(in string account, in string character, in string varName) const{
		return getVariable(PCID(account, character), varName);
	}


	/// Set the value of an existing variable using its index.
	///
	/// Params:
	///   T = $(TYPE)
	///   index = $(INDEX)
	///   value = value to set
	///   updateTimestamp = true to change the variable modified date, false to keep current value
	void setVariableValue(T)(size_t index, in T value, bool updateTimestamp = true)
	if(is(T == NWInt) || is(T == NWFloat) || is(T == NWString) || is(T == NWVector) || is(T == NWLocation) || is(T == BinaryObject))
	{
		auto record = table.getRecord(index);
		char type = record[RecOffset.VarType];

		enforce!BiowareDBException(type == toVarType!T,
			"Variable is not a "~T.stringof);

		import std.string: leftJustify, format;

		with(RecOffset){
			static if(is(T == NWInt)){
				record[Int .. IntEnd] =
					cast(ubyte[])value.to!string.leftJustify(IntEnd - Int);
			}
			else static if(is(T == NWFloat)){
				record[DBL1 .. DBL1End] =
					cast(ubyte[])value.to!string.leftJustify(DBL1End - DBL1);
			}
			else static if(is(T == NWString) || is(T == BinaryObject)){
				auto oldMemoIndexStr = (cast(const char[])record[Memo .. MemoEnd]).strip();
				auto oldMemoIndex = oldMemoIndexStr != ""? oldMemoIndexStr.to!size_t : 0;

				auto memoIndex = memo.setBlockValue(cast(const ubyte[])value, oldMemoIndex);

				record[Memo .. MemoEnd] =
					cast(ubyte[])memoIndex.to!string.leftJustify(MemoEnd - Memo);
			}
			else static if(is(T == NWVector)){
				record[DBL1 .. DBL1End] =
					cast(ubyte[])value[0].to!string.leftJustify(DBL1End - DBL1);
				record[DBL2 .. DBL2End] =
					cast(ubyte[])value[1].to!string.leftJustify(DBL2End - DBL2);
				record[DBL3 .. DBL3End] =
					cast(ubyte[])value[2].to!string.leftJustify(DBL3End - DBL3);
			}
			else static if(is(T == NWLocation)){
				import std.math: cos, sin, PI;

				record[Int .. IntEnd] =
					cast(ubyte[])value.area.to!string.leftJustify(IntEnd - Int);

				record[DBL1 .. DBL1End] =
					cast(ubyte[])value.position[0].to!string.leftJustify(DBL1End - DBL1);
				record[DBL2 .. DBL2End] =
					cast(ubyte[])value.position[1].to!string.leftJustify(DBL2End - DBL2);
				record[DBL3 .. DBL3End] =
					cast(ubyte[])value.position[2].to!string.leftJustify(DBL3End - DBL3);

				immutable float facingx = cos(value.facing * PI / 180.0) * 180.0 / PI;
				immutable float facingy = sin(value.facing * PI / 180.0) * 180.0 / PI;

				record[DBL4 .. DBL4End] =
					cast(ubyte[])facingx.to!string.leftJustify(DBL4End - DBL4);
				record[DBL5 .. DBL5End] =
					cast(ubyte[])facingy.to!string.leftJustify(DBL5End - DBL5);
				record[DBL6 .. DBL6End] =
					cast(ubyte[])"0.0".leftJustify(DBL6End - DBL6);
			}
			else static assert(0);

			//Update timestamp
			if(updateTimestamp){
				auto now = cast(DateTime)Clock.currTime;
				immutable ts = format("%02d/%02d/%02d%02d:%02d:%02d",
					now.month,
					now.day,
					now.year-2000,
					now.hour,
					now.minute,
					now.second);
				record[Timestamp .. TimestampEnd] =
					cast(ubyte[])ts.leftJustify(TimestampEnd - Timestamp);
			}

		}
	}

	/// Set / create a variable with its value
	///
	/// Params:
	///   T = $(TYPE)
	///   pcid = $(PCID)
	///   varName = $(VARNAME)
	///   value = value to set
	///   updateTimestamp = true to change the variable modified date, false to keep current value
	void setVariableValue(T)(in PCID pcid, in string varName, in T value, bool updateTimestamp = true)
	if(is(T == NWInt) || is(T == NWFloat) || is(T == NWString) || is(T == NWVector) || is(T == NWLocation) || is(T == BinaryObject))
	{
		auto existingIndex = getVariableIndex(pcid, varName);
		if(existingIndex.isNull == false){
			//Reuse existing var
			setVariableValue(existingIndex.get, value, updateTimestamp);
		}
		else{
			//new var
			auto index = table.addRecord();
			auto record = table.getRecord(index);
			record[0..$][] = ' ';

			with(RecOffset){
				record[VarName .. VarName + varName.length] = cast(const ubyte[])varName;
				record[PlayerID .. PlayerID + 32] = cast(const ubyte[])pcid;
				record[VarType] = toVarType!T;

				setVariableValue(index, value, true);
			}

			this.index[Key(pcid, varName)] = index;
		}

	}


	/// Remove a variable
	///
	/// Note: Only marks the variable as deleted. Data can still be accessed using the variable index.
	/// Params:
	///   index = $(INDEX)
	void deleteVariable(size_t index){
		auto var = this[index];

		this.index.remove(Key(var.playerid, var.name));
		table.getRecord(index)[0] = '*';
	}

	/// Remove a variable
	///
	/// Note: Only marks the variable as deleted. Data can still be accessed using the variable index.
	/// Params:
	///   pcid = $(PCID)
	///   varName = $(VARNAME)
	void deleteVariable(in PCID pcid, in string varName){
		auto var = this[pcid, varName];

		enforce!BiowareDBException(var.isNull == false,
			"Variable not found");

		this.index.remove(Key(var.get.playerid, var.get.name));
		table.getRecord(var.get.index)[0] = '*';
	}


	/// Alias for `getVariable`
	alias opIndex = getVariable;

	/// Number of variables (both active an deleted) stored in the database
	@property size_t length() const{
		return table.header.records_count;
	}

	/// Iterate over all variables (both active and deleted)
	/// Note: You need to check `Variable.deleted` value.
	int opApply(scope int delegate(in Variable) dlg) const{
		int res = 0;
		foreach(i ; 0 .. length){
			res = dlg(getVariable(i));
			if(res != 0) break;
		}
		return res;
	}
	/// ditto
	int opApply(scope int delegate(size_t, in Variable) dlg) const{
		int res = 0;
		foreach(i ; 0 .. length){
			res = dlg(i, getVariable(i));
			if(res != 0) break;
		}
		return res;
	}


private:
	Table table;//dbf
	//Index index;//cdx
	Memo memo;//fpt

	struct Key{
		this(in PCID pcid, in string var){
			this.pcid = pcid;

			if(var.length <= 32){
				this.var[0 .. var.length] = var;
				this.var[var.length .. $] = ' ';
			}
			else
				this.var = var[0 .. 32];
		}
		char[32] pcid;
		char[32] var;
	}
	size_t[Key] index = null;
	void buildTableIndex(){
		foreach(i ; 0..table.header.records_count){
			auto record = table.getRecord(i);

			if(record[0] == Table.DeletedFlag.False){
				//Not deleted
				index[Key(
					PCID(cast(char[32])record[RecOffset.PlayerID .. RecOffset.PlayerIDEnd]),
					(cast(char[])record[RecOffset.VarName .. RecOffset.VarNameEnd]).to!string,
					)] = i;
			}
		}
		index.rehash();
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
		VarName      = 1,
		VarNameEnd   = PlayerID,
		PlayerID     = 1 + 32,
		PlayerIDEnd  = Timestamp,
		Timestamp    = 1 + 32 + 32,
		TimestampEnd = VarType,
		VarType      = 1 + 32 + 32 + 16,
		VarTypeEnd   = Int,
		Int          = 1 + 32 + 32 + 16 + 1,
		IntEnd       = DBL1,
		DBL1         = 1 + 32 + 32 + 16 + 1 + 10,
		DBL1End      = DBL2,
		DBL2         = 1 + 32 + 32 + 16 + 1 + 10 + 20,
		DBL2End      = DBL3,
		DBL3         = 1 + 32 + 32 + 16 + 1 + 10 + 20 + 20,
		DBL3End      = DBL4,
		DBL4         = 1 + 32 + 32 + 16 + 1 + 10 + 20 + 20 + 20,
		DBL4End      = DBL5,
		DBL5         = 1 + 32 + 32 + 16 + 1 + 10 + 20 + 20 + 20 + 20,
		DBL5End      = DBL6,
		DBL6         = 1 + 32 + 32 + 16 + 1 + 10 + 20 + 20 + 20 + 20 + 20,
		DBL6End      = Memo,
		Memo         = 1 + 32 + 32 + 16 + 1 + 10 + 20 + 20 + 20 + 20 + 20 + 20,
		MemoEnd      = 1 + 32 + 32 + 16 + 1 + 10 + 20 + 20 + 20 + 20 + 20 + 20 + 10,
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
			version(none)//Unused: we assume fields follow BDB format
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

			auto record = records + (i * header.record_size);
			return cast(inout)record[0 .. header.record_size];
		}
		size_t addRecord(){
			auto recordIndex = header.records_count;
			data.length += header.record_size;
			header.records_count++;
			return recordIndex;
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

		///Return new index if it has been reallocated
		size_t setBlockValue(in ubyte[] content, size_t previousIndex = 0){
			immutable blockSize = header.block_size_bigendian.bigEndianToNative;

			//size_t requiredBlocks = content.length / blockSize + 1;

			Block* block = null;
			size_t blockIndex = 0;

			if(previousIndex > 0){
				auto previousMemoBlock = getBlock(previousIndex);
				auto previousBlocksWidth = previousMemoBlock.size_bigendian.bigEndianToNative / blockSize + 1;

				if(content.length <= previousBlocksWidth * blockSize){
					//Available room in this block
					block = previousMemoBlock;
					blockIndex = previousIndex;
				}
			}

			if(block is null){
				//New block needs to be allocated
				auto requiredBlocks = content.length / blockSize + 1;

				//Resize data
				data.length += requiredBlocks * blockSize;

				//Update header
				immutable freeBlockIndex = header.next_free_block_bigendian.bigEndianToNative;
				header.next_free_block_bigendian = (freeBlockIndex + requiredBlocks).to!uint32_t.nativeToBigEndian;

				//Set pointer to new block
				block = getBlock(freeBlockIndex);
				blockIndex = freeBlockIndex;
			}

			block.signature_bigendian = 1.nativeToBigEndian;//BDB only store Text blocks
			block.size_bigendian = content.length.to!uint32_t.nativeToBigEndian;
			block.data.ptr[0 .. content.length] = content;

			return blockIndex;
		}
	}



}


unittest{
	import std.range.primitives;
	import std.math: fabs, approxEqual;

	auto db = new BiowareDB(
		cast(immutable ubyte[])import("testcampaign.dbf"),
		cast(immutable ubyte[])import("testcampaign.cdx"),
		cast(immutable ubyte[])import("testcampaign.fpt"),
		);


	//Read checks
	auto var = db[0];
	assert(var.deleted == false);
	assert(var.name == "ThisIsAFloat");
	assert(var.playerid == PCID());
	assert(var.timestamp == DateTime(2017,06,25, 23,19,26));
	assert(var.type == 'F');
	assert(db.getVariableValue!NWFloat(var.index).approxEqual(13.37f));

	var = db[1];
	assert(var.deleted == false);
	assert(var.name == "ThisIsAnInt");
	assert(var.playerid == PCID());
	assert(var.timestamp == DateTime(2017,06,25, 23,19,27));
	assert(var.type == 'I');
	assert(db.getVariableValue!NWInt(var.index) == 42);

	var = db[2];
	assert(var.deleted == false);
	assert(var.name == "ThisIsAVector");
	assert(var.playerid == PCID());
	assert(var.timestamp == DateTime(2017,06,25, 23,19,28));
	assert(var.type == 'V');
	assert(db.getVariableValue!NWVector(var.index) == [1.1f, 2.2f, 3.3f]);

	var = db[3];
	assert(var.deleted == false);
	assert(var.name == "ThisIsALocation");
	assert(var.playerid == PCID());
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
	assert(var.playerid == PCID());
	assert(var.timestamp == DateTime(2017,06,25, 23,19,30));
	assert(var.type == 'S');
	assert(db.getVariableValue!NWString(var.index) == "Hello World");

	var = db[5];
	assert(var.deleted == false);
	assert(var.name == "StoredObjectName");
	assert(var.type == 'S');
	assert(var.playerid == PCID("Crom 29", "Adaur Harbor"));

	var = db[6];
	assert(var.deleted == false);
	assert(var.name == "StoredObject");
	assert(var.type == 'O');
	import nwn.gff;
	auto gff = new Gff(db.getVariableValue!BinaryObject(var.index));
	assert(gff["LocalizedName"].as!(GffType.ExoLocString).strref == 162153);

	var = db[7];
	assert(var.deleted == true);
	assert(var.name == "DeletedVarExample");


	//Variable searching
	auto var2 = db.getVariable(null, null, "ThisIsAString").get;
	assert(var2.name == "ThisIsAString");
	assert(var2.index == 4);
	assert(db.getVariableIndex(null, null, "ThisIsAString") == 4);

	var2 = db.getVariable("Crom 29", "Adaur Harbor", "StoredObjectName").get;
	assert(var2.name == "StoredObjectName");
	assert(var2.index == 5);

	var2 = db["Crom 29", "Adaur Harbor", "StoredObjectName"].get;
	assert(var2.name == "StoredObjectName");
	assert(var2.index == 5);

	var2 = db[PCID("Crom 29", "Adaur Harbor"), "StoredObject"].get;
	assert(var2.name == "StoredObject");
	assert(var2.index == 6);

	assert(db["Crom 29", "Adaur Harb", "StoredObject"].isNull);
	assert(db.getVariableValue!BinaryObject(PCID(), "StoredObject").isNull);

	assertThrown!BiowareDBException(db.getVariableValue!BinaryObject(0));//var type mismatch


	//Iteration
	foreach(var ; db){}
	foreach(i, var ; db){}



	//Value set
	assertThrown!BiowareDBException(db.setVariableValue(0, 88));

	db.setVariableValue(0, 42.42f);
	var = db[0];
	assert(var.timestamp != DateTime(2017,06,25, 23,19,26));
	assert(var.type == 'F');
	assert(db.getVariableValue!NWFloat(var.index).approxEqual(42.42f));

	db.setVariableValue(1, 12);
	var = db[1];
	assert(var.timestamp != DateTime(2017,06,25, 23,19,27));
	assert(var.type == 'I');
	assert(db.getVariableValue!NWInt(var.index) == 12);

	db.setVariableValue(2, NWVector([10.0f, 20.0f, 30.0f]));
	var = db[2];
	assert(var.timestamp != DateTime(2017,06,25, 23,19,28));
	assert(var.type == 'V');
	assert(db.getVariableValue!NWVector(var.index) == [10.0f, 20.0f, 30.0f]);

	db.setVariableValue(3, NWLocation(100, NWVector([10.0f, 20.0f, 30.0f]), 60.0f));
	var = db[3];
	assert(var.timestamp != DateTime(2017,06,25, 23,19,29));
	assert(var.type == 'L');
	with(db.getVariableValue!NWLocation(var.index)){
		assert(area == 100);
		assert(position == NWVector([10.0f, 20.0f, 30.0f]));
		assert(fabs(facing - 60.0f) <= 0.001);
	}


	// Memo reallocations
	size_t getMemoIndex(size_t varIndex){
		auto record = db.table.getRecord(varIndex);
		return (cast(const char[])record[BiowareDB.RecOffset.Memo .. BiowareDB.RecOffset.MemoEnd]).strip().to!size_t;
	}

	size_t oldMemoIndex;

	oldMemoIndex = getMemoIndex(4);
	db.setVariableValue(4, "small");//Can fit in the same memo block
	assert(getMemoIndex(4) == oldMemoIndex);
	assert(db.getVariableValue!NWString(4) == "small");

	import std.array: replicate, array, join;
	string veryLongValue = replicate(["ten chars!"], 52).array.join;//520 chars
	db.setVariableValue(4, veryLongValue);
	assert(getMemoIndex(4)  == 35);//Should reallocate
	assert(db.memo.header.next_free_block_bigendian.bigEndianToNative == 37);


	oldMemoIndex = getMemoIndex(6);
	db.setVariableValue(6, cast(BinaryObject)[0, 1, 2, 3, 4, 5]);
	assert(getMemoIndex(6)  == oldMemoIndex);
	assert(db.getVariableValue!BinaryObject(6) == [0, 1, 2, 3, 4, 5]);

	db.setVariableValue(PCID(), "ThisIsAString", "yolo string");
	assert(db.getVariableValue!NWString(4) == "yolo string");

	// Variable creation
	db.setVariableValue(PCID("player", "id"), "varname", "Hello string :)");
	assert(db.getVariableValue!NWString(PCID("player", "id"), "varname") == "Hello string :)");


	//Variable deleting
	var = db.getVariable(PCID("player", "id"), "varname");
	assert(var.deleted == false);
	db.deleteVariable(PCID("player", "id"), "varname");
	assert(db.getVariable(PCID("player", "id"), "varname").isNull);
	var = db.getVariable(var.index);
	assert(var.deleted == true);

	assertThrown!BiowareDBException(db.deleteVariable(PCID("player", "id"), "varname"));
	assertNotThrown(db.deleteVariable(var.index));

}




private T bigEndianToNative(T)(inout T i){
	import std.bitmanip: bigEndianToNative;
	return bigEndianToNative!T(cast(inout ubyte[T.sizeof])(&i)[0 .. 1]);
}
private T nativeToBigEndian(T)(inout T i){
	import std.bitmanip: nativeToBigEndian;
	return *(cast(T*)nativeToBigEndian(i).ptr);
}
