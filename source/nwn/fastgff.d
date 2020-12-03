/// Faster and more memory efficient GFF file reading without writing support
module nwn.fastgff;

import std.exception: enforce, assertNotThrown;
import std.stdint;
import std.stdio: writeln;
import std.conv: to;
import std.traits: EnumMembers;
import std.string;
import std.range.primitives;
import std.base64: Base64;
debug import std.stdio;

/// Parsing exception
class GffParseException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
/// Type mismatch exception
class GffTypeException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}


/// Type of data owned by a $(D GffField)
/// See_Also: $(D ToNative)
enum GffType: uint32_t{
	Invalid   = -1, /// Init value
	Byte      = 0,  /// Signed 8-bit int
	Char      = 1,  /// Unsigned 8-bit int
	Word      = 2,  /// Signed 16-bit int
	Short     = 3,  /// Unsigned 16-bit int
	DWord     = 4,  /// Signed 32-bit int
	Int       = 5,  /// Unsigned 32-bit int
	DWord64   = 6,  /// Signed 64-bit int
	Int64     = 7,  /// Unsigned 64-bit int
	Float     = 8,  /// 32-bit float
	Double    = 9,  /// 64-bit float
	String    = 10, /// String
	ResRef    = 11, /// String with width <= 16 (32 for NWN2)
	LocString = 12, /// Localized string
	Void      = 13, /// Binary data
	Struct    = 14, /// Map of other $(D GffField)
	List      = 15  /// Array of other $(D GffField)
}
/// A simple type can be stored inside the GffField value slot (32-bit or less)
bool isSimpleType(GffType type){
	with(GffType){
		return type <= Int || type == Float;
	}
}
/// Maps $(D GffType) to native D type
template ToNative(GffType t){
	     static if(t==GffType.Invalid)         static assert(0, "No native type for GffType.Invalid");
	else static if(t==GffType.Byte)            alias ToNative = GffByte;
	else static if(t==GffType.Char)            alias ToNative = GffChar;
	else static if(t==GffType.Word)            alias ToNative = GffWord;
	else static if(t==GffType.Short)           alias ToNative = GffShort;
	else static if(t==GffType.DWord)           alias ToNative = GffDWord;
	else static if(t==GffType.Int)             alias ToNative = GffInt;
	else static if(t==GffType.DWord64)         alias ToNative = GffDWord64;
	else static if(t==GffType.Int64)           alias ToNative = GffInt64;
	else static if(t==GffType.Float)           alias ToNative = GffFloat;
	else static if(t==GffType.Double)          alias ToNative = GffDouble;
	else static if(t==GffType.String)          alias ToNative = GffString;
	else static if(t==GffType.ResRef)          alias ToNative = GffResRef;
	else static if(t==GffType.LocString) alias ToNative = GffLocString;
	else static if(t==GffType.Void)            alias ToNative = GffVoid;
	else static if(t==GffType.Struct)          alias ToNative = GffStruct;
	else static if(t==GffType.List)            alias ToNative = GffList;
	else static assert(0);
}

/// Basic GFF value type
alias GffByte = uint8_t;
/// Basic GFF value type
alias GffChar = int8_t;
/// Basic GFF value type
alias GffWord = uint16_t;
/// Basic GFF value type
alias GffShort = int16_t;
/// Basic GFF value type
alias GffDWord = uint32_t;
/// Basic GFF value type
alias GffInt = int32_t;
/// Basic GFF value type
alias GffDWord64 = uint64_t;
/// Basic GFF value type
alias GffInt64 = int64_t;
/// Basic GFF value type
alias GffFloat = float;
/// Basic GFF value type
alias GffDouble = double;
/// Basic GFF value type
alias GffString = string;

/// GFF Resref value type (32 character string)
struct GffResRef{
	import nwnlibd.parseutils: stringToCharArray, charArrayToString;

	///
	this(in char[] value){
		assert(value.length <= 32, "Resref cannot be longer than 32 characters");
		data[0 .. value.length] = value;
		if(value.length < data.length)
			data[value.length .. $] = 0;
	}

