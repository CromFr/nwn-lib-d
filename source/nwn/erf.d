/// ERF file format (erf, hak, mod, ...)
module nwn.erf;

import std.stdio: File;
import std.stdint;
import std.string;
import std.conv: to;
import std.datetime;
import std.typecons: Nullable;
import std.exception: enforce;
import nwnlibd.parseutils;
import nwn.constants;
public import nwn.constants: NwnVersion, ResourceType, Language;

debug import std.stdio: writeln;
version(unittest) import std.exception: assertThrown, assertNotThrown;

/// Parsing exception
class ErfParseException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}
/// Value doesn't match constraints (ex: label too long)
class ErfValueSetException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

///
alias NWN1ErfFile = ErfFile!(NwnVersion.NWN1);
///
alias NWN2ErfFile = ErfFile!(NwnVersion.NWN2);

/// File stored in Erf class
struct ErfFile(NwnVersion NV){
	/// Construct a Erf file
	this(in string name, ResourceType type, ubyte[] data){
		this.name = name;
		this.type = type;
		this.data = data;
	}

	this(string filePath){
		import std.file: read;
		import std.path: baseName, stripExtension, extension;

		auto ext = ResourceType.invalid;
		immutable extStr = filePath.extension;
		if(extStr.length>1)
			ext = extStr[1..$].fileExtensionToResourceType;

		this(
			filePath.stripExtension.baseName.toLower,
			ext,
			cast(ubyte[])filePath.read);
	}
	unittest{
		import std.file: tempDir, writeFile=write;

		auto filePath = tempDir~"/unittest-nwn-lib-d-"~__MODULE__~".test.txt";
		filePath.writeFile("YOLO");

		auto erfFile = NWN2ErfFile(filePath);
		assert(erfFile.name == "unittest-nwn-lib-d-nwn.erf.test");
		assert(erfFile.type == ResourceType.txt);
		assert(erfFile.data == "YOLO");
	}


	@property{
		/// File name (without file extension)
		string name()const{return m_name;}
		/// ditto
		void name(string value){
			if(value.length>(NV==NwnVersion.NWN1? 16 : 32))
				throw new ErfValueSetException(
					"file name cannot be longer than "~(NV==NwnVersion.NWN1? 16 : 32).to!string~" characters");
			m_name = value;
		}
	}
	private string m_name;

	/// File type (related with its extension)
	ResourceType type;

	/// File raw data
	ubyte[] data;

	/// Expected file size. If not null, can be used to detect truncated files
	Nullable!size_t expectedLength;
}

///
alias NWN1Erf = Erf!(NwnVersion.NWN1);
///
alias NWN2Erf = Erf!(NwnVersion.NWN2);

/// ERF file parsing (.erf, .hak, .mod files)
class Erf(NwnVersion NV){

	///
	this(){}

	/// Parse raw binary data
	/// Params:
	///   data = ERF File raw data
	///   recover = Set to true to skip incomplete files and finish parsing a truncated ERF
	this(in ubyte[] data, bool recover = false){
		enforce!ErfParseException(data.length >= ErfHeader.sizeof, "ERF file is shorter than its header size. Cannot read");

		const header = cast(ErfHeader*)data.ptr;
		fileType = header.file_type.idup.stripRight;
		fileVersion = header.file_version.idup.stripRight;
		auto date = Date(header.build_year+1900, 1, 1);
		date.dayOfYear = header.build_day + 1;
		buildDate = date;

		enforce!ErfParseException(data.length > (header.localizedstrings_offset + header.localizedstrings_size),
			"Cannot read localized strings");

		auto locStrings = ChunkReader(
				data[header.localizedstrings_offset
				.. header.localizedstrings_offset + header.localizedstrings_size]);

		foreach(i ; 0..header.localizedstrings_count){
			immutable langage = cast(Language)locStrings.read!uint32_t;
			immutable length = locStrings.read!uint32_t;

			description[langage] = locStrings.readArray!char(length).idup;
		}

		const keys = cast(ErfKey*)(data.ptr + header.keys_offset);
		size_t keysLength = header.keys_count;
		const resources = cast(ErfResource*)(data.ptr + header.resources_offset);

		enforce!ErfParseException(data.length > header.keys_offset, "Cannot read keys table");
		if(recover){
			if(header.keys_offset + ErfKey.sizeof * keysLength >= data.length){
				// Set lower keysLength
				const availableSize = data.length - header.keys_offset;
				keysLength = availableSize / ErfKey.sizeof;
			}
		}

		// Read key table and allocate files
		files.length = keysLength;
		foreach(i, ref key ; keys[0 .. keysLength]){
			files[i].name = key.file_name.charArrayToString;
			files[i].type = cast(ResourceType)key.resource_type;

			if(recover && header.resources_offset + ErfResource.sizeof * key.resource_id >= data.length){
				continue;
			}
			const res = &resources[key.resource_id];
			size_t startOffset = res.resource_offset;
			size_t endOffset = res.resource_offset + res.resource_size;
			files[i].expectedLength = res.resource_size;

			if(recover){
				if(startOffset > data.length){
					// Null-sized file
					startOffset = 0;
					endOffset = 0;
				}
				else{
					// Truncate file
					endOffset = endOffset > data.length? data.length : endOffset;
				}
			}

			files[i].data = data[startOffset .. endOffset].dup;

		}

	}

	/// Localized module description
	string[Language] description;

