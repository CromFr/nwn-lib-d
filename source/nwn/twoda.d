/// Two Dimentional Array (2da)
module nwn.twoda;

import std.string;
import std.conv: to, ConvException;
import std.typecons: Nullable;
import std.exception: enforce;
import std.algorithm;
import std.uni;
debug import std.stdio: writeln;
version(unittest) import std.exception: assertThrown, assertNotThrown;


///
class TwoDAParseException : Exception{
	@safe pure nothrow this(string msg, string fileName, size_t fileLine, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super((fileName !is null? fileName : "twoda")~"("~fileLine.to!string~")"~msg, f, l, t);
	}
}
///
class TwoDAValueException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
///
class TwoDAColumnNotFoundException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
///
class TwoDAOutOfBoundsException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

/// 2da file
class TwoDA{

	/// Read a 2da file
	this(string filepath){
		import std.file: readFile=read;
		import std.path: baseName;
		this(cast(ubyte[])filepath.readFile, filepath.baseName);
	}

	/// Parse raw data
	this(in ubyte[] rawData, in string name=null){
		fileName = name;

		enum State{
			header, defaults, columns, data
		}
		auto state = State.header;

		foreach(lineIndex, line ; (cast(string)rawData).splitLines){
			if(state != State.header && line.all!isWhite)
				continue;// Skip empty lines

			final switch(state){
				case State.header:
					//Header
					enforce!TwoDAParseException(line.length >= 8, "First line is too short");
					fileType = line[0..4].stripRight;
					fileVersion = line[4..8].stripRight;
					state = State.defaults;
					break;

				case State.defaults:
					if(line.length >= 8 && line[0 .. 8].toUpper == "DEFAULT:"){
						//TODO: handle default definition?
						// line is: "DEFAULT: somevalue"
						// somevalue is returned if the row does not exist
						break;
					}

					state = State.columns;
					goto case;//fallthrough

				case State.columns:
					//Column name definition
					foreach(index, title ; extractRowData(line)){
						header[title.toLower] = index;
					}
					header.rehash();
					columnsCount = header.length;
					state = State.data;
					break;

				case State.data:
					//Data
					auto data = extractRowData(line);
					if(data.length < columnsCount + 1){
						auto oldLength = data.length;
						data.length = columnsCount + 1;
						data[oldLength .. $] = null;
					}

					valueList ~= data[1 .. 1 + columnsCount];
					break;
			}
		}
	}

	private this(){}