	alias toString this;


	version(FastGffWrite)
	void opAssign(in string str){
		assert(str.length <= 32, "Value is too long");
		data = str.stringToCharArray!(char[32]);
	}

	/// Converts `this.data` into a usable string (trim trailing NULL chars)
	string toString() const {
		return charArrayToString(data);
	}

package:
	char[32] data;
}

/// GFF Localized string value type (strref with eventually a `nwn.constants.Language` => `string` map)
struct GffLocString{
	uint32_t strref;
	string[int32_t] strings;

	/// Get the string value without attempting to resolve strref using TLKs
	string toString() const {
		return format!"{%d, %s}"(strref == strref.max ? -1 : cast(long)strref, strings);
	}

	import nwn.tlk: StrRefResolver, LanguageGender, TlkOutOfBoundsException;
	/// Get the string value using TLK tables if needed
	string resolve(in StrRefResolver resolver) const{
		if(strings.length > 0){
			immutable preferedLang = resolver.standartTable.language * 2;
			if(auto str = preferedLang in strings)
				return *str;
			if(auto str = preferedLang + 1 in strings)
				return *str;
			if(auto str = -2 in strings) // SetFirstName sets the -2 language
				return *str;

			foreach(lang ; EnumMembers!LanguageGender){
				if(auto str = lang in strings)
					return *str;
			}
		}

		if(strref != strref.max){
			try return resolver[strref];
			catch(TlkOutOfBoundsException){
				return "invalid_strref";
			}
		}

		return "";
	}
}
/// Basic GFF value type
alias GffVoid = ubyte[];

/// GFF structure value type (`string` => `GffField` map)
struct GffStruct{
	import std.typecons: Nullable;

	@property{
		/// Struct subtype ID
		uint32_t id() const{
			return internal.id;
		}
	}

	/// Get child GffField
	const(GffField) opIndex(in string label) const{
		assert(gff !is null, "GffStruct has no data");
		auto fieldIndex = index[label];
		return const(GffField)(gff, gff.getField(fieldIndex));
	}

	/// Allows `foreach(gffField ; this)`
	int opApply(scope int delegate(in GffField child) dlg) const{
		return _opApply(delegate(uint32_t fieldIndex){
			auto field = gff.getField(fieldIndex);
			return dlg(const(GffField)(gff, field));
		});
	}

	/// Return type for `"key" in gffStruct`. Behaves like a pointer.
	static struct NullableField {
		bool isNull = true;
		GffField value;

		//alias isNull this;
		bool opCast(T: bool)() const {
			return !isNull;
		}

		alias value this;
		GffField opUnary(string op: "*")() const {
			assert(!isNull, "NullableField is null");
			return value;
		}
	}

	/// Allows `"value" in this`
	const(NullableField) opBinaryRight(string op : "in")(string label) const
	{
		if(gff is null)
			return NullableField();

		if(auto fieldIndex = label in index)
			return const(NullableField)(false, const(GffField)(gff, gff.getField(*fieldIndex)));

		return NullableField();
	}


	/// Serialize the struct and its children in a human-readable format
	string toPrettyString(string tabs = null) const {
		string ret = format!"%s(Struct %s)"(tabs, id == id.max ? "-1" : id.to!string);
		foreach(field ; this){
			const innerTabs = tabs ~ "|  ";
			const type = (field.type != GffType.Struct && field.type != GffType.List) ? " (" ~ field.type.to!string ~ ")" : null;

			ret ~= format!"\n%s├╴ %-16s = %s%s"(
				tabs,
				field.label, field.toPrettyString(innerTabs)[innerTabs.length .. $], type
			);
		}
		return ret;
	}

package:
	this(inout(FastGff) gff, inout(FastGff.Struct)* internal) inout{
		this.gff = gff;
		this.internal = internal;

		uint32_t[string] index;
		_opApply(delegate(uint32_t fieldIndex){
			auto field = gff.getField(fieldIndex);
			index[gff.getLabel(field.label_index).toString] = fieldIndex;
			return 0;
		});
		this.index = cast(inout)index;
	}

private:
	FastGff gff = null;
	FastGff.Struct* internal = null;
	uint32_t[string] index;

