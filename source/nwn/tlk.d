/// TalkTable (tlk)
module nwn.tlk;

import std.stdint;
import std.string;
import std.conv;

import nwn.gff : GffNode, GffType, gffTypeToNative;

debug import std.stdio: writeln;
version(unittest) import std.exception: assertThrown, assertNotThrown;

public import nwn.constants: Language;

class TlkOutOfBoundsException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

alias StrRef = uint32_t;

class StrRefResolver{
	this(in Tlk standartTable, in Tlk userTable){
		this.standartTable = standartTable;
		this.userTable = userTable;
	}

	/// Get a localized string in the tlk tables (can be a standard or user strref)
	string opIndex(in StrRef strref)const{
		if(strref<Tlk.UserTlkIndexOffset){
			assert(standartTable !is null, "standartTable is null");
			return standartTable[strref];
		}
		else{
			assert(standartTable !is null, "userTable is null");
			return userTable[strref-Tlk.UserTlkIndexOffset];
		}
	}

	/// Resolves an ExoLocString GffNode to the appropriate language using the tlk tables and language ID
	string opIndex(in GffNode node)const{
		assert(node.type==GffType.ExoLocString, "Node '"~node.label~"' is not an ExoLocString");

		if(node.exoLocStringContainer.strref!=StrRef.max){
			try return this[node.exoLocStringContainer.strref];
			catch(TlkOutOfBoundsException){}
		}

		if(node.exoLocStringContainer.strings.length == 0)
			return "invalid_strref";

		immutable strid = standartTable.language * 2;
		//male
		if(auto s = strid in node.exoLocStringContainer.strings)
			return (*s).to!string;
		//female
		if(auto s = strid+1 in node.exoLocStringContainer.strings)
			return (*s).to!string;

		return node.exoLocStringContainer.strings.values[0].to!string;
	}

	const Tlk standartTable;
	const Tlk userTable;
}
unittest{
	immutable dialogTlk = cast(immutable ubyte[])import("dialog.tlk");
	immutable userTlk = cast(immutable ubyte[])import("user.tlk");

	auto strref = new StrRefResolver(
		new Tlk(dialogTlk),
		new Tlk(userTlk));

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

	assert(strref.standartTable.language == Language.French);
	assert(strref[0] == "Bad Strref");
	assert(strref[54] == lastLine);
	assertThrown!TlkOutOfBoundsException(strref[55]);

	assert(strref[Tlk.UserTlkIndexOffset + 0] == "Hello world");
	assert(strref[Tlk.UserTlkIndexOffset + 1] == "Café liégeois");

	auto node = GffNode(GffType.ExoLocString);
	node = Tlk.UserTlkIndexOffset + 1;
	node = [0:"male english", 1:"female english", 2:"male french"];

	assert(strref[node] == "Café liégeois");
	node = Tlk.UserTlkIndexOffset + 50;
	assert(strref[node] == "male french");
	node = StrRef.max;
	assert(strref[node] == "male french");
	node = StrRef.max;
	node = [1:"female english"];
	assert(strref[node] == "female english");
	node = [1:"female english", 3:"female french"];
	assert(strref[node] == "female french");
	node = [1:"female english", 4:"male yolo"];
	assert(strref[node] == "female english");
	node = (typeof(gffTypeToNative!(GffType.ExoLocString).strings)).init;
	assert(strref[node] == "invalid_strref");

}


class Tlk{

	this(Language langId, immutable(char[4]) tlkVersion = "V3.0"){
		header.file_type = "TLK ";
		header.file_version = tlkVersion;
	}

	this(in string path){
		import std.file: read;
		this(cast(ubyte[])path.read());
	}

	this(in ubyte[] rawData){
		header = *cast(TlkHeader*)rawData.ptr;
		strData = (cast(TlkStringData[])rawData[TlkHeader.sizeof .. header.string_entries_offset]).dup();
		strEntries = cast(char[])rawData[header.string_entries_offset .. $];
	}

	string opIndex(in StrRef strref) const{
		assert(strref < UserTlkIndexOffset, "Tlk indexes must be lower than "~UserTlkIndexOffset.to!string);

		if(strref >= header.string_count)
			throw new TlkOutOfBoundsException("strref "~strref.to!string~" out of bounds");

		immutable data = strData[strref];
		return cast(immutable)strEntries[data.offset_to_string .. data.offset_to_string + data.string_size];
	}

	@property size_t length() const{
		return header.string_count;
	}

	int opApply(scope int delegate(in string) dlg) const{
		int res = 0;
		foreach(ref data ; strData){
			res = dlg(cast(immutable)strEntries[data.offset_to_string .. data.offset_to_string + data.string_size]);
			if(res != 0) break;
		}
		return res;
	}
	int opApply(scope int delegate(size_t, in string) dlg) const{
		int res = 0;
		foreach(i, ref data ; strData){
			res = dlg(i, cast(immutable)strEntries[data.offset_to_string .. data.offset_to_string + data.string_size]);
			if(res != 0) break;
		}
		return res;
	}

	@property{
		Language language() const{
			return cast(Language)(header.language_id);
		}
	}

	immutable(ubyte[]) serialize() const{
		return ((cast(ubyte*)&header)[0 .. TlkHeader.sizeof]
		       ~(cast(ubyte[])strData)
		       ~(cast(ubyte[])strEntries)).idup();
	}



	void opIndexAssign(string text, StrRef strref){

		if(strref >= length){
			header.string_count = strref + 1;
			strData.length = header.string_count;
		}

		auto data = &strData[strref];
		if(data.flags & StringFlag.TEXT_PRESENT && text.length <= data.string_size){
			// Existing string
			// Rewrite content in place
			strEntries[data.offset_to_string .. data.offset_to_string + text.length] = text;
		}
		else{
			// Append text at the end
			data.flags = StringFlag.TEXT_PRESENT;
			data.offset_to_string = strEntries.length;
			data.sound_length = 0.0;

			strEntries ~= text;
		}
		data.string_size = text.length;
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