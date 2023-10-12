/// Generic File Format (gff)
module nwn.gff;


import std.stdio: File;
import std.stdint;
import std.conv: to;
import std.string;
import std.exception: enforce;
import std.base64: Base64;
import std.algorithm;
import std.array;
import std.traits;
import std.math;
import std.meta;

import nwnlibd.orderedaa;
import nwnlibd.orderedjson;
import nwnlibd.parseutils;

debug import std.stdio;
version(unittest) import std.exception: assertThrown, assertNotThrown;

/// Parsing exception
class GffParseException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
/// Value doesn't match constraints (ex: label too long)
class GffValueSetException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
/// Type mismatch (ex: trying to add a $(D GffNode) to a $(D GffType.Int))
class GffTypeException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
/// Child node not found
class GffNotFoundException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
/// Child node not found
class GffJsonParseException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

/// Type of data owned by a `GffNode`
/// See_Also: `gffTypeToNative`
enum GffType{
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
	Struct    = 14, /// Map of other $(D GffNode)
	List      = 15  /// Array of other $(D GffNode)
}

/// List of all dlang types that can be stored in a GFF value
alias GffNativeTypes = AliasSeq!(GffByte, GffChar, GffWord, GffShort, GffDWord, GffInt, GffDWord64, GffInt64, GffFloat, GffDouble, GffString, GffResRef, GffLocString, GffVoid, GffStruct, GffList, GffValue);

/// Maps $(D GffType) to native D type
template gffTypeToNative(GffType t){
	import std.typecons: Tuple;
	static if     (t==GffType.Invalid)   static assert(0, "No native type for GffType.Invalid");
	else static if(t==GffType.Byte)      alias gffTypeToNative = GffByte;
	else static if(t==GffType.Char)      alias gffTypeToNative = GffChar;
	else static if(t==GffType.Word)      alias gffTypeToNative = GffWord;
	else static if(t==GffType.Short)     alias gffTypeToNative = GffShort;
	else static if(t==GffType.DWord)     alias gffTypeToNative = GffDWord;
	else static if(t==GffType.Int)       alias gffTypeToNative = GffInt;
	else static if(t==GffType.DWord64)   alias gffTypeToNative = GffDWord64;
	else static if(t==GffType.Int64)     alias gffTypeToNative = GffInt64;
	else static if(t==GffType.Float)     alias gffTypeToNative = GffFloat;
	else static if(t==GffType.Double)    alias gffTypeToNative = GffDouble;
	else static if(t==GffType.String)    alias gffTypeToNative = GffString;
	else static if(t==GffType.ResRef)    alias gffTypeToNative = GffResRef;
	else static if(t==GffType.LocString) alias gffTypeToNative = GffLocString;
	else static if(t==GffType.Void)      alias gffTypeToNative = GffVoid;
	else static if(t==GffType.Struct)    alias gffTypeToNative = GffStruct;
	else static if(t==GffType.List)      alias gffTypeToNative = GffList;
	else static assert(0);
}
/// Converts a native type $(D T) to the associated $(D GffType). Types must match exactly
template nativeToGffType(T){
	import std.typecons: Tuple;
	static if     (is(T == GffByte))      alias nativeToGffType = GffType.Byte;
	else static if(is(T == GffChar))      alias nativeToGffType = GffType.Char;
	else static if(is(T == GffWord))      alias nativeToGffType = GffType.Word;
	else static if(is(T == GffShort))     alias nativeToGffType = GffType.Short;
	else static if(is(T == GffDWord))     alias nativeToGffType = GffType.DWord;
	else static if(is(T == GffInt))       alias nativeToGffType = GffType.Int;
	else static if(is(T == GffDWord64))   alias nativeToGffType = GffType.DWord64;
	else static if(is(T == GffInt64))     alias nativeToGffType = GffType.Int64;
	else static if(is(T == GffFloat))     alias nativeToGffType = GffType.Float;
	else static if(is(T == GffDouble))    alias nativeToGffType = GffType.Double;
	else static if(is(T == GffString))    alias nativeToGffType = GffType.String;
	else static if(is(T == GffResRef))    alias nativeToGffType = GffType.ResRef;
	else static if(is(T == GffLocString)) alias nativeToGffType = GffType.LocString;
	else static if(is(T == GffVoid))      alias nativeToGffType = GffType.Void;
	else static if(is(T == GffStruct))    alias nativeToGffType = GffType.Struct;
	else static if(is(T == GffList))      alias nativeToGffType = GffType.List;
	else static assert(0, "Type "~T.stringof~" is not a valid GffType");
}

/// returns true if T is implicitly convertible to a GFF storage type
template isGffNativeType(T){
	bool isGffNativeType(){
		bool ret = false;
		foreach(TYP ; GffNativeTypes){
			static if(is(T: TYP)){
				ret = true;
				break;
			}
		}
		return ret;
	}
}


/// Converts a GFF type to a string compatible with niv tools
string gffTypeToCompatStr(in GffType t){
	final switch(t) with(GffType) {
		case Invalid:   assert(0, "Invalid GffType");
		case Byte:      return "byte";
		case Char:      return "char";
		case Word:      return "word";
		case Short:     return "short";
		case DWord:     return "dword";
		case Int:       return "int";
		case DWord64:   return "dword64";
		case Int64:     return "int64";
		case Float:     return "float";
		case Double:    return "double";
		case String:    return "cexostr";
		case ResRef:    return "resref";
		case LocString: return "cexolocstr";
		case Void:      return "void";
		case Struct:    return "struct";
		case List:      return "list";
	}
}
/// Converts a string compatible with niv tools to a GFF type
GffType compatStrToGffType(in string t){
	switch(t) with(GffType) {
		case "byte":       return Byte;
		case "char":       return Char;
		case "word":       return Word;
		case "short":      return Short;
		case "dword":      return DWord;
		case "int":        return Int;
		case "dword64":    return DWord64;
		case "int64":      return Int64;
		case "float":      return Float;
		case "double":     return Double;
		case "cexostr":    return String;
		case "resref":     return ResRef;
		case "cexolocstr": return LocString;
		case "void":       return Void;
		case "struct":     return Struct;
		case "list":       return List;
		default:           return GffType.Invalid;
	}

}



alias GffByte    = uint8_t; //GFF type Byte ( $(D uint8_t) )
alias GffChar    = int8_t; //GFF type Char ( $(D int8_t) )
alias GffWord    = uint16_t; //GFF type Word ( $(D uint16_t) )
alias GffShort   = int16_t; //GFF type Short ( $(D int16_t) )
alias GffDWord   = uint32_t; //GFF type DWord ( $(D uint32_t) )
alias GffInt     = int32_t; //GFF type Int ( $(D int32_t) )
alias GffDWord64 = uint64_t; //GFF type DWord64 ( $(D uint64_t) )
alias GffInt64   = int64_t; //GFF type Int64 ( $(D int64_t) )
alias GffFloat   = float; //GFF type Float ( $(D float) )
alias GffDouble  = double; //GFF type Double ( $(D double) )
alias GffString  = string; //GFF type String ( $(D string) )

