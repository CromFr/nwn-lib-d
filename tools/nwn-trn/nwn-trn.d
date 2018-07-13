/// Authors: Thibaut CHARLES (Crom) cromfr@gmail.com
/// License: GPL-3.0
/// Copyright: Copyright Thibaut CHARLES 2016

module tools.nwntrn;

import std.stdio;
import std.conv: to, ConvException;
import std.traits;
import std.string;
import std.file;
import std.file: readFile = read, writeFile = write;
import std.path;
import std.stdint;
import std.typecons: Tuple, Nullable;
import std.algorithm;
import std.array;
import std.exception: enforce;
import std.random: uniform;
import std.format;
import std.math;

import nwnlibd.path;
import nwnlibd.parseutils;
import tools.common.getopt;
import nwn.trn;

class ArgException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

void usage(in string cmd){
	writeln("TRN / TRX tool");
	writeln("Usage: ", cmd, " command [args]");
	writeln();
	writeln("Commands");
	writeln("  bake: Bake an area (replacement for builtin nwn2toolset bake tool)");
	writeln("  aswm-check: Checks if a TRX file contains valid data");
	writeln("  aswm-strip: Optimize TRX file size");
	writeln("  aswm-export-fancy: Export walkmesh into a colored wavefront obj");
	writeln("  aswm-export: Export walkable walkmesh into a wavefront obj");
	writeln("  aswm-import: Import a wavefront obj as the walkmesh of an existing TRX file");
	writeln("  trrn-export: Export the terrain mesh and textures into a wavefront obj and DDS files");
	writeln("  trrn-import: Import a terrain mesh and textures into an existing TRN/TRX file");
	writeln();
	writeln("Advanced commands:");
	writeln("  aswm-extract: Unzip walkmesh data");
	writeln("  aswm-dump: Print walkmesh data using a (barely) human-readable format");
	writeln("  aswm-bake: Re-bake all tiles of an already baked walkmesh");
}