	int _opApply(scope int delegate(uint32_t fieldIndex) dlg) const{
		if(gff is null)
			return 0;

		if(internal.field_count == 1){
			auto fieldIndex = internal.data_or_data_offset;
			return dlg(fieldIndex);
		}
		else if(internal.field_count > 1){
			if(internal.data_or_data_offset != uint32_t.max){
				auto fieldList = gff.getFieldList(internal.data_or_data_offset);
				foreach(i ; 0 .. internal.field_count){
					auto fieldIndex = fieldList[i];
					int res = dlg(fieldIndex);
					if(res != 0)
						return res;
				}
			}
		}
		return 0;
	}

}
/// GFF list value type (Array of GffStruct)
struct GffList{
	/// Get nth child GffStruct
	const(GffStruct) opIndex(size_t index) const{
		assert(gff !is null && index < length, "Out of bound");
		return const(GffStruct)(gff, gff.getStruct(structIndexList[index]));
	}

	/// Number of children elements
	@property
	size_t length() const{
		return listLength;
	}

	///
	@property
	bool empty() const{
		return listLength == 0;
	}

	/// Converts the GffLIst into a list of GffStruct
	@property const(GffStruct)[] children() const {
		//auto ret = new GffStruct[listLength];
		const(GffStruct)[] ret;
		foreach(i ; 0 .. listLength){
			ret ~= const(GffStruct)(gff, gff.getStruct(structIndexList[i]));
			//ret[i] = const(GffStruct)(gff, gff.getStruct(structIndexList[i]));
		}
		return ret;
	}
	///
	alias children this;


	/// Serialize the list and its children in a human-readable format
	string toPrettyString(string tabs = null) const {
		string ret = format!"%s(List)"(tabs);
		foreach(child ; this){
			auto innerTabs = tabs ~ "|  ";
			ret ~= format!"\n%s├╴ %s"(
				tabs,
				child.toPrettyString(innerTabs)[innerTabs.length .. $]
			);
		}
		return ret;
	}

package:
	this(inout(FastGff) gff, uint32_t listOffset) inout{
		this.gff = gff;

		auto list = gff.getStructList(listOffset);
		this.listLength = list[0];
		this.structIndexList = &(list[1]);
	}


private:
	FastGff gff = null;
	uint32_t* structIndexList;
	uint32_t listLength;
}


/// GFF generic value (used for `GffStruct` children). This can be used as a Variant.
struct GffField{
	import std.variant: VariantN;
	alias Value = VariantN!(32,
		GffByte, GffChar,
		GffWord, GffShort,
		GffDWord, GffInt,
		GffDWord64, GffInt64,
		GffFloat, GffDouble,
		GffString, GffResRef, GffLocString, GffVoid,
		GffStruct, GffList);

	alias value this;

	@property{
		/// Value type
		GffType type() const{
			return internal.type;
		}

		/// Get the value as a Variant
		Value value() const{

			final switch(type) with(GffType){
				foreach(Type ; EnumMembers!GffType){
					case Type:
					static if(Type == Invalid)
						assert(0, "Invalid type");
					else static if(isSimpleType(Type)){
						return Value(*cast(ToNative!Type*)&internal.data_or_data_offset);
					}
					else static if(Type == Struct){
						return const(Value)(cast(GffStruct)const(GffStruct)(gff, gff.getStruct(internal.data_or_data_offset)));
					}
					else static if(Type == List){
						return const(Value)(cast(GffList)const(GffList)(gff, internal.data_or_data_offset));
					}
					else{
						auto fieldData = gff.getFieldData(internal.data_or_data_offset);
						static if(Type == DWord64 || Type == Int64 || Type == Double){
							return Value(*cast(ToNative!Type*)fieldData);
						}
						else static if(Type == String){
							auto length = *cast(uint32_t*)fieldData;
							return Value(cast(GffString)fieldData[4 .. 4 + length].idup);
						}
						else static if(Type == ResRef){
							auto length = *cast(uint8_t*)fieldData;
							return Value(GffResRef(cast(char[])fieldData[1 .. 1 + length]));
						}
						else static if(Type == LocString){
							auto blockLength = *cast(uint32_t*)fieldData;
							import nwnlibd.parseutils: ChunkReader;
							auto reader = ChunkReader(fieldData[4 .. 4 + blockLength]);

							GffLocString ret;
							ret.strref = reader.read!uint32_t;

							auto count = reader.read!uint32_t;
							foreach(i ; 0 .. count){
								auto id = reader.read!uint32_t;
								auto strlen = reader.read!uint32_t;

								ret.strings[id] = reader.readArray!char(strlen).idup;
							}
							return Value(ret);
						}
						else static if(Type == Void){
							auto length = *cast(uint32_t*)fieldData;
							return Value(fieldData[4 .. 4 + length].dup);
						}
					}
				}
			}
		}

		/// Get the label of this field
		string label() const{
			return gff.getLabel(internal.label_index).toString;
		}
	}