/// Gff type ResRef (32-char string)
struct GffResRef {
	///
	this(in string str){
		value = str;
	}

	@property @safe {
		/// Accessor for manipulating GffResRef like a string
		string value() const {
			return data.charArrayToString();
		}
		/// ditto
		void value(in string str){
			assert(str.length <= 32, "Resref cannot be longer than 32 characters");
			data = str.stringToCharArray!(char[32]);
		}
	}
	///
	alias value this;


	auto ref opAssign(in string _value){
		return value = _value;
	}
private:
	char[32] data;
}

/// Gff type LocString (TLK ID + translations)
struct GffLocString{
	/// String ref linking to a TLK entry
	uint32_t strref;
	/// Language => string pairs
	string[int32_t] strings;

	///
	this(uint32_t strref, string[int32_t] strings = null){
		this.strref = strref;
		this.strings = strings;
	}

	/// Duplicate GffLocString content
	GffLocString dup() const {
		string[int32_t] newStrings;
		foreach(k, v ; strings)
			newStrings[k] = v;
		return GffLocString(strref, newStrings);
	}

	/// Get the string value without attempting to resolve strref using TLKs
	string toString() const {
		if(strings.length > 0){
			foreach(lang ; EnumMembers!LanguageGender){
				if(auto str = lang in strings)
					return *str;
			}
		}

		if(strref != strref.max){
			return format!"{{STRREF:%d}}"(strref);
		}
		return "";
	}

	/// Get the string value without attempting to resolve strref using TLKs
	string toPrettyString() const {
		return format!"{%d, %s}"(strref == strref.max ? -1 : cast(long)strref, strings);
	}

	/// JSON to LocString
	this(in nwnlibd.orderedjson.JSONValue json){
		enforce!GffJsonParseException(json.type == JSONType.object, "json value " ~ json.toPrettyString ~ " is not an object");
		enforce!GffJsonParseException(json["type"].str == "cexolocstr", "json object "~ json.toPrettyString ~" is not a GffLocString");
		enforce!GffJsonParseException(json["value"].type == JSONType.object, "json .value "~ json.toPrettyString ~" is not an object");
		strref = json["str_ref"].get!uint32_t;
		foreach(lang, text ; json["value"].object){
			strings[lang.to!int32_t] = text.str;
		}
	}
	/// LocString to JSON
	nwnlibd.orderedjson.JSONValue toJson() const {
		JSONValue ret;
		ret["type"] = "cexolocstr";
		ret["str_ref"] = strref;
		ret["value"] = JSONValue(cast(JSONValue[string])null);
		foreach(ref lang, ref str ; strings)
			ret["value"][lang.to!string] = str;
		return ret;
	}

	/// Remove all localization and set its value to a unique string
	auto ref opAssign(in string value){
		strref = strref.max;
		strings = [0: value];
	}

	/// Set the strref
	auto ref opAssign(in uint32_t value){
		strref = value;
	}


