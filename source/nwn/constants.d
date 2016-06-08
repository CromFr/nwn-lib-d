/// NWN constants
module nwn.constants;

import std.stdint;

/// Neverwinter nights version (1/2)
enum NwnVersion{
	NWN1,
	NWN2
}

/// NWN resource type
/// used in erf and bif file formats
enum ResourceType: uint16_t{
	invalid = 0xFFFF, /// Invalid resource type
	bmp = 1,      /// Windows BMP file
	tga = 3,      /// TGA image format
	wav = 4,      /// WAV sound file
	plt = 6,      /// Bioware Packed Layered Texture, used for player character skins, allows for multiple color layers
	ini = 7,      /// Windows INI file format
	txt = 10,     /// Text file
	mdl = 2002,   /// Aurora model
	nss = 2009,   /// NWScript Source
	ncs = 2010,   /// NWScript Compiled Script
	are = 2012,   /// BioWare Aurora Engine Area file. Contains information on what tiles are located in an area, as well as other static area properties that cannot change via scripting. For each .are file in a .mod, there must also be a corresponding .git and .gic file having the same ResRef.
	set = 2013,   /// BioWare Aurora Engine Tileset
	ifo = 2014,   /// Module Info File. See the IFO Format document.
	bic = 2015,   /// Character/Creature
	wok = 2016,   /// Walkmesh
	twoda = 2017, /// 2-D Array (2DA)
	txi = 2022,   /// Extra Texture Info
	git = 2023,   /// Game Instance File
	uti = 2025,   /// Item Blueprint
	utc = 2027,   /// Creature Blueprint
	dlg = 2029,   /// Conversation File
	itp = 2030,   /// Tile/Blueprint Palette File
	utt = 2032,   /// Trigger Blueprint
	dds = 2033,   /// Compressed texture file
	uts = 2035,   /// Sound Blueprint
	ltr = 2036,   /// Letter-combo probability info for name generation
	gff = 2037,   /// Generic File Format. Used when undesirable to create a new file extension for a resource, but the resource is a GFF. (Examples of GFFs include itp, utc, uti, ifo, are, git)
	fac = 2038,   /// Faction File
	ute = 2040,   /// Encounter Blueprint
	utd = 2042,   /// Door Blueprint
	utp = 2044,   /// Placeable Object Blueprint
	dft = 2045,   /// Default Values file. Used by area properties dialog
	gic = 2046,   /// Game Instance Comments. Comments on instances are not used by the game, only the toolset, so they are stored in a gic instead of in the git with the other instance properties.
	gui = 2047,   /// Graphical User Interface layout used by game
	utm = 2051,   /// Store/Merchant Blueprint
	dwk = 2052,   /// Door walkmesh
	pwk = 2053,   /// Placeable Object walkmesh
	jrl = 2056,   /// Journal File
	utw = 2058,   /// Waypoint Blueprint. See Waypoint GFF document.
	ssf = 2060,   /// Sound Set File. See Sound Set File Format document
	ndb = 2064,   /// Script Debugger File
	ptm = 2065,   /// Plot Manager file/Plot Instance
	ptt = 2066,   /// Plot Wizard Blueprint
}

///
ResourceType fileExtensionToResourceType(in string fileExtension){
	import std.string: toLower;
	import std.conv: to;

	auto rtu = fileExtension.toLower;
	if(rtu == "2da") return ResourceType.twoda;

	return rtu.to!ResourceType;
}
///
string resourceTypeToFileExtension(in ResourceType resourceType){
	import std.conv: to;
	if(resourceType==ResourceType.twoda){
		return "2da";
	}
	return resourceType.to!string;
}


/// Language
enum Language{
	English=0,///
	French=1,///
	German=2,///
	Italian=3,///
	Spanish=4,///
	Polish=5,///
	Korean=128,///
	ChineseTrad=129,///
	ChineseSimp=130,///
	Japanese=131,///
}

/// Gender
enum Gender{
	Male = 0,///
	Female = 1,///
}

/// Language & gender
enum LanguageGender{
	EnglishMale=0,///
	EnglishFemale=1,///
	FrenchMale=2,///
	FrenchFemale=3,///
	GermanMale=4,///
	GermanFemale=5,///
	ItalianMale=6,///
	ItalianFemale=7,///
	SpanishMale=8,///
	SpanishFemale=9,///
	PolishMale=10,///
	PolishFemale=11,///
	KoreanMale=256,///
	KoreanFemale=257,///
	ChineseTradMale=258,///
	ChineseTradFemale=259,///
	ChineseSimpMale=260,///
	ChineseSimpFemale=261,///
	JapaneseMale=262,///
	JapaneseFemale=263,///
}