	/// Shorthand for getting child field assuming this field is a `GffStruct`
	const(GffField) opIndex(in string label) const{
		return value.get!GffStruct[label];
	}

	/// Shorthand for getting child field assuming this field is a `GffList`
	const(GffStruct) opIndex(in size_t index) const{
		return value.get!GffList[index];
	}

	/// Serialize the field in a human-readable format. Does not represents struct or list children.
	string toString() const{
		typeswitch:
		final switch(type) with(GffType){
			foreach(Type ; EnumMembers!GffType){
				case Type:
				static if(Type == Invalid)
					assert(0, "Invalid type");
				else static if(Type == Void){
					return Base64.encode(value.get!(ToNative!Type));
				}
				else static if(Type == Struct){
					return "{Struct}";
				}
				else static if(Type == List){
					return "[List]";
				}
				else{
					return value.get!(ToNative!Type).to!string;
				}
			}
		}
	}

	/// Serialize the field and its children in a human-readable format
	string toPrettyString(in string tabs = null) const{
		import std.string;
		string ret = tabs;

		typeswitch:
		final switch(type) with(GffType){
			foreach(Type ; EnumMembers!GffType){
				case Type:
				static if(Type == Invalid)
					assert(0, "Invalid type");
				else static if(Type == Void){
					return ret ~ Base64.encode(value.get!(ToNative!Type)).to!string;
				}
				else static if(Type == Struct || Type == List){
					return value.get!(ToNative!Type).toPrettyString(tabs);
				}
				else{
					return ret ~ value.get!(ToNative!Type).to!string;
				}
			}
		}
	}

	T to(T)() const {
		final switch(type) with(GffType) {
			case Byte:      static if(__traits(compiles, value.get!GffByte.to!T))      return value.get!GffByte.to!T;      else break;
			case Char:      static if(__traits(compiles, value.get!GffChar.to!T))      return value.get!GffChar.to!T;      else break;
			case Word:      static if(__traits(compiles, value.get!GffWord.to!T))      return value.get!GffWord.to!T;      else break;
			case Short:     static if(__traits(compiles, value.get!GffShort.to!T))     return value.get!GffShort.to!T;     else break;
			case DWord:     static if(__traits(compiles, value.get!GffDWord.to!T))     return value.get!GffDWord.to!T;     else break;
			case Int:       static if(__traits(compiles, value.get!GffInt.to!T))       return value.get!GffInt.to!T;       else break;
			case DWord64:   static if(__traits(compiles, value.get!GffDWord64.to!T))   return value.get!GffDWord64.to!T;   else break;
			case Int64:     static if(__traits(compiles, value.get!GffInt64.to!T))     return value.get!GffInt64.to!T;     else break;
			case Float:     static if(__traits(compiles, value.get!GffFloat.to!T))     return value.get!GffFloat.to!T;     else break;
			case Double:    static if(__traits(compiles, value.get!GffDouble.to!T))    return value.get!GffDouble.to!T;    else break;
			case String:    static if(__traits(compiles, value.get!GffString.to!T))    return value.get!GffString.to!T;    else break;
			case ResRef:    static if(__traits(compiles, value.get!GffResRef.to!T))    return value.get!GffResRef.to!T;    else break;
			case LocString: static if(__traits(compiles, value.get!GffLocString.to!T)) return value.get!GffLocString.to!T; else break;
			case Void:      static if(__traits(compiles, value.get!GffVoid.to!T))      return value.get!GffVoid.to!T;      else break;
			case Struct:    static if(__traits(compiles, value.get!GffStruct.to!T))    return value.get!GffStruct.to!T;    else break;
			case List:      static if(__traits(compiles, value.get!GffList.to!T))      return value.get!GffList.to!T;      else break;
			case Invalid:   assert(0, "No type set");
		}
		assert(0, format!"Cannot convert GFFType %s to %s"(type, T.stringof));
	}


package:
	this(inout(FastGff) gff, inout(FastGff.Field)* field) inout{
		this.gff = gff;
		internal = field;
	}
private:
	FastGff gff = null;
	FastGff.Field* internal = null;

}


