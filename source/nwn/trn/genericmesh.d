module nwn.trn.genericmesh;

import std.stdint;
import std.conv: to;
import std.algorithm;
import std.math;
import std.traits;
import std.string;
import std.stdio: File;
import std.exception: enforce;
import std.array: array;
import std.typecons: Nullable;
debug import std.stdio: stderr, write, writeln, writefln;

import nwnlibd.geometry;
import gfm.math.vector;


struct GenericMesh {
	vec3f[] vertices;

	static struct Triangle{
		uint32_t[3] vertices; /// Vertex indices composing the triangle
		uint32_t material = uint32_t.max;
	}
	Triangle[] triangles;

	uint32_t[][] lines;
	static struct Material{
		float[3] ambientColor; /// Ka
		string ambientTexture; /// map_Ka
		float[3] diffuseColor; /// Kd
		string diffuseTexture; /// map_Kd
		float[3] specularColor; /// Ks
		string specularTexture; /// map_Ks
		float specularWeight; /// Ns
		float transparency; /// Tr ; 0 = opaque
		string bumpTexture; /// bump
		string dispTexture; /// disp
		string decalTexture; /// decal
		enum Illumniation : ubyte {
			None = ubyte.max,
			ColorOnAmbientOff = 0, /// Color on and Ambient off
			ColorOnAmbientOn = 1, /// Color on and Ambient on
			HilightOn = 2, /// Highlight on
			ReflectRaytrace = 3, /// Reflection on and Ray trace on
			GlassRaytrace = 4, /// Transparency: Glass on, Reflection: Ray trace on
			FresnelRaytrace = 5, /// Reflection: Fresnel on and Ray trace on
			RefractRaytrace = 6, /// Transparency: Refraction on, Reflection: Fresnel off and Ray trace on
			RefractFresnelRaytrace = 7, /// Transparency: Refraction on, Reflection: Fresnel on and Ray trace on
			Reflect = 8, /// Reflection on and Ray trace off
			Glass = 9, /// Transparency: Glass on, Reflection: Ray trace off
			Shadows = 10, /// Casts shadows onto invisible surfaces
		}
		Illumniation illumination = Illumniation.None; /// illum
	}
	Material[] materials;

	GenericMesh dup() const {
		return GenericMesh(vertices.dup, triangles.dup, lines.dup.map!(a => a.dup).array, materials.dup);
	}

	/// Throw an exception if mesh contains invalid indices
	void validate(){
		foreach(i, ref t ; triangles)
			foreach(vi ; t.vertices)
				enforce(vi < vertices.length,
					"Triangle "~i.to!string~" contains invalid vertex index ("~vi.to!string~")");
	}

	/// Shuffle all data, while keeping the same 3d model
	void shuffle(){
		// Shuffle all triangles & vertices
		uint32_t[] vertTransTable, triTransTable;
		vertTransTable.length = vertices.length;
		triTransTable.length = triangles.length;
		foreach(i, ref val ; vertTransTable) val = cast(uint32_t)i;
		foreach(i, ref val ; triTransTable) val = cast(uint32_t)i;

		import std.random: randomShuffle;
		vertTransTable.randomShuffle();
		triTransTable.randomShuffle();

		auto oldVertices = this.vertices.idup;
		auto oldTriangles = this.triangles.idup;

		foreach(oldVIdx, newVIdx ; vertTransTable)
			vertices[newVIdx] = vec3f(oldVertices[oldVIdx]);

		foreach(oldTIdx, newTIdx ; triTransTable){
			auto oldTri = &oldTriangles[oldTIdx];
			triangles[newTIdx] = Triangle(oldTri.vertices);

			foreach(ref v ; triangles[newTIdx].vertices[].randomShuffle)
				v = vertTransTable[v];
		}
	}