	/// Files contained in the erf file
	ErfFile!NV[] files;


	@property{
		/// File type (ERF, HAK, MOD, ...)
		/// Max width: 4 chars
		string fileType()const{return m_fileType;}
		/// ditto
		void fileType(string value){
			if(value.length>4)
				throw new ErfValueSetException("fileType cannot be longer than 4 characters");
			m_fileType = value;
		}
	}
	private string m_fileType;

	@property{
		/// File version ("V1.0" for NWN1, "V1.1" for NWN2)
		/// Max width: 4 chars
		string fileVersion()const{return m_fileVersion;}
		/// ditto
		void fileVersion(string value){
			if(value.length>4)
				throw new ErfValueSetException("fileVersion cannot be longer than 4 characters");
			m_fileVersion = value;
		}
	}
	private string m_fileVersion;

	@property{
		/// Date when the erf file has been created
		Date buildDate()const{return m_buildDate;}
		/// ditto
		void buildDate(Date value){
			if(value.year<1900)
				throw new ErfValueSetException("buildDate year must be >= 1900");
			m_buildDate = value;
		}
	}
	private Date m_buildDate = Date(1900, 1, 1);


	/// Serialize erf data except file content
	ubyte[] serializeHead(){
		ubyte[] ret;
		ret.length = ErfHeader.sizeof;

		with(cast(ErfHeader*)ret.ptr){
			file_type = "    ";
			file_type[0..fileType.length] = fileType;
			file_version = "    ";
			file_version[0..fileVersion.length] = fileVersion;

			localizedstrings_count = cast(uint32_t)description.length;
			keys_count = cast(uint32_t)files.length;

			build_year = m_buildDate.year - 1900;
			build_day = m_buildDate.dayOfYear - 1;

			file_description_strref = 0;//TODO: seems to be always 0
			//reserved: keep null values

			localizedstrings_offset = ErfHeader.sizeof;
		}

		size_t locstringLength = 0;

		import std.algorithm: sort;
		import std.array: array;
		foreach(ref kv ; description.byKeyValue.array.sort!((a,b)=>a.key<b.key)){
			immutable langID = cast(uint32_t)kv.key;
			immutable length = cast(uint32_t)kv.value.length;

			locstringLength += 4+4+length;

			ret ~= cast(ubyte[])(&langID)[0..1].dup;
			ret ~= cast(ubyte[])(&length)[0..1].dup;
			ret ~= kv.value.dup;
		}

		immutable keysOffset = ret.length;
		immutable resourcesOffset = keysOffset + files.length*ErfKey.sizeof;

		with(cast(ErfHeader*)ret.ptr){
			localizedstrings_size = cast(uint32_t)locstringLength;
			keys_offset = cast(uint32_t)keysOffset;
			resources_offset = cast(uint32_t)resourcesOffset;
		}

		ret.length += files.length*(ErfKey.sizeof + ErfResource.sizeof);


		size_t fileDataOffset = ret.length;

		foreach(index, ref file ; files){
			with((cast(ErfKey*)(ret.ptr+keysOffset))[index]){
				file_name[0..file.name.length] = file.name.dup[0..$];
				resource_id   = cast(uint32_t)index;
				resource_type = file.type;
				reserved      = 0;
			}

			with((cast(ErfResource*)(ret.ptr+resourcesOffset))[index]){
				resource_offset = cast(uint32_t)fileDataOffset;
				resource_size   = cast(uint32_t)file.data.length;

				fileDataOffset += resource_size;
			}
		}

		return ret;
	}

	/// Serializes the erf data.
	/// Warning: can allocate a huge chunk of RAM
	ubyte[] serialize(){
		ubyte[] ret = serializeHead();

		foreach(ref f ; files){
			ret ~= f.data;
		}
		return ret;
	}

	/// Efficient writing to file, with less RAM consumption
	void writeToFile(File file){
		auto wr = file.lockingBinaryWriter;
		wr.rawWrite(serializeHead());

		foreach(ref f ; files){
			wr.rawWrite(f.data);
		}
	}


private:
	align(1) static struct ErfHeader{
		char[4] file_type;
		char[4] file_version;

		uint32_t localizedstrings_count;
		uint32_t localizedstrings_size;
		uint32_t keys_count;

		uint32_t localizedstrings_offset;
		uint32_t keys_offset;
		uint32_t resources_offset;

		uint32_t build_year;
		uint32_t build_day;
		uint32_t file_description_strref;
		ubyte[116] reserved;
	}
	align(1) static struct ErfKey{
		char[NV == NwnVersion.NWN1? 16 : 32] file_name;
		uint32_t resource_id;
		uint16_t resource_type;
		uint16_t reserved;
	}
	align(1) static struct ErfResource{
		uint32_t resource_offset;
		uint32_t resource_size;
	}

}

unittest{
	auto hak = new NWN2Erf(cast(ubyte[])import("test.hak"));

	assert(hak.files[0].name == "eye");
	assert(hak.files[0].type == ResourceType.tga);
	assert(hak.files[1].name == "test");
	assert(hak.files[1].type == ResourceType.txt);
	assert(cast(string)hak.files[1].data == "Hello world\n");

	auto modData = cast(ubyte[])import("module.mod");
	auto mod = new NWN2Erf(modData);
	assert(mod.description[Language.English]=="module description");
	assert(mod.buildDate == Date(2016, 6, 9));

	assert(mod.serialize() == modData);
}