int main(string[] args){
	version(unittest) if(args.length <= 1) return 0;

	if(args.length <= 1 || (args.length > 1 && (args[1] == "--help" || args[1] == "-h"))){
		usage(args[0]);
		return 1;
	}

	immutable command = args[1];
	args = args[0] ~ args[2..$];

	switch(command){
		default:
			usage(args[0]);
			return 1;
		case "aswm-strip":{
			bool inPlace = false;
			bool silent = false;
			string targetPath = null;

			auto res = getopt(args,
				"in-place|i", "Provide this flag to overwrite the provided TRX file", &inPlace,
				"output|o", "Output file or directory. Mandatory if --in-place is not provided.", &targetPath,
				"silent|s", "Do not display statistics", &silent,
				);
			if(res.helpWanted || args.length == 1){
				improvedGetoptPrinter(
					"Reduce TRX file size by removing non walkable polygons from calculated walkmesh\n"
					~"Usage: "~args[0]~" "~command~" map.trx -o stripped_map.trx\n"
					~"       "~args[0]~" "~command~" -i map.trx",
					res.options);
				return 0;
			}

			if(inPlace){
				enforce(targetPath is null, "You cannot use --in-place with --output");
				enforce(args.length >= 2, "No input file");
			}
			else{
				if(targetPath is null)
					targetPath = ".";
			}

			foreach(file ; args[1 .. $]){

				auto data = cast(ubyte[])file.read();
				auto trn = new Trn(data);
				size_t initLen = data.length;

				bool found = false;
				foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
					found = true;
					stripASWM(aswm, silent);
					aswm.validate();
				}

				enforce(found, "No ASWM packet found. Make sure you are targeting a TRX file.");

				auto finalData = trn.serialize();
				if(!silent)
					writeln("File size: ", initLen, "B => ", finalData.length, "B (stripped ", 100 - finalData.length * 100.0 / initLen, "%)");

				string outPath;
				if(inPlace)
					outPath = file;
				else{
					if(targetPath.exists && targetPath.isDir)
						outPath = buildPath(targetPath, file.baseName);
					else
						outPath = targetPath;
				}

				std.file.write(outPath, finalData);
			}



		}
		break;

		case "aswm-export-fancy":{
			string targetDir = null;
			string[] features = [];
			auto res = getopt(args,
				"output-dir|o", "Output directory where to write converted files", &targetDir,
				"feature|f", "Features to render. Can be provided multiple times. Default: [\"walkmesh\"]", &features,
				);

			if(res.helpWanted || args.length == 1){
				improvedGetoptPrinter(
					"Convert NWN2 walkmeshes into TRX / OBJ (only TRX => OBJ supported for now)\n"
					~"Usage: "~args[0]~" "~command~" map.trx\n"
					~"\n"
					~"Available features to render:\n"
					~"- walkmesh: All triangles including non-walkable.\n"
					~"- edges: Edges between two triangles.\n"
					~"- tiles: Each tile using random colors.\n"
					~"- pathtables-los: Line of sight pathtable property between two triangles.\n"
					~"- randomtilepaths: Calculate random paths between tile triangles.\n"
					~"- randomislandspaths: Calculate random paths between islands.\n"
					~"- islands: Each island using random colors.\n",
					res.options);
				return 0;
			}
			enforce(args.length == 2, "You can only provide one TRX file");

			if(targetDir == null && targetDir != "-"){
				targetDir = args[1].dirName;
			}

			auto outfile = targetDir == "-"? stdout : File(buildPath(targetDir, baseName(args[1])~".obj"), "w");

			if(features.length == 0)
				features = [ "walkmesh" ];


			auto trn = new Trn(args[1]);

			bool found = false;
			foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
				found = true;
				writeWalkmeshObj(
					aswm,
					args[1].baseName.stripExtension,
					outfile,
					features);
			}
			enforce(found, "No ASWM packet found. Make sure you are targeting a TRX file.");

			if(targetDir != "-"){
				auto colPath = buildPath(targetDir, "nwnlibd-colors.mtl");
				if(!colPath.exists)
					std.file.write(colPath, colors);
			}
		}
		break;

		case "aswm-export": {
			string outFile = ".";
			auto res = getopt(args,
				"output|o", "Output file or directory where to write the obj file. Default: '.'", &outFile,
				);

			if(res.helpWanted || args.length == 1){
				improvedGetoptPrinter(
					"Export all walkable triangles into a Wavefront OBJ file.\n"
					~"Usage: "~args[0]~" "~command~" map.trx\n"
					~"       "~args[0]~" "~command~" map.trx -o outputFile.obj\n",
					res.options);
				return 0;
			}
			enforce(args.length == 2, "You can only provide one TRN file");

			auto inputFile = args[1];

			if(outFile.exists && outFile.isDir)
				outFile = buildPath(outFile, inputFile.baseName ~ ".aswm.obj");

			foreach(ref TrnNWN2WalkmeshPayload aswm ; new Trn(inputFile)){
				aswm.toGenericMesh.toObj(File(outFile, "w"));
			}
		}
		break;

		case "aswm-import": {
			string trnFile;
			string objFile;
			string objName;
			string outFile;
			string terrain2daPath;
			auto res = getopt(args,
				config.required, "trn", "TRN file to set the walkmesh of", &trnFile,
				config.required, "obj", "Wavefront OBJ file to import", &objFile,
				"terrain2da", "Path to terrainmaterials.2da, to generate footstep sounds", &terrain2daPath,
				"obj-name", "Object name to import. Default: the first object declared.", &objName,
				"output|o", "Output file or directory where to write the obj file. Default: the file provided by --trn", &outFile,
				);

			if(res.helpWanted){
				improvedGetoptPrinter(
					"Import a Wavefront OBJ file and use it as the area walkmesh. All triangles will be walkable.\n"
					~"Usage: "~args[0]~" "~command~" --trn map.trx --obj walkmesh.obj --terrain2da ./terrainmaterials.2da -o newmap.trx\n"
					~"       "~args[0]~" "~command~" --trn map.trx --obj walkmesh.obj --terrain2da ./terrainmaterials.2da\n",
					res.options);
				return 0;
			}
			enforce(args.length == 1, "Too many arguments. See --help");

			if(outFile is null)
				outFile = trnFile;
			else if(outFile.exists && outFile.isDir)
				outFile = buildPath(outFile, trnFile.baseName);

			auto mesh = GenericMesh.fromObj(File(objFile), objName);

			TwoDA terrainmaterials;
			if(terrain2daPath !is null)
				terrainmaterials = new TwoDA(terrain2daPath);
			else
				writeln("Warning: No triangle soundstep flags will be set. Please provide --terrain2da");


			auto trn = new Trn(trnFile);
			foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
				aswm.setGenericMesh(mesh);

				aswm.bake();

				if(terrainmaterials !is null)
					aswm.setFootstepSounds(trn.packets, terrainmaterials);

				aswm.validate();
			}
			std.file.write(outFile, trn.serialize);
		}
		break;

		case "aswm-extract":{
			enforce(args.length == 2, "Bad argument number. Usage: "~args[0]~" "~command~" file.trx");

			auto trn = new Trn(args[1]);

			bool found = false;
			foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
				found = true;
				std.file.write(
					args[1].baseName~".aswm",
					aswm.serializeUncompressed());
			}
			enforce(found, "No ASWM packet found. Make sure you are targeting a TRX file.");
		}
		break;

		case "aswm-dump":{
			enforce(args.length == 2, "Bad argument number. Usage: "~args[0]~" "~command~" file.trx");

			auto trn = new Trn(args[1]);

			bool found = false;
			foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
				found = true;
				writeln(aswm.dump);
			}
			enforce(found, "No ASWM packet found. Make sure you are targeting a TRX file.");
		}
		break;

		case "aswm-bake":{
			bool inPlace = false;
			string targetPath = null;

			auto res = getopt(args,
				"in-place|i", "Provide this flag to overwrite the provided TRX file", &inPlace,
				"output|o", "Output file or directory. Mandatory if --in-place is not provided.", &targetPath,
				);
			if(res.helpWanted || args.length == 1){
				improvedGetoptPrinter(
					"Re-bake all tile / islands path tables of a baked TRX file.\n"
					~"Usage: "~args[0]~" "~command~" map.trx -o baked_map.trx\n"
					~"       "~args[0]~" "~command~" -i map.trx",
					res.options);
				return 0;
			}

			if(inPlace){
				enforce(targetPath is null, "You cannot use --in-place with --output");
				enforce(args.length == 2, "You can only provide one TRX file with --in-place");
				targetPath = args[1];
			}
			else{
				enforce(targetPath !is null, "No output file / directory. See --help");
				if(targetPath.exists && targetPath.isDir)
					targetPath = buildPath(targetPath, args[1].baseName);
			}

			auto trn = new Trn(args[1]);

			bool found = false;
			foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
				found = true;
				aswm.bake();
			}
			enforce(found, "No ASWM packet found. Make sure you are targeting a TRX file.");

			std.file.write(targetPath, trn.serialize());
		}
		break;


		case "aswm-check":{
			bool strict = false;
			auto res = getopt(args,
				"strict", "Check some inconsistencies that does not cause issues with nwn2\nDefault: false", &strict);
			if(res.helpWanted || args.length == 1){
				improvedGetoptPrinter(
					"Check if ASWM packets are valid.\n"
					~"Usage: "~args[0]~" "~command~" file1.trx file2.trx ...",
					res.options);
				return 0;
			}

			foreach(file ; args[1 .. $]){
				auto trn = new Trn(file);
				foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
					aswm.validate(strict);
				}
			}
		}
		break;


		case "bake":{
			import std.parallelism;
			// import nwn.gff;

			string targetPath = null;
			bool inPlace = false;
			bool reuseTrx = false;
			bool forceWalkable = false;
			bool keepBorders = false;
			bool unsafe = false;
			bool noWmCutters = false;
			string terrain2daPath = null;
			string trnPath = null;
			string gitPath = null;
			uint threads = 0;

			auto res = getopt(args,
				"output|o", "Output trx file or directory. Default: './'", &targetPath,
				"in-place|i", "Provide this flag to write TRX files next to the TRN files", &inPlace,
				"terrain2da", "Path to terrainmaterials.2da, to generate footstep sounds", &terrain2daPath,
				"trn", "TRN file path. Default to $map_name_without_extension.trn", &trnPath,
				"reuse-trx|r", "Reuse walkmesh from an already existing TRX file", &reuseTrx,
				"force-walkable", "Make all triangles walkable. Triangles removed with walkmesh cutters won't be walkable.", &forceWalkable,
				"no-wmcutter", "Do not remove triangles inside walkmesh cutters", &noWmCutters,
				"keep-borders", "Do not remove exterior area borders from baked mesh. (can be used with --force-walkable to make borders walkable).", &keepBorders,
				// "git", "GIT file path. Default to $map_name_without_extension.git", &gitPath,
				"j", "Parallel threads for baking multiple maps at the same time", &threads,
				"unsafe", "Skip TRX validation checks, ie for dumping content & debugging", &unsafe,
				);
			if(res.helpWanted || (args.length == 1 && trnPath is null)){
				improvedGetoptPrinter(
					"Generate baked TRX file.\n"
					~"Usage: "~args[0]~" "~command~" map_name -o baked.trx\n"
					~"       "~args[0]~" "~command~" --terrain2da ./terrainmaterials.2da map_name map_name_2 ...\n"
					~" `map_name` can be any map file with or without its extension (.are, .git, .gic, .trn, .trx)",
					res.options);
				return 0;
			}

			if(inPlace)
				enforce(targetPath is null, "You cannot use --in-place with --output");
			if(targetPath is null)
				targetPath = ".";

			enforce(args.length >= 2 || trnPath !is null, "No input map name given");
			if(args.length > 2)
				enforce(trnPath is null && gitPath is null && targetPath.exists && targetPath.isDir,
					"Cannot use --trn, --git or --output=file with multiple input files");


			if(threads > 0)
				defaultPoolThreads = threads;

			if(trnPath !is null)
				args ~= trnPath;

			TwoDA terrainmaterials;
			if(terrain2daPath !is null)
				terrainmaterials = new TwoDA(terrain2daPath);
			else
				writeln("Warning: No triangle soundstep flags will be set. Please provide --terrain2da");

			foreach(resname ; args[1 .. $].parallel){
				if(trnPath !is null){
					switch(resname.extension.toLower){
						case null:
							break;
						case ".are", ".git", ".gic", ".trn", ".trx":
							resname = resname.stripExtension;
							break;
						default: enforce(0, "Unknown file extension "~resname.extension.toLower);
					}
				}
				else
					resname = resname.stripExtension;

				immutable dir = resname.dirName;
				string trnFilePath = trnPath is null? buildPathCI(dir, resname.baseName~(reuseTrx? ".trx" : ".trn")) : trnPath;
				string gitFilePath = gitPath is null? buildPathCI(dir, resname.baseName~".git") : gitPath;
				string trxFilePath;
				if(inPlace)
					trxFilePath = resname ~ ".trx";
				else{
					if(targetPath.exists && targetPath.isDir)
						trxFilePath = buildPathCI(targetPath, resname.baseName~".trx");
					else
						trxFilePath = targetPath;
				}


				auto trn = new Trn(trnFilePath);
				import nwn.fastgff;
				auto git = new FastGff(gitFilePath);

				import std.datetime.stopwatch: StopWatch;
				auto sw = new StopWatch;
				sw.start();

				foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){

					aswm.tiles_flags = 31;
					if(forceWalkable){
						foreach(ref t ; aswm.triangles)
							t.flags |= t.Flags.walkable;
					}
					aswm.bake(!keepBorders);

					if(terrainmaterials !is null)
						aswm.setFootstepSounds(trn.packets, terrainmaterials);

					if(!unsafe){
						aswm.validate();
					}
				}
				sw.stop();
				writeln(resname.baseName.leftJustify(32), " ", sw.peek.total!"msecs"/1000.0, " seconds");

				std.file.write(trxFilePath, trn.serialize());

			}

		}
		break;


		case "trrn-export":{
			string outFolder = ".";
			bool noDds = false;
			auto res = getopt(args,
				"output|o", "Output directory where to write the OBJ and DDS file. Default: '.'", &outFolder,
				"no-dds", "Do not output texture alpha maps", &noDds,
				);

			if(res.helpWanted || args.length == 1){
				improvedGetoptPrinter(
					"Export terrain mesh and textures into wavefront obj and DDS files.\n"
					~"Note: works on both TRN and TRX files, though TRN files are only used by the toolset.\n"
					~"Usage: "~args[0]~" "~command~" map.trx\n"
					~"       "~args[0]~" "~command~" map.trx -o converted/\n"
					~"\n"
					~"Wavefront format notes:\n"
					~"- Each megatile is stored in a different object named with its megatile coordinates: 'x6y9'. This naming scheme is mandatory.\n"
					~"- Vertex colors are exported, but many 3d tools don't handle it.\n"
					~"- Grass is not exported.\n",
					res.options);
				return 0;
			}
			enforce(args.length == 2, "You can only provide one TRN file");


			auto trnFile = args[1];
			auto trnFileName = trnFile.baseName.stripExtension;
			auto trn = new Trn(trnFile);

			TrnNWN2TerrainDimPayload* trwh = null;
			foreach(ref TrnNWN2TerrainDimPayload _trwh ; trn){
				trwh = &_trwh;
			}
			enforce(trwh !is null, "No TRWH packet found");


			string objData;
			//string textureData;
			size_t vertexOffset = 1;

			size_t trrnCounter = 0;
			foreach(ref TrnNWN2MegatilePayload trrn ; trn){
				size_t x = trrnCounter % trwh.width;
				size_t y = trrnCounter / trwh.width;


				objData ~= format!"o megatile-x%dy%d\n"(x, y);

				//foreach(j, ref texture ; trrn.textures){
				//	textureData ~= format("%d %s", j, texture.name.charArrayToString);
				//}
				//auto ddsA = new Dds(trrn.dds_a);
				//auto ddsB = new Dds(trrn.dds_b);

				if(!noDds){
					auto megatileName = format!"%s_x%d_y%d"(trnFileName, x, y);
					std.file.write(buildPath(outFolder, megatileName~".a.dds"), trrn.dds_a);
					std.file.write(buildPath(outFolder, megatileName~".b.dds"), trrn.dds_b);
				}

				// Vertices
				foreach(ref v ; trrn.vertices){
					auto tint = v.tinting[0 .. 3].to!(float[]);
					tint[] /= 255.0;

					objData ~= format!"v %(%f %) 1.0 %(%f %)\n"(v.position, tint);
					objData ~= format!"vt %(%f %)\n"(v.uv);
					objData ~= format!"vn %(%f %)\n"(v.normal);
				}

				// Triangles
				foreach(ref t ; trrn.triangles){
					import std.range : repeat;
					objData ~= format("f %(%d/%) %(%d/%) %(%d/%)\n",
						(vertexOffset + t.vertices[0]).repeat(3),
						(vertexOffset + t.vertices[1]).repeat(3),
						(vertexOffset + t.vertices[2]).repeat(3)
					);
				}

				vertexOffset += trrn.vertices.length;

				// TODO: handle grass data

				//objData ~= "g grass\n";
				//trrn.grass.blades
				//	.each!((ref t){
				//		objData ~= format("l %(%d %)\n", [v.vertices[0] + 1, v.vertices[1] + 1, v.vertices[2] + 1]);
				//	});

				trrnCounter++;
			}

			buildPath(outFolder, trnFile.baseName.stripExtension ~ ".trrn.obj")
				.writeFile(objData);
		}
		break;


		case "trrn-import":{
			string trnFile;
			string ddsPath = null;
			bool noDds = false;
			auto res = getopt(args,
				config.required, "trn", "Existing TRN or TRX file to store the terrain mesh", &trnFile,
				"dds-path", "Folder containing DDS files to import as texture alpha maps", &ddsPath,
				"no-dds", "Do not import texture alpha maps", &noDds,
				);

			if(res.helpWanted || args.length == 1){
				improvedGetoptPrinter(
					"Import terrain mesh and textures into an existing TRN or TRX file\n"
					~"Usage: "~args[0]~" "~command~" map.obj --trn map.trx\n"
					~"\n"
					~"Wavefront format notes:\n"
					~"- Each megatile must be stored in a different object named with its megatile coordinates: 'megatile-x6y9'.\n"
					~"- If a megatile is not in the obj file, the TRN/TRX megatile won't be modified\n"
					~"- Grass is not imported.\n",
					res.options);
				return 0;
			}

			enforce(args.length == 2, "You can only provide one OBJ file");

			auto objFilePath = args[1];
			//auto objFile = File(objFilePath);

			if(ddsPath is null)
				ddsPath = objFilePath.dirName;

			auto trn = new Trn(trnFile);

			import nwnlibd.wavefrontobj;
			auto wfobj = new WavefrontObj(objFilePath.readText);
			wfobj.validate();

			TrnNWN2TerrainDimPayload* trwh = null;
			foreach(ref TrnNWN2TerrainDimPayload _trwh ; trn){
				trwh = &_trwh;
			}
			enforce(trwh !is null, "No TRWH packet found");

			TrnNWN2MegatilePayload*[] megatiles;
			megatiles.length = trwh.width * trwh.height;

			size_t trrnCounter = 0;
			foreach(ref TrnNWN2MegatilePayload trrn ; trn){
				size_t x = trrnCounter % trwh.width;
				size_t y = trrnCounter / trwh.width;

				if(!noDds){
					auto megatileName = format!"megatile-%s_x%d_y%d"(
						trnFile.baseName.stripExtension, x, y);

					trrn.dds_a = cast(ubyte[])buildPath(ddsPath, megatileName~".a.dds").readFile();
					trrn.dds_b = cast(ubyte[])buildPath(ddsPath, megatileName~".b.dds").readFile();
				}

				megatiles[trrnCounter] = &trrn;
				trrnCounter++;
			}

			foreach(name, ref obj ; wfobj.objects){
				TrnNWN2MegatilePayload* megatile = null;

				if(name.length >= 9 && name[0 .. 9] == "megatile-"){
					try{
						size_t x, y;
						name.dup.formattedRead!"megatile-x%dy%d"(x, y);
						megatile = megatiles[y * trwh.width + x];
					}
					catch(FormatException){}
				}

				if(megatile is null)
					stderr.writeln("Warning: object '", name, "' skipped");
				else{
					megatile.vertices.length = 0;
					megatile.triangles.length = 0;


					uint16_t vtxIdx = 0;
					uint16_t[size_t] vtxTransTable;
					auto triangles = obj
						.values
						.map!(g => g.faces)
						.join
						.filter!(t => t.vertices.length == 3);// Ignore non triangles
					foreach(ref t ; triangles){
						TrnNWN2MegatilePayload.Triangle trrnTri;
						foreach(i, v ; t.vertices){
							if(v !in vtxTransTable){
								vtxTransTable[v] = megatile.vertices.length.to!uint16_t;

								ubyte[4] color;
								if(wfobj.vertices[v - 1].color.isNull)
									color = [255, 255, 255, 255];
								else
									color = (wfobj.vertices[v - 1].color[] ~ 1.0)
										.map!(a => (a * 255).to!ubyte)
										.array[0 .. 4];

								megatile.vertices ~= TrnNWN2MegatilePayload.Vertex(
									wfobj.vertices[v - 1].position.v[0 .. 3],
									wfobj.normals[t.normals[i] - 1].v[0 .. 3],
									color,
									wfobj.textCoords[t.textCoords[i] - 1].v[0 .. 2],
									wfobj.textCoords[t.textCoords[i] - 1][].map!(a => cast(float)(fabs(a) / 10.0)).array[0 .. 2],
									);
							}

							trrnTri.vertices[i] = vtxTransTable[v];
						}
						megatile.triangles ~= trrnTri;
					}
				}
			}


			trnFile.writeFile(trn.serialize());
		}
		break;
	}
	return 0;
}