/// GFF file parser
class FastGff{

	/// Parse GFF file
	this(in string filePath){
		import std.file: read;
		this(cast(ubyte[])filePath.read());
	}

	/// Parse GFF raw data
	this(in ubyte[] rawData){
		enforce!GffParseException(rawData.length >= header.sizeof,
			"rawData length is too small");

		header       = *cast(Header*)rawData.ptr;
		structs      = cast(Struct[])   rawData[header.struct_offset        .. header.struct_offset        + Struct.sizeof * header.struct_count    ].dup;
		fields       = cast(Field[])    rawData[header.field_offset         .. header.field_offset         + Field.sizeof  * header.field_count     ].dup;
		labels       = cast(Label[])    rawData[header.label_offset         .. header.label_offset         + Label.sizeof  * header.label_count     ].dup;
		fieldData    = cast(ubyte[])    rawData[header.field_data_offset    .. header.field_data_offset    + ubyte.sizeof  * header.field_data_count].dup;
		fieldIndices = cast(uint32_t[]) rawData[header.field_indices_offset .. header.field_indices_offset + header.field_indices_count             ].dup;
		listIndices  = cast(uint32_t[]) rawData[header.list_indices_offset  .. header.list_indices_offset  + header.list_indices_count              ].dup;

	}

	alias root this;

	@property{
		/// Get root node (accessible with alias this)
		const const(GffStruct) root(){
			return const(GffStruct)(this, getStruct(0));
		}

		/// GFF file type string
		const string fileType(){
			return header.file_type.idup().stripRight;
		}

		/// GFF file version string
		const string fileVersion(){
			return header.file_version.idup().stripRight;
		}
	}

	/// Serialize the entire file in a human-readable format
	string toPrettyString() const{
		import std.string: stripRight;
		return "========== GFF-"~header.file_type.idup.stripRight~"-"~header.file_version.idup.stripRight~" ==========\n"
				~ root.toPrettyString;
	}


private:
	Header header;
	Struct[] structs;
	Field[] fields;
	Label[] labels;

	ubyte[] fieldData;
	uint32_t[] fieldIndices;
	uint32_t[] listIndices;



	inout(Struct)* getStruct(in size_t id) inout {
		return &structs[id];
	}
	inout(Field)* getField(in size_t id) inout {
		return &fields[id];
	}
	inout(Label)* getLabel(in size_t id) inout {
		return &labels[id];
	}

	inout(ubyte)* getFieldData(in size_t offset) inout {
		return &fieldData[offset];
	}
	inout(uint32_t)* getFieldList(in size_t offset) inout {
		return cast(inout(uint32_t)*)
		       &(cast(ubyte[])fieldIndices)[offset];
	}
	inout(uint32_t)* getStructList(in size_t offset) inout {
		return cast(inout(uint32_t)*)
		       &(cast(ubyte[])listIndices)[offset];
	}




