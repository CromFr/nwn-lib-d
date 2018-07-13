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
	writeln("  aswm-dump: Print walkmesh data using a (barely) human-readable format");
	writeln("  aswm-bake: Re-bake all tiles of an already baked walkmesh");
}

int main(string[] args){
	version(unittest) if(args.length <= 1) return 0;

	if(args.length <= 1 || (args.length > 1 && (args[1] == "--help" || args[1] == "-h"))){
		usage(args[0]);
		return 0;
	}

	immutable command = args[1];
	args = args[0] ~ args[2..$];

	switch(command){
		default:
			usage(args[0]);
			return 1;
		case "aswm-strip":{
			bool inPlace = false;
			bool quiet = false;
			string targetPath = null;

			auto res = getopt(args,
				"in-place|i", "Provide this flag to overwrite the provided TRX file", &inPlace,
				"output|o", "Output file or directory. Mandatory if --in-place is not provided.", &targetPath,
				"quiet|q", "Do not display statistics", &quiet,
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

					import aswmstrip: stripASWM;
					stripASWM(aswm, quiet);
					aswm.validate();
				}

				enforce(found, "No ASWM packet found. Make sure you are targeting a TRX file.");

				auto finalData = trn.serialize();
				if(!quiet)
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

				import aswmtoobj: writeWalkmeshObj;
				writeWalkmeshObj(
					aswm,
					args[1].baseName.stripExtension,
					outfile,
					features);
			}
			enforce(found, "No ASWM packet found. Make sure you are targeting a TRX file.");

			if(targetDir != "-"){
				import aswmtoobj: colors;

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
			string outputFile = null;
			auto res = getopt(args,
				config.required, "trn", "Existing TRN or TRX file to store the terrain mesh", &trnFile,
				"dds-path", "Folder containing DDS files to import as texture alpha maps.\nDefault: search in --trn file's directory", &ddsPath,
				"no-dds", "Do not import texture alpha maps", &noDds,
				"output|o", "TRN/TRX file to write.\nDefault: the file provided by --trn", &outputFile,
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
			if(outputFile is null)
				outputFile = trnFile;

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
					auto megatileName = format!"%s_x%d_y%d"(
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

					megatile.validate();
				}

			}


			outputFile.writeFile(trn.serialize());
		}
		break;
	}
	return 0;
}




unittest{
	import std.file: tempDir, read, writeFile=write, exists;
	import std.path: buildPath;

	version(Windows)
		auto nullFile = "nul";
	else
		auto nullFile = "/dev/null";

	auto stdout_ = stdout;
	stdout = File(nullFile, "w");

	auto filePath = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__);

	assert(main(["nwn-trn", "--help"]) == 0);

	assert(main(["nwn-trn", "bake", "--help"]) == 0);
	assert(main([
			"nwn-trn", "bake",
			"--terrain2da=unittest/terrainmaterials.2da",
			"unittest/WalkmeshObjects",
			"-o", nullFile,
		]) == 0);

	assert(main(["nwn-trn", "aswm-check", "--help"]) == 0);
	assert(main([
			"nwn-trn", "aswm-check",
			"unittest/WalkmeshObjects.trn", "unittest/WalkmeshObjects.trx", "unittest/eauprofonde-portes.trx",
		]) == 0);

	assert(main(["nwn-trn", "aswm-strip", "--help"]) == 0);
	assert(main([
			"nwn-trn", "aswm-strip",
			"unittest/eauprofonde-portes.trx",
			"-o", filePath,
		]) == 0);
	auto trn = new Trn(filePath);
	foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
		assert(aswm.vertices.length == 15706);
		assert(aswm.edges.length == 42578);
		assert(aswm.triangles.length == 26814);
	}

	assert(main(["nwn-trn", "aswm-export-fancy", "--help"]) == 0);
	assert(main([
			"nwn-trn", "aswm-export-fancy",
			"-f", "walkmesh",
			"-f", "edges",
			"-f", "tiles",
			"-f", "pathtables-los",
			"-f", "randomtilepaths",
			"-f", "randomislandspaths",
			"-f", "islands",
			"unittest/eauprofonde-portes.trx",
			"-o", tempDir,
		]) == 0);

	assert(main(["nwn-trn", "aswm-export", "--help"]) == 0);
	assert(main([
			"nwn-trn", "aswm-export",
			"unittest/eauprofonde-portes.trn",
			"-o", filePath,
		]) == 0);

	assert(main(["nwn-trn", "aswm-import", "--help"]) == 0);
	assert(main([
			"nwn-trn", "aswm-import",
			"--obj", filePath,
			"--trn", "unittest/eauprofonde-portes.trx",
			"--terrain2da=unittest/terrainmaterials.2da",
			"-o", nullFile,
		]) == 0);

	assert(main(["nwn-trn", "trrn-export", "--help"]) == 0);
	assert(main([
			"nwn-trn", "trrn-export",
			"unittest/eauprofonde-portes.trx",
			"-o", tempDir,
		]) == 0);

	assert(main(["nwn-trn", "trrn-import", "--help"]) == 0);
	assert(main([
			"nwn-trn", "trrn-import",
			filePath,
			"--trn", "unittest/eauprofonde-portes.trx",
			"--dds-path", tempDir,
			"-o", nullFile,
		]) == 0);

	assert(main(["nwn-trn", "aswm-dump", "unittest/WalkmeshObjects.trx"]) == 0);

	assert(main(["nwn-trn", "aswm-bake", "--help"]) == 0);
	assert(main([
			"nwn-trn", "aswm-bake",
			"unittest/WalkmeshObjects.trx",
			"-o", nullFile,
		]) == 0);


	stdout = stdout_;
}
