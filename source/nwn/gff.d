module nwn.gff;


import std.stdio: File;
import std.stdint;
import std.string;
import std.conv: to;

debug import std.stdio: writeln;
version(unittest) import std.exception: assertThrown, assertNotThrown;

class GffValueSetException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
class GffTypeException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

/// Type of data stored in the GffNode
enum GffType{
	Invalid      = -1,
	Byte         = 0,
	Char         = 1,
	Word         = 2,
	Short        = 3,
	DWord        = 4,
	Int          = 5,
	DWord64      = 6,
	Int64        = 7,
	Float        = 8,
	Double       = 9,
	ExoString    = 10,
	ResRef       = 11,
	ExoLocString = 12,
	Void         = 13,
	Struct       = 14,
	List         = 15
}

template gffTypeToNative(GffType t){
	import std.typecons: Tuple;
	static if(t==GffType.Invalid)      static assert(0, "No native type for GffType.Invalid");
	static if(t==GffType.Byte)         alias gffTypeToNative = uint8_t;
	static if(t==GffType.Char)         alias gffTypeToNative = int8_t;
	static if(t==GffType.Word)         alias gffTypeToNative = uint16_t;
	static if(t==GffType.Short)        alias gffTypeToNative = int16_t;
	static if(t==GffType.DWord)        alias gffTypeToNative = uint32_t;
	static if(t==GffType.Int)          alias gffTypeToNative = int32_t;
	static if(t==GffType.DWord64)      alias gffTypeToNative = uint64_t;
	static if(t==GffType.Int64)        alias gffTypeToNative = int64_t;
	static if(t==GffType.Float)        alias gffTypeToNative = float;
	static if(t==GffType.Double)       alias gffTypeToNative = double;
	static if(t==GffType.ExoString)    alias gffTypeToNative = string;
	static if(t==GffType.ResRef)       alias gffTypeToNative = string;// length<=32
	static if(t==GffType.ExoLocString) alias gffTypeToNative = Tuple!(uint32_t,"strref", string[int32_t],"strings");
	static if(t==GffType.Void)         alias gffTypeToNative = void[];
	static if(t==GffType.Struct)       alias gffTypeToNative = GffNode[];
	static if(t==GffType.List)         alias gffTypeToNative = GffNode[];
}

struct GffNode{
	this(GffType t, string lbl=null){
		m_type = t;
		label = lbl;
	}

	@property{
		const string label(){return m_label;}
		void label(string lbl){
			if(lbl.length>16)
				throw new GffValueSetException("Labels cannot be longer than 16 characters");
			m_label = lbl;
		}
	}
	unittest{
		assertThrown!GffValueSetException(GffNode(GffType.Struct, "ThisLabelIsLongerThan16Chars"));
		auto node = GffNode(GffType.Struct, "labelok");
		assertThrown!GffValueSetException(node.label = "ThisLabelIsLongerThan16Chars");
	}

	@property const GffType type(){return m_type;}

	/// Access by reference the underlying data stored in the GffNode.
	/// The type of this data is determined by gffTypeToNative.
	/// Types must match exactly or it will throw
	const ref const(gffTypeToNative!T) as(GffType T)(){
		return cast(const)((cast(GffNode)this).as!T);
	}
	/// ditto
	ref gffTypeToNative!T as(GffType T)(){
		static assert(T!=GffType.Invalid, "Cannot use GffNode.as with type Invalid");
		if(T != type || type==GffType.Invalid)
			throw new GffTypeException("Type mismatch: GffNode of type "~type.to!string~" cannot be used with as!(GffNode."~T.to!string~")");

		with(GffType)
		static if(
			   T==Byte || T==Char
			|| T==Word || T==Short
			|| T==DWord || T==Int
			|| T==DWord64 || T==Int64
			|| T==Float || T==Double){
			return *cast(gffTypeToNative!T*)&simpleTypeContainer;
		}
		else static if(T==ExoString || T==ResRef)
			return stringContainer;
		else static if(T==ExoLocString) return exoLocStringContainer;
		else static if(T==Void)         return rawContainer;
		else static if(T==Struct || T==List)
			return aggrContainer;
		else
			static assert(0, "Type "~T.stringof~" not implemented");
	}
	unittest{
		import std.exception;
		import std.traits: EnumMembers;
		with(GffType){
			foreach(m ; EnumMembers!GffType){
				static if(m!=GffType.Invalid)
					GffNode(m).as!m;
			}

			assertThrown!GffTypeException(GffNode(GffType.Float).as!(GffType.Double));
		}
	}

