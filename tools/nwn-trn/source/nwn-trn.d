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
import std.exception;
import std.random: uniform;
import std.format;
import std.math;
import std.parallelism;

import nwnlibd.path;
import nwnlibd.parseutils;
import nwnlibd.geometry;
import tools.common.getopt;
import nwn.trn;
import nwn.dds;
import gfm.math.vector;

class ArgException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

void usage(in string cmd){
	writeln("TRN / TRX tool");
	writeln("Usage: ", cmd.baseName, " command [args]");
	writeln();
	writeln("Commands");
	writeln("  info: Print TRN and packets header information");
	writeln("  bake: Bake an area (replacement for builtin nwn2toolset bake tool)");
	writeln("  check: Performs several checks on the TRN packets data");
	writeln("  optimize: Reduce the TRX file size for client or server usage");
	writeln("  trrn-export: Export the terrain mesh, textures and grass");
	writeln("  trrn-import: Import a terrain mesh, textures and grass into an existing TRN/TRX file");
	writeln("  watr-export: Export water mesh");
	writeln("  watr-import: Import a water mesh into an existing TRN/TRX file");
	writeln("  aswm-strip: Optimize TRX file size");
	writeln("  aswm-export: Export walkable walkmesh into a wavefront obj");
	writeln("  aswm-export-fancy: Export custom walkmesh data into a colored wavefront obj");
	writeln("  aswm-import: Import a wavefront obj as the walkmesh of an existing TRX file");
	writeln();
	writeln("Advanced commands:");
	writeln("  aswm-check: Checks if a TRX file contains valid data");
	writeln("  aswm-dump: Print walkmesh data using a (barely) human-readable format");
	writeln("  aswm-bake: Re-bake all tiles of an already baked walkmesh");
}

