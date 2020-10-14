import std.stdio;
import std.conv: to;
import std.string;
import std.stdint;
import std.algorithm;
import std.array;
import std.random: uniform;

import nwn.trn;


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