	/// Recover a damaged 2DA file
	static auto recover(string filepath){
		import std.file: readFile=read;
		import std.path: baseName;
		return recover(cast(ubyte[])filepath.readFile, filepath.baseName);
	}
	/// ditto
	static auto recover(in ubyte[] rawData, in string name=null){

		static struct Ret {
			TwoDA twoDA;
			static struct Error {
				string type;
				size_t line;
				string msg;
			}
			Error[] errors;
		}
		auto ret = Ret(new TwoDA);
		with(ret.twoDA){
			fileName = name;

			string[] columns;

			enum State{
				header, defaults, columns, data
			}
			auto state = State.header;

			size_t currentIndex = 0;
			size_t prevLineIndex = size_t.max;
			foreach(iLine, line ; (cast(string)rawData).splitLines){
				if(state != State.header && line.all!isWhite)
					continue;// Skip empty lines

				final switch(state){
					case State.header:
						//Header
						if(line.length >= 8){
							fileType = line[0..4].stripRight;
							fileVersion = line[4..8].stripRight;
						}
						else{
							ret.errors ~= Ret.Error(
								"Error", iLine + 1,
								"Bad first line: Should be 8 characters with file type and file version (e.g. '2DA V2.0')"
							);
							fileType = "2DA ";
							fileVersion = "V2.0";
						}
						state = State.defaults;
						break;

					case State.defaults:
						if(line.length >= 8 && line[0 .. 8].toUpper == "DEFAULT:"){
							//TODO: handle default definition?
							// line is: "DEFAULT: somevalue"
							// somevalue must be returned if the row does not exist
							// However it doesn't appear to be used in NWN2
							break;
						}

						state = State.columns;
						goto case;//fallthrough

					case State.columns:
						//Column name definition
						columns = extractRowData(line);
						foreach(index, title ; columns){
							header[title.toLower] = index;
						}
						header.rehash();
						columnsCount = header.length;
						if(columnsCount == 0){
							ret.errors ~= Ret.Error(
								"Error", iLine + 1,
								"No columns"
							);
							return ret;
						}
						state = State.data;
						break;

					case State.data:
						//Data
						auto data = extractRowData(line);

						if(data.length == 0){
							ret.errors ~= Ret.Error(
								"Notice", iLine + 1,
								"Empty line"
							);
							continue;
						}

						size_t writtenIndex;
						try writtenIndex = data[0].to!size_t;
						catch(ConvException e){
							ret.errors ~= Ret.Error(
								"Error", iLine + 1,
								format!"Invalid line index: '%s' is not a positive integer"(data[0])
							);
						}

						if(writtenIndex != currentIndex){
							ret.errors ~= Ret.Error(
								"Warning", iLine + 1,
								prevLineIndex != size_t.max ?
									format!"Line index mismatch: Written line index is %d, while previous index was %d. If kept as is, the line effective index will be %d."(writtenIndex, currentIndex - 1, rows)
									: format!"Line index mismatch: First written line index is %d instead of 0. If kept as is, the line effective index will be %d."(writtenIndex, rows)
							);
							currentIndex = writtenIndex;
						}
						prevLineIndex = currentIndex;
						currentIndex++;

						if(data.length != columnsCount + 1){
							ret.errors ~= Ret.Error(
								"Error", iLine + 1,
								format!"Bad number of columns: Line has %d columns instead of %d"(data.length, columnsCount + 1)
							);
						}

						foreach(i, field ; data){
							if(field.length > 0 && field != "****" && field.all!"a == '*'"){
								ret.errors ~= Ret.Error(
									"Notice", iLine + 1,
									i < columns.length ?
										format!"Bad null field: Column '%s' has %d stars instead of 4"(columns[i], field.length)
										: format!"Bad null field: Column number %d has %d stars instead of 4"(i, field.length)
								);
							}
						}

						if(data.length < columnsCount + 1){
							auto oldLength = data.length;
							data.length = columnsCount + 1;
							data[oldLength .. $] = null;
						}

						valueList ~= data[1 .. 1 + columnsCount];
						break;
				}
			}

		}
		return ret;
	}

	/// Get a value in the 2da, converted to T.
	/// Returns: if T is string returns the string value, else returns a `Nullable!T` that is null if the value is empty
	/// Throws: `std.conv.ConvException` if the conversion into T fails
	auto ref get(T = string)(in size_t colIndex, in size_t line) const {
		assert(line < rows, "Line is out of bounds");
		assert(colIndex < columnsCount, "Column is out of bounds");

		static if(is(T == string)){
			return this[colIndex, line];
		}
		else {
			if(this[colIndex, line] is null){
				return Nullable!T();
			}
			try return Nullable!T(this[colIndex, line].to!T);
			catch(ConvException e){
				//Annotate conv exception
				string colName;
				foreach(ref name, index ; header){
					if(index == colIndex){
						colName = name;
						break;
					}
				}
				e.msg ~= " ("~fileName~": column: "~colIndex.to!string~", line: "~line.to!string~")";
				throw e;
			}
		}
	}

	/// Get a value in the 2da, converted to T.
	/// Returns: value if found, otherwise defaultValue
	T get(T = string)(in string colName, in size_t line, T defaultValue) const {
		if(line >= rows)
			return defaultValue;

		if(auto colIndex = colName.toLower in header){
			if(this[*colIndex, line] !is null){
				try return this[*colIndex, line].to!T;
				catch(ConvException){}
			}
		}
		return defaultValue;
	}

	/// ditto
	/// Throws: `TwoDAColumnNotFoundException` if the column does not exist
	auto ref get(T = string)(in string colName, in size_t line) const {
		return get!T(columnIndex(colName), line);
	}


