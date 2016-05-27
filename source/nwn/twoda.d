/// Two Dimentional Array (2da)
module nwn.twoda;

import std.string;
import std.conv : to;
debug import std.stdio: writeln;
version(unittest) import std.exception: assertThrown, assertNotThrown;



class TwoDAParseException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
class TwoDAColumnNotFoundException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
class TwoDAOutOfBoundsException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

class TwoDA{

	this(string filepath){
		import std.file: readFile=read;
		this.filepath = filepath;
		this(filepath.readFile);
	}
	this(in void[] rawData){

		foreach(lineIndex, line ; (cast(string)rawData).splitLines){
			if(lineIndex<2)continue;

			auto data = extractRowData(line);

			if(lineIndex==2){
				foreach(index, title ; data){
					header[title] = index;
				}
				header.rehash();
			}
			else{
				if(data.length != header.length+1){
					throw new TwoDAParseException(
						(filepath !is null? filepath : "twoda")~"("~lineIndex.to!string~"): Incorrect number of fields");
				}

				auto lineNo = data[0].to!size_t;
				if(lineNo >= values.length)
					values.length = lineNo+1;
				values[lineNo] = data[1..$];
			}

		}

	}

	const auto ref get(T = string)(in string colName, in size_t line){
		if(line >= rows)
			throw new TwoDAOutOfBoundsException("Line out of bounds");

		auto colIndex = colName in header;
		if(colIndex){
			if(values[line] is null)
				return "".to!T;
			return values[line][*colIndex].to!T;
		}
		else
			throw new TwoDAColumnNotFoundException("Column '"~colName~"' not found");
	}

	@property{
		const size_t rows(){
			return values.length;
		}
	}

	immutable string filepath = null;
private:
	size_t[string] header;
	string[][] values;

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
							ret ~= "";
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
	immutable polymorphTwoDA = cast(immutable void[])import("polymorph.2da");
	auto twoda = new TwoDA(polymorphTwoDA);

	assert(twoda.get("Name", 0) == "POLYMORPH_TYPE_WEREWOLF");
	assert(twoda.get!int("RacialType", 0) == 23);
	assert(twoda.get("EQUIPPED", 0) == null);
	assert(twoda.get!int("MergeA", 13) == 1);
	assert(twoda.get("Name", 21) == "MULTI WORD VALUE");

	assert(twoda.get("Name", 1) == "POLYMORPH_TYPE_WERERAT");
	assert(twoda.get("Name", 8) == null);//deleted line
	assert(twoda.get("Name", 17) == "POLYMORPH_TYPE_ELDER_FIRE_ELEMENTAL");//misordered line
	assert(twoda.get("Name", 26) == null);//empty value
	assert(twoda.get("Name", 207) == "POLYMORPH_TYPE_LESS_EMBER_GUARD");//last line

	assertThrown!TwoDAColumnNotFoundException(twoda.get("Yolooo", 1));
	assertThrown!TwoDAOutOfBoundsException(twoda.get("Name", 208));
}
