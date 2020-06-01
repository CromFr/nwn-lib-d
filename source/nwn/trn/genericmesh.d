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
import std.container.dlist;

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

	void removeUnusedVertices(){
		bool[] usedVertices;
		usedVertices.length = vertices.length;
		usedVertices[] = false;

		foreach(ref t ; triangles)
			t.vertices.each!(a => usedVertices[a] = true);
		foreach(ref l ; lines)
			l.each!(a => usedVertices[a] = true);

		uint32_t[] vertexTransTable;
		vertexTransTable.length = vertices.length;

		uint32_t newIndex = 0;
		foreach(oldIndex, used ; usedVertices){
			if(used){
				vertexTransTable[oldIndex] = newIndex;
				vertices[newIndex] = vertices[oldIndex];
				newIndex++;
			}
		}
		vertices.length = newIndex;

		foreach(ref t ; triangles)
			t.vertices.each!((ref a) => vertexTransTable[a]);

		foreach(ref l ; lines)
			l.each!((ref a) => vertexTransTable[a]);
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

		alias EDGE = uint32_t[2];
		uint32_t[EDGE] verticesOnEdge;
		uint32_t addVertex(in vec3f vertex, in EDGE edge = [uint32_t.max, uint32_t.max]){
			if(edge[0] != uint32_t.max && edge[1] != uint32_t.max){
				EDGE sortedEdge = edge[].dup.sort.array;
				if(auto v = sortedEdge in verticesOnEdge){
					return *v;
				}
				auto index = ret.newVertices.length.to!uint32_t;
				verticesOnEdge[sortedEdge] = index;
				ret.newVertices ~= vertex;
				return index;
			}
			else{
				auto index = ret.newVertices.length.to!uint32_t;
				ret.newVertices ~= vertex;
				return index;
			}
		}


		auto lineVec = vec2f(line[1] - line[0]).normalized;

		auto lineVecPer = vec2f(lineVec[1], -lineVec[0]);
		auto lineDist = line[0].dot(lineVecPer);

		foreach(i, ref t ; triangles){
			// TODO: optimize by checking against an AABB

			vec3f[3] triVertices = t.vertices[]
				.map!(a => vertices[a])
				.array[0 .. 3];
			vec2f[3] tri2DVertices = t.vertices[]
				.map!(a => vec2f(vertices[a].v[0 .. 2]))
				.array[0 .. 3];


			// Check if the triangle collides with the infinite line
			float[3] ndot;
			static foreach(j ; 0 .. 3){
				// we calculate the distance between the cutting line and each
				// point of the triangle.
				// If the distance will be >0 or <0 depending on which side of
				// the line is the point.
				ndot[j] = vec2f(tri2DVertices[j]).dot(lineVecPer) - lineDist;
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

			assert(cutEdges.length != 1, "Cutting on triangle vertex not supported yet");
			assert(cutEdges.length == 2,
				"Non-Euclidean geometry: You succeeded at cutting "~cutEdges.length.to!string~" edges of a triangle with a line, well done !");

			auto triDirection = isTriangleClockwise(tri2DVertices);

			// bool[cut edge 0/1][line start/end]
			bool[2][2] edgeDirections;
			foreach(iLinePoint, linePoint ; line){
				foreach(j, edge ; cutEdges){
					edgeDirections[j][iLinePoint] = isTriangleClockwise([tri2DVertices[edge], tri2DVertices[(edge + 1) % 3], linePoint]);
				}
			}

			auto triCut = TriCut(cast(uint32_t)i);
			//stderr.writefln("Triangle collides infinite line on %d edges", cutEdges.length);
			foreach(j, edge ; cutEdges){
				// value == triDirection <=> point is inside of the triangle edge
				if(edgeDirections[j][0] != edgeDirections[j][1]){
					// Calculate intersection point
					auto edgePos = [tri2DVertices[edge], tri2DVertices[(edge + 1) % 3]];

					auto intersection = getLineIntersection(edgePos[0..2], line);
					assert(intersection.intersect, "Should intersect");

					auto altitude = getAltitudeOnPlane(triVertices, intersection.position);
					auto intersectIndex = addVertex(
						vec3f(intersection.position.x, intersection.position.y, altitude),
						[t.vertices[edge], t.vertices[(edge + 1) % 3]],
					);

					triCut.cutVertices[j] = intersectIndex;
					triCut.verticesEdge[j] = edge;
					//stderr.writeln("  cut through edge ", j, " => verticesEdge=", triCut.verticesEdge);
				}
			}
			foreach(j ; 0 .. 2){
				if(edgeDirections[0][j] == triDirection && edgeDirections[1][j] == triDirection){

					auto altitude = getAltitudeOnPlane(triVertices, line[j]);
					auto linePointIndex = addVertex(
						vec3f(line[j].x, line[j].y, altitude),
					);

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
		uint32_t[float[2]] insertedPolygonVertices;
		size_t[][uint32_t] triangleToTriCutIndices;
		foreach(polyVertIdx ; 0 .. polygon.length){
			auto nextCut = lineCut([polygon[polyVertIdx], polygon[(polyVertIdx + 1) % polygon.length]]);

			// Add new vertices as needed, and construct a vertex translate table
			uint32_t[] vertTransTable;// index in nextCut.newVertices => index in this.vertices
			vertTransTable.length = nextCut.newVertices.length;
			foreach(ni, ref nv ; nextCut.newVertices){
				float[2] newVertex2D = nv.v[0 .. 2];
				if(newVertex2D == polygon[polyVertIdx] || newVertex2D == (polygon[(polyVertIdx + 1) % polygon.length])){
					// The vertex is one of the polygon's vertices
					if(auto ov = (newVertex2D in insertedPolygonVertices)){
						// Vertex is already added, link back to it
						vertTransTable[ni] = *ov;
					}
					else{
						// Add vertex
						auto pos = (vertices.length + mergedCut.newVertices.length).to!uint32_t;
						vertTransTable[ni] = pos;
						insertedPolygonVertices[newVertex2D] = pos;
						mergedCut.newVertices ~= nv;
					}
				}
				else{
					// The vertex is on a triangle edge
					vertTransTable[ni] = (vertices.length + mergedCut.newVertices.length).to!uint32_t;
					mergedCut.newVertices ~= nv;
				}
			}

			// Translate nextCut vertex indices
			foreach(j, ref tc ; nextCut.trianglesCut){
				// Keep a list of cuts for a given triangle
				if(tc.triangle in triangleToTriCutIndices)
					triangleToTriCutIndices[tc.triangle] ~= mergedCut.trianglesCut.length + j;
				else
					triangleToTriCutIndices[tc.triangle] = [mergedCut.trianglesCut.length + j];

				// Translate vertex indices
				foreach(ref v ; tc.cutVertices)
					v = vertTransTable[v];
			}

			// Append TriCut
			mergedCut.trianglesCut ~= nextCut.trianglesCut;
		}
		vertices ~= mergedCut.newVertices;
		mergedCut.newVertices.length = 0;

		foreach(triangleIndex, const ref triangleCutIndices ; triangleToTriCutIndices){

			// Merge cut segments into chains (multi-vertex cut lines)
			// and build tables for relationship between vertices, triangle edges and polygon cut ends
			Chains!uint32_t cutChains;
			foreach(ref tcut ; triangleCutIndices.map!(a => mergedCut.trianglesCut[a])){
				assert(tcut.cutVertices[0] != uint32_t.max && tcut.cutVertices[1] != uint32_t.max);
				cutChains.extend(tcut.cutVertices);
			}
			uint32_t[][3] verticesOnEdge; // Ordered list of vertices on one edge
			size_t[uint32_t] vertexToCutChainIndex; // Vertex => polygon cut offset
			ubyte[uint32_t] vertexToEdge; // vertex ID => edge offset
			foreach(ref tcut ; triangleCutIndices.map!(a => mergedCut.trianglesCut[a])){
				static foreach(i ; 0 .. 2){{
					immutable edgeIndex = tcut.verticesEdge[i];
					if(edgeIndex != ubyte.max){
						immutable vertexIndex = tcut.cutVertices[i];

						auto cutChainIndex = cutChains.countUntil!(a => a.front == vertexIndex || a.back == vertexIndex);
						assert(cutChainIndex >= 0);

						verticesOnEdge[edgeIndex] ~= vertexIndex;
						vertexToCutChainIndex[vertexIndex] = cutChainIndex;
						vertexToEdge[vertexIndex] = edgeIndex;
					}
				}}
			}

			debug{
				foreach(ref cut ; cutChains){
					assert(cut.front in vertexToEdge, format!"Cut %s first vertex is not on a triangle edge (incomplete cut)"(cut.array));
					assert(cut.back in vertexToEdge, format!"Cut %s last vertex is not on a triangle edge (incomplete cut)"(cut.array));
				}
			}

			// Sort verticesOnEdge by distance to triangle edge
			foreach(i, ref voe ; verticesOnEdge){
				auto start = &vertices[ triangles[triangleIndex].vertices[i] ];
				voe = voe
					.sort!((a, b) => start.squaredDistanceTo(vertices[a]) < start.squaredDistanceTo(vertices[b]))
					.array;
			}

			ubyte[] exploredCuts;// 0b01 for triangle-oriented direction, 0b10 for reverse direction
			exploredCuts.length = cutChains.length;
			uint32_t[] exploreCut(size_t cutIndex, byte direction){
				assert(direction == -1 || direction == 1);
				uint32_t[] resPolygon = cutChains[cutIndex].array;
				ubyte directionMask = direction == 1? 0b01 : 0b10;

				assert((exploredCuts[cutIndex] & directionMask) == 0, "Already explored cut " ~ cutIndex.to!string);
				exploredCuts[cutIndex] |= directionMask;

				while(1){
					// Explore last vertex of resPolygon

					auto nextCutIndex = size_t.max;
					bool orderedCut;// true=normal, false=reversed
					while(nextCutIndex == size_t.max){
						auto startVertex = resPolygon[$-1];

						if(startVertex in vertexToEdge){
							// startVertex is a vertex on the triangle edge

							auto edgeIndex = vertexToEdge[startVertex];
							auto indexOnEdge = verticesOnEdge[edgeIndex].countUntil(startVertex).to!uint32_t;

							if(direction > 0 ? indexOnEdge + 1 < verticesOnEdge[edgeIndex].length : indexOnEdge > 0){
								// nextEdgeVertex will be a cut vertex on the same edge
								auto nextEdgeVertex = verticesOnEdge[edgeIndex][indexOnEdge + direction];
								if(nextEdgeVertex == resPolygon[0])
									return resPolygon;
								nextCutIndex = vertexToCutChainIndex[nextEdgeVertex];
								orderedCut = nextEdgeVertex == cutChains[nextCutIndex].front;
								debug if(!orderedCut) assert(nextEdgeVertex == cutChains[nextCutIndex].back);
							}
							else{
								// Add next triangle vertex
								auto nextTriangleVertexIndex = direction > 0 ? (edgeIndex + 1) % 3 : edgeIndex;
								resPolygon ~= triangles[triangleIndex].vertices[nextTriangleVertexIndex];
							}
						}
						else{
							// startVertex is a triangle vertex

							auto triangleVertexIndex = triangles[triangleIndex].vertices[].countUntil(startVertex).to!uint32_t;
							auto nextEdge = direction > 0 ? triangleVertexIndex : ((triangleVertexIndex + 2) % 3);

							if(verticesOnEdge[nextEdge].length > 0){
								// there are cuts on nextEdge, follow them
								auto nextEdgeVertex = verticesOnEdge[nextEdge][direction > 0 ? 0 : $-1];
								if(nextEdgeVertex == resPolygon[0])
									return resPolygon;
								nextCutIndex = vertexToCutChainIndex[nextEdgeVertex];
								orderedCut = nextEdgeVertex == cutChains[nextCutIndex].front;
								debug if(!orderedCut) assert(nextEdgeVertex == cutChains[nextCutIndex].back);
							}
							else{
								// There are no cuts on nextEdge, add next triangle vertex
								auto nextTriangleVertexIndex = (triangleVertexIndex + 3 + direction) % 3;
								resPolygon ~= triangles[triangleIndex].vertices[nextTriangleVertexIndex];
							}

						}
					}

					if(orderedCut){
						resPolygon ~= cutChains[nextCutIndex].array;
						assert((exploredCuts[nextCutIndex] & directionMask) == 0);
						exploredCuts[nextCutIndex] |= directionMask;
					}
					else{
						resPolygon ~= cutChains[nextCutIndex].array.reverse.array;
						assert((exploredCuts[nextCutIndex] & (directionMask ^ 0b11)) == 0);
						exploredCuts[nextCutIndex] |= directionMask ^ 0b11;
					}

					assert(resPolygon.dup.sort.uniq.array.length == resPolygon.length, "Loop detected in polygon " ~ resPolygon.to!string);
				}
			}

			uint32_t[][] finalPolygons;
			foreach(polygonCutIndex ; 0 .. cutChains.length){
				if((exploredCuts[polygonCutIndex] & 0b01) == 0){
					finalPolygons ~= exploreCut(polygonCutIndex, 1);
				}
				if((exploredCuts[polygonCutIndex] & 0b10) == 0){
					finalPolygons ~= exploreCut(polygonCutIndex, -1);
				}
			}

			foreach(ref p ; finalPolygons){
				triangulatePolygon(p);
			}


			// Mark triangle for removal
			triangles[triangleIndex].vertices[0] = uint32_t.max;
		}

		if(removeInside){
			// Remove triangles which center point is inside the polygon
			foreach(i, ref t ; triangles){
				if(t.vertices[0] == uint32_t.max)
					continue;

				auto center = (vertices[t.vertices[0]] + vertices[t.vertices[1]] + vertices[t.vertices[2]]) / 3.0;
				if(!isPointInsidePolygon(vec2f(center[0..2]), polygon) == false){
					t.vertices[0] = uint32_t.max;
				}
			}
		}
		triangles = triangles.filter!(a => a.vertices[0] != uint32_t.max).array;
	}

	unittest {
		GenericMesh simpleMesh;
		simpleMesh.vertices = [
			vec3f(0, 0, 0),
			vec3f(0, 1, 0),
			vec3f(1, 0, 0),
		];
		simpleMesh.triangles ~= GenericMesh.Triangle([0, 1, 2]);

		GenericMesh mesh;
		mesh = simpleMesh.dup();
		mesh.polygonCut([
			vec2f(2, 0.2),
			vec2f(0.2, 0.2),
			vec2f(0.2, 2),
		]);
		assert(mesh.vertices.length == 6);
		assert(mesh.triangles.length == 4);

		mesh = simpleMesh.dup();
		mesh.polygonCut([
				vec2f(2, -1),
				vec2f(0.2, 0.2),
				vec2f(0.2, 2),
		]);
		mesh.removeUnusedVertices();
		assert(mesh.vertices.length == 5);
		assert(mesh.triangles.length == 3);

		mesh = simpleMesh.dup();
		mesh.polygonCut([
			vec2f(0.5, 1),
			vec2f(-0.5, 0),
			vec2f(0, -0.5),
			vec2f(1, 0.5),
		]);
		mesh.removeUnusedVertices();
		assert(mesh.vertices.length == 6);
		assert(mesh.triangles.length == 2);

		mesh = simpleMesh.dup();
		mesh.polygonCut([
			vec2f(0.2, 2),
			vec2f(0.2, 0.2),
			vec2f(0.4, 2),
			vec2f(0.5, -0.5),
			vec2f(1, 3),
		]);
		assert(mesh.vertices.length == 10);
		assert(mesh.triangles.length == 6);

		//// polygon on triangle vertex
		//mesh = simpleMesh.dup();
		//mesh.polygonCut([
		//	vec2f(0, 0),
		//	vec2f(0.2, 0.2),
		//	vec2f(0.4, 2),
		//	vec2f(0.5, -0.5),
		//	vec2f(1, 3),
		//]);
		//mesh.removeUnusedVertices();
		//assert(mesh.vertices.length == 10);
		//assert(mesh.triangles.length == 6);
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
	foreach(_, trigger ; git["TriggerList"].get!GffList){

		if(trigger["Type"].get!GffInt == 3){
			// Walkmesh cutter
			WMCutter cutter;

			auto pos = [trigger["XPosition"].get!GffFloat, trigger["YPosition"].get!GffFloat];

			// what about: XOrientation YOrientation ZOrientation ?
			foreach(_, point ; trigger["Geometry"].get!GffList){
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


		aswm.setGenericMesh(mesh);
		aswm.bake();
		aswm.validate();



	}


}