	/// Convert the node value to a certain type.
	/// If the type is string, any type of value gets converted into string. Structs and lists are not expanded.
	const auto ref const(DestType) to(DestType)(){
		import std.traits;

		final switch(type) with(GffType){

			case Invalid: throw new GffTypeException("Cannot convert "~type.to!string);

			foreach(TYPE ; EnumMembers!GffType){
				static if(TYPE!=Invalid){
					case TYPE:
						alias NativeType = gffTypeToNative!TYPE;
						static if(is(DestType==NativeType) || isImplicitlyConvertible!(NativeType, DestType)){
							static if(TYPE==Void) return as!Void.dup;
							else                  return as!TYPE;
						}
						else static if(TYPE==Void && isArray!DestType && ForeachType!DestType.sizeof==1 && !isSomeString!DestType)
							return cast(DestType)as!Void.dup;
						else static if(TYPE==ExoLocString && isSomeString!DestType){
							if(exoLocStringContainer.strref!=uint32_t.max)
								return ("{{STRREF:"~exoLocStringContainer.strref.to!string~"}}").to!DestType;
							else{
								if(exoLocStringContainer.strings.length>0)
									return exoLocStringContainer.strings.values[0].to!DestType;
								return "{{INVALID_LOCSTRING}}".to!DestType;
							}
						}
						else static if(__traits(compiles, as!TYPE.to!DestType)){
							static if(TYPE==Struct && isSomeString!DestType)
								return "{{Struct}}".to!DestType;
							else static if(TYPE==List && isSomeString!DestType)
								return "{{List("~aggrContainer.length.to!string~")}}".to!string;
							else static if(TYPE==Void && isSomeString!DestType){
								string ret = "0x";
								foreach(i, b ; cast(ubyte[])rawContainer){
									ret ~= format("%s%02x", (i%2==0 && i!=0)? " ":null, b);
								}
								return ret.to!DestType;
							}
							else
								return as!TYPE.to!DestType;
						}
						else
							throw new GffTypeException("Cannot convert GffType."~type.to!string~" from "~NativeType.stringof~" to "~DestType.stringof);

				}
			}
		}
	}
	unittest{
		with(GffType){
			GffNode node;

			node = GffNode(Void);
			ubyte[] voidData = [0, 2, 5, 9, 255, 6];
			node.as!Void = voidData;
			assert(node.to!(ubyte[])[3] == 9);
			assert(node.to!(byte[])[4] == -1);
			assert(node.to!string == "0x0002 0509 ff06");
			assertThrown!GffTypeException(node.to!int);

			node = GffNode(ExoLocString);
			node.as!ExoLocString.strref = 12;
			//assert(node.to!int == 12);//TODO
			assert(node.to!string == "{{STRREF:12}}");
			node.as!ExoLocString.strref = -1;
			assert(node.to!string == "{{INVALID_LOCSTRING}}");
			node.as!ExoLocString.strings = [0: "a", 3: "b"];
			assert(node.to!string == "a");
			//assert(node.to!(string[int]) == [0: "a", 3: "b"]);//TODO
			assertThrown!GffTypeException(node.to!float);

			node = GffNode(Struct);
			assert(node.to!string == "{{Struct}}");
			assertThrown!GffTypeException(node.to!int);

			node = GffNode(List);
			node.as!List = [GffNode(Struct), GffNode(Struct)];
			assert(node.to!string == "{{List(2)}}");

			node = GffNode(Int);
			node.as!Int = 42;
			assert(node.to!byte == 42);

			node = GffNode(Invalid);
			assertThrown!GffTypeException(node.to!string);

		}
	}