	private static struct TriCut{
		uint32_t triangle;
		// Vertices created by cutting this triangle
		uint32_t[2] cutVertices = [uint32_t.max, uint32_t.max];
		// 0 1 or 2 if the cutVertices[i] is on edge 0 1 or 2
		ubyte[2] verticesEdge = [ubyte.max, ubyte.max];
	}
	private static struct Cut {
		TriCut[] trianglesCut;
		vec3f[] newVertices;
	}
	private auto lineCut(vec2f[2] line) const {
		Cut ret;

		uint32_t addVertex(in vec3f vertex){
			foreach(i, ref v ; ret.newVertices){
				if(v.squaredDistanceTo(vertex) < 0.0001)
					return i.to!uint32_t;
			}
			auto index = ret.newVertices.length;
			ret.newVertices ~= vertex;
			return index.to!uint32_t;
		}


		auto lineVec = vec2f(line[1] - line[0]).normalized;

		auto lineVecPer = vec2f(lineVec[1], -lineVec[0]);
		auto lineDist = line[0].dot(lineVecPer);

		foreach(i, ref t ; triangles){
			// TODO: optimize by checking against an AABB

			vec2f[3] triVertices = t.vertices[]
				.map!(a => vec2f(vertices[a].v[0 .. 2]))
				.array[0 .. 3];


			// Check if the triangle is aligned with the cur line
			float[3] ndot;
			foreach(j ; 0 .. 3){
				// we calculate the distance between the cutting line and each
				// point of the triangle.
				// If the distance will be >0 or <0 depending on which side of
				// the line is the point.
				ndot[j] = vec2f(triVertices[j]).dot(lineVecPer) - lineDist;
			}

			ubyte[] cutEdges;// will contain the list of edges cut by an infinite line
			static foreach(j ; 0 .. 3){
				// ndot[j] * ndot[(j + 1) % 3] is <0 if the two vertices of
				// a triangle edge are on each side of the cutting line
				if(ndot[j] * ndot[(j + 1) % 3] < 0)
					cutEdges ~= j;
			}

			if(cutEdges.length == 0)
				continue; // The cutting line does not cross any triangle edge

			// TODO: What happens if the cutting line goes exactly through a vertex, and cut only one edge
			assert(cutEdges.length == 2,
				"Non-Euclidean geometry: You succeeded at cutting "~cutEdges.length.to!string~" edges of a triangle with a line, well done");

			auto triDirection = isTriangleClockwise(triVertices);

			// bool[cut edge 0/1][line start/end]
			bool[2][2] edgeDirections;
			foreach(iLinePoint, linePoint ; line){
				foreach(j, edge ; cutEdges){
					edgeDirections[j][iLinePoint] = isTriangleClockwise([triVertices[edge], triVertices[(edge + 1) % 3], linePoint]);
				}
			}

			auto triCut = TriCut(cast(uint32_t)i);
			//stderr.writefln("Triangle collides infinite line on %d edges", cutEdges.length);
			foreach(j, edge ; cutEdges){
				// value == triDirection <=> point is inside of the triangle edge
				if(edgeDirections[j][0] != edgeDirections[j][1]){
					// Calculate intersection point
					auto edgePos = [triVertices[edge], triVertices[(edge + 1) % 3]];
					auto edgeVec = edgePos[1] - edgePos[0];

					auto intersection = getLineIntersection(edgePos[0..2], line);
					assert(intersection.intersect, "Should intersect");

					auto intersectIndex = addVertex(vec3f(intersection.position.x, intersection.position.y, 0.0)); //TODO: handle z

					triCut.cutVertices[j] = intersectIndex;
					triCut.verticesEdge[j] = edge;
					//stderr.writeln("  cut through edge ", j, " => verticesEdge=", triCut.verticesEdge);
				}
			}
			foreach(j ; 0 .. 2){
				if(edgeDirections[0][j] == triDirection && edgeDirections[1][j] == triDirection){
					auto linePointIndex = addVertex(vec3f(line[j].x, line[j].y, 0.0)); //TODO: handle z

					ubyte insertPos = triCut.cutVertices[0] == uint32_t.max? 0 : 1;
					assert(triCut.cutVertices[insertPos] == uint32_t.max);

					triCut.cutVertices[insertPos] = linePointIndex;
					//stderr.writefln("  Line point %d (%s) is inside the triangle %s => verticesEdge=", j, line[j], triVertices, triCut.verticesEdge);
				}
			}

			//if(triCut.cutEdges.length == 0){
			//	continue;// TODO: handle inner cuts
			//}
			if(triCut.cutVertices[0] == uint32_t.max && triCut.cutVertices[1] == uint32_t.max){
				continue;
			}
			assert(triCut.cutVertices[0] != uint32_t.max && triCut.cutVertices[1] != uint32_t.max);


			debug{
				foreach(j, e ; triCut.verticesEdge){
					if(e != ubyte.max){
						vec2f[2] edge = [vertices[t.vertices[e]].toVec2f, vertices[t.vertices[(e + 1)%3]].toVec2f];
						vec2f intersection = ret.newVertices[triCut.cutVertices[j]].toVec2f;

						assert(distance(edge, intersection) < 0.01,
							"New vertex is not on the correct edge: distance="~distance(edge[0..2], intersection).to!string);
					}
				}
			}

			ret.trianglesCut ~= triCut;
		}
		return ret;

	}