void stripASWM(ref TrnNWN2WalkmeshPayload aswm, bool silent){


	auto initVertices = aswm.vertices.length;
	auto initEdges = aswm.edges.length;
	auto initTriangles = aswm.triangles.length;



	uint32_t[] vertTransTable, edgeTransTable, triTransTable;//table[oldIndex] = newIndex
	vertTransTable.length = aswm.vertices.length;
	edgeTransTable.length = aswm.edges.length;
	triTransTable.length = aswm.triangles.length;
	uint32_t newIndex;

	bool[] usedVertices, usedEdges;
	usedVertices.length = aswm.vertices.length;
	usedEdges.length = aswm.edges.length;
	usedVertices[] = false;
	usedEdges[] = false;

	// Reduce triangle list & flag used vertices & edges
	newIndex = 0;
	foreach(i, ref triangle ; aswm.triangles){
		if(triangle.island != uint16_t.max){

			// Flag used / unused vertices & edges
			foreach(vert ; triangle.vertices){
				usedVertices[vert] = true;
			}
			foreach(edge ; triangle.linked_edges){
				if(edge != uint32_t.max)
					usedEdges[edge] = true;
			}

			// Reduce triangle list in place
			aswm.triangles[newIndex] = triangle;
			triTransTable[i] = newIndex++;
		}
		else
			triTransTable[i] = uint32_t.max;
	}
	aswm.triangles.length = newIndex;


	// Reduce vertices list
	newIndex = 0;
	foreach(i, used ; usedVertices){
		if(used){
			aswm.vertices[newIndex] = aswm.vertices[i];
			vertTransTable[i] = newIndex++;
		}
		else
			vertTransTable[i] = uint32_t.max;
	}
	aswm.vertices.length = newIndex;

	// Reduce edges list
	newIndex = 0;
	foreach(i, used ; usedEdges){
		if(used){
			aswm.edges[newIndex] = aswm.edges[i];
			edgeTransTable[i] = newIndex++;
		}
		else
			edgeTransTable[i] = uint32_t.max;
	}
	aswm.edges.length = newIndex;

	// Adjust indices in mesh data
	aswm.translateIndices(triTransTable, edgeTransTable, vertTransTable);


	// Adjust indices inside tiles pathtable
	uint32_t currentOffset = 0;
	foreach(i, ref tile ; aswm.tiles){

		struct Tri {
			uint32_t id;
			ubyte node;
		}
		Tri[] newLtn;
		foreach(j, ltn ; tile.path_table.local_to_node){
			// Ignore non unused/unwalkable triangles
			if(ltn == 0xff)
				continue;

			const newTriIndex = triTransTable[j + tile.header.triangles_offset];

			// Ignore removed triangles
			if(newTriIndex == uint32_t.max)
				continue;

			newLtn ~= Tri(newTriIndex, ltn);
		}

		foreach(ref ntl ; tile.path_table.node_to_local){
			assert(triTransTable[ntl + tile.header.triangles_offset] != uint32_t.max, "todo");
			ntl = triTransTable[ntl + tile.header.triangles_offset];
		}

		// Find new offset
		tile.header.triangles_offset = newLtn.length == 0? currentOffset : min(
			newLtn.minElement!"a.id".id,
			tile.path_table.node_to_local.minElement);

		// Adjust node_to_local indices with new offset
		tile.path_table.node_to_local[] -= tile.header.triangles_offset;

		// Adjust newLtn indices with new offset
		foreach(ref ltn ; newLtn)
			ltn.id -= tile.header.triangles_offset;

		// Resize & erase ltn data
		tile.path_table.local_to_node.length = newLtn.length == 0? 0 : newLtn.maxElement!"a.id".id + 1;
		tile.path_table.local_to_node[] = 0xff;

		// Set ltn data
		foreach(ltn ; newLtn){
			tile.path_table.local_to_node[ltn.id] = ltn.node;
		}


		tile.header.triangles_count = tile.path_table.local_to_node.length.to!uint32_t;

		currentOffset = tile.header.triangles_offset + tile.header.triangles_count;

		// Re-count linked vertices / edges
		tile.header.vertices_count = tile.path_table.node_to_local
			.map!(a => a != a.max? aswm.triangles[a].vertices[] : [])
			.join.sort.uniq.array.length.to!uint32_t;
		tile.header.edges_count = tile.path_table.node_to_local
			.map!(a => a != a.max?  aswm.triangles[a].linked_edges[] : [])
			.join.sort.uniq.array.length.to!uint32_t;
	}
	// Adjust indices in islands
	foreach(ref island ; aswm.islands){
		foreach(ref t ; island.exit_triangles){
			t = triTransTable[t];
			assert(t != uint32_t.max && t < aswm.triangles.length, "Invalid triangle index");
		}
	}

	if(!silent){
		writeln("Vertices: ", initVertices, " => ", aswm.vertices.length, " (stripped ", 100 - aswm.vertices.length * 100.0 / initVertices, "%)");
		writeln("Edges: ", initEdges, " => ", aswm.edges.length, " (stripped ", 100 - aswm.edges.length * 100.0 / initEdges, "%)");
		writeln("Triangles: ", initTriangles, " => ", aswm.triangles.length, " (stripped ", 100 - aswm.triangles.length * 100.0 / initTriangles, "%)");
	}
}


