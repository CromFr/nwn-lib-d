/// TalkTable (tlk)
module nwn.tlk;

import std.stdint;
import std.string;
import std.conv;
import std.traits: EnumMembers;

debug import std.stdio: writeln;
version(unittest) import std.exception: assertThrown, assertNotThrown;

public import nwn.constants: Language, LanguageGender;

class TlkOutOfBoundsException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

/// String ref base type
alias StrRef = uint32_t;

/// Utility class to resolve string refs using two TLKs
class StrRefResolver{
	this(in Tlk standartTable, in Tlk userTable = null){
		this.standartTable = standartTable;
		this.userTable = userTable;
	}

	/// Get a localized string in the tlk tables (can be a standard or user strref)
	string opIndex(in StrRef strref)const{
		if(strref < Tlk.UserTlkIndexOffset){
			assert(standartTable !is null, "standartTable is null");
			return standartTable[strref];
		}
		else if(userTable !is null){
			return userTable[strref-Tlk.UserTlkIndexOffset];
		}
		return "unknown_strref_" ~ strref.to!string;
	}

	const Tlk standartTable;
	const Tlk userTable;
}
unittest{
	auto resolv = new StrRefResolver(
		new Tlk(cast(immutable ubyte[])import("dialog.tlk")),
		new Tlk(cast(immutable ubyte[])import("user.tlk"))
	);

	enum string lastLine =
		 "Niveau(x) de lanceur de sorts : prêtre 1, paladin 1\n"
		~"Niveau inné : 1\n"
		~"Ecole : Evocation\n"
		~"Registre(s) : \n"
		~"Composante(s) : verbale, gestuelle\n"
		~"Portée : personnelle\n"
		~"Zone d'effet / cible : lanceur\n"
		~"Durée : 60 secondes\n"
		~"Jet de sauvegarde : aucun\n"
		~"Résistance à la magie : non\n"
		~"\n"
		~"Tous les trois niveaux effectifs de lanceur de sorts, vous gagnez un bonus de +1 à vos jets d'attaque et un bonus de +1 de dégâts magiques (minimum +1, maximum +3).";

	assert(resolv.standartTable.language == Language.French);
	assert(resolv[0] == "Bad Strref");
	assert(resolv[54] == lastLine);
	assertThrown!TlkOutOfBoundsException(resolv[55]);

	assert(resolv[Tlk.UserTlkIndexOffset + 0] == "Hello world");
	assert(resolv[Tlk.UserTlkIndexOffset + 1] == "Café liégeois");
}

/// TLK (read only)
class Tlk{
	///
	this(Language langId, immutable(char[4]) tlkVersion = "V3.0"){
		header.file_type = "TLK ";
		header.file_version = tlkVersion;
	}
	///
	this(in string path){
		import std.file: read;
		this(cast(ubyte[])path.read());
	}
	///
	this(in ubyte[] rawData){
		header = *cast(TlkHeader*)rawData.ptr;
		strData = (cast(TlkStringData[])rawData[TlkHeader.sizeof .. header.string_entries_offset]).dup();
		strEntries = cast(char[])rawData[header.string_entries_offset .. $];
	}

	/// tlk[strref]
	string opIndex(in StrRef strref) const{
		assert(strref < UserTlkIndexOffset, "Tlk indexes must be lower than "~UserTlkIndexOffset.to!string);

		if(strref >= header.string_count)
			throw new TlkOutOfBoundsException("strref "~strref.to!string~" out of bounds");

		immutable data = strData[strref];
		return cast(immutable)strEntries[data.offset_to_string .. data.offset_to_string + data.string_size];
	}

	/// Number of entries
	@property size_t length() const{
		return header.string_count;
	}

	/// foreach(text ; tlk)
	int opApply(scope int delegate(in string) dlg) const{
		int res = 0;
		foreach(ref data ; strData){
			res = dlg(cast(immutable)strEntries[data.offset_to_string .. data.offset_to_string + data.string_size]);
			if(res != 0) break;
		}
		return res;
	}
	/// foreach(strref, text ; tlk)
	int opApply(scope int delegate(StrRef, in string) dlg) const{
		int res = 0;
		foreach(i, ref data ; strData){
			res = dlg(cast(StrRef)i, cast(immutable)strEntries[data.offset_to_string .. data.offset_to_string + data.string_size]);
			if(res != 0) break;
		}
		return res;
	}

	@property{
		/// TLK language ID
		Language language() const{
			return cast(Language)(header.language_id);
		}
	}

	enum UserTlkIndexOffset = 16777216;

private:
	TlkHeader header;
	TlkStringData[] strData;
	char[] strEntries;


	align(1) struct TlkHeader{
		char[4] file_type;
		char[4] file_version;
		uint32_t language_id;
		uint32_t string_count;
		uint32_t string_entries_offset;
	}
	align(1) struct TlkStringData{
		uint32_t flags;
		char[16] sound_resref;
		uint32_t _volume_variance;
		uint32_t _pitch_variance;
		uint32_t offset_to_string;
		uint32_t string_size;
		float sound_length;
	}

	enum StringFlag{
		TEXT_PRESENT=0x1,
		SND_PRESENT=0x2,
		SNDLENGTH_PRESENT=0x4,
	}
}