	/// Get the index of a column by its name, for faster access
	size_t columnIndex(in string colName) const {
		if(auto colIndex = colName.toLower in header){
			return *colIndex;
		}
		throw new TwoDAColumnNotFoundException("Column '"~colName~"' not found");
	}

	/// Check if a column exists in the 2da, and returns a pointer to its index
	const(size_t*) opBinaryRight(string op: "in")(in string colName) const {
		return colName.toLower in header;
	}

	/// Get a specific cell value
	/// Note: column 0 is the first named column (not the index column)
	ref inout(string) opIndex(size_t column, size_t row) inout nothrow {
		assert(column < columns, "column out of bounds");
		assert(row < rows, "row out of bounds");
		return valueList[row * columnsCount + column];
	}
	/// ditto
	ref inout(string) opIndex(string column, size_t row) inout {
		assert(column.toLower in header, "Column not found in header");
		return this[header[column.toLower], row];
	}

	// Get row
	const(string[]) opIndex(size_t i) const {
		return valueList[i * columnsCount .. (i + 1) * columnsCount];
	}
	// Set row
	void opIndexAssign(in string[] value, size_t i){
		valueList[i * columnsCount .. (i + 1) * columnsCount] = value;
	}


	@property{
		/// File type (should always be "2DA")
		/// Max width: 4 chars
		string fileType()const{return m_fileType;}
		/// ditto
		void fileType(string value){
			if(value.length>4)
				throw new TwoDAValueException("fileType cannot be longer than 4 characters");
			m_fileType = value;
		}
	}
	private string m_fileType;
	@property{
		/// File version (should always be "V2.0")
		/// Max width: 4 chars
		string fileVersion()const{return m_fileVersion;}
		/// ditto
		void fileVersion(string value){
			if(value.length>4)
				throw new TwoDAValueException("fileVersion cannot be longer than 4 characters");
			m_fileVersion = value;
		}
	}
	private string m_fileVersion;



	@property{
		/// Number of rows in the 2da
		size_t rows() const nothrow {
			if(columnsCount == 0)
				return 0;
			return valueList.length / columnsCount;
		}
		/// Resize the 2da table
		void rows(size_t rowsCount) nothrow {
			valueList.length = columnsCount * rowsCount;
		}

		/// Number of named columns in the 2da (i.e. without the index column)
		size_t columns() const nothrow {
			return columnsCount;
		}
	}

	/// Outputs 2da text content
	ubyte[] serialize() const {
		import std.algorithm: map, sort;
		import std.array: array;
		import std.string: leftJustify;
		char[] ret;

		//Header
		ret ~="        \n";
		ret[0..fileType.length] = fileType;
		ret[4..4+fileVersion.length] = fileVersion;

		//Default
		ret ~= "\n";

		//column width calculation
		import std.math: log10, floor;
		size_t[] columnsWidth =
			(cast(int)log10(rows)+2)
			~(header
				.byKeyValue
				.array
				.sort!((a, b) => a.value < b.value)
				.map!(a => (a.key.length < 4 ? 4 : a.key.length) + 1)
				.array);

		foreach(row ; 0 .. rows){
			foreach(col ; 0 .. columnsCount){
				auto value = this[col, row];
				if(value.length + 1 > columnsWidth[col + 1])
					columnsWidth[col + 1] = value.length + 1;
			}
		}

		//Column names
		ret ~= "".leftJustify(columnsWidth[0]);
		foreach(ref kv ; header.byKeyValue.array.sort!((a,b)=>a.value<b.value)){
			ret ~= kv.key.leftJustify(columnsWidth[kv.value+1]);
		}
		ret ~= "\n";

		//Data
		foreach(row ; 0 .. rows){
			ret ~= row.to!string.leftJustify(columnsWidth[0]);
			foreach(col ; 0 .. columnsCount){
				auto value = this[col, row];
				string serializedValue;
				if(value is null || value.length == 0)
					serializedValue = "****";
				else{
					if(value.indexOf('"') >= 0)
						throw new TwoDAValueException("A 2da field cannot contain double quotes");

					if(value.indexOf(' ') >= 0)
						serializedValue = '"'~value~'"';
					else
						serializedValue = value;
				}

				if(col == columnsCount - 1)
					ret ~= serializedValue;
				else
					ret ~= serializedValue.leftJustify(columnsWidth[col + 1]);


			}
			ret ~= "\n";
		}

		return cast(ubyte[])ret;
	}