int main(string[] args){
	if(args.any!(a => a == "--version")){
		import nwn.ver: NWN_LIB_D_VERSION;
		writeln(NWN_LIB_D_VERSION);
		return 0;
	}
	if(args.length >= 2 && (args[1] == "--help" || args[1] == "-h")){
		usage(args[0]);
		return 0;
	}

	enforce(args.length > 1, "No subcommand provided");
	immutable command = args[1];
	args = args[0] ~ args[2..$];

	switch(command){
		default:
			usage(args[0]);
			return 1;

		case "info":
			bool strict = false;
			auto res = getopt(args,
				"strict", "Check some inconsistencies that does not cause issues with nwn2\nDefault: false", &strict);
			if(res.helpWanted){
				improvedGetoptPrinter(
					"Print TRN file information\n"
					~"Usage: "~args[0].baseName~" "~command~" file.trn",
					res.options);
				return 0;
			}
			enforce(args.length > 1, "No input file provided");
			enforce(args.length <=2, "Too many input files provided");

			auto data = cast(ubyte[])args[1].read();
			auto trn = new Trn(data);
			writeln("nwnVersion: ", trn.nwnVersion);
			writeln("versionMajor: ", trn.versionMajor);
			writeln("versionMinor: ", trn.versionMinor);
			writeln("packetsCount: ", trn.packets.length);
			foreach(i, ref packet ; trn.packets){
				writeln("# Packet ", i);
				writeln("packet[", i, "].type: ", packet.type);
				final switch(packet.type) with(TrnPacketType){
					case NWN2_TRWH:
						auto p = packet.as!TrnNWN2TerrainDimPayload;
						writeln("packet[", i, "].width: ", p.width);
						writeln("packet[", i, "].height: ", p.height);
						writeln("packet[", i, "].id: ", p.id);
						break;
					case NWN2_TRRN:
						auto p = packet.as!TrnNWN2MegatilePayload;
						writeln("packet[", i, "].name: ", p.name.charArrayToString.toSafeString);
						foreach(j, ref t ; p.textures){
							writeln("packet[", i, "].textures[", j, "].name: ", t.name.charArrayToString.toSafeString);
							writeln("packet[", i, "].textures[", j, "].color: ", t.color);
						}
						break;
					case NWN2_WATR:
						auto p = packet.as!TrnNWN2WaterPayload;
						writeln("packet[", i, "].name: ", p.name.charArrayToString.toSafeString);
						writeln("packet[", i, "].color: ", p.color);
						writeln("packet[", i, "].ripple: ", p.ripple);
						writeln("packet[", i, "].smoothness: ", p.smoothness);
						writeln("packet[", i, "].reflect_bias: ", p.reflect_bias);
						writeln("packet[", i, "].reflect_power: ", p.reflect_power);
						writeln("packet[", i, "].specular_power: ", p.specular_power);
						writeln("packet[", i, "].specular_cofficient: ", p.specular_cofficient);
						foreach(j, ref t ; p.textures){
							writeln("packet[", i, "].textures[", j, "].name: ", t.name.charArrayToString.toSafeString);
							writeln("packet[", i, "].textures[", j, "].direction: ", t.direction);
							writeln("packet[", i, "].textures[", j, "].rate: ", t.rate);
							writeln("packet[", i, "].textures[", j, "].angle: ", t.angle);
						}
						writeln("packet[", i, "].uv_offset: ", p.uv_offset);
						break;
					case NWN2_ASWM:
						auto p = packet.as!TrnNWN2WalkmeshPayload;
						writeln("packet[", i, "].aswm_version: ", p.header.aswm_version.format!"0x%02x");
						writeln("packet[", i, "].name: ", p.header.name.charArrayToString.toSafeString);
						writeln("packet[", i, "].owns_data: ", p.header.owns_data);
						writeln("packet[", i, "].vertices_count: ", p.vertices.length);
						writeln("packet[", i, "].edges_count: ", p.edges.length);
						writeln("packet[", i, "].triangles_count: ", p.triangles.length);
						break;
				}
			}
			break;

		case "check":
			bool strict = false;
			auto res = getopt(args,
				"strict", "Check some inconsistencies that does not cause issues with nwn2\nDefault: false", &strict);
			if(res.helpWanted){
				improvedGetoptPrinter(
					"Check if TRN packets contains valid data\n"
					~"Usage: "~args[0].baseName~" "~command~" file1.trx file2.trn ...",
					res.options);
				return 0;
			}
			enforce(args.length > 1, "No input file provided");

			foreach(file ; args[1 .. $]){
				Trn trn;
				try trn = new Trn(file);
				catch(Exception e){
					writeln("Error while parsing ", file, ": ", e);
				}

				if(trn !is null){
					foreach(i, ref packet ; trn.packets){
						try{
							final switch(packet.type){
								case TrnPacketType.NWN2_TRWH:
									break;
								case TrnPacketType.NWN2_TRRN:
									packet.as!(TrnPacketType.NWN2_TRRN).validate();
									break;
								case TrnPacketType.NWN2_WATR:
									packet.as!(TrnPacketType.NWN2_WATR).validate();
									break;
								case TrnPacketType.NWN2_ASWM:
									packet.as!(TrnPacketType.NWN2_ASWM).validate(strict);
									break;
							}
						}
						catch(TrnInvalidValueException e){
							writefln!"Error in %s on packet[%d] of type %s: %s"(file, i, packet.type, e.msg);
						}
					}
				}
			}
			break;

		case "optimize":{
			bool inPlace = false;
			bool quiet = false;
			bool server = false;
			string targetPath = null;
			uint threads = 0;
			float roundBound = float.nan;

			auto res = getopt(args,
				"in-place|i", "Provide this flag to overwrite the provided TRX file", &inPlace,
				"output|o", "Output file or directory. Mandatory if --in-place is not provided.", &targetPath,
				"server", "Optimize for server usage (Optimize for client if not provided).", &server,
				"quiet|q", "Do not display statistics", &quiet,
				"round", "Round floating point values, to enhance compressibility. Set to 0.02 to round to the nearest multiple of 0.02.", &roundBound,
				"j", "Threads to use. Default to the number of available threads on this machine.", &threads,
				);
			if(res.helpWanted){
				improvedGetoptPrinter(
					"Optimize TRN/TRX files to improve file size, compressibility and game/server memory usage.\n"
					~"\n"
					~"Usage: "~args[0].baseName~" "~command~" map.trx -o optimized_map.trx\n"
					~"       "~args[0].baseName~" "~command~" -i map.trx",
					res.options,
					multilineStr!"
						Optimization details:
						- TRWH (area size):
						  + Zero-out ID field
						- TRRN (terrain mesh & grass):
						  + Zero-out megatile name and grass patch names
						  + Clean trailing garbage in texture names and grass patch names
						- WATR (water mesh):
						  + Zero-out megatile name and padding
						  + Reduce the triangles count to 2 per megatile (only if the water is planar)
						- ASWM (walk mesh):
						  + Zero-out megatile name, tile names and island padding
						  + Remove triangles that are not walkable, and their associated data (using aswm-strip)

						Server optimization details:
						- All the above optimizations
						- Remove TRRN and WATR data (keeping only TRWH and ASWM)

						Notes:
						You shouldn't optimize TRN files, as these files are only used by the toolset
						and it may not work very well with certain optimizations (for example, you
						won't be able to extend water planes after the optimization).
					");
				return 0;
			}
			enforce(args.length > 1, "No input file provided");

			if(inPlace){
				enforce(targetPath is null, "You cannot use --in-place with --output");
				enforce(args.length >= 2, "No input file");
			}
			else{
				enforce(args.length <=2, "Too many input files provided");
				if(targetPath is null)
					targetPath = ".";
			}

			if(threads > 0)
				defaultPoolThreads = threads;

			float roundFloat(in float f){
				return round(f / roundBound) * roundBound;
			}

			foreach(file ; args[1 .. $].parallel){
				auto data = cast(ubyte[])file.read();
				auto trn = new Trn(data);
				size_t initLen = data.length;

				// Remove unneeded packets
				if(server){
					typeof(trn.packets) newPackets;
					foreach(i, ref packet ; trn.packets){
						final switch(packet.type){
							case TrnPacketType.NWN2_TRRN:
							case TrnPacketType.NWN2_WATR:
								break;
							case TrnPacketType.NWN2_TRWH:
							case TrnPacketType.NWN2_ASWM:
								newPackets ~= packet;
								break;
						}
					}
					trn.packets = newPackets;
				}

				// Size of a megatile
				// 9.0 for interior areas, 40.0 for exterior areas
				float megatileSize = 9.0;
				foreach(ref TrnNWN2MegatilePayload packet ; trn){
					megatileSize = 40.0;
					break;
				}


				// Clean garbage in fields (uninitialized memory written that was written to the file)
				foreach(ref packet ; trn.packets){
					final switch(packet.type){
						case TrnPacketType.NWN2_TRWH:
							packet.as!TrnNWN2TerrainDimPayload.id = 0;
							break;
						case TrnPacketType.NWN2_TRRN:
							with(packet.as!TrnNWN2MegatilePayload){
								// Zero out trailing / useless data
								name[] = 0;

								foreach(ref t ; textures)
									t.name = t.name.charArrayToString.stringToCharArray!(typeof(t.name));

								foreach(ref g ; grass){
									g.name[] = 0;
									g.texture = g.texture.charArrayToString.stringToCharArray!(typeof(g.texture));
								}


								if(!roundBound.isNaN){
									foreach(ref v ; vertices){
										v.position.each!((ref f){f = roundFloat(f);});
										v.normal.each!((ref f){f = roundFloat(f);});
										v.weights.each!((ref f){f = roundFloat(f);});
									}
								}

								validate();
							}
							break;

						case TrnPacketType.NWN2_WATR:
							with(packet.as!TrnNWN2WaterPayload){
								// Zero out trailing / useless data
								name[] = 0;
								unknown[] = 0;

								// If planar water mesh, simplify the mesh
								float altitude = vertices[0].position[2];
								bool isPlanar = vertices.all!(v => v.position[2] == altitude);

								if(isPlanar){
									import gfm.math.box;
									auto waterMask = Dds(dds).toBitmap!(ubyte);

									// Build bounding box of water pixels
									box2f aabb;
									foreach(y ; 0 .. waterMask.height){
										foreach(x ; 0 .. waterMask.width){
											if(waterMask[x, y] == ubyte.max){
												box2f pixBox = box2f(vec2f(x, y), vec2f(x + 1, y + 1));

												if(aabb.min.x.isNaN)
													aabb = pixBox;
												else if(!aabb.contains(pixBox))
													aabb = aabb.expand(pixBox);
											}
										}
									}

									if(aabb.min.x.isNaN){
										vertices.length = 0;
										triangles.length = 0;
										triangles_flags[] = 0;
									}
									else{
										// Move / resize bounding box to match megatile size & position
										const offset = vec2f(megatile_position[0], megatile_position[1]) * megatileSize;
										aabb.min = aabb.min * megatileSize / 128f + offset;
										aabb.max = aabb.max * megatileSize / 128f + offset;

										// 4 corners of the aabb
										float[3] a = [aabb.min.x, aabb.min.y, altitude];
										float[3] b = [aabb.max.x, aabb.min.y, altitude];
										float[3] c = [aabb.max.x, aabb.max.y, altitude];
										float[3] d = [aabb.min.x, aabb.max.y, altitude];

										vertices = [
											TrnNWN2WaterPayload.Vertex(a),
											TrnNWN2WaterPayload.Vertex(b),
											TrnNWN2WaterPayload.Vertex(c),
											TrnNWN2WaterPayload.Vertex(d),
										];
										// calculate texture coordinates
										vertices.each!((ref v){
											v.uv = [(v.position[0] - offset.x) / megatileSize, (v.position[1] - offset.y) / megatileSize];
											v.uvx5 = v.uv[] * 5.0;
										});
										triangles = [
											TrnNWN2WaterPayload.Triangle([1, 3, 0]),
											TrnNWN2WaterPayload.Triangle([2, 3, 1]),
										];
										triangles_flags = [0, 0];
									}
								}


								if(!roundBound.isNaN){
									foreach(ref v ; vertices){
										v.position.each!((ref f){f = roundFloat(f);});
										v.uvx5.each!((ref f){f = roundFloat(f);});
										v.uv.each!((ref f){f = roundFloat(f);});
									}
								}

								validate();
							}
							break;
						case TrnPacketType.NWN2_ASWM:
							import aswmstrip: stripASWM;
							stripASWM(packet.as!TrnNWN2WalkmeshPayload, true);

							with(packet.as!TrnNWN2WalkmeshPayload){
								// Zero out trailing / useless data
								header.name[] = 0;

								header.unknownB = 0;

								foreach(ref t ; tiles)
									t.header.name[] = 0;

								foreach(ref ipn ; islands_path_nodes)
									ipn._padding = 0;

								if(!roundBound.isNaN){
									foreach(ref v ; vertices){
										v.position.each!((ref f){f = roundFloat(f);});
									}
									foreach(ref t ; triangles){
										t.center.each!((ref f){f = roundFloat(f);});
										t.normal.each!((ref f){f = roundFloat(f);});
										t.dot_product = roundFloat(t.dot_product);
									}
									foreach(ref tile ; tiles){
										foreach(ref v ; tile.vertices){
											v.position.each!((ref f){f = roundFloat(f);});
										}
									}
									foreach(ref i ; islands){
										i.header.center.position.each!((ref f){f = roundFloat(f);});
										i.adjacent_islands_dist.each!((ref f){f = roundFloat(f);});
									}
									islands_path_nodes.each!((ref ipn){ipn.weight = roundFloat(ipn.weight);});
								}

								validate();
							}
							break;
					}
				}

				auto finalData = trn.serialize();
				if(!quiet){
					writefln("%-32s File size: %9dB => %9dB (stripped %.2f%%)",
						file.baseName.stripExtension, initLen, finalData.length, 100 - finalData.length * 100.0 / initLen
					);
				}

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

		case "aswm-strip":{
			bool inPlace = false;
			bool quiet = false;
			string targetPath = null;

			auto res = getopt(args,
				"in-place|i", "Provide this flag to overwrite the provided TRX file", &inPlace,
				"output|o", "Output file or directory. Mandatory if --in-place is not provided.", &targetPath,
				"quiet|q", "Do not display statistics", &quiet,
				);
			if(res.helpWanted){
				improvedGetoptPrinter(
					"Reduce TRX file size by removing non walkable triangles from walkmesh and path tables\n"
					~"Usage: "~args[0].baseName~" "~command~" map.trx -o stripped_map.trx\n"
					~"       "~args[0].baseName~" "~command~" -i map.trx",
					res.options);
				return 0;
			}
			enforce(args.length > 1, "No input file provided");

			if(inPlace){
				enforce(targetPath is null, "You cannot use --in-place with --output");
				enforce(args.length >= 2, "No input file");
			}
			else{
				enforce(args.length <=2, "Too many input files provided");
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

			if(res.helpWanted){
				improvedGetoptPrinter(
					"Convert NWN2 walkmeshes into TRX / OBJ (only TRX => OBJ supported for now)\n"
					~"Usage: "~args[0].baseName~" "~command~" map.trx\n"
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
			enforce(args.length > 1, "No input file provided");
			enforce(args.length <=2, "Too many input files provided");

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

			if(res.helpWanted){
				improvedGetoptPrinter(
					"Export all walkable triangles into a Wavefront OBJ file.\n"
					~"Usage: "~args[0].baseName~" "~command~" map.trx\n"
					~"       "~args[0].baseName~" "~command~" map.trx -o outputFile.obj\n",
					res.options);
				return 0;
			}
			enforce(args.length > 1, "No input file provided");
			enforce(args.length <=2, "Too many input files provided");

			auto inputFile = args[1];

			if(outFile.exists && outFile.isDir)
				outFile = buildPath(outFile, inputFile.baseName ~ ".aswm.obj");

			foreach(ref TrnNWN2WalkmeshPayload aswm ; new Trn(inputFile)){
				aswm.toGenericMesh.toObj(outFile);
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
					~"Usage: "~args[0].baseName~" "~command~" --trn map.trx --obj walkmesh.obj --terrain2da ./terrainmaterials.2da -o newmap.trx\n"
					~"       "~args[0].baseName~" "~command~" --trn map.trx --obj walkmesh.obj --terrain2da ./terrainmaterials.2da\n",
					res.options);
				return 0;
			}
			enforce(args.length == 1, "Too many arguments");

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
			if(args.any!(a => a == "-h" || a == "--help")){
				writeln("Dump walkmesh data");
				writeln("Usage: "~args[0].baseName~" "~command~" file.trx");
				return 0;
			}
			enforce(args.length > 1, "No input file provided");
			enforce(args.length <=2, "Too many input files provided");

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
			if(res.helpWanted){
				improvedGetoptPrinter(
					"Re-bake all tile / islands path tables of a baked TRX file.\n"
					~"Usage: "~args[0].baseName~" "~command~" map.trx -o baked_map.trx\n"
					~"       "~args[0].baseName~" "~command~" -i map.trx",
					res.options);
				return 0;
			}
			enforce(args.length > 1, "No input file provided");

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
			if(res.helpWanted){
				improvedGetoptPrinter(
					"Check if ASWM packets are valid.\n"
					~"Usage: "~args[0].baseName~" "~command~" file1.trx file2.trx ...",
					res.options);
				return 0;
			}
			enforce(args.length > 1, "No input file provided");

			foreach(file ; args[1 .. $]){
				auto trn = new Trn(file);
				foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
					aswm.validate(strict);
				}
			}
		}
		break;


		case "bake":{
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
				"terrain2da", "Path to terrainmaterials.2da, to generate footstep sounds. By default the official NWN2 2da will be used.", &terrain2daPath,
				"trn", "TRN file path. Default to $map_name_without_extension.trn", &trnPath,
				"reuse-trx|r", "Reuse walkmesh from an already existing TRX file", &reuseTrx,
				"force-walkable", "Make all triangles walkable. Triangles removed with walkmesh cutters won't be walkable.", &forceWalkable,
				"no-wmcutter", "Do not remove triangles inside walkmesh cutters", &noWmCutters,
				"keep-borders", "Do not remove exterior area borders from baked mesh. (can be used with --force-walkable to make borders walkable).", &keepBorders,
				// "git", "GIT file path. Default to $map_name_without_extension.git", &gitPath,
				"j", "Parallel threads for baking multiple maps at the same time", &threads,
				"unsafe", "Skip TRX validation checks, ie for dumping content & debugging", &unsafe,
			);
			if(res.helpWanted){
				improvedGetoptPrinter(
					"Generate baked TRX file.\n"
					~"Usage: "~args[0].baseName~" "~command~" map_name -o baked.trx\n"
					~"       "~args[0].baseName~" "~command~" --terrain2da ./terrainmaterials.2da map_name map_name_2 ...\n"
					~" `map_name` can be any map file with or without its extension (.are, .git, .gic, .trn, .trx)",
					res.options);
				return 0;
			}

			enforce(args.length > 1 || trnPath !is null, "No input file provided");
			enforce(args.length <= 2 || trnPath !is null, "Too many input files provided");

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
				terrainmaterials = new TwoDA(cast(ubyte[])import("terrainmaterials.2da"));

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

				// Extract all walkmesh cutters data
				alias WMCutter = vec2f[];
				WMCutter[] wmCutters;
				foreach(trigger ; git["TriggerList"].get!GffList){
					if(trigger["Type"].get!GffInt == 3){
						// Walkmesh cutter
						auto start = [trigger["XPosition"].get!GffFloat, trigger["YPosition"].get!GffFloat];

						// what about: XOrientation YOrientation ZOrientation ?
						WMCutter cutter;
						foreach(point ; trigger["Geometry"].get!GffList){
							cutter ~= vec2f(
								start[0] + point["PointX"].get!GffFloat,
								start[1] + point["PointY"].get!GffFloat,
							);
						}

						wmCutters ~= cutter;
					}
				}

				import std.datetime.stopwatch: StopWatch;
				auto sw = new StopWatch;
				sw.start();

				foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){

					stderr.writeln("Cutting mesh");
					auto mesh = aswm.toGenericMesh();
					foreach(i, ref wmCutter ; wmCutters){
						stderr.writefln("  Walkmesh cutter %d / %d", i + 1, wmCutters.length);
						if(wmCutter.length < 3){
							stderr.writeln("    Warning: Invalid walkmesh cutter geometry (cutter n°%d has only %d vertices)", i + 1, wmCutter.length);
							continue;
						}
						if(isPolygonComplex(wmCutter)){
							stderr.writeln("    Warning: Complex / self intersecting walkmesh cutters are not supported yet: ", wmCutter);
							continue;
						}
						mesh.polygonCut(wmCutter);
					}
					aswm.setGenericMesh(mesh);

					stderr.writeln("Calculating path tables");
					aswm.tiles_flags = 31;
					if(forceWalkable){
						foreach(ref t ; aswm.triangles)
							t.flags |= t.Flags.walkable;
					}
					aswm.bake(!keepBorders);

					if(terrainmaterials !is null){
						stderr.writeln("Setting footstep sounds");
						aswm.setFootstepSounds(trn.packets, terrainmaterials);
					}

					if(!unsafe){
						stderr.writeln("Verifying walkmesh");
						aswm.validate();
					}
				}
				sw.stop();
				writeln(resname.baseName.leftJustify(32), " ", sw.peek.total!"msecs"/1000.0, " seconds");

				stderr.writeln("Writing file");
				std.file.write(trxFilePath, trn.serialize());

			}

		}
		break;


		case "trrn-export":{
			string outFolder = ".";
			bool noTextures = false;
			bool noGrass = false;
			auto res = getopt(args,
				"output|o", "Output directory where to write the OBJ and DDS file. Default: '.'", &outFolder,
				"no-textures", "Do not output texture data (DDS alpha maps & config)", &noTextures,
				"no-grass", "Do not output grass data (3D lines & config)", &noGrass,
			);

			if(res.helpWanted){
				improvedGetoptPrinter(
					"Export terrain mesh, textures and grass into wavefront obj, json and DDS files.\n"
					~"Note: works for both TRN and TRX files, though TRN files are only used by the toolset.\n"
					~"Usage: "~args[0].baseName~" "~command~" map.trx\n"
					~"       "~args[0].baseName~" "~command~" map.trx -o converted/\n"
					~"\n"
					~"Wavefront format notes:\n"
					~"- Each megatile is stored in a different object named with its megatile coordinates: 'megatile-x6y9' or 'megatile-x6y9-MTName' if the megatile has a name.\n"
					~"  This naming scheme is mandatory.\n"
					~"- There can be only one megatile at a given megatile coordinate.\n"
					~"- Vertex colors are exported, but many 3d tools don't handle it.\n"
					~"- Grass is exported as lines using an arbitrary format:\n"
					~"    + first point: grass blade position\n"
					~"    + second point: grass blade normal + position\n"
					~"    + third point: grass blade dimension + normal + position\n",
					res.options);
				return 0;
			}
			enforce(args.length > 1, "No input file provided");
			enforce(args.length <=2, "Too many input files provided");


			auto trnFile = args[1];
			auto trnFileName = trnFile.baseName;
			auto trn = new Trn(trnFile);

			TrnNWN2TerrainDimPayload* trwh = null;
			foreach(ref TrnNWN2TerrainDimPayload _trwh ; trn){
				trwh = &_trwh;
			}
			enforce(trwh !is null, "No TRWH packet found");


			import nwnlibd.wavefrontobj: WavefrontObj;
			auto wfobj = new WavefrontObj();
			import std.json: JSONValue;
			JSONValue trrnConfig;


			size_t trrnCounter = 0;
			foreach(ref TrnNWN2MegatilePayload trrn ; trn){
				size_t x = trrnCounter % trwh.width;
				size_t y = trrnCounter / trwh.width;
				auto id = format!"x%dy%d"(x, y);

				// Json
				trrnConfig[id] = JSONValue([
						"name": JSONValue(trrn.name[0] == 0? null : trrn.name.ptr.fromStringz)
					]);
				if(!noTextures){
					trrnConfig[id]["textures"] = JSONValue(trrn.textures[].map!(a => JSONValue([
							"name":  JSONValue(a.name.ptr.fromStringz),
							"color": JSONValue(a.color),
						])).array);
				}
				if(!noGrass){
					trrnConfig[id]["grass"] = JSONValue(trrn.grass[].map!(a => JSONValue([
							"name":  JSONValue(a.name.ptr.fromStringz),
							"texture": JSONValue(a.texture.ptr.fromStringz),
						])).array);
				}

				// DDS
				if(!noTextures){

					buildPath(outFolder, trnFileName ~ ".trrn." ~ id ~ ".a.dds")
						.writeFile(trrn.dds_a);
					buildPath(outFolder, trnFileName ~ ".trrn." ~ id ~ ".b.dds")
						.writeFile(trrn.dds_b);
				}

				// Vertices
				size_t vi = wfobj.vertices.length + 1;
				size_t vti = wfobj.textCoords.length + 1;
				size_t vni = wfobj.normals.length + 1;

				foreach(ref v ; trrn.vertices){
					auto tint = vec3f(v.tinting[0 .. 3].to!(float[])) / 255.0;

					wfobj.vertices ~= WavefrontObj.WFVertex(vec3f(v.position), Nullable!vec3f(tint));
					wfobj.textCoords ~= vec2f(v.uv);
					wfobj.normals ~= vec3f(v.normal);
				}

				// Triangles
				auto grp = WavefrontObj.WFGroup();
				foreach(ref triangle ; trrn.triangles){
					auto v = triangle.vertices.to!(size_t[]);
					v[] += vi;
					auto vt = triangle.vertices.to!(size_t[]);
					vt[] += vti;
					auto vn = triangle.vertices.to!(size_t[]);
					vn[] += vni;

					grp.faces ~= WavefrontObj.WFFace(
						v,
						Nullable!(size_t[])(vt),
						Nullable!(size_t[])(vn));
				}
				wfobj.objects[format!"megatile-%s"(id)] = WavefrontObj.WFObject([
					null: grp,
				]);

				// Grass
				if(!noGrass && trrn.grass.length > 0){
					// TODO: need to understand how grass works in order to
					// display relevant data
					foreach(gi, ref g ; trrn.grass){
						auto grassGrp = WavefrontObj.WFGroup();
						foreach(ref b ; g.blades){
							vi = wfobj.vertices.length + 1;

							auto pos = vec3f(b.position);
							auto dir = vec3f(b.direction);
							auto dim = vec3f(b.dimension);

							wfobj.vertices ~= WavefrontObj.WFVertex(pos);
							wfobj.vertices ~= WavefrontObj.WFVertex(pos + dir);
							wfobj.vertices ~= WavefrontObj.WFVertex(pos + dir + dim);

							grassGrp.lines ~= WavefrontObj.WFLine([
								vi,
								vi + 1,
								vi + 2,
								vi]);
						}
						wfobj.objects[format!"grass-%s-%d"(id, gi)] = WavefrontObj.WFObject([
							null: grassGrp,
						]);
					}
				}

				trrnCounter++;
			}

			enforce(trrnCounter > 0, "No TRRN data found. Note: interior areas have no TRRN data.");

			wfobj.validate();
			buildPath(outFolder, trnFileName ~ ".trrn.obj").writeFile(wfobj.serialize());
			buildPath(outFolder, trnFileName ~ ".trrn.json").writeFile(trrnConfig.toPrettyString);
		}
		break;


		case "trrn-import":{
			string trnFile;
			bool noTextures = false;
			bool noGrass = false;
			string outputFile = null;
			bool emptyMegatiles = false;
			auto res = getopt(args,
				config.required, "trn", "Existing TRN or TRX file to store the terrain mesh", &trnFile,
				"no-textures", "Do not import texture data (DDS alpha maps & config)", &noTextures,
				"no-grass", "Do not import grass data (3D lines & config)", &noGrass,
				"rm", "Empty all megatiles before importing new mesh.\nUse with --no-textures to obtain harmless but glitchy textures.", &emptyMegatiles,
				"output|o", "TRN/TRX file to write.\nDefault: overwrite the file provided by --trn", &outputFile,
			);

			if(res.helpWanted){
				improvedGetoptPrinter(
					"Import terrain mesh, textures and grass into an existing TRN or TRX file\n"
					~"All needed files (json, dds) must be located in the same directory as the obj file.\n"
					~"Usage: "~args[0].baseName~" "~command~" map.obj --trn map.trx\n"
					~"\n"
					~"Wavefront format notes:\n"
					~"- Each megatile must be stored in a different object named with its megatile coordinates: 'megatile-x6y9'.\n"
					~"- If a megatile is not in the obj file, the TRN/TRX megatile won't be modified\n",
					res.options);
				return 0;
			}
			enforce(args.length > 1, "No input file provided");
			enforce(args.length <=2, "Too many input files provided");

			auto objFilePath = args[1];
			auto objFileDir = objFilePath.dirName;
			auto objFileBaseName = objFilePath.baseName(".trrn.obj");

			if(outputFile is null)
				outputFile = trnFile;

			auto trn = new Trn(trnFile);

			import nwnlibd.wavefrontobj;
			auto wfobj = new WavefrontObj(objFilePath.readText);
			wfobj.validate();

			import std.json;
			auto trrnConfig = buildPath(objFileDir, objFileBaseName ~ ".trrn.json").readText.parseJSON;


			TrnNWN2TerrainDimPayload* trwh = null;
			foreach(ref TrnNWN2TerrainDimPayload _trwh ; trn){
				trwh = &_trwh;
			}
			enforce(trwh !is null, "No TRWH packet found");


			size_t trrnCounter;
			foreach(ref TrnNWN2MegatilePayload trrn ; trn){
				size_t x = trrnCounter % trwh.width;
				size_t y = trrnCounter / trwh.width;
				string id = format!"x%dy%d"(x, y);

				if(emptyMegatiles){
					trrn.name[] = 0;
					foreach(ref t ; trrn.textures){
						t.name[] = 0;
						t.color[] = 1.0;
					}
					trrn.vertices.length = 0;
					trrn.triangles.length = 0;
					// TODO: empty DDS
					trrn.grass.length = 0;
				}

				// Megatile name
				trrn.name = trrnConfig[id]["name"].str.stringToCharArray!(char[128]);

				// Mesh
				if(auto o = ("megatile-"~id) in wfobj.objects){
					trrn.vertices.length = 0;
					trrn.triangles.length = 0;

					uint16_t[size_t] vtxTransTable;
					auto triangles = o.groups
						.values
						.map!(g => g.faces)
						.join
						.filter!(t => t.vertices.length == 3);// Ignore non triangles
					foreach(ref t ; triangles){
						TrnNWN2MegatilePayload.Triangle trrnTri;
						foreach(i, v ; t.vertices){
							if(v !in vtxTransTable){
								// Add vertices as needed
								vtxTransTable[v] = trrn.vertices.length.to!uint16_t;

								ubyte[4] color;
								if(wfobj.vertices[v - 1].color.isNull)
									color = [255, 255, 255, 255];
								else
									color = (wfobj.vertices[v - 1].color[] ~ 1.0)
										.map!(a => (a * 255).to!ubyte)
										.array[0 .. 4];

								trrn.vertices ~= TrnNWN2MegatilePayload.Vertex(
									wfobj.vertices[v - 1].position.v[0 .. 3],
									wfobj.normals[t.normals[i] - 1].v[0 .. 3],
									color,
									wfobj.textCoords[t.textCoords[i] - 1].v[0 .. 2],
									wfobj.textCoords[t.textCoords[i] - 1][].map!(a => cast(float)(fabs(a) / 10.0)).array[0 .. 2],
								);
							}

							trrnTri.vertices[i] = vtxTransTable[v];
						}
						trrn.triangles ~= trrnTri;
					}

				}

				// DDS & textures
				if(!noTextures && id in trrnConfig){
					// Textures
					foreach(i, ref t ; trrn.textures){
						t.name = trrnConfig[id]["textures"][i]["name"]
							.str
							.stringToCharArray!(char[32]);
						t.color = trrnConfig[id]["textures"][i]["color"]
							.array
							.map!(a => a.toString.to!float)
								.array;
					}

					// DDS
					trrn.dds_a = cast(ubyte[])buildPath(objFileDir, objFileBaseName ~ ".trrn." ~ id ~ ".a.dds").readFile();
					trrn.dds_b = cast(ubyte[])buildPath(objFileDir, objFileBaseName ~ ".trrn." ~ id ~ ".b.dds").readFile();
				}

				// Grass
				if(!noGrass && id in trrnConfig){
					trrn.grass.length = 0;

					size_t i;
					WavefrontObj.WFObject* o;
					for(i = 0, o = format!"grass-%s-%d"(id, i) in wfobj.objects
						; o !is null
						; i++, o = format!"grass-%s-%d"(id, i) in wfobj.objects){

						TrnNWN2MegatilePayload.Grass grass;

						// Textures
						grass.name = trrnConfig[id]["grass"][i]["name"].str.stringToCharArray!(char[32]);
						grass.texture = trrnConfig[id]["grass"][i]["texture"].str.stringToCharArray!(char[32]);

						// Data
						auto lines = o.groups
							.values
							.map!(g => g.lines)
							.join
							.filter!(t => t.vertices.length == 4);
						foreach(ref l ; lines){
							auto position  = wfobj.vertices[l.vertices[0] - 1].position;
							auto direction = wfobj.vertices[l.vertices[1] - 1].position - position;
							auto dimension = wfobj.vertices[l.vertices[2] - 1].position - direction - position;

							grass.blades ~= TrnNWN2MegatilePayload.Grass.Blade(
								position.v[0..3],
								direction.v[0..3],
								dimension.v[0..3]);
						}

						trrn.grass ~= grass;
					}
				}

				trrnCounter++;
			}

			enforce(trrnCounter > 0, "No TRRN data found. Note: interior areas have no TRRN data.");
			outputFile.writeFile(trn.serialize());
		}
		break;

		case "watr-export":{

			string outFolder = ".";
			bool noTextures = false;
			bool exportAll = false;
			auto res = getopt(args,
				"output|o", "Output directory where to write the OBJ, JSON and DDS files. Default: '.'", &outFolder,
				"no-textures", "Do not output texture data (DDS alpha maps & config)", &noTextures,
				"all", "Export all triangles, including those without water", &exportAll,
				);

			if(res.helpWanted){
				improvedGetoptPrinter(
					"Export water mesh and properties into a wavefront obj, json and dds files.\n"
					~"Note: works on both TRN and TRX files, though TRN files are only used by the toolset.\n"
					~"Usage: "~args[0].baseName~" "~command~" map.trx\n"
					~"       "~args[0].baseName~" "~command~" map.trx -o converted/\n",
					res.options);
				return 0;
			}
			enforce(args.length > 1, "No input file provided");
			enforce(args.length <=2, "Too many input files provided");


			auto trnFile = args[1];
			auto trnFileName = trnFile.baseName;
			auto trn = new Trn(trnFile);

			import nwnlibd.wavefrontobj: WavefrontObj;
			auto wfobj = new WavefrontObj();
			wfobj.mtllibs ~= trnFileName ~ ".watr.mtl";
			string wfmtl = "# This file is not used during WATR importation\n";
			import std.json: JSONValue;
			JSONValue watrConfig;

			size_t watrIdx;
			foreach(ref TrnNWN2WaterPayload watr ; trn){
				immutable name = format!"water-%d"(watrIdx);

				// Config
				watrConfig[watrIdx.to!string] = JSONValue([
					"name":                JSONValue(watr.name.ptr.fromStringz),
					"megatile_position":   JSONValue(watr.megatile_position),
					"color":               JSONValue(watr.color),
					"ripple":              JSONValue(watr.ripple),
					"smoothness":          JSONValue(watr.smoothness),
					"reflect_bias":        JSONValue(watr.reflect_bias),
					"reflect_power":       JSONValue(watr.reflect_power),
					"specular_power":      JSONValue(watr.specular_power),
					"specular_cofficient": JSONValue(watr.specular_cofficient),
					"textures":            JSONValue(watr.textures[].map!(a => JSONValue([
							"name":        JSONValue(a.name.ptr.fromStringz),
							"direction":   JSONValue(a.direction),
							"rate":        JSONValue(a.rate),
							"angle":       JSONValue(a.angle),
						])).array),
					"uv_offset":           JSONValue(watr.uv_offset),
				]);
				// TODO: unknown not handled

				// Vertices & faces
				size_t vi = wfobj.vertices.length + 1;
				size_t vti = wfobj.textCoords.length + 1;

				foreach(ref v ; watr.vertices){
					wfobj.vertices ~= WavefrontObj.WFVertex(vec3f(v.position));
					wfobj.textCoords ~= vec2f(v.uv);
				}

				auto grpWater = WavefrontObj.WFGroup();
				auto grpNoWater = WavefrontObj.WFGroup();
				foreach(ti, ref triangle ; watr.triangles){
					if(!exportAll && watr.triangles_flags[ti] == 1)
						continue;// don't export triangles without water

					WavefrontObj.WFFace face;
					face.vertices = triangle.vertices.to!(size_t[]);
					face.vertices[] += vi;
					face.textCoords = triangle.vertices.to!(size_t[]);
					face.textCoords.get[] += vti;

					if(watr.triangles_flags[ti] == 0)
						grpWater.faces ~= face;
					else
						grpNoWater.faces ~= face;
				}
				wfobj.objects[name] = WavefrontObj.WFObject([null: grpWater]);
				if(exportAll)
					wfobj.objects[name ~ "-nowater"] = WavefrontObj.WFObject([null: grpNoWater]);


				// Alpha bitmap
				immutable ddsName = format!"%s.watr.%d.dds"(trnFileName, watrIdx);
				buildPath(outFolder, ddsName).writeFile(watr.dds);

				// Material
				wfmtl ~= format!"newmtl %s\n"(name);
				wfmtl ~= format!"map_d %s\n"(ddsName);
				wfmtl ~= "\n";

				watrIdx++;
			}

			writeFile(buildPath(outFolder, trnFileName ~ ".watr.obj"), wfobj.serialize());
			writeFile(buildPath(outFolder, trnFileName ~ ".watr.mtl"), wfmtl);
			writeFile(buildPath(outFolder, trnFileName ~ ".watr.json"), watrConfig.toPrettyString());
		}
		break;

		case "watr-import":{
			string trnFile;
			string outputFile = null;
			bool emptyWatr = false;
			auto res = getopt(args,
				config.required, "trn", "Existing TRN or TRX file to store the water mesh", &trnFile,
				"output|o", "TRN/TRX file to write.\nDefault: the file provided by --trn", &outputFile,
			);

			if(res.helpWanted){
				improvedGetoptPrinter(
					"Import mater mesh properties into an existing TRN or TRX file\n"
					~"Usage: "~args[0].baseName~" "~command~" map.watr.obj --trn map.trx\n"
					~"\n"
					~"Wavefront format notes:\n"
					~"- Water data is always cleared before importing\n",
					res.options);
				return 0;
			}
			enforce(args.length > 1, "No input file provided");
			enforce(args.length <=2, "Too many input files provided");

			auto objFilePath = args[1];
			auto objFileDir = objFilePath.dirName;
			auto objFileBaseName = objFilePath.baseName(".watr.obj");

			if(outputFile is null)
				outputFile = trnFile;

			auto trn = new Trn(trnFile);


			import nwnlibd.wavefrontobj: WavefrontObj;
			auto wfobj = new WavefrontObj(buildPath(objFileDir, objFileBaseName ~ ".watr.obj").readText);
			import std.json;
			auto watrConfig = buildPath(objFileDir, objFileBaseName ~ ".watr.json").readText.parseJSON;

			// Remove previous packets
			trn.packets = trn.packets
				.filter!(a => a.type != TrnPacketType.NWN2_WATR)
				.array;

			foreach(oName, ref o ; wfobj.objects){
				if(oName.length < 6 || oName[0 .. 6] != "water-")
					continue;

				trn.packets ~= TrnPacket(TrnPacketType.NWN2_WATR);
				auto watr = &trn.packets[$ - 1].as!TrnNWN2WaterPayload();

				size_t id;
				oName.dup.formattedRead!"water-%d"(id);
				auto watrIdx = id.to!string;

				// Set properties
				watr.name                = watrConfig[watrIdx]["name"].str.stringToCharArray!(char[32]);
				watr.unknown[]           = 0;//TODO: reverse & save unknown block
				watr.megatile_position   = watrConfig[watrIdx]["megatile_position"].array.map!(a => a.toString.to!uint32_t).array[0 .. 2];
				watr.color               = watrConfig[watrIdx]["color"].array.map!(a => a.toString.to!float).array[0 .. 3];
				watr.ripple              = watrConfig[watrIdx]["ripple"].array.map!(a => a.toString.to!float).array[0 .. 2];
				watr.smoothness          = watrConfig[watrIdx]["smoothness"].toString.to!float;
				watr.reflect_bias        = watrConfig[watrIdx]["reflect_bias"].toString.to!float;
				watr.reflect_power       = watrConfig[watrIdx]["reflect_power"].toString.to!float;
				watr.specular_power      = watrConfig[watrIdx]["specular_power"].toString.to!float;
				watr.specular_cofficient = watrConfig[watrIdx]["specular_cofficient"].toString.to!float;
				foreach(i, ref t ; watr.textures){
					t.name      = watrConfig[watrIdx]["textures"][i]["name"].str.stringToCharArray!(char[32]);
					t.direction = watrConfig[watrIdx]["textures"][i]["direction"].array.map!(a => a.toString.to!float).array[0 .. 2];
					t.rate      = watrConfig[watrIdx]["textures"][i]["rate"].toString.to!float;
					t.angle     = watrConfig[watrIdx]["textures"][i]["angle"].toString.to!float;
				}
				watr.uv_offset = watrConfig[watrIdx]["uv_offset"].array.map!(a => a.toString.to!float).array[0 .. 2];


				// Vertices & triangles
				watr.vertices.length = 0;
				watr.triangles.length = 0;

				uint16_t[size_t] vtxTransTable;
				auto triangles = o.groups
					.values
					.map!(g => g.faces)
					.join
					.filter!(t => t.vertices.length == 3);// Ignore non triangles
				foreach(ref t ; triangles){

					foreach(i, v ; t.vertices){
						if(v !in vtxTransTable){
							// Add vertices as needed
							vtxTransTable[v] = watr.vertices.length.to!uint16_t;

							auto uv_1 = wfobj.textCoords[t.textCoords[i] - 1];
							auto uv_0 = uv_1 * 5.0;

							watr.vertices ~= TrnNWN2WaterPayload.Vertex(
								wfobj.vertices[v - 1].position.v[0 .. 3],
								uv_0.v,
								uv_1.v,
							);
						}
					}

					if(watr.triangles.length < watr.triangles_flags.length)
						watr.triangles_flags[watr.triangles.length - 1] = 0;
					watr.triangles ~= TrnNWN2WaterPayload.Triangle(
						t.vertices
							.map!(a => vtxTransTable[a])
							.array[0 .. 3]
					);
				}

				// DDS
				watr.dds = cast(ubyte[])buildPath(objFileDir, format!"%s.watr.%d.dds"(objFileBaseName, id)).readFile();

				// check
				watr.validate();
			}

			outputFile.writeFile(trn.serialize());
		}
		break;
	}
	return 0;
}




unittest{
	version(Windows)
		auto nullFile = "nul";
	else
		auto nullFile = "/dev/null";

	auto stdout_ = stdout;
	auto tmpOut = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__);
	stdout = File(tmpOut, "w");
	scope(success) tmpOut.remove();
	scope(exit) stdout = stdout_;


	assertThrown(main(["nwn-trn"]));
	assert(main(["nwn-trn","--help"]) == 0);
	assert(main(["nwn-trn","--version"]) == 0);

	auto filePath = buildPath(tempDir, "unittest-nwn-lib-d-"~__MODULE__);

	assert(main(["nwn-trn", "check", "--help"]) == 0);

	assert(main(["nwn-trn", "bake", "--help"]) == 0);
	assert(main([
			"nwn-trn", "bake",
			"--terrain2da=../../unittest/terrainmaterials.2da",
			"../../unittest/WalkmeshObjects",
			"-o", nullFile,
		]) == 0);

	assert(main(["nwn-trn", "aswm-check", "--help"]) == 0);
	assert(main([
			"nwn-trn", "aswm-check",
			"../../unittest/WalkmeshObjects.trn", "../../unittest/WalkmeshObjects.trx", "../../unittest/TestImportExportTRN.trx",
		]) == 0);

	assert(main(["nwn-trn", "aswm-strip", "--help"]) == 0);
	assert(main([
			"nwn-trn", "aswm-strip",
			"../../unittest/TestImportExportTRN.trx",
			"-o", filePath,
		]) == 0);
	auto trn = new Trn(filePath);
	foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
		assert(aswm.vertices.length == 2141);
		assert(aswm.edges.length == 5864);
		assert(aswm.triangles.length == 3703);
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
			"../../unittest/TestImportExportTRN.trx",
			"-o", tempDir,
		]) == 0);


	// Import/export functions

	// ASWM
	assert(main(["nwn-trn", "aswm-export", "--help"]) == 0);
	assert(main([
			"nwn-trn", "aswm-export",
			"../../unittest/TestImportExportTRN.trn",
			"-o", filePath,
		]) == 0);

	assert(main(["nwn-trn", "aswm-import", "--help"]) == 0);
	assert(main([
			"nwn-trn", "aswm-import",
			"--obj", filePath,
			"--trn", "../../unittest/TestImportExportTRN.trx",
			"--terrain2da=../../unittest/terrainmaterials.2da",
			"-o", buildPath(tempDir, "TestImportExportTRN.new.trx"),
		]) == 0);

	assert(main(["nwn-trn", "check", buildPath(tempDir, "TestImportExportTRN.new.trx")]) == 0);

	// TRRN
	assert(main(["nwn-trn", "trrn-export", "--help"]) == 0);
	assert(main([
			"nwn-trn", "trrn-export",
			"../../unittest/TestImportExportTRN.trx",
			"-o", tempDir,
		]) == 0);

	assert(main(["nwn-trn", "trrn-import", "--help"]) == 0);
	assert(main([
			"nwn-trn", "trrn-import",
			buildPath(tempDir, "TestImportExportTRN.trx.trrn.obj"),
			"--trn", "../../unittest/TestImportExportTRN.trx",
			"-o", buildPath(tempDir, "TestImportExportTRN.new.trx"),
		]) == 0);

	assert(main(["nwn-trn", "check", buildPath(tempDir, "TestImportExportTRN.new.trx")]) == 0);

	// WATR
	assert(main(["nwn-trn", "watr-export", "--help"]) == 0);
	assert(main([
			"nwn-trn", "watr-export",
			"../../unittest/TestImportExportTRN.trx",
			"-o", tempDir,
		]) == 0);

	assert(main(["nwn-trn", "watr-import", "--help"]) == 0);
	assert(main([
			"nwn-trn", "watr-import",
			buildPath(tempDir, "TestImportExportTRN.trx.watr.obj"),
			"--trn", "../../unittest/TestImportExportTRN.trx",
			"-o", buildPath(tempDir, "TestImportExportTRN.new.trx"),
		]) == 0);

	assert(main(["nwn-trn", "check", buildPath(tempDir, "TestImportExportTRN.new.trx")]) == 0);


	// Advanced commands
	assert(main(["nwn-trn", "aswm-dump", "../../unittest/WalkmeshObjects.trx"]) == 0);

	assert(main(["nwn-trn", "aswm-bake", "--help"]) == 0);
	assert(main([
			"nwn-trn", "aswm-bake",
			"../../unittest/WalkmeshObjects.trx",
			"-o", nullFile,
		]) == 0);


	stdout = stdout_;
}
