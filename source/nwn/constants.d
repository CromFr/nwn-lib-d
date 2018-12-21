/// NWN constants
module nwn.constants;

import std.stdint;
version(unittest) import std.exception: assertThrown, assertNotThrown;

/// Neverwinter nights version (1/2)
enum NwnVersion{
	NWN1,
	NWN2
}

/// NWN resource type
/// used in erf and bif file formats
enum ResourceType: uint16_t{
	invalid = 0xFFFF, /// Invalid resource type
	res = 0,      ///
	bmp = 1,      /// Windows BMP file
	mve = 2,      ///
	tga = 3,      /// TGA image format
	wav = 4,      /// WAV sound file
	wfx = 5,      ///
	plt = 6,      /// Bioware Packed Layered Texture, used for player character skins, allows for multiple color layers
	ini = 7,      /// Windows INI file format
	mp3 = 8,      ///
	mpg = 9,      ///
	txt = 10,     /// Text file
	plh = 2000,   ///
	tex = 2001,   ///
	mdl = 2002,   /// Aurora model
	thg = 2003,   ///
	fnt = 2005,   ///
	lua = 2007,   ///
	slt = 2008,   ///
	nss = 2009,   /// NWScript Source
	ncs = 2010,   /// NWScript Compiled Script
	mod = 2011,   ///
	are = 2012,   /// BioWare Aurora Engine Area file. Contains information on what tiles are located in an area, as well as other static area properties that cannot change via scripting. For each .are file in a .mod, there must also be a corresponding .git and .gic file having the same ResRef.
	set = 2013,   /// BioWare Aurora Engine Tileset
	ifo = 2014,   /// Module Info File. See the IFO Format document.
	bic = 2015,   /// Character/Creature
	wok = 2016,   /// Walkmesh
	twoda = 2017, /// 2-D Array (2DA)
	tlk = 2018,   ///
	txi = 2022,   /// Extra Texture Info
	git = 2023,   /// Game Instance File
	bti = 2024,   ///
	uti = 2025,   /// Item Blueprint
	btc = 2026,   ///
	utc = 2027,   /// Creature Blueprint
	dlg = 2029,   /// Conversation File
	itp = 2030,   /// Tile/Blueprint Palette File
	btt = 2031,   ///
	utt = 2032,   /// Trigger Blueprint
	dds = 2033,   /// Compressed texture file
	bts = 2034,   ///
	uts = 2035,   /// Sound Blueprint
	ltr = 2036,   /// Letter-combo probability info for name generation
	gff = 2037,   /// Generic File Format. Used when undesirable to create a new file extension for a resource, but the resource is a GFF. (Examples of GFFs include itp, utc, uti, ifo, are, git)
	fac = 2038,   /// Faction File
	bte = 2039,   ///
	ute = 2040,   /// Encounter Blueprint
	btd = 2041,   ///
	utd = 2042,   /// Door Blueprint
	btp = 2043,   ///
	utp = 2044,   /// Placeable Object Blueprint
	dft = 2045,   /// Default Values file. Used by area properties dialog
	gic = 2046,   /// Game Instance Comments. Comments on instances are not used by the game, only the toolset, so they are stored in a gic instead of in the git with the other instance properties.
	gui = 2047,   /// Graphical User Interface layout used by game
	css = 2048,   ///
	ccs = 2049,   ///
	btm = 2050,   ///
	utm = 2051,   /// Store/Merchant Blueprint
	dwk = 2052,   /// Door walkmesh
	pwk = 2053,   /// Placeable Object walkmesh
	btg = 2054,   ///
	utg = 2055,   ///
	jrl = 2056,   /// Journal File
	sav = 2057,   ///
	utw = 2058,   /// Waypoint Blueprint. See Waypoint GFF document.
	fourpc = 2059,///
	ssf = 2060,   /// Sound Set File. See Sound Set File Format document
	hak = 2061,   ///
	nwm = 2062,   ///
	bik = 2063,   ///
	ndb = 2064,   /// Script Debugger File
	ptm = 2065,   /// Plot Manager file/Plot Instance
	ptt = 2066,   /// Plot Wizard Blueprint
	bak = 2067,   ///
	osc = 3000,   ///
	usc = 3001,   ///
	trn = 3002,   ///
	utr = 3003,   ///
	uen = 3004,   ///
	ult = 3005,   ///
	sef = 3006,   ///
	pfx = 3007,   ///
	cam = 3008,   ///
	lfx = 3009,   ///
	bfx = 3010,   ///
	upe = 3011,   ///
	ros = 3012,   ///
	rst = 3013,   ///
	ifx = 3014,   ///
	pfb = 3015,   ///
	zip = 3016,   ///
	wmp = 3017,   ///
	bbx = 3018,   ///
	tfx = 3019,   ///
	wlk = 3020,   ///
	xml = 3021,   ///
	scc = 3022,   ///
	ptx = 3033,   ///
	ltx = 3034,   ///
	trx = 3035,   ///
	mdb = 4000,   ///
	mda = 4001,   ///
	spt = 4002,   ///
	gr2 = 4003,   ///
	fxa = 4004,   ///
	fxe = 4005,   ///
	jpg = 4007,   ///
	pwc = 4008,   ///
	ids = 9996,   ///
	erf = 9997,   ///
	bif = 9998,   ///
	key = 9999,   ///
}

///
ResourceType fileExtensionToResourceType(in string fileExtension){
	import std.string: toLower;
	import std.conv: to, ConvException;

	auto rtu = fileExtension.toLower;
	if(rtu == "2da") return ResourceType.twoda;
	if(rtu == "4pc") return ResourceType.fourpc;

	try return rtu.to!ResourceType;
	catch(ConvException) return ResourceType.invalid;
}
unittest{
	assert(fileExtensionToResourceType("txt")==ResourceType.txt);
	assert(fileExtensionToResourceType("2da")==ResourceType.twoda);
	assert(fileExtensionToResourceType("oia")==ResourceType.invalid);
}

///
string resourceTypeToFileExtension(in ResourceType resourceType){
	import std.conv: to;
	switch(resourceType){
		case ResourceType.twoda:  return "2da";
		case ResourceType.fourpc: return "4pc";
		default: return resourceType.to!string;
	}
}
unittest{
	assert(resourceTypeToFileExtension(ResourceType.txt)=="txt");
	assert(resourceTypeToFileExtension(ResourceType.twoda)=="2da");
	assert(resourceTypeToFileExtension(ResourceType.invalid)=="invalid");
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