	/// Parse a 2DA row
	static string[] extractRowData(in string line){
		string[] ret;

		enum State{
			Whitespace,
			Field,
			QuotedField,
		}
		string fieldBuf;
		auto state = State.Whitespace;
		foreach(c ; line~" "){
			final switch(state){
				case State.Whitespace:
					if(c.isWhite)
						continue;
					else{
						fieldBuf = "";
						if(c=='"')
							state = State.QuotedField;
						else{
							fieldBuf ~= c;
							state = State.Field;
						}
					}
					break;

				case State.Field:
					if(c.isWhite){
						if(fieldBuf.length > 0 && fieldBuf.all!"a == '*'")
							ret ~= null;
						else
							ret ~= fieldBuf;
						state = State.Whitespace;
					}
					else
						fieldBuf ~= c;
					break;

				case State.QuotedField:
					if(c=='"'){
						ret ~= fieldBuf;
						state = State.Whitespace;
					}
					else
						fieldBuf ~= c;
					break;
			}
		}
		return ret;
	}

	/// Optional 2DA file name set during construction
	string fileName = null;
private:
	size_t[string] header;
	size_t columnsCount;
	string[] valueList;
}
unittest{
	immutable polymorphTwoDA = cast(immutable ubyte[])import("polymorph.2da");
	auto twoda = new TwoDA(polymorphTwoDA);

	assert(twoda.fileType == "2DA");
	assertThrown!TwoDAValueException(twoda.fileType = "12345");
	assert(twoda.fileVersion == "V2.0");
	assertThrown!TwoDAValueException(twoda.fileVersion = "12345");

	assert(twoda["Name", 0] == "POLYMORPH_TYPE_WEREWOLF");
	assert(twoda.get("Name", 0) == "POLYMORPH_TYPE_WEREWOLF");
	assert(twoda.get("name", 0) == "POLYMORPH_TYPE_WEREWOLF");

	assert(twoda.get!int("RacialType", 0) == 23);
	assert(twoda.get("EQUIPPED", 0) == null);
	assert(twoda.get!int("MergeA", 13) == 1);
	assert(twoda.get("Name", 20) == "MULTI WORD VALUE");

	assert(twoda.get("Name", 1) == "POLYMORPH_TYPE_WERERAT");
	assert(twoda.get("Name", 8) == "POLYMORPH_TYPE_FIRE_GIANT");//deleted line
	assert(twoda.get("Name", 10) == "POLYMORPH_TYPE_ELDER_FIRE_ELEMENTAL");//misordered line
	assert(twoda.get("Name", 25) == null);//empty value
	assert(twoda.get("Name", 206) == "POLYMORPH_TYPE_LESS_EMBER_GUARD");//last line

	assertThrown!TwoDAColumnNotFoundException(twoda.get("Yolooo", 1));
	assertThrown!Error(twoda.get("Name", 207));

	twoda = new TwoDA(polymorphTwoDA);
	auto twodaSerialized = twoda.serialize();
	auto twodaReparsed = new TwoDA(twodaSerialized);

	assert(twoda.header == twodaReparsed.header);
	assert(twoda.valueList == twodaReparsed.valueList);


	twoda = new TwoDA(cast(immutable ubyte[])import("terrainmaterials.2da"));
	assert(twoda["Material", 52] == "Stone");
	assert(twoda.get("STR_REF", 56, 42) == 42);

	twoda = new TwoDA(cast(immutable ubyte[])import("exptable.2da"));
	assert(twoda.get!ulong("XP", 0).get == 0);
	assert(twoda.get!ulong("XP", 1).get == 1000);
	assert(twoda.get!ulong("XP", 10).get == 55000);
	assert(twoda.get!ulong("XP", 100, 42) == 42);
}