	static align(1) struct Header{
		static assert(this.sizeof == 56);
		align(1):
		char[4]  file_type;
		char[4]  file_version;
		uint32_t struct_offset;
		uint32_t struct_count;
		uint32_t field_offset;
		uint32_t field_count;
		uint32_t label_offset;
		uint32_t label_count;
		uint32_t field_data_offset;
		uint32_t field_data_count;
		uint32_t field_indices_offset;
		uint32_t field_indices_count;
		uint32_t list_indices_offset;
		uint32_t list_indices_count;

		string toString() const{
			return "Header: |"~file_type.to!string~"|"~file_version.to!string~"|\n"
			      ~"  struct: "~struct_offset.to!string~" ("~struct_count.to!string~")\n"
			      ~"  field: "~field_offset.to!string~" ("~field_count.to!string~")\n"
			      ~"  label: "~label_offset.to!string~" ("~label_count.to!string~")\n"
			      ~"  field_data: "~field_data_offset.to!string~" ("~field_data_count.to!string~")\n"
			      ~"  field_indices: "~field_indices_offset.to!string~" ("~field_indices_count.to!string~")\n"
			      ~"  list_indices: "~list_indices_offset.to!string~" ("~list_indices_count.to!string~")\n";
		}
	}
	static align(1) struct Struct{
		static assert(this.sizeof == 12);
		align(1):
		uint32_t id;
		uint32_t data_or_data_offset;
		uint32_t field_count;
		debug string toString() const {
			return format!"Struct(id=%d dodo=%d fc=%d)"(id, data_or_data_offset, field_count);
		}
	}
	static align(1) struct Field{
		static assert(this.sizeof == 12);
		align(1):
		GffType type;
		uint32_t label_index;
		uint32_t data_or_data_offset;
		debug string toString() const {
			return format!"Field(t=%s lblidx=%d dodo=%d)"(type.to!GffType, label_index, data_or_data_offset);
		}
	}
	static align(1) struct Label{
		static assert(this.sizeof == 16);
		align(1):
		char[16] value;
		string toString() const{
			import nwnlibd.parseutils: charArrayToString;
			return value.charArrayToString;
		}
	}


}



unittest{
	import std.file : read;
	with(GffType){
		immutable krogarDataOrig = cast(immutable ubyte[])import("krogar.bic");
		auto gff = new FastGff(krogarDataOrig);

		//Parsing checks
		assert(gff.fileType == "BIC");
		assert(gff.fileVersion == "V3.2");

		assert(gff["IsPC"].get!GffByte == true);
		assert(gff["RefSaveThrow"].get!GffChar == 13);
		assert(gff["SoundSetFile"].get!GffWord == 363);
		assert(gff["HitPoints"].get!GffShort == 320);
		assert(gff["Gold"].get!GffDWord == 6400);
		assert(gff["Age"].get!GffInt == 50);
		//assert(gff[""].get!GffDWord64 == );
		//assert(gff[""].get!GffInt64 == );
		assert(gff["XpMod"].get!GffFloat == 1);
		//assert(gff[""].get!GffDouble == );
		assert(gff["Deity"].get!GffString == "Gorm Gulthyn");
		assert(gff["ScriptHeartbeat"].get!GffResRef == "gb_player_heart");
		assert(gff["FirstName"].get!GffLocString.strref == -1);
		assert(gff["FirstName"].get!GffLocString.strings[0] == "Krogar");
		//assert(gff[""].get!GffVoid == );
		assert(gff["Tint_Head"]["Tintable"]["Tint"]["1"]["b"].get!GffByte == 109);
		assert(gff["ClassList"][0]["Class"].get!GffInt == 4);

		// Tintable appears two times in the gff
		assert(gff["Tintable"]["Tint"]["1"]["r"].get!GffByte == 253);

		assertNotThrown(gff.toPrettyString());


		// parity with nwn.gff.Gff
		static import nwn.gff;
		assert(new FastGff(krogarDataOrig).toPrettyString == new nwn.gff.Gff(krogarDataOrig).toPrettyString);
		//assert(new FastGff(krogarDataOrig).toJson.toString == new nwn.gff.Gff(krogarDataOrig).toJson.toString);
	}

}