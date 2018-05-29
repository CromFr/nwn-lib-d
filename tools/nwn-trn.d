/// Authors: Thibaut CHARLES (Crom) cromfr@gmail.com
/// License: GPL-3.0
/// Copyright: Copyright Thibaut CHARLES 2016

module nwntrn;

import std.stdio;
import std.conv: to, ConvException;
import std.getopt;
import std.traits;
import std.string;
import std.file;
import std.path;
import std.stdint;
import std.typecons: Tuple, Nullable;
import std.algorithm;
import std.array;
import std.exception: enforce;
import std.random: uniform;

import nwn.trn;

version(unittest){}
else{
	int main(string[] args){return _main(args);}
}

class ArgException : Exception{
	@safe pure nothrow this(string msg, string f=__FILE__, size_t l=__LINE__, Throwable t=null){
		super(msg, f, l, t);
	}
}

void usage(in string cmd){
	writeln("TRN / TRX tool");
	writeln("Usage: ", cmd, " command [args]");
	writeln("Commands");
	writeln("  aswm-strip: optimize TRX files");
	writeln("  aswm-convert: convert walkmesh into wavefront obj");
	writeln("Advanced commands:");
	writeln("  aswm-extract: unzip walkmesh data");
	writeln("  aswm-dump: print walkmesh data using a (barely) human-readable format");
	writeln("  aswm-bake: Re-bake all tiles of an already baked walkmesh");
}

