module nwnareastripper;

import std.stdio;
import std.exception;
import std.algorithm;
import std.string;
import std.conv;
import std.file: writeFile = write;

version(unittest){}
else{
	int main(string[] args){return _main(args);}
}

class ArgException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}


int _main(string[] args){

	//args = ["prg", "-s",
	//	"C:\\Users\\Crom\\Documents\\Neverwinter Nights 2\\modules\\LcdaDev\\marais-enclave_illithid.git",
	//	"C:\\Users\\Crom\\Documents\\Neverwinter Nights 2\\modules\\LcdaDev\\marais-enclave_illithid-stripped.git"];
	//args = ["prg", "-s",
	//	"C:\\Users\\Crom\\Documents\\Neverwinter Nights 2\\modules\\LcdaDev\\ombreterre-reseau_central.git",
	//	"C:\\Users\\Crom\\Documents\\Neverwinter Nights 2\\modules\\LcdaDev\\ombreterre-reseau_central-stripped.git"];

	import std.getopt : getopt, defaultGetoptPrinter;

	bool agressivePlacedFxCleaning = true;
	bool showStats = false;
	bool inPlace = false;
	auto res = getopt(args,
		"agressive-placedfx", "Remove tag/name/locvars/resref from placed FX", &agressivePlacedFxCleaning,
		"s|stats", "Show stripping stats", &showStats,
		"i|inplace", "Strip the given files. Allow to pass N args to command line", &inPlace,
		);
	if(res.helpWanted){
		defaultGetoptPrinter(
			"Remove unused GIT area information for production usage\nUsage: " ~ args[0] ~ " input_area.git output_area.git",
			res.options);
		return 0;
	}


	ubyte[] stripFile(in string path){
		import nwn.gff;
		auto gff = new Gff(path);


		void stripGff(ref GffNode node){
			final switch(node.type) with(GffType){
				case Invalid:
					assert(0);
				case Byte:
				case Char:
				case Word:
				case Short:
				case DWord:
				case Int:
				case DWord64:
				case Int64:
				case Float:
				case Double:
					node = 0;
					break;
				case ExoString:
				case ResRef:
					node = "";
					break;
				case ExoLocString:
					with(node.as!ExoLocString){
						strref = -1;
						strings.clear();
					}
					break;
				case Void:
					node = [];
					break;
				case Struct:
					foreach(ref inner ; node.as!Struct.byKeyValue){
						stripGff(inner.value);
					}
					break;
				case List:
					node.as!List.length = 0;
					break;
			}
		}

		foreach(ref node ; gff["Encounter List"].as!(GffType.List)){
			stripGff(node["Description"]);
			stripGff(node["Classification"]);
		}
		foreach(ref node ; gff["PlacedFXList"].as!(GffType.List)){
			if(agressivePlacedFxCleaning){
				stripGff(node["Tag"]);
				stripGff(node["LocName"]);
				stripGff(node["VarTable"]);
			}
			stripGff(node["TemplateResRef"]);
			stripGff(node["Description"]);
			stripGff(node["Classification"]);
		}
		foreach(ref node ; gff["TreeList"].as!(GffType.List)){
			stripGff(node["Tag"]);
			stripGff(node["TemplateResRef"]);
			stripGff(node["LocName"]);
			stripGff(node["Classification"]);
			stripGff(node["Description"]);
		}
		foreach(ref node ; gff["StaticCameraList"].as!(GffType.List)){
			stripGff(node["TemplateResRef"]);
			stripGff(node["LocName"]);
			stripGff(node["Description"]);
			stripGff(node["Classification"]);
			stripGff(node["VarTable"]);
		}
		//TODO: TreasureList
		//TODO: List
		foreach(ref node ; gff["Creature List"].as!(GffType.List)){
			stripGff(node["Classification"]);
		}
		foreach(ref node ; gff["LightList"].as!(GffType.List)){
			stripGff(node["LocalizedName"]);
			stripGff(node["TemplateResRef"]);
			stripGff(node["Description"]);
			stripGff(node["Classification"]);
		}
		//TODO: StoreList
		foreach(ref node ; gff["WaypointList"].as!(GffType.List)){
			stripGff(node["LocalizedName"]);
			stripGff(node["Description"]);
			stripGff(node["Classification"]);
			stripGff(node["Tintable"]);

			if(node["MapNoteEnabled"].as!(GffType.Byte) == 0 && node["HasMapNote"].as!(GffType.Byte) == 0)
				stripGff(node["MapNote"]);
		}
		foreach(ref node ; gff["Placeable List"].as!(GffType.List)){
			if(node["Static"].as!(GffType.Byte) == 1){
				stripGff(node["LocName"]);
				stripGff(node["Description"]);
				stripGff(node["Conversation"]);
				stripGff(node["TemplateResRef"]);
				stripGff(node["ItemList"]);
				stripGff(node["Tag"]);
				stripGff(node["VarTable"]);

				stripGff(node["KeyName"]);
				stripGff(node["KeyReqFeedback"]);

				stripGff(node["OnClosed"]);
				stripGff(node["OnMeleeAttacked"]);
				stripGff(node["OnUsed"]);
				stripGff(node["OnOpen"]);
				stripGff(node["OnUnlock"]);
				stripGff(node["OnSpellCastAt"]);
				stripGff(node["OnDialog"]);
				stripGff(node["OnDeath"]);
				stripGff(node["OnHeartbeat"]);
				stripGff(node["OnLock"]);
				stripGff(node["OnTrapTriggered"]);
				stripGff(node["OnInvDisturbed"]);
				stripGff(node["OnUserDefined"]);
				stripGff(node["OnDisarm"]);
				stripGff(node["OnLeftClick"]);
				stripGff(node["OnDamaged"]);
			}
			else if(node["Useable"].as!(GffType.Byte) == 0){
				stripGff(node["Description"]);
				stripGff(node["KeyName"]);
				stripGff(node["KeyReqFeedback"]);
			}
			stripGff(node["Classification"]);
		}
		foreach(ref node ; gff["SoundList"].as!(GffType.List)){
			stripGff(node["LocName"]);
			stripGff(node["TemplateResRef"]);
			stripGff(node["Classification"]);
			stripGff(node["Tag"]);// <----------- dangerous?
			stripGff(node["VarTable"]);
		}

		// Triggers
		gff["TriggerList"].as!(GffType.List) = gff["TriggerList"].as!(GffType.List).remove!(node => node["Type"].as!(GffType.Int) == 3);
		foreach(ref node ; gff["TriggerList"].as!(GffType.List)){
			stripGff(node["Description"]);
			stripGff(node["TemplateResRef"]);
			stripGff(node["Classification"]);
		}
		foreach(ref node ; gff["EnvironmentList"].as!(GffType.List)){
			stripGff(node["Tag"]);
			stripGff(node["VarTable"]);
			stripGff(node["TemplateResRef"]);
			stripGff(node["LocName"]);

			stripGff(node["Classification"]);
			stripGff(node["Description"]);
		}
		foreach(ref node ; gff["Door List"].as!(GffType.List)){
			if(node["Static"].as!(GffType.Int) == 1){
				stripGff(node["LocName"]);
				stripGff(node["LinkedTo"]);
				stripGff(node["Description"]);
				stripGff(node["KeyRequired"]);
				stripGff(node["TemplateResRef"]);
				stripGff(node["Conversation"]);
				stripGff(node["KeyName"]);
				stripGff(node["KeyReqFeedback"]);
				stripGff(node["Tag"]);
				stripGff(node["VarTable"]);

				stripGff(node["OnClosed"]);
				stripGff(node["OnMeleeAttacked"]);
				stripGff(node["OnUsed"]);
				stripGff(node["OnOpen"]);
				stripGff(node["OnClick"]);
				stripGff(node["OnUnlock"]);
				stripGff(node["OnSpellCastAt"]);
				stripGff(node["OnDialog"]);
				stripGff(node["OnDeath"]);
				stripGff(node["OnHeartbeat"]);
				stripGff(node["OnFailToOpen"]);
				stripGff(node["OnLock"]);
				stripGff(node["OnTrapTriggered"]);
				stripGff(node["OnUserDefined"]);
				stripGff(node["OnDisarm"]);
				stripGff(node["OnDamaged"]);
			}
			stripGff(node["Classification"]);
		}

		auto outData = gff.serialize();
		if(showStats){
			import std.file: getSize;
			immutable long inSize = path.getSize, outSize = outData.length;
			immutable long diff = inSize - outSize;
			writeln(path);
			writeln("Original file size: ", inSize.to!string.rightJustify(8));
			writeln("Stripped file size: ", outSize.to!string.rightJustify(8), " (", diff, " bytes saved, ", diff * 100.0 / inSize, "%)");
		}
		return outData;
	}

	if(inPlace){
		foreach(path ; args[1 .. $]){
			path.writeFile(stripFile(path));
		}
	}
	else{
		enforce(args.length >= 3, "Need input_area and output_area arguments. See --help");

		immutable inFile = args[1];
		immutable outFile = args[2];

		outFile.writeFile(stripFile(inFile));
	}

	return 0;
}