	void opAssign(T)(T rhs) if(!is(T==GffNode)){
		import std.traits;

		switch(type) with(GffType){
			foreach(TYPE ; EnumMembers!GffType){
				static if(TYPE==Invalid){
					case TYPE:
					throw new GffTypeException("GffNode type is Invalid");
				}
				else static if(TYPE==ResRef){
					static if(isSomeString!T){
						case TYPE:
						immutable str = rhs.to!(gffTypeToNative!TYPE);
						if(str.length > 32)
							throw new GffValueSetException("String is too long for a ResRef (32 characters limit)");
						as!TYPE = str;
						return;
					}
				}
				else static if(TYPE==ExoLocString){
					static if(is(T==gffTypeToNative!ExoLocString)){
						case TYPE:
						as!TYPE = rhs;
						return;
					}
					static if(__traits(isIntegral, T)){
						//set strref
						case TYPE:
						as!TYPE.strref = rhs.to!uint32_t;
						return;
					}
					else static if(is(T==typeof(gffTypeToNative!ExoLocString.strings))){
						//set strings
						case TYPE:
						as!TYPE.strings = rhs;
						return;
					}
				}
				else{
					static if(isAssignable!(gffTypeToNative!TYPE, T)){
						case TYPE:
						static if(TYPE==List){
							//Check if all nodes are structs
							foreach(ref s ; rhs){
								if(s.type != GffType.Struct)
									throw new GffValueSetException("The list contains one or more GffNode that is not a struct");
							}
						}
						as!TYPE = rhs;
						static if(TYPE==Struct)
							updateFieldLabelMap();
						return;
					}
					else static if(
						   (isScalarType!T && isScalarType!(gffTypeToNative!TYPE))
						|| (isSomeString!T && isSomeString!(gffTypeToNative!TYPE))){
						case TYPE:
						as!TYPE = rhs.to!(gffTypeToNative!TYPE);
						return;
					}
				}
			}
			default: break;
		}

		throw new GffValueSetException("Cannot set GffNode of type "~type.to!string~" with "~rhs.to!string~" of type "~T.stringof);
	}
	unittest{
		with(GffType){
			auto node = GffNode(Byte);
			assertThrown!ConvOverflowException(node = -1);
			assertThrown!ConvOverflowException(node = 256);
			assertThrown!GffValueSetException(node = "somestring");
			node = 42;
			assert(node.as!(Byte) == 42);

			node = GffNode(Char);
			assertThrown!ConvOverflowException(node = -129);
			assertThrown!ConvOverflowException(node = 128);
			assertThrown!GffValueSetException(node = "somestring");
			node = 'a';
			node = 'z';
			assert(node.as!(Char) == 'z');

			node = GffNode(ExoString);
			node = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.";
			node = "Hello";
			assert(node.stringContainer == "Hello");

			node = GffNode(ResRef);
			assertThrown!GffValueSetException(node = "This text is longer than 32 characters");
			assertThrown!GffValueSetException(node = 42);
			node = "HelloWorld";
			assert(node.stringContainer == "HelloWorld");

			node = GffNode(ExoLocString);
			node = 1337;//set strref
			node = [0: "English guy", 1: "English girl", 3: "French girl"];
			assert(node.exoLocStringContainer.strref == 1337);
			assert(node.exoLocStringContainer.strings.length == 3);
			assert(node.exoLocStringContainer.strings[0] == "English guy");
			assert(node.exoLocStringContainer.strings[3] == "French girl");

			node = GffNode(Void);
			ubyte[] data = [0,1,2,3,4,5,6];
			node = data;
			assert((cast(ubyte[])node.rawContainer)[3] == 3);

			node = GffNode(Struct);
			node = [
				GffNode(Byte, "TestByte"),
				GffNode(ExoString, "TestExoString"),
			];
			assertNotThrown(node["TestByte"]);
			assertNotThrown(node["TestExoString"]);

			auto listStructs = [
				GffNode(Struct, "StructA"),
				GffNode(Struct, "StructB"),
			];
			listStructs[0].as!(Struct) ~= GffNode(Int, "TestInt");
			listStructs[0].as!(Struct) ~= GffNode(Float, "TestFloat");
			listStructs[0].updateFieldLabelMap();
			listStructs[0]["TestInt"] = 6;
			listStructs[0]["TestFloat"] = float.epsilon;
			listStructs[1].as!(Struct) ~= GffNode(Void, "TestVoid");
			listStructs[1].updateFieldLabelMap();

			node = GffNode(List);
			node = listStructs;
			assertNotThrown(node[0]);
			assertNotThrown(node[0]["TestInt"]);
			assert(node[0]["TestInt"].as!(Int) == 6);
			assertNotThrown(node[0]["TestFloat"]);
			assert(node[0]["TestFloat"].as!(Float) == float.epsilon);
			assertNotThrown(node[1]);
			assertNotThrown(node[1]["TestVoid"]);
			assertThrown!GffValueSetException(node = [GffNode(Byte, "TestByte")]);

			node = GffNode(Invalid);
			assertThrown!GffTypeException(node = 5);
		}
	}

	const ref const(GffNode) opIndex(in string label){
		return (cast(GffNode)this).opIndex(label);
	}
	const ref const(GffNode) opIndex(in size_t index){
		return (cast(GffNode)this).opIndex(index);
	}

	ref GffNode opIndex(in string label){
		if(type!=GffType.Struct)
			throw new GffTypeException("Not a struct");

		auto index = label in structLabelMap;
		if(!index){
			//Try to find it by updating the label map
			updateFieldLabelMap();
			return aggrContainer[structLabelMap[label]];
		}
		return aggrContainer[*index];
	}
	ref GffNode opIndex(in size_t index){
		if(type!=GffType.List)
			throw new GffTypeException("Not a list");

		return aggrContainer[index];
	}
	unittest{
		with(GffType){
			GffNode node;
			const(GffNode)* constNode;

			node = GffNode(Struct);
			constNode = &node;
			node = [GffNode(Byte, "TestByte"), GffNode(Float, "TestFloat")];

			assertNotThrown((*constNode)["TestByte"]);
			assertNotThrown((*constNode)["TestFloat"]);
			assertThrown!Error((*constNode)["yoloooo"]);
			assertThrown!GffTypeException((*constNode)[0]);

			node = GffNode(List);
			constNode = &node;
			node = [GffNode(Struct), GffNode(Struct)];
			assertNotThrown((*constNode)[0]);
			assertNotThrown((*constNode)[1]);
			assertThrown!Error((*constNode)[2]);
			assertThrown!GffTypeException((*constNode)["yoloooo"]);


			node = GffNode(Void);
			assertThrown!GffTypeException(node["any"]);
		}
	}

