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
	INVALID = 0xFFFF, /// Invalid resource type
	BMP = 1,      /// Windows BMP file
	TGA = 3,      /// TGA image format
	WAV = 4,      /// WAV sound file
	PLT = 6,      /// Bioware Packed Layered Texture, used for player character skins, allows for multiple color layers
	INI = 7,      /// Windows INI file format
	TXT = 10,     /// Text file
	MDL = 2002,   /// Aurora model
	NSS = 2009,   /// NWScript Source
	NCS = 2010,   /// NWScript Compiled Script
	ARE = 2012,   /// BioWare Aurora Engine Area file. Contains information on what tiles are located in an area, as well as other static area properties that cannot change via scripting. For each .are file in a .mod, there must also be a corresponding .git and .gic file having the same ResRef.
	SET = 2013,   /// BioWare Aurora Engine Tileset
	IFO = 2014,   /// Module Info File. See the IFO Format document.
	BIC = 2015,   /// Character/Creature
	WOK = 2016,   /// Walkmesh
	TWODA = 2017, /// 2-D Array (2DA)
	TXI = 2022,   /// Extra Texture Info
	GIT = 2023,   /// Game Instance File
	UTI = 2025,   /// Item Blueprint
	UTC = 2027,   /// Creature Blueprint
	DLG = 2029,   /// Conversation File
	ITP = 2030,   /// Tile/Blueprint Palette File
	UTT = 2032,   /// Trigger Blueprint
	DDS = 2033,   /// Compressed texture file
	UTS = 2035,   /// Sound Blueprint
	LTR = 2036,   /// Letter-combo probability info for name generation
	GFF = 2037,   /// Generic File Format. Used when undesirable to create a new file extension for a resource, but the resource is a GFF. (Examples of GFFs include itp, utc, uti, ifo, are, git)
	FAC = 2038,   /// Faction File
	UTE = 2040,   /// Encounter Blueprint
	UTD = 2042,   /// Door Blueprint
	UTP = 2044,   /// Placeable Object Blueprint
	DFT = 2045,   /// Default Values file. Used by area properties dialog
	GIC = 2046,   /// Game Instance Comments. Comments on instances are not used by the game, only the toolset, so they are stored in a gic instead of in the git with the other instance properties.
	GUI = 2047,   /// Graphical User Interface layout used by game
	UTM = 2051,   /// Store/Merchant Blueprint
	DWK = 2052,   /// Door walkmesh
	PWK = 2053,   /// Placeable Object walkmesh
	JRL = 2056,   /// Journal File
	UTW = 2058,   /// Waypoint Blueprint. See Waypoint GFF document.
	SSF = 2060,   /// Sound Set File. See Sound Set File Format document
	NDB = 2064,   /// Script Debugger File
	PTM = 2065,   /// Plot Manager file/Plot Instance
	PTT = 2066,   /// Plot Wizard Blueprint
}

///
ResourceType stringToResourceType(in string resourceType){
	import std.string: toUpper;
	import std.conv: to;

	auto rtu = resourceType.toUpper;
	if(rtu == "2DA") rtu = "TWODA";

	return rtu.to!ResourceType;
}
///
string resourceTypeToString(in ResourceType resourceType){
	import std.conv: to;
	if(resourceType==ResourceType.TWODA){
		return "2DA";
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
