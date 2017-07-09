/// Two Dimentional Array (2da)
module nwn.twoda;

import std.string;
import std.conv : to;
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

		foreach(lineIndex, line ; (cast(string)rawData).splitLines){
			switch(lineIndex){
				case 0:
					//Header
					fileType = line[0..4].stripRight;
					fileVersion = line[4..8].stripRight;
					break;

				case 1:
					//TODO: handle default definition?
					// line is: "DEFAULT: somevalue"
					// somevalue is returned if the row does not exist
					break;

				case 2:
					//Column name definition
					foreach(index, title ; extractRowData(line)){
						header[title] = index;
					}
					header.rehash();
					columnsCount = header.length;
					break;

				default:
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

	///
	auto ref get(T = string)(in string colName, in size_t line)const{
		assert(line < rows, "Line is out of bounds");

		if(auto colIndex = colName in header){
			return this[line, *colIndex].to!T;
		}
		else
			throw new TwoDAColumnNotFoundException("Column '"~colName~"' not found");
	}

	/// Note: column 0 is the first named column (not the index column)
	ref inout(string) opIndex(size_t row, size_t column) inout {
		assert(column < columnsCount);
		return valueList[row * columnsCount + column];
	}
	ref inout(string) opIndex(size_t row, string column) inout {
		return this[row, header[column]];
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
		size_t rows()const{
			return valueList.length / columnsCount;
		}
	}

	ubyte[] serialize() const{
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
				auto value = this[row, col];
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
				auto value = this[row, col];
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

	///
	immutable string fileName = null;
private:
	size_t[string] header;
	size_t columnsCount;
	string[] valueList;

	auto ref extractRowData(in string line){
		import std.uni;
		string[] ret;

		enum State{
			Whitespace,
			Field,
			QuotedField,
		}
		string fieldBuf;
		auto state = State.Whitespace;
		foreach(ref c ; line~" "){
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
						if(fieldBuf=="****")
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
}
unittest{
	immutable polymorphTwoDA = cast(immutable ubyte[])import("polymorph.2da");
	auto twoda = new TwoDA(polymorphTwoDA);

	assert(twoda.fileType == "2DA");
	assertThrown!TwoDAValueException(twoda.fileType = "12345");
	assert(twoda.fileVersion == "V2.0");
	assertThrown!TwoDAValueException(twoda.fileVersion = "12345");

	assert(twoda.get("Name", 0) == "POLYMORPH_TYPE_WEREWOLF");
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
	import std.file;
	std.file.write("test.2da", twodaSerialized);
	auto twodaReparsed = new TwoDA(twodaSerialized);

	assert(twoda.header == twodaReparsed.header);
	assert(twoda.valueList == twodaReparsed.valueList);

}