	void polygonCut(vec2f[] polygon, bool removeInside = true){
		validate();

		Cut mergedCut;
		foreach(i ; 0 .. polygon.length){
			auto nextCut = lineCut([polygon[i], polygon[(i + 1) % polygon.length]]);

			// Merge new vertices together. We directly translate nextCut indices to GenericMesh.vertices indices
			uint32_t[] vertTransTable;
			vertTransTable.length = nextCut.newVertices.length;
			foreach(ni, ref nv ; nextCut.newVertices){
				bool foundSimilar = false;
				foreach(oi, ref ov ; mergedCut.newVertices){
					if(nv.squaredDistanceTo(ov) < 0.0001){
						vertTransTable[ni] = vertices.length + oi;
						foundSimilar = true;
						break;
					}
				}
				if(!foundSimilar){
					vertTransTable[ni] = vertices.length + mergedCut.newVertices.length;
					mergedCut.newVertices ~= nv;
				}
			}

			// Merge TriCuts...
			immutable tcutLen = mergedCut.trianglesCut.length;
			mergedCut.trianglesCut ~= nextCut.trianglesCut;
			// ... and update vertex indices
			foreach(ref tc ; mergedCut.trianglesCut[tcutLen .. $])
				foreach(ref v ; tc.cutVertices)
					v = vertTransTable[v];
		}

		vertices ~= mergedCut.newVertices;

		// Separate triangles that has been cut more than once (they will be triangulated)
		TriCut*[] simpleCuts;
		TriCut*[][] complexCuts;

		TriCut*[] lastCuts;
		foreach(ref tc ; mergedCut.trianglesCut.sort!"a.triangle < b.triangle"){
			if(lastCuts.length == 0 || tc.triangle == lastCuts[0].triangle){
				lastCuts ~= &tc;
			}
			else{
				if(lastCuts.length == 1){
					assert(lastCuts[0].verticesEdge[0] != 255 && lastCuts[0].verticesEdge[1] != 255,
						"simple cuts should be cut through");
					simpleCuts ~= lastCuts[0];
				}
				else{
					complexCuts ~= lastCuts;
				}
				lastCuts.length = 1;
				lastCuts[0] = &tc;
			}
		}

		// Proceed to cutting
		foreach(i, tc ; simpleCuts){

			auto triangle = triangles[tc.triangle];

			ubyte commonVertTriOffset;
			auto cutEdgesOffsets = tc.verticesEdge[].sort.array();

			if(cutEdgesOffsets == [0,1])      commonVertTriOffset = 1;
			else if(cutEdgesOffsets == [1,2]) commonVertTriOffset = 2;
			else if(cutEdgesOffsets == [0,2]) commonVertTriOffset = 0;
			else assert(0);
			uint32_t commonVertIdx = triangle.vertices[commonVertTriOffset];

			auto isCommonInside = removeInside == true ? isPointInsidePolygon(vec2f(vertices[commonVertIdx][0..2]), polygon) : false;

			// Add triangle next to the common vertex
			if(removeInside == false || !isCommonInside){
				triangles ~= Triangle([commonVertIdx, tc.cutVertices[0], tc.cutVertices[1]]);
			}
			 // Add two triangle to fill the 4-edge shape
			if(removeInside == false || isCommonInside){
				auto isClockwise = isTriangleClockwise(triangle.vertices[].map!(a => vec2f(vertices[a].v[0..2])).array[0 .. 3]);
				// newVert[0] -> newVert[1] -> common vertex
				auto abcCw = isTriangleClockwise([
					vertices[tc.cutVertices[0]].toVec2f,
					vertices[tc.cutVertices[1]].toVec2f,
					vertices[commonVertIdx].toVec2f
				]);

				triangles ~= Triangle(
					[
						tc.cutVertices[0],
						tc.cutVertices[1],
						triangle.vertices[(commonVertTriOffset + (abcCw != isClockwise? 1 : 2)) % 3],
					]);
				triangles ~= Triangle(
					[
						tc.cutVertices[0],
						triangle.vertices[(commonVertTriOffset + (abcCw != isClockwise? 1 : 2)) % 3],
						triangle.vertices[(commonVertTriOffset + (abcCw != isClockwise? 2 : 1)) % 3],
					]);
			}

			// Mark triangle for removal
			triangles[tc.triangle].vertices[0] = uint32_t.max;
		}

		foreach(ref tcs ; complexCuts){
			// TODO

			// Mark triangle for removal
			triangles[tcs[0].triangle].vertices[0] = uint32_t.max;
		}

		//debug{
		//	immutable oldLen = triangles.length;
		//	triangles = triangles.filter!(a => a.vertices[0] != uint32_t.max).array;

		//	assert(triangles.length + mergedTriCut.length == oldLen,
		//		(oldLen - triangles.length).to!string ~ " triangles removed, instead of " ~ mergedTriCut.length.to!string);
		//}

		if(removeInside){
			foreach(i, ref t ; triangles){
				if(t.vertices[0] == uint32_t.max)
					continue;

				bool inside = true;
				foreach(v ; t.vertices){
					// TODO: optimize by checking against an AABB
					if(isPointInsidePolygon(vec2f(vertices[v][0..2]), polygon) == false){
						inside = false;
						break;
					}
				}
				if(inside)
					t.vertices[0] = uint32_t.max;
			}
		}
		triangles = triangles.filter!(a => a.vertices[0] != uint32_t.max).array;
	}