	/// Produces a readable string of the node and its children
	const string toPrettyString(){

		string toPrettyStringInternal(const(GffNode)* node, string tabs){
			import std.string: leftJustify;

			if(node.type == GffType.Struct){
				string ret = tabs~"("~node.type.to!string~")";
				if(node.label !is null)
					ret ~= " "~node.label;
				ret ~= "\n";
				foreach(ref childNode ; node.aggrContainer){
					ret ~= toPrettyStringInternal(&childNode, tabs~"   | ");
				}
				return ret;
			}
			else if(node.type == GffType.List){
				string ret = tabs~node.label.leftJustify(16)~": ("~node.type.to!string~")\n";
				foreach(ref childNode ; node.aggrContainer){
					ret ~= toPrettyStringInternal(&childNode, tabs~"   | ");
				}
				return ret;
			}
			else if(node.type == GffType.Invalid){
				return tabs~node.label.leftJustify(16)~": {{INVALID}}\n";
			}
			else{
				return tabs~node.label.leftJustify(16)~": "~node.to!string~" ("~node.type.to!string~")\n";
			}
		}


		return toPrettyStringInternal(&this, "");
	}

	/// Updates the structLabelMap for struct fields lookup.
	/// Should be called each time the struct field list is modified or a field's label is modified
	void updateFieldLabelMap(){
		if(type != GffType.Struct)
			throw new GffTypeException(__FUNCTION__~" can only be called on a GffNode of type Struct");

		structLabelMap.clear();
		foreach(index, ref node ; aggrContainer){
			structLabelMap[node.label] = index;
		}
		structLabelMap.rehash();
	}
	unittest{
		auto node = GffNode(GffType.Int64);
		assertThrown!GffTypeException(node.updateFieldLabelMap);
	}


package:
	GffType m_type = GffType.Invalid;
	string m_label;
	void[] rawContainer;
	uint64_t simpleTypeContainer;
	string stringContainer;
	GffNode[] aggrContainer;
	size_t[string] structLabelMap;
	gffTypeToNative!(GffType.ExoLocString) exoLocStringContainer;
	uint32_t structType = 0;
}

class Gff{

	this(){}

	this(in string path){
		import std.file : read;
		this(path.read());
	}
	this(in void[] data){
		auto parser = Parser(data.ptr);
		version(gff_verbose) parser.printData();

		import std.string: stripRight;
		m_fileType = parser.headerPtr.file_type.stripRight;
		m_fileVersion = parser.headerPtr.file_version.stripRight;

		parser.buildNodeFromStructInPlace(0, &firstNode);
	}
	this(File stream){
		void[] data;
		data.length = GffHeader.sizeof;
		stream.rawRead(data);

		GffHeader* header = cast(GffHeader*)data.ptr;
		immutable size_t fileLength =
			header.list_indices_offset + header.list_indices_count;

		data.length = fileLength;
		stream.rawRead(data[GffHeader.sizeof..$]);

		this(data);
	}

	@property{
		const string fileType(){return m_fileType;}
		void fileType(in string type){
			if(type.length>4)
				throw new GffValueSetException("fileType length must be <= 4");
			m_fileType = type;
		}
		const string fileVersion(){return m_fileVersion;}
		void fileVersion(in string ver){
			if(ver.length>4)
				throw new GffValueSetException("fileVersion length must be <= 4");
			m_fileVersion = ver;
		}
	}


	alias firstNode this;
	GffNode firstNode;


	void[] serialize(){
		Serializer serializer;
		serializer.registerStruct(&firstNode);
		return serializer.serialize(m_fileType, m_fileVersion);
	}

private:
	string m_fileType, m_fileVersion;