	import nwn.tlk: StrRefResolver, LanguageGender, TlkOutOfBoundsException;
	/// Resolve the localized string using TLKs
	string resolve(in StrRefResolver resolver) const {
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
unittest {
	// TLK resolving
	import nwn.tlk;
	auto resolv = new StrRefResolver(
		new Tlk(cast(ubyte[])import("dialog.tlk")),
		new Tlk(cast(ubyte[])import("user.tlk"))
	);

	auto locStr = GffLocString();
	locStr.strref = Tlk.UserTlkIndexOffset + 1;
	locStr.strings = [0:"male english", 1:"female english", 2:"male french"];

	assert(locStr.resolve(resolv) == "male french");
	assert(locStr.to!string == "male english");// without TLK, use english

	locStr.strings = [0:"male english", 1:"female english"];
	assert(locStr.resolve(resolv) == "male english");
	assert(locStr.to!string == "male english");

	locStr.strings = [4:"male german", 6:"female italian"];
	assert(locStr.resolve(resolv) == "male german");
	assert(locStr.to!string == "male german");

	locStr.strings.clear;
	assert(locStr.resolve(resolv) == "Café liégeois");
	assert(locStr.to!string == "{{STRREF:16777217}}");

	locStr.strref = StrRef.max;
	assert(locStr.resolve(resolv) == "");
	assert(locStr.to!string == "");
}

/// Gff type Void ( $(D ubyte[]) )
alias GffVoid = ubyte[];


/// Gff type Struct ( `GffValue[string]` )
struct GffStruct {
	///
	this(GffValue[string] children, uint32_t id){
		foreach(k, ref v ; children){
			this[k] = v;
		}
		this.id = id;
	}
	///
	this(OrderedAA!(string, GffValue) children, uint32_t id){
		this.children = children;
		this.id = id;
	}
	/// Copy constructor
	this(GffStruct other){
		m_children = other.m_children;
		id = other.id;
	}

	/// Duplicate GffStruct content
	GffStruct dup() const {
		auto dup_children = children.dup();
		foreach(ref GffValue c ; dup_children){
			switch(c.type) {
				case GffType.Struct:
					c = GffValue(c.get!GffStruct.dup());
					break;
				case GffType.List:
					c = GffValue(c.get!GffList.dup());
					break;
				case GffType.LocString:
					c = GffValue(c.get!GffLocString.dup());
					break;
				case GffType.Void:
					c = GffValue(c.get!GffVoid.dup());
					break;
				default:
					break;
			}
		}
		return GffStruct(dup_children, this.id);
	}


	/// Struct ID
	uint32_t id = 0;


	@property{
		/// GffStruct children associative array
		ref inout(ChildrenAA) children() inout return {
			return *cast(inout(ChildrenAA)*)(&m_children);
		}
		/// ditto
		void children(ChildrenAA children){
			m_children = *cast(ChildrenStor*)&children;
		}
	}
	///
	alias children this;


	/// Automatically encapsulate and add a GFF native type
	ref GffValue opIndexAssign(T)(T rhs, in string label) if(isGffNativeType!T) {
		children[label] = GffValue(rhs);
		return children[label];
	}

	/// Converts a GffStruct to a user-friendly string
	string toPrettyString(string tabs = null) const {
		string ret = format!"%s(Struct %s)"(tabs, id == id.max ? "-1" : id.to!string);
		foreach(ref kv ; children.byKeyValue){
			const innerTabs = tabs ~ "|  ";
			const type = (kv.value.type != GffType.Struct && kv.value.type != GffType.List) ? " (" ~ kv.value.type.to!string ~ ")" : null;

			ret ~= format!"\n%s├╴ %-16s = %s%s"(
				tabs,
				kv.key, kv.value.toPrettyString(innerTabs)[innerTabs.length .. $], type
			);
		}
		return ret;
	}


	/// JSON to GffStruct
	this(in nwnlibd.orderedjson.JSONValue json){
		enforce(json.type == JSONType.object, "json value " ~ json.toPrettyString ~ " is not an object");
		enforce(json["type"].str == "struct", "json .type "~ json.toPrettyString ~" is not a sruct");
		enforce(json["value"].type == JSONType.object, "json .value "~ json.toPrettyString ~" is not an object");
		if(auto structId = ("__struct_id" in json))
			id = structId.get!uint32_t;
		foreach(ref label ; json["value"].objectKeyOrder){
			children[label] = GffValue(json["value"][label]);
		}
	}
	/// GffStruct to JSON
	nwnlibd.orderedjson.JSONValue toJson() const {
		JSONValue ret;
		ret["type"] = "struct";
		ret["__struct_id"] = id;
		ret["value"] = JSONValue(cast(JSONValue[string])null);
		foreach(ref kv ; children.byKeyValue){
			ret["value"][kv.key] = kv.value.toJson();
		}
		return ret;
	}


private:
	alias ChildrenAA = OrderedAA!(string, GffValue);
	alias ChildrenStor = OrderedAA!(string, ubyte[_gffValueSize]);

	// We store children as ubyte[5] instead of GffValue, because GffValue
	// needs a complete GffStruct definition
	enum _gffValueSize = 5;
	static assert(ceil(GffValue.sizeof / 8.0) * 8 == 8 * _gffValueSize);
	OrderedAA!(string, ubyte[_gffValueSize]) m_children;
}

/// Gff type List ( `GffStruct[]` )
struct GffList {
	///
	this(GffStruct[] children){
		this.children = children;
	}

	/// Copy constructor
	this(GffList other){
		children = other.children;
	}

	/// Duplicate GffList content
	GffList dup() const {
		return GffList(children.map!(a => a.dup()).array());
	}

	/// GffList children list
	GffStruct[] children;
	alias children this;

	/// Converts a GffStruct to a user-friendly string
	string toPrettyString(string tabs = null) const {
		string ret = format!"%s(List)"(tabs);
		foreach(i, ref child ; children){
			auto innerTabs = tabs ~ "|  ";

			ret ~= format!"\n%s├╴ %s"(
				tabs,
				child.toPrettyString(innerTabs)[innerTabs.length .. $]
			);
		}
		return ret;
	}

	/// JSON to GffList
	this(in nwnlibd.orderedjson.JSONValue json){
		assert(json.type == JSONType.object, "json value " ~ json.toPrettyString ~ " is not an object");
		assert(json["type"].str == "list", "json object "~ json.toPrettyString ~" is not a GffList");
		assert(json["value"].type == JSONType.array, "json .value "~ json.toPrettyString ~" is not an array");
		children.length = json["value"].array.length;
		foreach(i, ref child ; json["value"].array){
			children[i] = GffStruct(child);
		}
	}
	/// GffList to JSON
	nwnlibd.orderedjson.JSONValue toJson() const {
		JSONValue ret;
		ret["type"] = "list";
		ret["value"] = JSONValue(cast(JSONValue[])null);
		ret["value"].array.length = children.length;
		foreach(i, ref child ; children){
			ret["value"][i] = child.toJson();
		}
		return ret;
	}
}




/// GFF value that can contain any type of GFF node
struct GffValue {
	import std.variant: VariantN;
	///
	alias Value = VariantN!(32,
		GffByte, GffChar,
		GffWord, GffShort,
		GffDWord, GffInt,
		GffDWord64, GffInt64,
		GffFloat, GffDouble,
		GffString, GffResRef, GffLocString, GffVoid,
		GffStruct, GffList,
	);

	///
	Value value;
	///
	alias value this;

	///
	this(T)(T _value) if(isGffNativeType!T) {
		value = _value;
	}

	///
	this(GffType _type) {
		final switch(_type) with(GffType) {
			case Byte:      value = GffByte.init;      break;
			case Char:      value = GffChar.init;      break;
			case Word:      value = GffWord.init;      break;
			case Short:     value = GffShort.init;     break;
			case DWord:     value = GffDWord.init;     break;
			case Int:       value = GffInt.init;       break;
			case DWord64:   value = GffDWord64.init;   break;
			case Int64:     value = GffInt64.init;     break;
			case Float:     value = GffFloat.init;     break;
			case Double:    value = GffDouble.init;    break;
			case String:    value = GffString.init;    break;
			case ResRef:    value = GffResRef.init;    break;
			case LocString: value = GffLocString.init; break;
			case Void:      value = GffVoid.init;      break;
			case Struct:    value = GffStruct.init;    break;
			case List:      value = GffList.init;      break;
			case Invalid:   assert(0);
		}
	}

	@property {
		/// Get currently stored GFF type
		GffType type() const {
			static GffType[ulong] lookupTable = null;
			if(lookupTable is null){
				import std.traits: EnumMembers;
				static foreach(gffType ; EnumMembers!GffType){
					static if(gffType != GffType.Invalid)
						lookupTable[typeid(gffTypeToNative!gffType).toHash] = gffType;
					else
						lookupTable[typeid(void).toHash] = gffType;
				}
			}
			return lookupTable[value.type.toHash];
		}
	}

	/// Retrieve a reference to the GFF value or throws
	/// Throws: GffTypeException if the types don't match
	ref inout(T) get(T)() inout {
		if(auto ptr = value.peek!T)
			return *cast(inout T*)ptr;
		throw new GffTypeException(format!"GFF Type mismatch: node is %s, trying to get it as %s"(value.type, T.stringof));
	}

	/// Shorthand for modifying the GffValue as a GffStruct
	auto ref opIndex(in string label){
		return value.get!GffStruct[label];
	}
	/// ditto
	auto ref opIndexAssign(T)(T rhs, in string label) if(is(T: GffValue) || isGffNativeType!T){
		static if(isGffNativeType!T)
			return value.get!GffStruct[label] = GffValue(rhs);
		else
			return value.get!GffStruct[label] = rhs;
	}

	/// Shorthand for modifying the GffValue as a GffList
	auto ref opIndex(size_t index){
		return value.get!GffList[index];
	}
	/// ditto
	auto ref opIndexAssign(GffStruct rhs, size_t index){
		return value.get!GffList[index] = rhs;
	}

	/// Converts the stored value into the given type
	T to(T)() const {
		final switch(type) with(GffType) {
			case Byte:      static if(__traits(compiles, get!GffByte.to!T))      return get!GffByte.to!T;      else break;
			case Char:      static if(__traits(compiles, get!GffChar.to!T))      return get!GffChar.to!T;      else break;
			case Word:      static if(__traits(compiles, get!GffWord.to!T))      return get!GffWord.to!T;      else break;
			case Short:     static if(__traits(compiles, get!GffShort.to!T))     return get!GffShort.to!T;     else break;
			case DWord:     static if(__traits(compiles, get!GffDWord.to!T))     return get!GffDWord.to!T;     else break;
			case Int:       static if(__traits(compiles, get!GffInt.to!T))       return get!GffInt.to!T;       else break;
			case DWord64:   static if(__traits(compiles, get!GffDWord64.to!T))   return get!GffDWord64.to!T;   else break;
			case Int64:     static if(__traits(compiles, get!GffInt64.to!T))     return get!GffInt64.to!T;     else break;
			case Float:     static if(__traits(compiles, get!GffFloat.to!T))     return get!GffFloat.to!T;     else break;
			case Double:    static if(__traits(compiles, get!GffDouble.to!T))    return get!GffDouble.to!T;    else break;
			case String:    static if(__traits(compiles, get!GffString.to!T))    return get!GffString.to!T;    else break;
			case ResRef:    static if(__traits(compiles, get!GffResRef.to!T))    return get!GffResRef.to!T;    else break;
			case LocString: static if(__traits(compiles, get!GffLocString.to!T)) return get!GffLocString.to!T; else break;
			case Void:      static if(__traits(compiles, get!GffVoid.to!T))      return get!GffVoid.to!T;      else break;
			case Struct:    static if(__traits(compiles, get!GffStruct.to!T))    return get!GffStruct.to!T;    else break;
			case List:      static if(__traits(compiles, get!GffList.to!T))      return get!GffList.to!T;      else break;
			case Invalid:   assert(0, "No type set");
		}
		assert(0, format!"Cannot convert GFFType %s to %s"(type, T.stringof));
	}
	/// Create a GffValue by parsing JSON.
	/// JSON format should be like `{"type": "resref", "value": "hello world"}`
	this(in nwnlibd.orderedjson.JSONValue json){
		assert(json.type == JSONType.object, "json value " ~ json.toPrettyString ~ " is not an object");
		switch(json["type"].str.compatStrToGffType) with(GffType) {
			case Byte:      value = cast(GffByte)json["value"].get!GffByte;       break;
			case Char:      value = cast(GffChar)json["value"].get!GffChar;       break;
			case Word:      value = cast(GffWord)json["value"].get!GffWord;       break;
			case Short:     value = cast(GffShort)json["value"].get!GffShort;     break;
			case DWord:     value = cast(GffDWord)json["value"].get!GffDWord;     break;
			case Int:       value = cast(GffInt)json["value"].get!GffInt;         break;
			case DWord64:   value = cast(GffDWord64)json["value"].get!GffDWord64; break;
			case Int64:     value = cast(GffInt64)json["value"].get!GffInt64;     break;
			case Float:     value = cast(GffFloat)json["value"].get!GffFloat;     break;
			case Double:    value = cast(GffDouble)json["value"].get!GffDouble;   break;
			case String:    value = json["value"].str;                break;
			case ResRef:    value = GffResRef(json["value"].str);     break;
			case LocString: value = GffLocString(json);               break;
			case Void:      value = Base64.decode(json["value"].str); break;
			case Struct:    value = GffStruct(json);                  break;
			case List:      value = GffList(json);                    break;
			default: throw new GffJsonParseException("Unknown Gff type string: '"~json["type"].str~"'");
		}
	}
	/// Converts to JSON
	nwnlibd.orderedjson.JSONValue toJson() const {
		JSONValue ret;
		final switch(type) with(GffType) {
			case Byte:      ret["value"] = get!GffByte; break;
			case Char:      ret["value"] = get!GffChar; break;
			case Word:      ret["value"] = get!GffWord; break;
			case Short:     ret["value"] = get!GffShort; break;
			case DWord:     ret["value"] = get!GffDWord; break;
			case Int:       ret["value"] = get!GffInt; break;
			case DWord64:   ret["value"] = get!GffDWord64; break;
			case Int64:     ret["value"] = get!GffInt64; break;
			case Float:     ret["value"] = get!GffFloat; break;
			case Double:    ret["value"] = get!GffDouble; break;
			case String:    ret["value"] = get!GffString; break;
			case ResRef:    ret["value"] = get!GffResRef.value; break;
			case LocString: return get!GffLocString.toJson;
			case Void:      ret["value"] = Base64.encode(get!GffVoid).to!string; break;
			case Struct:    return get!GffStruct.toJson;
			case List:      return get!GffList.toJson;
			case Invalid:   assert(0, "No type set");
		}
		ret["type"] = type.gffTypeToCompatStr;
		return ret;
	}

	/// Converts to a user-readable string
	string toPrettyString(string tabs = null) const {
		final switch(type) with(GffType) {
			case Byte, Char, Word, Short, DWord, Int, DWord64, Int64, Float, Double, String:
			case ResRef:
				return tabs ~ to!string;
			case LocString:
				return tabs ~ get!GffLocString.toPrettyString;
			case Void:
				import std.base64: Base64;
				return tabs ~ Base64.encode(get!GffVoid).to!string;
			case Struct:
				return get!GffStruct.toPrettyString(tabs);
			case List:
				return get!GffList.toPrettyString(tabs);
			case Invalid:
				assert(0);
		}
	}
}




/// Complete GFF file
class Gff{
	/// Empty GFF
	this(){}

	/// Create a Gff by parsing the binary format
	this(in ubyte[] data){
		GffRawParser(data).parse(this);
	}
	/// Create a Gff by parsing a file in binary format
	this(File file){
		ubyte[] data;
		data.length = GffRawParser.RawHeader.sizeof;
		auto readCount = file.rawRead(data).length;
		enforce!GffParseException(readCount >= GffRawParser.RawHeader.sizeof,
			"File is too small to be GFF: "~readCount.to!string~" bytes read, "~GffRawParser.RawHeader.sizeof.to!string~" needed !");

		auto header = cast(GffRawParser.RawHeader*)data.ptr;
		immutable size_t fileLength =
			header.list_indices_offset + header.list_indices_count;

		data.length = fileLength;
		readCount += file.rawRead(data[GffRawParser.RawHeader.sizeof..$]).length;
		enforce!GffParseException(readCount >= fileLength,
			"File is too small to be GFF: "~readCount.to!string~" bytes read, "~fileLength.to!string~" needed !");

		this(data);
	}
	// ditto
	this(in string path){
		this(File(path, "r"));
	}

	/// Convert to binary format
	ubyte[] serialize(){
		return GffRawSerializer().serialize(this);
	}

	/// Create a Gff by parsing JSON
	this(in nwnlibd.orderedjson.JSONValue json){
		fileType = json["__data_type"].str;
		fileVersion = "__data_version" in json ? json["__data_version"].str : "V3.2";
		root = GffStruct(json);
	}

	/// Convert to JSON
	nwnlibd.orderedjson.JSONValue toJson() const {
		auto ret = root.toJson();
		ret["__data_type"] = fileType;
		ret["__data_version"] = fileVersion;
		return ret;
	}

	/// Converts the GFF into a user-friendly string
	string toPrettyString() const {
		return "========== GFF-"~fileType~"-"~fileVersion~" ==========\n"
			~ root.toPrettyString;
	}

	@property{
		/// GFF type name stored in the GFF file
		/// Max width: 4 chars
		const string fileType(){return m_fileType.idup.stripRight;}
		/// ditto
		void fileType(in string type){
			const len = type.length;
			enforce!GffValueSetException(type.length <= 4, "fileType length must be <= 4");
			m_fileType[0 .. len] = type;
			if(len < 4)
				m_fileType[len .. $] = ' ';
		}
		/// GFF version stored in the GFF file. Usually "V3.2"
		/// Max width: 4 chars
		const string fileVersion(){return m_fileVersion.idup.stripRight;}
		/// ditto
		void fileVersion(in string ver){
			const len = ver.length;
			enforce!GffValueSetException(ver.length <= 4, "fileVersion length must be <= 4");
			m_fileVersion[0 .. len] = ver;
			if(len < 4)
				m_fileVersion[len .. $] = ' ';
		}
	}


	///
	alias root this;
	/// Root $(D GffStruct)
	GffStruct root;

private:
	char[4] m_fileType, m_fileVersion;
}



private struct GffRawParser{
	@disable this();
	this(in ubyte[] _data){
		enforce(_data.length >= RawHeader.sizeof, "Data length is so small it cannot even contain the header");

		data = _data;
		headerPtr       = cast(const RawHeader*)      (data.ptr);
		structsPtr      = cast(const RawStruct*)      (data.ptr + headerPtr.struct_offset);
		fieldsPtr       = cast(const RawField*)       (data.ptr + headerPtr.field_offset);
		labelsPtr       = cast(const RawLabel*)       (data.ptr + headerPtr.label_offset);
		fieldDatasPtr   = cast(const RawFieldData*)   (data.ptr + headerPtr.field_data_offset);
		fieldIndicesPtr = cast(const RawFieldIndices*)(data.ptr + headerPtr.field_indices_offset);
		listIndicesPtr  = cast(const RawListIndices*) (data.ptr + headerPtr.list_indices_offset);

		enforce(data.length == headerPtr.list_indices_offset+headerPtr.list_indices_count,
			"Data length do not match header");
	}

	static align(1) struct RawHeader{
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
	}
	static align(1) struct RawStruct{
		uint32_t id;
		uint32_t data_or_data_offset;
		uint32_t field_count;
		debug string toString() const {
			return format!"Struct(id=%d dodo=%d fc=%d)"(id, data_or_data_offset, field_count);
		}
	}
	static align(1) struct RawField{
		uint32_t type;
		uint32_t label_index;
		uint32_t data_or_data_offset;
		debug string toString() const {
			return format!"Field(t=%s lblidx=%d dodo=%d)"(type.to!GffType, label_index, data_or_data_offset);
		}
	}
	static align(1) struct RawLabel{
		char[16] value;
		debug string toString() const {
			return format!"Label(%s)"(value.charArrayToString);
		}
	}
	static align(1) struct RawFieldData{
		uint8_t first_data;//First byte of data. Other follows
	}
	static align(1) struct RawFieldIndices{
		uint32_t field_index;
	}
	static align(1) struct RawListIndices{
		uint32_t length;
		uint32_t first_struct_index;
		debug string toString() const {
			return format!"ListIndices(len=%d start=%d)"(length, first_struct_index);
		}
	}

	const ubyte[] data;
	const RawHeader* headerPtr;
	const RawStruct* structsPtr;
	const RawField*  fieldsPtr;
	const RawLabel*  labelsPtr;
	const void*         fieldDatasPtr;
	const void*         fieldIndicesPtr;
	const void*         listIndicesPtr;

	const(RawStruct*) getRawStruct(in size_t index) const {
		enforce(index < headerPtr.struct_count, "index "~index.to!string~" out of bounds");
		return &structsPtr[index];
	}
	const(RawField*) getRawField(in size_t index) const {
		enforce(index < headerPtr.field_count, "index "~index.to!string~" out of bounds");
		return &fieldsPtr[index];
	}
	const(RawLabel*) getRawLabel(in size_t index) const {
		enforce(index < headerPtr.label_count, "index "~index.to!string~" out of bounds");
		return &labelsPtr[index];
	}
	const(RawFieldData*) getRawFieldData(in size_t offset) const {
		enforce(offset < headerPtr.field_data_count, "offset "~offset.to!string~" out of bounds");
		return cast(const RawFieldData*)(fieldDatasPtr + offset);
	}
	const(RawFieldIndices*) getRawFieldIndices(in size_t offset) const {
		enforce(offset < headerPtr.field_indices_count, "offset "~offset.to!string~" out of bounds");
		return cast(const RawFieldIndices*)(fieldIndicesPtr + offset);
	}
	const(RawListIndices*) getRawListIndices(in size_t offset) const {
		enforce(offset < headerPtr.list_indices_count, "offset "~offset.to!string~" out of bounds");
		return cast(const RawListIndices*)(listIndicesPtr + offset);
	}

	void parse(Gff gff){
		gff.fileType = headerPtr.file_type.to!string;
		gff.fileVersion = headerPtr.file_version.to!string;
		gff.root = buildStruct(0);
	}

	GffStruct buildStruct(size_t structIndex){
		GffStruct ret;

		auto s = getRawStruct(structIndex);
		ret.id = s.id;

		version(gff_verbose_parse){
			stderr.writefln("%sParsing struct: index=%d %s",
				gff_verbose_rtIndent, structIndex, *s
			);
			gff_verbose_rtIndent ~= "│ ";
		}

		if(s.field_count==1){
			const fieldIndex = s.data_or_data_offset;

			auto f = getRawField(fieldIndex);
			const label = charArrayToString(getRawLabel(f.label_index).value);
			version(gff_verbose_parse){
				stderr.writefln("%s%d: %s ↴",
					gff_verbose_rtIndent, 0, label
				);
				gff_verbose_rtIndent ~= "   ";
			}
			ret.dirtyAppendKeyValue(label, buildValue(fieldIndex));
			version(gff_verbose_parse) gff_verbose_rtIndent = gff_verbose_rtIndent[0 .. $ - 3];
		}
		else if(s.field_count > 1){
			auto fi = getRawFieldIndices(s.data_or_data_offset);

			foreach(i ; 0 .. s.field_count){
				const fieldIndex = fi[i].field_index;
				auto f = getRawField(fieldIndex);
				const label = charArrayToString(getRawLabel(f.label_index).value);

				version(gff_verbose_parse){
					stderr.writefln("%s%d: %s ↴",
						gff_verbose_rtIndent, i, label
					);
					gff_verbose_rtIndent ~= "   ";
				}

				ret.dirtyAppendKeyValue(label, buildValue(fieldIndex));

				version(gff_verbose_parse) gff_verbose_rtIndent = gff_verbose_rtIndent[0 .. $ - 3];
			}
		}

		version(gff_verbose_parse) gff_verbose_rtIndent = gff_verbose_rtIndent[0 .. $ - 4];

		return ret;
	}


	GffList buildList(size_t listIndex){
		GffList ret;
		auto li = getRawListIndices(listIndex);
		if(li.length>0){
			const indices = &li.first_struct_index;

			ret.length = li.length;
			foreach(i, ref gffStruct ; ret){
				gffStruct = buildStruct(indices[i]);
			}
		}
		return ret;
	}

	GffValue buildValue(size_t fieldIndex){
		GffValue ret;
		auto f = getRawField(fieldIndex);

		version(gff_verbose_parse){
			stderr.writefln("%sParsing value: type=%s fieldIndex=%d field=%s",
				gff_verbose_rtIndent, f.type.to!GffType, fieldIndex, *f,
			);
			gff_verbose_rtIndent ~= "│ ";
		}

		final switch(f.type) with(GffType){
			case Invalid: assert(0, "Invalid value type");

			case Byte:  ret.value = *cast(GffByte*) &f.data_or_data_offset; break;
			case Char:  ret.value = *cast(GffChar*) &f.data_or_data_offset; break;
			case Word:  ret.value = *cast(GffWord*) &f.data_or_data_offset; break;
			case Short: ret.value = *cast(GffShort*)&f.data_or_data_offset; break;
			case DWord: ret.value = *cast(GffDWord*)&f.data_or_data_offset; break;
			case Int:   ret.value = *cast(GffInt*)  &f.data_or_data_offset; break;
			case Float: ret.value = *cast(GffFloat*)&f.data_or_data_offset; break;

			case DWord64:
			case Int64:
			case Double:
				const d = getRawFieldData(f.data_or_data_offset);
				switch(f.type){
					case DWord64: ret.value = *cast(GffDWord64*)d; break;
					case Int64:   ret.value = *cast(GffInt64*)  d; break;
					case Double:  ret.value = *cast(GffDouble*) d; break;
					default: assert(0);
				}
				break;

			case String:
				const data = getRawFieldData(f.data_or_data_offset);
				const size = cast(const uint32_t*)data;
				const chars = cast(const char*)(data + uint32_t.sizeof);
				ret.value = chars[0..*size].idup;
				break;

			case ResRef:
				const data = getRawFieldData(f.data_or_data_offset);
				const size = cast(const uint8_t*)data;
				const chars = cast(const char*)(data + uint8_t.sizeof);
				ret.value = GffResRef(chars[0..*size].idup);
				break;

			case LocString:
				const data = getRawFieldData(f.data_or_data_offset);
				const str_ref = cast(const uint32_t*)(data+uint32_t.sizeof);
				const str_count = cast(const uint32_t*)(data+2*uint32_t.sizeof);
				auto sub_str = cast(void*)(data+3*uint32_t.sizeof);

				auto val = GffLocString(*str_ref);
				foreach(i ; 0 .. *str_count){
					const id = cast(const int32_t*)sub_str;
					const length = cast(const int32_t*)(sub_str+uint32_t.sizeof);
					const str = cast(const char*)(sub_str+2*uint32_t.sizeof);

					val.strings[*id] = str[0..*length].idup;
					sub_str += 2*uint32_t.sizeof + char.sizeof*(*length);
				}
				ret.value = val;
				break;

			case Void:
				const data = getRawFieldData(f.data_or_data_offset);
				const size = cast(const uint32_t*)data;
				const dataVoid = cast(const ubyte*)(data+uint32_t.sizeof);
				ret.value = dataVoid[0..*size].dup;
				break;

			case Struct:
				ret.value = buildStruct(f.data_or_data_offset);
				break;

			case List:
				ret.value = buildList(f.data_or_data_offset);
				break;

		}
		version(gff_verbose_parse) gff_verbose_rtIndent = gff_verbose_rtIndent[0..$-4];
		return ret;
	}
	string dumpRawGff() const{
		import std.string: center, rightJustify, toUpper;
		import nwnlibd.parseutils;

		string ret;

		void printTitle(in string title){
			ret ~= "======================================================================================\n";
			ret ~= title.toUpper.center(86)~"\n";
			ret ~= "======================================================================================\n";
		}

		printTitle("header");
		with(headerPtr){
			ret ~= "'"~file_type~"'    '"~file_version~"'\n";
			ret ~= "struct:        offset="~struct_offset.to!string~"  count="~struct_count.to!string~"\n";
			ret ~= "field:         offset="~field_offset.to!string~"  count="~field_count.to!string~"\n";
			ret ~= "label:         offset="~label_offset.to!string~"  count="~label_count.to!string~"\n";
			ret ~= "field_data:    offset="~field_data_offset.to!string~"  count="~field_data_count.to!string~"\n";
			ret ~= "field_indices: offset="~field_indices_offset.to!string~"  count="~field_indices_count.to!string~"\n";
			ret ~= "list_indices:  offset="~list_indices_offset.to!string~"  count="~list_indices_count.to!string~"\n";
		}
		printTitle("structs");
		foreach(id, ref a ; structsPtr[0..headerPtr.struct_count])
			ret ~= id.to!string.rightJustify(4)~" >"
				~"  id="~a.id.to!string
				~"  dodo="~a.data_or_data_offset.to!string
				~"  fc="~a.field_count.to!string
				~"\n";

		printTitle("fields");
		foreach(id, ref a ; fieldsPtr[0..headerPtr.field_count])
			ret ~= id.to!string.rightJustify(4)~" >"
				~"  type="~a.type.to!string
				~"  lbl="~a.label_index.to!string
				~"  dodo="~a.data_or_data_offset.to!string
				~"\n";

		printTitle("labels");
		foreach(id, ref a ; labelsPtr[0..headerPtr.label_count])
			ret ~= id.to!string.rightJustify(4)~" > "~a.to!string~"\n";

		printTitle("field data");
		ret ~= dumpByteArray(cast(ubyte[])fieldDatasPtr[0..headerPtr.field_data_count]);

		printTitle("field indices");
		ret ~= dumpByteArray(cast(ubyte[])fieldIndicesPtr[0..headerPtr.field_indices_count]);

		printTitle("list indices");
		ret ~= dumpByteArray(cast(ubyte[])listIndicesPtr[0..headerPtr.list_indices_count]);

		return ret;
	}

	version(gff_verbose_parse) string gff_verbose_rtIndent;
}

private struct GffRawSerializer{
	GffRawParser.RawHeader   header;
	GffRawParser.RawStruct[] structs;
	GffRawParser.RawField[]  fields;
	GffRawParser.RawLabel[]  labels;
	ubyte[]     fieldDatas;
	ubyte[]     fieldIndices;
	ubyte[]     listIndices;

	uint32_t[string]  knownLabels;
	version(gff_verbose_ser) string gff_verbose_rtIndent;

	uint32_t registerStruct(in GffStruct gffStruct){
		immutable createdStructIndex = cast(uint32_t)structs.length;
		structs ~= GffRawParser.RawStruct();

		immutable fieldCount = cast(uint32_t)gffStruct.length;
		structs[createdStructIndex].id = gffStruct.id;
		structs[createdStructIndex].field_count = fieldCount;


		version(gff_verbose_ser){
			stderr.writeln(gff_verbose_rtIndent,
				"Registering struct id=",createdStructIndex,
				"(type=",structs[createdStructIndex].type,", fields_count=",structs[createdStructIndex].field_count,")");
			gff_verbose_rtIndent ~= "│ ";
		}

		if(fieldCount == 1){
			//index in field array
			auto child = &gffStruct.byKeyValue[0];
			immutable fieldId = registerField(child.key, child.value);
			structs[createdStructIndex].data_or_data_offset = fieldId;
		}
		else if(fieldCount>1){
			//byte offset in field indices array
			immutable fieldIndicesIndex = cast(uint32_t)fieldIndices.length;
			structs[createdStructIndex].data_or_data_offset = fieldIndicesIndex;

			fieldIndices.length += uint32_t.sizeof * fieldCount;
			foreach(i, ref kv ; gffStruct.byKeyValue){

				immutable fieldId = registerField(kv.key, kv.value);

				immutable offset = fieldIndicesIndex + i * uint32_t.sizeof;
				fieldIndices[offset..offset+uint32_t.sizeof] = cast(ubyte[])(cast(uint32_t*)&fieldId)[0..1];
			}
		}
		else{
			structs[createdStructIndex].data_or_data_offset = -1;
		}

		version(gff_verbose_ser) gff_verbose_rtIndent = gff_verbose_rtIndent[0..$-4];
		return createdStructIndex;
	}

	uint32_t registerField(in string label, in GffValue value){
		immutable createdFieldIndex = cast(uint32_t)fields.length;
		fields ~= GffRawParser.RawField(value.type);

		version(gff_verbose_ser){
			stderr.writefln("%sRegistering field id=%d: %s %s = %s",
				gff_verbose_rtIndent, createdFieldIndex, value.type, label, value
			);
			gff_verbose_rtIndent ~= "│ ";
		}

		enforce(label.length <= 16, "Label too long");//TODO: Throw exception on GffNode.label set

		if(auto i = (label in knownLabels)){
			fields[createdFieldIndex].label_index = *i;
		}
		else{
			fields[createdFieldIndex].label_index = cast(uint32_t)labels.length;
			knownLabels[label] = cast(uint32_t)labels.length;
			labels ~= GffRawParser.RawLabel(label.stringToCharArray!(char[16]));
		}

		final switch(value.type) with(GffType){
			case Invalid: assert(0, "type has not been set");

			//cast is ok because all those types are <= 32bit
			case Byte:  fields[createdFieldIndex].data_or_data_offset = *cast(uint32_t*)&value.get!GffByte(); break;
			case Char:  fields[createdFieldIndex].data_or_data_offset = *cast(uint32_t*)&value.get!GffChar(); break;
			case Word:  fields[createdFieldIndex].data_or_data_offset = *cast(uint32_t*)&value.get!GffWord(); break;
			case Short: fields[createdFieldIndex].data_or_data_offset = *cast(uint32_t*)&value.get!GffShort(); break;
			case DWord: fields[createdFieldIndex].data_or_data_offset = *cast(uint32_t*)&value.get!GffDWord(); break;
			case Int:   fields[createdFieldIndex].data_or_data_offset = *cast(uint32_t*)&value.get!GffInt(); break;
			case Float: fields[createdFieldIndex].data_or_data_offset = *cast(uint32_t*)&value.get!GffFloat(); break;

			case DWord64:
			case Int64:
			case Double:
				fields[createdFieldIndex].data_or_data_offset = cast(uint32_t)fieldDatas.length;
				switch(value.type){
					case DWord64: fieldDatas ~= cast(ubyte[])(&value.get!GffDWord64())[0..1].dup; break;
					case Int64:   fieldDatas ~= cast(ubyte[])(&value.get!GffInt64())[0..1].dup; break;
					case Double:  fieldDatas ~= cast(ubyte[])(&value.get!GffDouble())[0..1].dup; break;
					default: assert(0);
				}
				break;

			case String:
				immutable strLen = cast(uint32_t)value.get!GffString.length;

				fields[createdFieldIndex].data_or_data_offset = cast(uint32_t)fieldDatas.length;
				fieldDatas ~= cast(ubyte[])(&strLen)[0..1].dup;
				fieldDatas ~= (cast(ubyte*)value.get!GffString.ptr)[0..strLen].dup;
				break;
			case ResRef:
				enforce(value.get!GffResRef.length <= 32, "Resref too long (max length: 32 characters)");
				immutable strLen = cast(uint8_t)value.get!GffResRef.length;

				fields[createdFieldIndex].data_or_data_offset = cast(uint32_t)fieldDatas.length;
				fieldDatas ~= cast(ubyte[])(&strLen)[0..1].dup;
				fieldDatas ~= (cast(ubyte*)value.get!GffResRef.ptr)[0..strLen].dup;
				break;
			case LocString:
				immutable fieldDataIndex = fieldDatas.length;
				fields[createdFieldIndex].data_or_data_offset = cast(uint32_t)fieldDataIndex;

				//total size
				fieldDatas ~= [0,0,0,0];//uint32_t

				immutable strref = cast(uint32_t)value.get!GffLocString.strref;
				fieldDatas ~= cast(ubyte[])(&strref)[0..1].dup;

				immutable strcount = cast(uint32_t)value.get!GffLocString.strings.length;
				fieldDatas ~= cast(ubyte[])(&strcount)[0..1].dup;

				import std.algorithm: sort;
				import std.array: array;
				foreach(locstr ; value.get!GffLocString.strings.byKeyValue.array.sort!((a,b)=>a.key<b.key)){
					immutable key = cast(int32_t)locstr.key;
					fieldDatas ~= cast(ubyte[])(&key)[0..1].dup;//string id

					immutable length = cast(int32_t)locstr.value.length;
					fieldDatas ~= cast(ubyte[])(&length)[0..1].dup;

					fieldDatas ~= cast(ubyte[])locstr.value.ptr[0..length].dup;
				}

				//total size
				immutable totalSize = cast(uint32_t)(fieldDatas.length-fieldDataIndex) - 4;//totalSize does not count first 4 bytes
				fieldDatas[fieldDataIndex..fieldDataIndex+4] = cast(ubyte[])(&totalSize)[0..1].dup;
				break;
			case Void:
				auto dataLength = cast(uint32_t)value.get!GffVoid.length;
				fields[createdFieldIndex].data_or_data_offset = cast(uint32_t)fieldDatas.length;
				fieldDatas ~= cast(ubyte[])(&dataLength)[0..1];
				fieldDatas ~= value.get!GffVoid;
				break;
			case Struct:
				immutable structId = registerStruct(value.get!GffStruct);
				fields[createdFieldIndex].data_or_data_offset = structId;
				break;
			case List:
				immutable createdListOffset = cast(uint32_t)listIndices.length;
				fields[createdFieldIndex].data_or_data_offset = createdListOffset;

				uint32_t listLength = cast(uint32_t)value.get!GffList.length;
				listIndices ~= cast(ubyte[])(&listLength)[0..1];
				listIndices.length += listLength * uint32_t.sizeof;
				if(value.get!GffList !is null){
					foreach(i, ref field ; value.get!GffList){
						immutable offset = createdListOffset+uint32_t.sizeof*(i+1);

						uint32_t structIndex = registerStruct(field);
						listIndices[offset..offset+uint32_t.sizeof] = cast(ubyte[])(&structIndex)[0..1];
					}

				}
				break;
		}
		version(gff_verbose_ser) gff_verbose_rtIndent = gff_verbose_rtIndent[0..$-4];
		return createdFieldIndex;
	}

	ubyte[] serialize(Gff gff){
		registerStruct(gff.root);

		enforce(gff.fileType.length <= 4);
		header.file_type = "    ";
		header.file_type[0..gff.fileType.length] = gff.fileType.dup;

		enforce(gff.fileVersion.length <= 4);
		header.file_version = "    ";
		header.file_version[0..gff.fileVersion.length] = gff.fileVersion.dup;

		uint32_t offset = cast(uint32_t)GffRawParser.RawHeader.sizeof;

		header.struct_offset = offset;
		header.struct_count = cast(uint32_t)structs.length;
		offset += GffRawParser.RawStruct.sizeof * structs.length;

		header.field_offset = offset;
		header.field_count = cast(uint32_t)fields.length;
		offset += GffRawParser.RawField.sizeof * fields.length;

		header.label_offset = offset;
		header.label_count = cast(uint32_t)labels.length;
		offset += GffRawParser.RawLabel.sizeof * labels.length;

		header.field_data_offset = offset;
		header.field_data_count = cast(uint32_t)fieldDatas.length;
		offset += fieldDatas.length;

		header.field_indices_offset = offset;
		header.field_indices_count = cast(uint32_t)fieldIndices.length;
		offset += fieldIndices.length;

		header.list_indices_offset = offset;
		header.list_indices_count = cast(uint32_t)listIndices.length;
		offset += listIndices.length;


		version(unittest) auto offsetCheck = 0;
		ubyte[] data;
		data.reserve(offset);
		data ~= cast(ubyte[])(&header)[0..1];
		version(unittest) offsetCheck += GffRawParser.RawHeader.sizeof;
		version(unittest) assert(data.length == offsetCheck);
		data ~= cast(ubyte[])structs;
		version(unittest) offsetCheck += structs.length * GffRawParser.RawStruct.sizeof;
		version(unittest) assert(data.length == offsetCheck);
		data ~= cast(ubyte[])fields;
		version(unittest) offsetCheck += fields.length * GffRawParser.RawStruct.sizeof;
		version(unittest) assert(data.length == offsetCheck);
		data ~= cast(ubyte[])labels;
		version(unittest) offsetCheck += labels.length * GffRawParser.RawLabel.sizeof;
		version(unittest) assert(data.length == offsetCheck);
		data ~= cast(ubyte[])fieldDatas;
		version(unittest) offsetCheck += fieldDatas.length;
		version(unittest) assert(data.length == offsetCheck);
		data ~= fieldIndices;
		version(unittest) offsetCheck += fieldIndices.length;
		version(unittest) assert(data.length == offsetCheck);
		data ~= listIndices;
		version(unittest) offsetCheck += listIndices.length;
		version(unittest) assert(data.length == offsetCheck);

		assert(data.length == offset);
		return data;
	}
}



unittest{
	import std.file : read;

	immutable krogarDataOrig = cast(immutable ubyte[])import("krogar.bic");
	auto gff = new Gff(krogarDataOrig);

	//Parsing checks
	assert(gff.fileType == "BIC");
	assert(gff.fileVersion == "V3.2");
	//assert(gff.fileVersion)
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
	assert(gff["Deity"].get!GffString    == "Gorm Gulthyn");
	assert(gff["ScriptHeartbeat"].get!GffResRef       == "gb_player_heart");
	assert(gff["FirstName"].get!GffLocString.strref == -1);
	assert(gff["FirstName"].get!GffLocString.strings[0] == "Krogar");
	assert(gff["FirstName"].to!string == "Krogar");
	//assert(gff[""].get!GffVoid == );
	assert(gff["Tint_Head"]["Tintable"]["Tint"]["1"]["b"].get!GffByte == 109);
	assert(gff["ClassList"][0]["Class"].get!GffInt == 4);

	assertThrown!GffTypeException(gff["IsPC"].get!GffInt);
	assertThrown!GffTypeException(gff["ClassList"].get!GffStruct);

	// Tintable appears two times in the gff
	// Both must be stored but only the last one should be accessed by its key
	assert(gff.byKeyValue[53].key == "Tintable");
	assert(gff.byKeyValue[53].value["Tint"]["1"]["r"].get!GffByte == 255);
	assert(gff.byKeyValue[188].key == "Tintable");
	assert(gff.byKeyValue[188].value["Tint"]["1"]["r"].get!GffByte == 253);
	assert(gff["Tintable"]["Tint"]["1"]["r"].get!GffByte == 253);

	//Perfect Serialization
	auto krogarDataSerialized = gff.serialize();
	auto gffSerialized = new Gff(krogarDataSerialized);

	assert(gff.toPrettyString() == gffSerialized.toPrettyString(), "Serialization data mismatch");
	assert(krogarDataOrig == krogarDataSerialized, "Serialization not byte perfect");

	////Dup
	//auto gffRoot2 = gff.root.dup;
	//assert(gffRoot2 == gff.root);

	assertThrown!GffValueSetException(gff.fileType = "FILETYPE");
	gff.fileType = "A C";
	assert(gff.fileType == "A C");
	assertThrown!GffValueSetException(gff.fileVersion = "VERSION");
	gff.fileVersion = "V42";
	assert(gff.fileVersion == "V42");

	auto data = cast(char[])gff.serialize();
	assert(data[0..4]=="A C ");
	assert(data[4..8]=="V42 ");


	//Gff modifications
	gff["Deity"] = "Crom";
	assert(gff["Deity"].get!GffString == "Crom");

	gff["NewValue"] = GffInt(42);
	assert(gff["NewValue"].get!GffInt == 42);

	assertThrown!Error(GffResRef("this is a bit longer than 32 characters"));
	gff["ResRefExample"] = GffResRef("Hello");
	assert(gff["ResRefExample"].get!GffResRef == "Hello");
	gff["ResRefExample"].get!GffResRef = GffResRef("world");
	assert(gff["ResRefExample"].to!string == "world");

	gff["Equip_ItemList"][1] = GffStruct();
	gff["Equip_ItemList"][1]["Hello"] = "world";
	assert(gff["Equip_ItemList"][1]["Hello"].get!GffString == "world");
	assertThrown!Error(gff["Equip_ItemList"][99] = GffStruct());



	// JSON parsing /serialization
	immutable dogeDataOrig = cast(immutable ubyte[])import("doge.utc");
	auto dogeGff = new Gff(dogeDataOrig);

	// duplication fixing serializations
	auto dogeJson = dogeGff.toJson();
	auto dogeFromJson = new Gff(dogeJson);
	auto dogeFromJsonStr = new Gff(parseJSON(dogeJson.toString()));
	assert(dogeFromJson.serialize() == dogeDataOrig);
	assert(dogeFromJsonStr.serialize() == dogeDataOrig);
}