	/**
	Build a generic mesh by reading a Wavefront OBJ file

	Params:
	obj = OBJ file to read
	objectName = If null, the first object will be used, if a string, will import the mesh from the given object name
	*/
	static GenericMesh fromObj(File obj, string objectName = null){
		GenericMesh mesh;
		bool registerData = false;
		foreach(line ; obj.byLine.map!strip.filter!(a => a[0] != '#')){
			import std.format;

			string type;
			line.formattedRead!"%s "(type);


			switch(type){
				case "o":{
					string name;
					line.formattedRead!"%s"(name);
					if(objectName is null || objectName == name){
						registerData = true;
						objectName = name;
					}
					else
						registerData = false;
				}
				break;
				case "v":{
					vec3f v;
					line.formattedRead!"%f %f %f"(v.x, v.y, v.z);
					mesh.vertices ~= v;
				}
				break;
				case "f":{
					string data;
					line.formattedRead!"%s"(data);

					Triangle t;
					auto abc = data.split(" ");
					enforce(abc.length == 3, "Wrong number of vertices for a face. Every face must be a triangle");

					foreach(i, s ; abc){
						t.vertices[i] = s.split("/")[0].to!uint32_t - 1;
					}
					mesh.triangles ~= t;

				}
				break;
				case "l":{
					string data;
					line.formattedRead!"%s"(data);
					mesh.lines ~= data.split(" ").map!(a => a.to!uint32_t - 1).array;
				}
				break;

				default: break;

			}

		}
		return mesh;
	}