int _main(string[] args){
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
			bool postCheck = true;
			string targetPath = null;

			auto res = getopt(args,
				"in-place|i", "Provide this flag to overwrite the provided TRX file", &inPlace,
				"output|o", "Output file or directory. Mandatory if --in-place is not provided.", &targetPath,
				"check", "Check all vertex/junction/triangle indices point to valid data. Default to true", &postCheck,
				);
			if(res.helpWanted || args.length == 1){
				defaultGetoptPrinter(
					"Reduce TRX file size by removing non walkable polygons from calculated walkmesh\n"
					~"Usage: "~args[0]~" "~command~" map.trx -o stripped_map.trx\n"
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



			immutable data = cast(immutable ubyte[])args[1].read();
			auto trn = new Trn(data);
			size_t initLen = data.length;

			bool found = false;
			foreach(ref packet ; trn.packets){
				if(packet.type == TrnPacketType.NWN2_ASWM){
					found = true;

					stripASWM(packet.as!(TrnPacketType.NWN2_ASWM), postCheck);
				}
			}

			enforce(found, "No ASWM packet found. Make sure you are targeting a TRX file.");

			immutable finalData = cast(immutable ubyte[])trn.serialize();
			writeln("File size: ", initLen, "B => ", finalData.length, "B (stripped ", 100 - finalData.length * 100.0 / initLen, "%)");

			std.file.write(targetPath, finalData);
		}
		break;

		case "aswm-convert":{
			string targetDir = null;
			string[] features = [];
			auto res = getopt(args,
				"output-dir|o", "Output directory where to write converted files", &targetDir,
				"feature|f", "Features to render. Can be provided multiple times. Default: [\"walkmesh\"]", &features,
				);

			if(res.helpWanted || args.length == 1){
				defaultGetoptPrinter(
					"Convert NWN2 walkmeshes into TRX / OBJ (only TRX => OBJ supported for now)\n"
					~"Usage: "~args[0]~" "~command~" map.trx\n"
					~"\n"
					~"Available features to render:\n"
					~"- walkmesh: All triangles including non-walkable.\n"
					~"- junctions: Junctions between two triangles.\n"
					~"- tiles: Each tile using random colors.\n"
					~"- pathtables-los: Line of sight pathtable property between two triangles.\n"
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
			foreach(ref packet ; trn.packets){
				if(packet.type == TrnPacketType.NWN2_ASWM){
					found = true;
					writeWalkmeshObj(
						packet.as!(TrnPacketType.NWN2_ASWM),
						args[1].baseName.stripExtension,
						outfile,
						features);
				}
			}
			enforce(found, "No ASWM packet found. Make sure you are targeting a TRX file.");

			if(targetDir != "-"){
				auto colPath = buildPath(targetDir, "nwnlibd-colors.mtl");
				if(!colPath.exists)
					std.file.write(colPath, colors);
			}

		}
		break;

		case "aswm-extract":{
			enforce(args.length == 2, "Bad argument number. Usage: "~args[0]~" "~command~" file.trx");

			auto trn = new Trn(args[1]);

			bool found = false;
			foreach(i, ref packet ; trn.packets){
				if(packet.type == TrnPacketType.NWN2_ASWM){
					found = true;
					std.file.write(
						args[1].baseName~"."~i.to!string~".aswm",
						packet.as!(TrnPacketType.NWN2_ASWM).serializeUncompressed());
				}
			}
			enforce(found, "No ASWM packet found. Make sure you are targeting a TRX file.");
		}
		break;

		case "aswm-dump":{
			enforce(args.length == 2, "Bad argument number. Usage: "~args[0]~" "~command~" file.trx");

			auto trn = new Trn(args[1]);

			bool found = false;
			foreach(i, ref packet ; trn.packets){
				if(packet.type == TrnPacketType.NWN2_ASWM){
					found = true;
					writeln(packet.as!(TrnPacketType.NWN2_ASWM).dump);
				}
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
				defaultGetoptPrinter(
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
			foreach(i, ref packet ; trn.packets){
				if(packet.type == TrnPacketType.NWN2_ASWM){
					found = true;
					packet.as!(TrnPacketType.NWN2_ASWM).bake();
				}
			}
			enforce(found, "No ASWM packet found. Make sure you are targeting a TRX file.");

			std.file.write(targetPath, trn.serialize());
		}
		break;
	}
	return 0;
}



void stripASWM(ref TrnNWN2WalkmeshPayload aswm, bool postCheck){


	auto initVertices = aswm.vertices.length;
	auto initJunctions = aswm.junctions.length;
	auto initTriangles = aswm.triangles.length;



	uint32_t[] vertTransTable, juncTransTable, triTransTable;//table[oldIndex] = newIndex
	vertTransTable.length = aswm.vertices.length;
	juncTransTable.length = aswm.junctions.length;
	triTransTable.length = aswm.triangles.length;
	uint32_t newIndex;

	bool[] usedVertices, usedJunctions;
	usedVertices.length = aswm.vertices.length;
	usedJunctions.length = aswm.junctions.length;
	usedVertices[] = false;
	usedJunctions[] = false;

	// Reduce triangle list & flag used vertices & junctions
	newIndex = 0;
	foreach(i, ref triangle ; aswm.triangles){
		if(triangle.island != uint16_t.max){

			// Flag used / unused vertices & junctions
			foreach(vert ; triangle.vertices){
				usedVertices[vert] = true;
			}
			foreach(junc ; triangle.linked_junctions){
				if(junc != uint32_t.max)
					usedJunctions[junc] = true;
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

	// Reduce junctions list
	newIndex = 0;
	foreach(i, used ; usedJunctions){
		if(used){
			aswm.junctions[newIndex] = aswm.junctions[i];
			juncTransTable[i] = newIndex++;
		}
		else
			juncTransTable[i] = uint32_t.max;
	}
	aswm.junctions.length = newIndex;


	// Adjust indices in junctions data
	foreach(ref junction ; aswm.junctions){
		foreach(ref vert ; junction.vertices){
			vert = vertTransTable[vert];
			assert(vert != uint32_t.max && vert < aswm.vertices.length, "Invalid vertex index");
		}
		foreach(ref tri ; junction.triangles){
			if(tri != uint32_t.max){
				tri = triTransTable[tri];
				assert(tri == uint32_t.max || tri < aswm.triangles.length, "Invalid triangle index");
			}
		}
		// Pack triangle indices
		if(junction.triangles[0] == uint32_t.max && junction.triangles[1] != uint32_t.max){
			junction.triangles[0] = junction.triangles[1];
			junction.triangles[1] = uint32_t.max;
		}
	}

	// Adjust indices in triangles data
	foreach(ref triangle ; aswm.triangles){
		foreach(ref vert ; triangle.vertices){
			vert = vertTransTable[vert];
			assert(vert != uint32_t.max && vert < aswm.vertices.length, "Invalid vertex index");
		}
		foreach(ref junc ; triangle.linked_junctions){
			junc = juncTransTable[junc];
			assert(junc < aswm.junctions.length, "Invalid junction index");
		}

		foreach(ref tri ; triangle.linked_triangles){
			if(tri != uint32_t.max){
				tri = triTransTable[tri];
			}
		}
		//Pack triangles indices TODO quick & dirty
		foreach(i, tri ; triangle.linked_triangles){
			if(tri == uint32_t.max && i + 1 < triangle.linked_triangles.length){
				triangle.linked_triangles[i] = triangle.linked_triangles[i + 1];
				triangle.linked_triangles[i + 1] = uint32_t.max;
			}

			assert(tri == uint32_t.max || tri < aswm.triangles.length, "Invalid triangle index");
		}
	}


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

		// Re-count linked vertices / junctions
		tile.header.vertices_count = tile.path_table.node_to_local
			.map!(a => a != a.max? aswm.triangles[a].vertices[] : [])
			.join.sort.uniq.array.length.to!uint32_t;
		tile.header.junctions_count = tile.path_table.node_to_local
			.map!(a => a != a.max?  aswm.triangles[a].linked_junctions[] : [])
			.join.sort.uniq.array.length.to!uint32_t;
	}
	// Adjust indices in islands
	foreach(ref island ; aswm.islands){
		foreach(ref t ; island.exit_triangles){
			t = triTransTable[t];
			assert(t != uint32_t.max && t < aswm.triangles.length, "Invalid triangle index");
		}
	}

	writeln("Vertices: ", initVertices, " => ", aswm.vertices.length, " (stripped ", 100 - aswm.vertices.length * 100.0 / initVertices, "%)");
	writeln("Junctions: ", initJunctions, " => ", aswm.junctions.length, " (stripped ", 100 - aswm.junctions.length * 100.0 / initJunctions, "%)");
	writeln("Triangles: ", initTriangles, " => ", aswm.triangles.length, " (stripped ", 100 - aswm.triangles.length * 100.0 / initTriangles, "%)");

	if(postCheck){
		immutable vertLen = aswm.vertices.length;
		immutable juncLen = aswm.junctions.length;
		immutable triLen = aswm.triangles.length;

		foreach(i, ref junc ; aswm.junctions){
			foreach(vert ; junc.vertices) assert(vert < vertLen, "Wrong vertex index "~vert.to!string~" in junction "~i.to!string);
			foreach(tri ; junc.triangles) assert(tri < triLen || tri == uint32_t.max, "Wrong triangle index "~tri.to!string~" in junction "~i.to!string);

			assert(junc.vertices[0] != uint32_t.max && junc.vertices[1] != uint32_t.max, "Junction "~i.to!string~" has bad nb of vertices");
			assert(junc.triangles[0] != uint32_t.max || junc.triangles[1] != uint32_t.max, "Junction "~i.to!string~" has no triangles");
		}
		foreach(i, ref tri ; aswm.triangles){
			foreach(vert ; tri.vertices) assert(vert < vertLen, "Wrong vertex index "~vert.to!string~" in triangle "~i.to!string);
			foreach(junc ; tri.linked_junctions) assert(junc < juncLen || junc == uint32_t.max, "Wrong vertex index "~junc.to!string~" in triangle "~i.to!string);
			foreach(ltri ; tri.linked_triangles) assert(ltri < triLen || ltri == uint32_t.max, "Wrong triangle index "~ltri.to!string~" in triangle "~i.to!string);
		}
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

	if(!features.find("junctions").empty){
		writeln("junctions");

		obj.writeln("g junctions");

		foreach(ref junc ; aswm.junctions){

			randomColor();

			auto vertA = aswm.vertices[junc.vertices[0]];
			auto vertB = aswm.vertices[junc.vertices[1]];

			auto vertCenterHigh = vertA.position;
			vertCenterHigh[] += vertB.position[];
			vertCenterHigh[] /= 2.0;
			vertCenterHigh[2] += 0.5;

			obj.writefln("v %(%s %)", vertCenterHigh);
			vertexOffset++;
			obj.writefln("f %s %s %s", junc.vertices[0] + 1, junc.vertices[1] + 1, vertexOffset);//Start index is 1

			if(junc.triangles[0] != uint32_t.max && junc.triangles[1] != uint32_t.max){

				auto triA = aswm.triangles[junc.triangles[0]];
				auto triB = aswm.triangles[junc.triangles[1]];

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


						const node = tile.path_table.nodes[fromNodeIdx * tile.path_table.header.node_to_local_length + toNodeIdx];
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

	if(!features.find("randompaths").empty){
		writeln("randompaths");

		obj.writeln("g randompaths");

		foreach(tileid, ref tile ; aswm.tiles) with(tile) {
			immutable offset = tile.header.triangles_offset;
			immutable len = tile.path_table.header.node_to_local_length;

			if(len == 0)
				continue;

			foreach(_ ; 0 .. 2){
				auto from = uniform(0, len) + offset;
				auto to = uniform(0, len) + offset;


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