	align(1) struct GffHeader{
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
	align(1) struct GffStruct{
		uint32_t type;
		uint32_t data_or_data_offset;
		uint32_t field_count;
	}
	align(1) struct GffField{
		uint32_t type;
		uint32_t label_index;
		uint32_t data_or_data_offset;
	}
	align(1) struct GffLabel{
		char[16] value;
	}
	align(1) struct GffFieldData{
		uint8_t first_data;//First byte of data. Other follows
	}
	align(1) struct GffFieldIndices{
		uint32_t field_index;
	}
	align(1) struct GffListIndices{
		uint32_t length;
		uint32_t first_struct_index;
	}

	struct Parser{
		@disable this();
		this(const(void)* rawData){
			headerPtr       = cast(immutable GffHeader*)      (rawData);
			structsPtr      = cast(immutable GffStruct*)      (rawData + headerPtr.struct_offset);
			fieldsPtr       = cast(immutable GffField*)       (rawData + headerPtr.field_offset);
			labelsPtr       = cast(immutable GffLabel*)       (rawData + headerPtr.label_offset);
			fieldDatasPtr   = cast(immutable GffFieldData*)   (rawData + headerPtr.field_data_offset);
			fieldIndicesPtr = cast(immutable GffFieldIndices*)(rawData + headerPtr.field_indices_offset);
			listIndicesPtr  = cast(immutable GffListIndices*) (rawData + headerPtr.list_indices_offset);
		}

		immutable GffHeader*       headerPtr;
		immutable GffStruct*       structsPtr;
		immutable GffField*        fieldsPtr;
		immutable GffLabel*        labelsPtr;
		immutable GffFieldData*    fieldDatasPtr;
		immutable GffFieldIndices* fieldIndicesPtr;
		immutable GffListIndices*  listIndicesPtr;

		immutable(GffStruct*) getStruct(in size_t index){
			assert(index < headerPtr.struct_count, "index "~index.to!string~" out of bounds");
			return &structsPtr[index];
		}
		immutable(GffField*) getField(in size_t index){
			assert(index < headerPtr.field_count, "index "~index.to!string~" out of bounds");
			return &fieldsPtr[index];
		}
		immutable(GffLabel*) getLabel(in size_t index){
			assert(index < headerPtr.label_count, "index "~index.to!string~" out of bounds");
			return &labelsPtr[index];
		}
		immutable(GffFieldData*) getFieldData(in size_t offset){
			assert(offset < headerPtr.field_data_count, "offset "~offset.to!string~" out of bounds");
			return cast(immutable GffFieldData*)(cast(void*)fieldDatasPtr + offset);
		}
		immutable(GffFieldIndices*) getFieldIndices(in size_t offset){
			assert(offset < headerPtr.field_indices_count, "offset "~offset.to!string~" out of bounds");
			return cast(immutable GffFieldIndices*)(cast(void*)fieldIndicesPtr + offset);
		}
		immutable(GffListIndices*) getListIndices(in size_t offset){
			assert(offset < headerPtr.list_indices_count, "offset "~offset.to!string~" out of bounds");
			return cast(immutable GffListIndices*)(cast(void*)listIndicesPtr + offset);
		}

		version(gff_verbose) string gff_verbose_rtIndent;

		void buildNodeFromStructInPlace(in size_t structIndex, GffNode* destNode){
			destNode.m_type = GffType.Struct;

			auto s = getStruct(structIndex);
			destNode.structType = s.type;

			version(gff_verbose){
				writeln(gff_verbose_rtIndent, "Parsing struct: id=",structIndex,
					" dodo=", s.data_or_data_offset,
					" field_count=", s.field_count,
					" type=",s.type);
				gff_verbose_rtIndent ~= "│ ";
			}

			if(s.field_count==1){
				destNode.aggrContainer.length++;
				GffNode* field = &destNode.aggrContainer[0];

				buildNodeFromFieldInPlace(s.data_or_data_offset, field);
				destNode.structLabelMap[field.label] = 0;
			}
			else if(s.field_count > 1){
				auto fi = getFieldIndices(s.data_or_data_offset);

				destNode.aggrContainer.length = s.field_count;

				foreach(i, ref field ; destNode.aggrContainer)
					buildNodeFromFieldInPlace(fi[i].field_index, &field);

				foreach(i, ref field ; destNode.aggrContainer)
					destNode.structLabelMap[field.label] = i;
			}

			version(gff_verbose) gff_verbose_rtIndent = gff_verbose_rtIndent[0..$-4];
		}

		void buildNodeFromListInPlace(in size_t listIndex, GffNode* destList){
			destList.m_type = GffType.List;

			auto li = getListIndices(listIndex);
			if(li.length>0){
				immutable uint32_t* indices = &li.first_struct_index;

				destList.aggrContainer.length = li.length;

				foreach(i, ref structNode ; destList.aggrContainer){
					buildNodeFromStructInPlace(indices[i], &structNode);
				}
			}
		}


		void buildNodeFromFieldInPlace(in size_t fieldIndex, GffNode* destField){
			import std.typetuple: TypeTuple;
			auto ref string parseLabel(in uint32_t labelIndex){
				immutable lbl = getLabel(labelIndex).value;
				if(lbl[$-1]=='\0') return lbl.ptr.fromStringz.idup;
				else               return lbl.idup;
			}

			try{
				import std.conv : to;
				immutable f = getField(fieldIndex);

				destField.m_type = cast(GffType)f.type;
				destField.label = parseLabel(f.label_index);

				version(gff_verbose){
					writeln(gff_verbose_rtIndent, "Parsing  field: '", destField.label,
						"' (",destField.type,
						", id=",fieldIndex,
						", dodo:",f.data_or_data_offset,")");
					gff_verbose_rtIndent ~= "│ ";
				}

				typeswitch:
				final switch(destField.type) with(GffType){
					case Invalid: assert(0, "type has not been set");

					foreach(TYPE ; TypeTuple!(Byte,Char,Word,Short,DWord,Int,Float)){
						case TYPE:
							alias NativeType = gffTypeToNative!TYPE;
							*cast(NativeType*)&destField.simpleTypeContainer = *cast(NativeType*)&f.data_or_data_offset;
							break typeswitch;
					}
					foreach(TYPE ; TypeTuple!(DWord64,Int64,Double)){
						case TYPE:
							alias NativeType = gffTypeToNative!TYPE;
							immutable d = getFieldData(f.data_or_data_offset);
							*cast(NativeType*)&destField.simpleTypeContainer = cast(NativeType)d;
							break typeswitch;
					}
					case ExoString:
						immutable data = getFieldData(f.data_or_data_offset);
						immutable size = cast(immutable uint32_t*)data;
						immutable chars = cast(immutable char*)(data+uint32_t.sizeof);

						destField.stringContainer = chars[0..*size].idup;
						break;
					case ResRef:
						immutable data = getFieldData(f.data_or_data_offset);
						immutable size = cast(immutable uint8_t*)data;
						immutable chars = cast(immutable char*)(data+uint8_t.sizeof);

						destField.stringContainer = chars[0..*size].idup;
						break;

					case ExoLocString:
						immutable data = getFieldData(f.data_or_data_offset);
						//immutable total_size = cast(uint32_t*)data;
						immutable str_ref = cast(immutable uint32_t*)(data+uint32_t.sizeof);
						immutable str_count = cast(immutable uint32_t*)(data+2*uint32_t.sizeof);
						auto sub_str = cast(void*)(data+3*uint32_t.sizeof);

						destField.exoLocStringContainer.strref = *str_ref;

						foreach(i ; 0 .. *str_count){
							immutable id = cast(immutable int32_t*)sub_str;
							immutable length = cast(immutable int32_t*)(sub_str+uint32_t.sizeof);
							immutable str = cast(immutable char*)(sub_str+2*uint32_t.sizeof);

							destField.exoLocStringContainer.strings[*id] = str[0..*length].idup;
							sub_str += 2*uint32_t.sizeof + char.sizeof*(*length);
						}
						break;

					case Void:
						immutable data = getFieldData(f.data_or_data_offset);
						immutable size = cast(immutable uint32_t*)data;
						immutable dataVoid = cast(immutable void*)(data+uint32_t.sizeof);

						destField.rawContainer = dataVoid[0..*size].dup;
						break;

					case Struct:
						buildNodeFromStructInPlace(f.data_or_data_offset, destField);
						break;

					case List:
						buildNodeFromListInPlace(f.data_or_data_offset, destField);
						break;
				}
				version(gff_verbose) gff_verbose_rtIndent = gff_verbose_rtIndent[0..$-4];
			}
			catch(Throwable t){
				if(t.msg.length==0 || t.msg[0] != '@'){
					t.msg = "@"~destField.label~": "~t.msg;
				}
				throw t;
			}
		}

		version(gff_verbose)
		void printData(){
			import std.string: center, rightJustify, toUpper;
			import std.algorithm: chunkBy;
			import std.stdio: write;

			void printTitle(in string title){
				writeln("============================================================");
				writeln(title.toUpper.center(60));
				writeln("============================================================");
			}
			void printByteArray(in void* byteArray, size_t length){
				foreach(i ; 0..20){
					if(i==0)write("    / ");
					write(i.to!string.rightJustify(4, '_'));
				}
				writeln();
				foreach(i ; 0..length){
					auto ptr = cast(void*)byteArray + i;
					if(i%20==0)write((i/10).to!string.rightJustify(3), " > ");
					write((*cast(ubyte*)ptr).to!string.rightJustify(4));
					if(i%20==19)writeln();
				}
				writeln();
			}

			printTitle("header");
			with(headerPtr){
				writeln("'",file_type, "'    '",file_version,"'");
				writeln("struct: ",struct_offset," ",struct_count);
				writeln("field: ",field_offset," ",field_count);
				writeln("label: ",label_offset," ",label_count);
				writeln("field_data: ",field_data_offset," ",field_data_count);
				writeln("field_indices: ",field_indices_offset," ",field_indices_count);
				writeln("list_indices: ",list_indices_offset," ",list_indices_count);
			}
			printTitle("structs");
			foreach(id, ref a ; structsPtr[0..headerPtr.struct_count])
				writeln(id.to!string.rightJustify(4), " > ",a);

			printTitle("fields");
			foreach(id, ref a ; fieldsPtr[0..headerPtr.field_count])
				writeln(id.to!string.rightJustify(4), " > ",a);

			printTitle("labels");
			foreach(id, ref a ; labelsPtr[0..headerPtr.label_count])
				writeln(id.to!string.rightJustify(4), " > ",a);

			printTitle("field data");
			printByteArray(fieldDatasPtr, headerPtr.field_data_count);

			printTitle("field indices");
			printByteArray(fieldIndicesPtr, headerPtr.field_indices_count);

			printTitle("list indices");
			printByteArray(listIndicesPtr, headerPtr.list_indices_count);
		}
	}

	struct Serializer{
		GffHeader   header;
		GffStruct[] structs;
		GffField[]  fields;
		GffLabel[]  labels;
		void[]      fieldDatas;
		void[]      fieldIndices;
		void[]      listIndices;

		version(gff_verbose) string gff_verbose_rtIndent;


		uint32_t registerStruct(const(GffNode)* node){
			assert(node.type == GffType.Struct);

			immutable createdStructIndex = cast(uint32_t)structs.length;
			structs ~= GffStruct();

			immutable fieldCount = cast(uint32_t)node.aggrContainer.length;
			structs[createdStructIndex].type = node.structType;
			structs[createdStructIndex].field_count = fieldCount;


			version(gff_verbose){
				writeln(gff_verbose_rtIndent,
					"Registering struct id=",createdStructIndex,
					" from node '",node.label,"'",
					"(type=",structs[createdStructIndex].type,", fields_count=",structs[createdStructIndex].field_count,")");
				gff_verbose_rtIndent ~= "│ ";
			}

			if(fieldCount == 1){
				//index in field array
				immutable fieldId = registerField(&node.aggrContainer[0]);
				structs[createdStructIndex].data_or_data_offset = fieldId;
			}
			else if(fieldCount>1){
				//byte offset in field indices array
				immutable fieldIndicesIndex = cast(uint32_t)fieldIndices.length;
				structs[createdStructIndex].data_or_data_offset = fieldIndicesIndex;

				fieldIndices.length += uint32_t.sizeof*fieldCount;
				foreach(i, ref field ; node.aggrContainer){

					immutable fieldId = registerField(&field);

					immutable offset = fieldIndicesIndex + +i*uint32_t.sizeof;
					fieldIndices[offset..offset+uint32_t.sizeof] = (cast(uint32_t*)&fieldId)[0..1];
				}
			}
			else{
				structs[createdStructIndex].data_or_data_offset = -1;
			}

			version(gff_verbose) gff_verbose_rtIndent = gff_verbose_rtIndent[0..$-4];
			return createdStructIndex;
		}
		uint32_t registerField(const(GffNode)* node){
			immutable createdFieldIndex = cast(uint32_t)fields.length;
			fields ~= GffField(node.type);

			version(gff_verbose){
				writeln(gff_verbose_rtIndent, "Registering  field: '", node.label,
					"' (",node.type,
					", id=",createdFieldIndex,
					", value=",node.to!string,")");
				gff_verbose_rtIndent ~= "│ ";
			}

			assert(node.label.length <= 16, "Label too long");//TODO: Throw exception on GffNode.label set

			char[16] label = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
			label[0..node.label.length] = node.label.dup;
			//TODO: this may be totally stupid and complexity too high
			bool labelFound = false;
			foreach(i, ref s ; labels){
				if(s.value == label){
					labelFound = true;
					fields[createdFieldIndex].label_index = cast(uint32_t)i;
					break;
				}
			}
			if(!labelFound){
				fields[createdFieldIndex].label_index = cast(uint32_t)labels.length;
				labels ~= GffLabel(label);
			}

			final switch(node.type) with(GffType){
				case Invalid: assert(0, "type has not been set");
				case Byte, Char, Word, Short, DWord, Int, Float:
					//cast is ok because all those types are <= 32bit
					fields[createdFieldIndex].data_or_data_offset = *cast(uint32_t*)&node.simpleTypeContainer;
					break;
				case DWord64, Int64, Double:
					//stored in fieldDatas
					fields[createdFieldIndex].data_or_data_offset = cast(uint32_t)fieldDatas.length;
					fieldDatas ~= (&node.simpleTypeContainer)[0..1].dup;
					break;
				case ExoString:
					immutable stringLength = cast(uint32_t)node.stringContainer.length;

					fields[createdFieldIndex].data_or_data_offset = cast(uint32_t)fieldDatas.length;
					fieldDatas ~= (&stringLength)[0..1].dup;
					fieldDatas ~= (cast(void*)node.stringContainer.ptr)[0..stringLength].dup;
					break;
				case ResRef:
					assert(node.stringContainer.length<=32, "Resref too long (max length: 32 characters)");//TODO: Throw exception on GffNode value set

					immutable stringLength = cast(uint8_t)node.stringContainer.length;

					fields[createdFieldIndex].data_or_data_offset = cast(uint32_t)fieldDatas.length;
					fieldDatas ~= (&stringLength)[0..1].dup;
					fieldDatas ~= (cast(void*)node.stringContainer.ptr)[0..stringLength].dup;
					break;
				case ExoLocString:
					immutable fieldDataIndex = fieldDatas.length;
					fields[createdFieldIndex].data_or_data_offset = cast(uint32_t)fieldDataIndex;

					//total size
					fieldDatas ~= [cast(uint32_t)0];

					immutable strref = cast(uint32_t)node.exoLocStringContainer.strref;
					fieldDatas ~= (&strref)[0..1].dup;

					immutable strcount = cast(uint32_t)node.exoLocStringContainer.strings.length;
					fieldDatas ~= (&strcount)[0..1].dup;

					import std.algorithm: sort;
					import std.array: array;
					foreach(locstr ; node.exoLocStringContainer.strings.byKeyValue.array.sort!((a,b)=>a.key<b.key)){
						immutable key = cast(int32_t)locstr.key;
						fieldDatas ~= (&key)[0..1].dup;//string id

						immutable length = cast(int32_t)locstr.value.length;
						fieldDatas ~= (&length)[0..1].dup;

						fieldDatas ~= locstr.value.ptr[0..length].dup;
					}

					//total size
					immutable totalSize = cast(uint32_t)(fieldDatas.length-fieldDataIndex) - 4;//totalSize does not count first 4 bytes
					fieldDatas[fieldDataIndex..fieldDataIndex+4] = (&totalSize)[0..1].dup;
					break;
				case Void:
					auto dataLength = cast(uint32_t)node.rawContainer.length;
					fields[createdFieldIndex].data_or_data_offset = cast(uint32_t)fieldDatas.length;
					fieldDatas ~= (&dataLength)[0..1];
					fieldDatas ~= node.rawContainer;
					break;
				case Struct:
					immutable structId = registerStruct(node);
					fields[createdFieldIndex].data_or_data_offset = structId;
					break;
				case List:
					immutable createdListOffset = cast(uint32_t)listIndices.length;
					fields[createdFieldIndex].data_or_data_offset = createdListOffset;

					uint32_t listLength = cast(uint32_t)node.aggrContainer.length;
					listIndices ~= (&listLength)[0..1];
					listIndices.length += listLength * uint32_t.sizeof;
					if(node.aggrContainer !is null){
						foreach(i, ref listField ; node.aggrContainer){
							immutable offset = createdListOffset+uint32_t.sizeof*(i+1);

							uint32_t structIndex = registerStruct(&listField);
							listIndices[offset..offset+uint32_t.sizeof] = (&structIndex)[0..1];
						}

					}
					break;
			}
			version(gff_verbose) gff_verbose_rtIndent = gff_verbose_rtIndent[0..$-4];
			return createdFieldIndex;
		}

		void[] serialize(in string fileType, in string fileVersion){
			assert(fileType.length <= 4);
			header.file_type = "    ";
			header.file_type[0..fileType.length] = fileType.dup;

			assert(fileVersion.length <= 4);
			header.file_version = "    ";
			header.file_version[0..fileVersion.length] = fileVersion.dup;

			uint32_t offset = cast(uint32_t)GffHeader.sizeof;

			header.struct_offset = offset;
			header.struct_count = cast(uint32_t)structs.length;
			offset += GffStruct.sizeof * structs.length;

			header.field_offset = offset;
			header.field_count = cast(uint32_t)fields.length;
			offset += GffField.sizeof * fields.length;

			header.label_offset = offset;
			header.label_count = cast(uint32_t)labels.length;
			offset += GffLabel.sizeof * labels.length;

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
			void[] data;
			data.reserve(offset);
			data ~= (&header)[0..1];
			version(unittest) offsetCheck += GffHeader.sizeof;
			version(unittest) assert(data.length == offsetCheck);
			data ~= structs;
			version(unittest) offsetCheck += structs.length * GffStruct.sizeof;
			version(unittest) assert(data.length == offsetCheck);
			data ~= fields;
			version(unittest) offsetCheck += fields.length * GffStruct.sizeof;
			version(unittest) assert(data.length == offsetCheck);
			data ~= labels;
			version(unittest) offsetCheck += labels.length * GffLabel.sizeof;
			version(unittest) assert(data.length == offsetCheck);
			data ~= fieldDatas;
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
}
unittest{
	import std.file : read;
	with(GffType){
		auto gff = new Gff("unittest/vault/CromFr/krogar.bic");

		//Parsing checks
		assert(gff.fileType == "BIC");
		assert(gff.fileVersion == "V3.2");
		//assert(gff.fileVersion)
		assert(gff["IsPC"].as!Byte == true);
		assert(gff["RefSaveThrow"].as!Char == 13);
		assert(gff["SoundSetFile"].as!Word == 363);
		assert(gff["HitPoints"].as!Short == 320);
		assert(gff["Gold"].as!DWord == 6400);
		assert(gff["Age"].as!Int == 50);
		//assert(gff[""].as!DWord64 == );
		//assert(gff[""].as!Int64 == );
		assert(gff["XpMod"].as!Float == 1);
		//assert(gff[""].as!Double == );
		assert(gff["Deity"].as!ExoString    == "Gorm Gulthyn");
		assert(gff["ScriptHeartbeat"].as!ResRef       == "gb_player_heart");
		assert(gff["FirstName"].as!ExoLocString.strref == -1);
		assert(gff["FirstName"].as!ExoLocString.strings[0] == "Krogar");
		//assert(gff[""].as!Void == );
		assert(gff["Tint_Head"]["Tintable"]["Tint"]["1"]["b"].as!Byte == 109);
		assert(gff["ClassList"][0]["Class"].as!Int == 4);

		auto krogarDataOrig = cast(ubyte[])read("unittest/vault/CromFr/krogar.bic");
		gff = new Gff(krogarDataOrig);

		auto krogarDataSerialized = cast(ubyte[])gff.serialize();
		auto gffSerialized = new Gff(krogarDataSerialized);

		assert(gff.toPrettyString() == gffSerialized.toPrettyString(), "Serialization data mismatch");
		assert(krogarDataSerialized == krogarDataOrig, "Serialization not byte perfect");

		assertThrown!GffValueSetException(gff.fileType = "FILETYPE");
		gff.fileType = "A C";
		assert(gff.fileType == "A C");
		assertThrown!GffValueSetException(gff.fileVersion = "VERSION");
		gff.fileVersion = "V42";
		assert(gff.fileVersion == "V42");

		auto data = cast(char[])gff.serialize();
		assert(data[0..4]=="A C ");
		assert(data[4..8]=="V42 ");
	}

}