void writeWalkmeshObj(ref TrnNWN2WalkmeshPayload aswm, in string name, ref File obj, string[] features){
	obj.writeln("mtllib nwnlibd-colors.mtl");
	obj.writeln("o ",name);

	foreach(ref v ; aswm.vertices){
		obj.writefln("v %(%s %)", v.position);
	}

	string currColor = null;
	void setColor(string clr){
		if(clr!=currColor){
			obj.writeln("usemtl ", clr);
			currColor = clr;
		}
	}
	void randomColor(){
		switch(uniform(0, 12)){
			case 0:  setColor("default");    break;
			case 1:  setColor("dirt");       break;
			case 2:  setColor("grass");      break;
			case 3:  setColor("stone");      break;
			case 4:  setColor("wood");       break;
			case 5:  setColor("carpet");     break;
			case 6:  setColor("metal");      break;
			case 7:  setColor("swamp");      break;
			case 8:  setColor("mud");        break;
			case 9:  setColor("leaves");     break;
			case 10: setColor("water");      break;
			case 11: setColor("unwalkable"); break;
			default: assert(0);
		}
	}
	aswm.Vertex getTriangleCenter(in aswm.Triangle t){
		auto ret = aswm.vertices[t.vertices[0]];
		ret.position[] += aswm.vertices[t.vertices[1]].position[];
		ret.position[] += aswm.vertices[t.vertices[2]].position[];
		ret.position[] /= 3.0;
		return ret;
	}

	setColor("default");
	obj.writeln("s off");
	auto vertexOffset = aswm.vertices.length;

	if(!features.find("walkmesh").empty){
		writeln("walkmesh");

		obj.writeln("g walkmesh");

		foreach(i, ref t ; aswm.triangles) with(t) {
			if(flags & Flags.walkable && island != island.max){
				if(flags & Flags.dirt)
					setColor("dirt");
				else if(flags & Flags.grass)
					setColor("grass");
				else if(flags & Flags.stone)
					setColor("stone");
				else if(flags & Flags.wood)
					setColor("wood");
				else if(flags & Flags.carpet)
					setColor("carpet");
				else if(flags & Flags.metal)
					setColor("metal");
				else if(flags & Flags.swamp)
					setColor("swamp");
				else if(flags & Flags.mud)
					setColor("mud");
				else if(flags & Flags.leaves)
					setColor("leaves");
				else if(flags & (Flags.water | Flags.puddles))
					setColor("water");
				else
					setColor("default");
			}
			else
				setColor("unwalkable");

			if(flags & Flags.clockwise)
				obj.writefln("f %s %s %s", vertices[2]+1, vertices[1]+1, vertices[0]+1);
			else
				obj.writefln("f %s %s %s", vertices[0]+1, vertices[1]+1, vertices[2]+1);
		}
	}

	if(!features.find("edges").empty){
		writeln("edges");

		obj.writeln("g edges");

		foreach(ref edge ; aswm.edges){

			randomColor();

			auto vertA = aswm.vertices[edge.vertices[0]];
			auto vertB = aswm.vertices[edge.vertices[1]];

			auto vertCenterHigh = vertA.position;
			vertCenterHigh[] += vertB.position[];
			vertCenterHigh[] /= 2.0;
			vertCenterHigh[2] += 0.5;

			obj.writefln("v %(%s %)", vertCenterHigh);
			vertexOffset++;
			obj.writefln("f %s %s %s", edge.vertices[0] + 1, edge.vertices[1] + 1, vertexOffset);//Start index is 1

			if(edge.triangles[0] != uint32_t.max && edge.triangles[1] != uint32_t.max){

				auto triA = aswm.triangles[edge.triangles[0]];
				auto triB = aswm.triangles[edge.triangles[1]];

				double zAvg(ref aswm.Triangle triangle){
					double res = 0.0;
					foreach(v ; triangle.vertices)
						res += aswm.vertices[v].position[2];
					return res / 3.0;
				}

				auto centerA = [triA.center[0], triA.center[1], zAvg(triA)];
				auto centerB = [triB.center[0], triB.center[1], zAvg(triB)];

				obj.writefln("v %(%s %)", centerA);
				obj.writefln("v %(%s %)", centerB);
				vertexOffset += 2;

				obj.writefln("f %s %s %s", vertexOffset - 2, vertexOffset - 1, vertexOffset);//Start index is 1
			}

		}
	}

	if(!features.find("tiles").empty){
		writeln("tiles");

		obj.writeln("g tiles");

		foreach(ref tile ; aswm.tiles) with(tile) {
			randomColor();

			auto tileTriangles = path_table.node_to_local.dup.sort.uniq.array;
			tileTriangles[] += header.triangles_offset;

			foreach(t ; tileTriangles) with(aswm.triangles[t]) {
				obj.writefln("f %s %s %s", vertices[2]+1, vertices[1]+1, vertices[0]+1);
			}
		}
	}
	if(!features.find("pathtables-los").empty){
		writeln("pathtables-los");

		void writeLOS(bool losStatus){
			foreach(ref tile ; aswm.tiles) with(tile) {
				immutable offset = tile.header.triangles_offset;

				foreach(fromLocIdx, fromNodeIdx ; tile.path_table.local_to_node){
					if(fromNodeIdx == 0xff) continue;
					foreach(toLocIdx, toNodeIdx ; tile.path_table.local_to_node){
						if(toNodeIdx == 0xff) continue;


						const node = tile.path_table.nodes[fromNodeIdx * tile.path_table.node_to_local.length + toNodeIdx];
						if(node != 0xff && ((node & 0b1000_0000) > 0) == losStatus){

							auto a = getTriangleCenter(aswm.triangles[fromLocIdx + offset]).position;
							auto b = getTriangleCenter(aswm.triangles[toLocIdx + offset]).position;

							obj.writefln("v %(%s %)", a);
							obj.writefln("v %(%s %)", b);
							vertexOffset += 2;

							obj.writefln("l %s %s", vertexOffset - 1, vertexOffset);
						}
					}
				}
			}
		}

		obj.writeln("g pathtables-los");
		writeLOS(true);
		obj.writeln("g pathtables-nolos");
		writeLOS(false);
	}

	if(!features.find("randomtilepaths").empty){
		writeln("randomtilepaths");

		obj.writeln("g randomtilepaths");

		foreach(tileid, ref tile ; aswm.tiles) with(tile) {
			immutable offset = tile.header.triangles_offset;
			immutable len = tile.path_table.node_to_local.length;

			if(len == 0)
				continue;

			foreach(_ ; 0 .. 2){
				auto from = (uniform(0, len) + offset).to!uint32_t;
				auto to = (uniform(0, len) + offset).to!uint32_t;


				auto path = findPath(from, to);
				if(path.length > 1){
					auto firstCenter = getTriangleCenter(aswm.triangles[from]).position;
					firstCenter[2] += 1.0;
					obj.writefln("v %(%s %)", firstCenter);

					foreach(t ; path){
						auto center = getTriangleCenter(aswm.triangles[t]).position;
						obj.writefln("v %(%s %)", getTriangleCenter(aswm.triangles[t]).position);
					}

					obj.write("l ");
					foreach(i ; 0 .. path.length + 1){
						obj.write(vertexOffset + i + 1, " ");
					}
					obj.write(vertexOffset + 1); // loop on first point
					obj.writeln();

					vertexOffset += path.length + 1;
				}

			}

		}
	}

	if(!features.find("randomislandspaths").empty){
		writeln("randomislandspaths");

		obj.writeln("g randomislandspaths");
		foreach(_ ; 0 .. 8){
			immutable len = aswm.islands.length;
			auto from = uniform(0, len).to!uint16_t;
			auto to = uniform(0, len).to!uint16_t;


			auto path = aswm.findIslandsPath(from, to);
			if(path.length > 1){
				auto firstCenter = aswm.islands[from].header.center.position;
				firstCenter[2] += 1.0;
				obj.writefln("v %(%s %)", firstCenter);

				foreach(i ; path)
					obj.writefln("v %(%s %)", aswm.islands[i].header.center.position);

				obj.write("l ");
				foreach(i ; 0 .. path.length + 1){
					obj.write(vertexOffset + i + 1, " ");
				}
				obj.write(vertexOffset + 1); // loop on first point
				obj.writeln();

				vertexOffset += path.length + 1;
			}
		}

	}


	if(!features.find("islands").empty){
		writeln("islands");

		obj.writeln("g islands");

		foreach(ref island ; aswm.islands){
			randomColor();

			auto islandCenterIndex = vertexOffset;

			auto islandCenter = aswm.Vertex(island.header.center.position.dup[0..3]);
			float z = 0.0;
			island.exit_triangles
				.map!(t => aswm.triangles[t].vertices[])
				.join
				.each!(v => z += aswm.vertices[v].z);
			z /= island.exit_triangles.length * 3.0;

			islandCenter.z = z;
			obj.writefln("v %(%s %)", islandCenter.position);
			islandCenter.z += 1.0;
			obj.writefln("v %(%s %)", islandCenter.position);
			vertexOffset += 2;

			foreach(t ; island.exit_triangles) with(aswm.triangles[t]) {
				if(flags & Flags.clockwise)
					obj.writefln("f %s %s %s", vertices[0]+1, vertices[1]+1, vertices[2]+1);
				else
					obj.writefln("f %s %s %s", vertices[2]+1, vertices[1]+1, vertices[0]+1);

				float triCenterZ = 0.0;
				vertices[].map!(v => aswm.vertices[v].z).each!(a => triCenterZ += a);
				triCenterZ /= 3;

				obj.writefln("v %(%s %)", center[0 .. 2] ~ triCenterZ);
				vertexOffset++;

				obj.writefln("f %s %s %s", islandCenterIndex + 1, islandCenterIndex + 2, vertexOffset);
			}
		}
	}
}

