/// ERF file format (erf, hak, mod, ...)
module nwn.erf;

import std.stdio: File;
import std.stdint;
import std.string;
import std.conv: to;
import nwnlibd.parseutils;
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

alias NWN1ErfFile = ErfFile!(NwnVersion.NWN1);
alias NWN2ErfFile = ErfFile!(NwnVersion.NWN2);

/// File stored in Erf class
struct ErfFile(NwnVersion NV){
	this(string filePath){
		import std.path: baseName, stripExtension;

		m_name = filePath.stripExtension.baseName;

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

	///
	ResourceType type;

	///
	void[] data;
}

alias NWN1Erf = Erf!(NwnVersion.NWN1);
alias NWN2Erf = Erf!(NwnVersion.NWN2);

/// ERF file parsing
class Erf(NwnVersion NV){

	///
	this(in void[] data){
		const header = cast(ErfHeader*)data.ptr;
		fileType = header.file_type.charArrayToString;
		fileVersion = header.file_version.charArrayToString;


		const keys = cast(ErfKey*)(data.ptr+header.keys_offset);
		const resources = cast(ErfResource*)(data.ptr+header.resources_offset);

		files.length = header.keys_count;
		foreach(i, ref key ; keys[0..header.keys_count]){
			files[i].name = key.file_name.charArrayToString;
			files[i].type = cast(ResourceType)key.resource_type;

			const res = resources + key.resource_id;
			files[i].data = data[res.resource_offset .. res.resource_offset+res.resource_size].dup;
		}
	}

	///
	ErfFile!NV[] files;


	@property{
		///
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
		///
		string fileVersion()const{return m_fileVersion;}
		/// ditto
		void fileVersion(string value){
			if(value.length>4)
				throw new ErfValueSetException("fileVersion cannot be longer than 4 characters");
			m_fileVersion = value;
		}
	}
	private string m_fileVersion;



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
	auto hakData = import("test.hak");
	auto erf = new NWN2Erf(hakData);

	assert(erf.files[0].name == "eye");
	assert(erf.files[1].name == "test");
	assert(cast(string)erf.files[1].data == "Hello world\n");
}