	void toObj(in string file, in string objectName = "genericmesh") const {
		auto obj = File(file, "w");
		File mtl;
		if(materials.length > 0)
			mtl = File(file ~ ".mtl", "w");

		// OBJ definition
		if(materials.length > 0)
			obj.writefln("mtllib %s", file ~ ".mtl");
		obj.writeln("o ",objectName);
		foreach(ref v ; vertices){
			obj.writefln("v %(%f %)", v.v);
		}

		auto currentMaterial = uint32_t.max;
		foreach(ref t ; triangles){
			if(t.material != currentMaterial){
				if(t.material == uint32_t.max)
					obj.writeln("usemtl");
				else
					obj.writefln("usemtl mtl%d", t.material);
				currentMaterial = t.material;
			}

			if(isTriangleClockwise(t.vertices[].map!(a => vec2f(vertices[a].v[0..2])).array[0 .. 3]))
				obj.writefln("f %s %s %s", t.vertices[2]+1, t.vertices[1]+1, t.vertices[0]+1);
			else
				obj.writefln("f %s %s %s", t.vertices[0]+1, t.vertices[1]+1, t.vertices[2]+1);
		}
		foreach(ref l ; lines){
			obj.writefln("l %(%s %)", l.map!(a => a + 1).array);
		}

		// Material lib
		foreach(i, ref material ; materials){
			mtl.writefln("newmtl mtl%d", i);
			if(material.ambientColor[0] != float.nan)  mtl.writefln("Ka %(%f %)", material.ambientColor);
			if(material.ambientTexture !is null)       mtl.writefln("map_Ka %s", material.ambientTexture);
			if(material.diffuseColor[0] != float.nan)  mtl.writefln("Kd  %(%f %)", material.diffuseColor);
			if(material.diffuseTexture !is null)       mtl.writefln("map_Kd %s", material.diffuseTexture);
			if(material.specularColor[0] != float.nan) mtl.writefln("Ks  %(%f %)", material.specularColor);
			if(material.specularTexture !is null)      mtl.writefln("map_Ks %s", material.specularTexture);
			if(material.specularWeight != float.nan)   mtl.writefln("Ns %f", material.specularWeight);
			if(material.transparency != float.nan)     mtl.writefln("Tr %f", material.transparency);
			if(material.bumpTexture !is null)          mtl.writefln("bump %s", material.bumpTexture);
			if(material.dispTexture !is null)          mtl.writefln("disp %s", material.dispTexture);
			if(material.decalTexture !is null)         mtl.writefln("decal %s", material.decalTexture);
			if(material.illumination != Material.Illumniation.None) mtl.writefln("illum %d", material.illumination);
		}
	}

	/// Triangulates a set of vertices and adds the created triangles to the mesh (ear clipping algorithm)
	void triangulatePolygon(in uint32_t[] polygon){
		assert(polygon.length >= 3);

		auto remainingPolygon = polygon.dup;
		while(remainingPolygon.length > 3){
			debug auto prevLen = remainingPolygon.length;

			foreach(i ; 0 .. remainingPolygon.length){
				auto aIndex = i;
				auto bIndex = (i + 1) % remainingPolygon.length;
				auto cIndex = (i + 2) % remainingPolygon.length;

				auto potentialTriangle = [aIndex, bIndex, cIndex].map!(a => vec2f(vertices[remainingPolygon[a]][0..2])).array;

				int isEar = true;
				foreach(v ; remainingPolygon){
					// Check if any polygon vertices are contained by ear triangle
					if(v == remainingPolygon[aIndex] || v == remainingPolygon[bIndex] || v == remainingPolygon[cIndex])
						continue;

					if(isPointInsidePolygon(
						vec2f(vertices[v][0..2]),
						potentialTriangle[0..3],
					)){
						isEar = false;
						break;
					}
				}
				if(isEar){
					// Check if ear vertex is inside potential polygon
					auto potentialPolygon = remainingPolygon.dup().remove(bIndex);
					if(isPointInsidePolygon(
						vec2f(vertices[remainingPolygon[bIndex]][0..2]),
						potentialPolygon.map!(a => vec2f(vertices[a][0..2])).array,
					)){
						isEar = false;
					}
				}

				if(isEar){
					// it is an ear
					triangles ~= Triangle([remainingPolygon[aIndex], remainingPolygon[bIndex], remainingPolygon[cIndex]]);
					remainingPolygon = remainingPolygon.remove(bIndex);
					break;
				}
			}
			debug assert(remainingPolygon.length < prevLen);
		}
		assert(remainingPolygon.length == 3);
		triangles ~= Triangle(remainingPolygon[0 .. 3]);
	}
}