enum colors = `
newmtl default
Ns 96.078431
Ka 1.0 1.0 1.0
Kd 0.80 0.80 0.80
Ks 0.5 0.5 0.5
Ke 0.0 0.0 0.0
Ni 1.0
d 1.0
illum 2

newmtl dirt
Ns 96.078431
Ka 1.0 1.0 1.0
Kd 0.76 0.61 0.48
Ks 0.5 0.5 0.5
Ke 0.0 0.0 0.0
Ni 1.0
d 1.0
illum 2

newmtl grass
Ns 96.078431
Ka 1.0 1.0 1.0
Kd 0.39 0.74 0.42
Ks 0.5 0.5 0.5
Ke 0.0 0.0 0.0
Ni 1.0
d 1.0
illum 2

newmtl stone
Ns 96.078431
Ka 1.0 1.0 1.0
Kd 0.60 0.60 0.60
Ks 0.5 0.5 0.5
Ke 0.0 0.0 0.0
Ni 1.0
d 1.0
illum 2

newmtl wood
Ns 96.078431
Ka 1.0 1.0 1.0
Kd 0.45 0.32 0.12
Ks 0.5 0.5 0.5
Ke 0.0 0.0 0.0
Ni 1.0
d 1.0
illum 2

newmtl carpet
Ns 96.078431
Ka 1.0 1.0 1.0
Kd 0.51 0.20 0.35
Ks 0.5 0.5 0.5
Ke 0.0 0.0 0.0
Ni 1.0
d 1.0
illum 2

newmtl metal
Ns 96.078431
Ka 1.0 1.0 1.0
Kd 0.75 0.75 0.75
Ks 0.5 0.5 0.5
Ke 0.0 0.0 0.0
Ni 1.0
d 1.0
illum 2

newmtl swamp
Ns 96.078431
Ka 1.0 1.0 1.0
Kd 0.53 0.63 0.30
Ks 0.5 0.5 0.5
Ke 0.0 0.0 0.0
Ni 1.0
d 1.0
illum 2

newmtl mud
Ns 96.078431
Ka 1.0 1.0 1.0
Kd 0.63 0.56 0.30
Ks 0.5 0.5 0.5
Ke 0.0 0.0 0.0
Ni 1.0
d 1.0
illum 2

newmtl leaves
Ns 96.078431
Ka 1.0 1.0 1.0
Kd 0.64 0.71 0.39
Ks 0.5 0.5 0.5
Ke 0.0 0.0 0.0
Ni 1.0
d 1.0
illum 2

newmtl leaves
Ns 96.078431
Ka 1.0 1.0 1.0
Kd 0.64 0.71 0.39
Ks 0.5 0.5 0.5
Ke 0.0 0.0 0.0
Ni 1.0
d 1.0
illum 2

newmtl water
Ns 92.156863
Ka 1.0 1.0 1.0
Kd 0.07 0.44 0.74
Ks 0.5 0.5 0.5
Ke 0.0 0.0 0.0
Ni 1.0
d 0.5
illum 2

newmtl unwalkable
Ns 96.078431
Ka 1.0 1.0 1.0
Kd 0.03 0.01 0.01
Ks 0.5 0.5 0.5
Ke 0.0 0.0 0.0
Ni 1.0
d 1.0
illum 2
`;