unittest{
	import nwn.trn;
	import std.algorithm;
	import std.math;
	import std.file;
	import std.path;
	auto trn = new Trn(cast(ubyte[])import("TestImportExportTRN.trx"));

	foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
		auto mesh = aswm.toGenericMesh();
		mesh.validate;

		auto file = tempDir.buildPath("test.obj");
		mesh.toObj(file);

		auto mesh2 = GenericMesh.fromObj(File(file));

		assert(mesh.vertices.length == mesh2.vertices.length);
		foreach(i ; 0 .. mesh.vertices.length){
			if(!equal!approxEqual(mesh.vertices[i][], mesh2.vertices[i][]))
				writeln(mesh.vertices[i], "!=", mesh2.vertices[i]);
		}

		assert(equal!((a,b)=>equal!approxEqual(a[], b[]))(mesh.vertices, mesh2.vertices));
		assert(equal!((a,b)=>isPermutation(a.vertices[], b.vertices[]))(mesh.triangles, mesh2.triangles));
	}

}

unittest{
	import nwn.trn;
	import nwn.fastgff;
	import std.range;

	auto git = new FastGff("unittest/WalkmeshObjects.git");
	auto trn = new Trn("unittest/WalkmeshObjects.trn");

	alias WMCutter = vec2f[];
	WMCutter[] wmCutters;
	foreach(_, GffStruct trigger ; git["TriggerList"].get!GffList){

		if(trigger["Type"].get!GffInt == 3){
			// Walkmesh cutter
			WMCutter cutter;

			auto pos = [trigger["XPosition"].get!GffFloat, trigger["YPosition"].get!GffFloat];

			// what about: XOrientation YOrientation ZOrientation ?
			foreach(_, GffStruct point ; trigger["Geometry"].get!GffList){
				cutter ~= vec2f(
					point["PointX"].get!GffFloat + pos[0],
					point["PointY"].get!GffFloat + pos[1],
				);
			}

			wmCutters ~= cutter;
		}
	}

	foreach(ref TrnNWN2WalkmeshPayload aswm ; trn){
		auto mesh = aswm.toGenericMesh();

		// Cut mesh
		foreach(i, ref wmCutter ; wmCutters){
			mesh.polygonCut(wmCutter);
		}

		auto offset = cast(uint32_t)mesh.vertices.length;
		mesh.vertices ~= vec3f(0, 0, 0);
		mesh.vertices ~= vec3f(2, 0, 0);
		mesh.vertices ~= vec3f(2, 2, 0);
		mesh.vertices ~= vec3f(1.2, 1, 0);
		mesh.vertices ~= vec3f(0, 2, 0);
		mesh.vertices ~= vec3f(-0.5, 1, 0);
		mesh.vertices ~= vec3f(-0.7, -1, 0);
		mesh.vertices ~= vec3f(1, -1, 0);
		mesh.triangulatePolygon(iota(offset, offset+7).array);

		aswm.setGenericMesh(mesh);
		aswm.bake();
		aswm.validate();

		auto f = File("test.obj", "w");
		mesh.toObj(f);

		f.writefln("o walkmeshcutters");
		size_t vertOffset = mesh.vertices.length + 1;
		foreach(i, ref wmCutter ; wmCutters){

			foreach(ref v ; wmCutter){
				f.writefln("v %(%s %) 0.1", v.v);
			}
			f.writefln("l %(%s %)", iota(vertOffset, vertOffset + wmCutter.length).array ~ vertOffset);

			vertOffset += wmCutter.length;
		}
	}


}


