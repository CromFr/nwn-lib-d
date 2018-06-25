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
debug import std.stdio: write, writeln;

import nwnlibd.geometry;
import gfm.math.vector;


struct GenericMesh {
	vec3f[] vertices;

	static struct Triangle{
		uint32_t[3] vertices; /// Vertex indices composing the triangle
	}
	Triangle[] triangles;

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
		foreach(uint32_t i, ref val ; vertTransTable) val = i;
		foreach(uint32_t i, ref val ; triTransTable) val = i;

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



	auto findTrianglesIntersecting(vec2f[2] line) const {
		struct TriCut{
			uint32_t triangle;
			static struct CutEdge{
				ubyte edgeOffset;
				vec3f intersection;
			}
			CutEdge[] cutEdges;
			vec3f[] innerVertices;
		}
		TriCut[] ret;


		auto lineVec = vec2f(line[1] - line[0]).normalized;

		auto lineVecPer = vec2f(lineVec[1], -lineVec[0]);
		auto lineDist = line[0].dot(lineVecPer);

		foreach(uint32_t i, ref t ; triangles){

			vec2f[3] triVertices = t.vertices[]
				.map!(a => vec2f(vertices[a].v[0 .. 2]))
				.array[0 .. 3];

			// TODO: optimize by checking against an AABB

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
			assert(cutEdges.length <= 2,
				"You succeeded at cutting "~cutEdges.length.to!string~" edges of a triangle with an infinite line");

			auto cw = isTriangleClockwise(triVertices);

			// bool[edge 0/1][line start/end]
			bool[2][2] edgeCw;
			foreach(iLinePoint, linePoint ; line){
				foreach(j, edge ; cutEdges){
					edgeCw[j][iLinePoint] = isTriangleClockwise([triVertices[edge], triVertices[(edge + 1) % 3], linePoint]);
				}
			}

			auto triCut = TriCut(i, []);

			foreach(j, edge ; cutEdges){
				// value == cw <=> point is inside of the triangle edge
				if((edgeCw[j][0] == cw && edgeCw[j][1] != cw)
				|| (edgeCw[j][0] != cw && edgeCw[j][1] == cw)){
					// Calculate intersection point
					auto edgePos = [triVertices[edge], triVertices[(edge + 1) % 3]];
					auto edgeVec = edgePos[1] - edgePos[0];

					auto intersection = getLineIntersection(edgePos[0..2], line);
					assert(intersection.intersect, "Should intersect");

					// Register cutted edge
					triCut.cutEdges ~= TriCut.CutEdge(
						edge,
						vec3f(intersection[1].x, intersection[1].y, 0.0)//TODO: handle z
					);
				}
			}

			if(triCut.cutEdges.length == 0)
				continue;

			// Add created vertices inside the triangle
			foreach(j ; 0 .. 2){
				if(j >= triCut.cutEdges.length)
					triCut.innerVertices ~= vec3f(line[j].x, line[j].y, 0.0);//TODO: handle z
			}

			debug{
				foreach(j, e ; triCut.cutEdges){
					vec2f[2] edge = [vertices[t.vertices[e.edgeOffset]].toVec2f, vertices[t.vertices[(e.edgeOffset + 1)%3]].toVec2f];
					assert(distance(edge, e.intersection.toVec2f) < 0.001,
						"New vertice is not on the correct edge: distance="~distance(edge[0..2], e.intersection.toVec2f).to!string);
				}
			}

			ret ~= triCut;
		}
		return ret;

	}



	void polygonCut(vec2f[] polygon, bool removeInside = true){
		validate();

		ReturnType!findTrianglesIntersecting mergedTriCut;

		{
			ReturnType!findTrianglesIntersecting triCut;
			foreach(i ; 0 .. polygon.length){
				triCut ~= findTrianglesIntersecting([polygon[i], polygon[(i + 1) % polygon.length]]);
			}

			// Merge triangle cuts together
			uint32_t lastTri = uint32_t.max;
			foreach(ref tc ; triCut.sort!"a.triangle < b.triangle"){
				if(tc.triangle == lastTri){
					mergedTriCut[$ - 1].cutEdges = (mergedTriCut[$ - 1].cutEdges ~ tc.cutEdges)
						.sort!"a.edgeOffset < b.edgeOffset"
						.uniq!"a.edgeOffset == b.edgeOffset"
						.array;

					foreach(ref v ; tc.innerVertices){
						bool matchFound = false;
						foreach(ref ov ; mergedTriCut[$ - 1].innerVertices){
							if(v.squaredDistanceTo(ov) < 0.001){
								matchFound = true;
								break;
							}
						}
						if(matchFound == false)
							mergedTriCut[$ - 1].innerVertices ~= v;
					}
				}
				else{
					mergedTriCut ~= tc;
				}
				lastTri = tc.triangle;
			}
		}

		// Proceed to cutting
		foreach(i, ref tc ; mergedTriCut){

			auto triangle = triangles[tc.triangle];

			//TODO: handle (tc.cutEdges == 1 && tc.newVertices == 1), ie the line cut the triangle through one vertex
			if(tc.cutEdges.length == 2 && tc.innerVertices.length == 0){
				auto vertIdx = vertices.length.to!uint32_t;
				foreach(ref e ; tc.cutEdges)
					vertices ~= e.intersection;

				ubyte commonVertTriOffset;
				auto cutEdgesOffsets = tc.cutEdges.map!(a => a.edgeOffset).array;

				if(cutEdgesOffsets == [0,1])      commonVertTriOffset = 1;
				else if(cutEdgesOffsets == [1,2]) commonVertTriOffset = 2;
				else if(cutEdgesOffsets == [0,2]) commonVertTriOffset = 0;
				else assert(0);
				uint32_t commonVertIdx = triangle.vertices[commonVertTriOffset];

				auto isCommonInside = removeInside == true ? isPointInsidePolygon(vec2f(vertices[commonVertIdx][0..2]), polygon) : false;

				// Add triangle next to the common vertex
				if(removeInside == false || !isCommonInside){
					triangles ~= Triangle([commonVertIdx, vertIdx, vertIdx + 1]);
				}
				 // Add two triangle to fill the 4-edge shape
				if(removeInside == false || isCommonInside){
					auto isClockwise = isTriangleClockwise(triangle.vertices[].map!(a => vec2f(vertices[a].v[0..2])).array[0 .. 3]);
					// newVert[0] -> newVert[1] -> common vertex
					auto abcCw = isTriangleClockwise([
						vertices[vertIdx].toVec2f,
						vertices[vertIdx + 1].toVec2f,
						vertices[commonVertIdx].toVec2f
					]);

					triangles ~= Triangle(
						[
							vertIdx,
							vertIdx + 1,
							triangle.vertices[(commonVertTriOffset + (abcCw != isClockwise? 1 : 2)) % 3],
						]);
					triangles ~= Triangle(
						[
							vertIdx,
							triangle.vertices[(commonVertTriOffset + (abcCw != isClockwise? 1 : 2)) % 3],
							triangle.vertices[(commonVertTriOffset + (abcCw != isClockwise? 2 : 1)) % 3],
						]);
				}

			}

			// Mark triangle for removal
			triangles[tc.triangle].vertices[0] = uint32_t.max;
		}

		debug{
			immutable oldLen = triangles.length;
			triangles = triangles.filter!(a => a.vertices[0] != uint32_t.max).array;

			assert(triangles.length + mergedTriCut.length == oldLen,
				(oldLen - triangles.length).to!string ~ " triangles removed, instead of " ~ mergedTriCut.length.to!string);
		}
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

				default: break;

			}

		}
		return mesh;
	}


	void toObj(File obj, in string name = "genericmesh") const {
		obj.writeln("o ",name);
		foreach(ref v ; vertices){
			obj.writefln("v %(%f %)", v.v);
		}

		foreach(ref t ; triangles){
			if(isTriangleClockwise(t.vertices[].map!(a => vec2f(vertices[a].v[0..2])).array[0 .. 3]))
				obj.writefln("f %s %s %s", t.vertices[2]+1, t.vertices[1]+1, t.vertices[0]+1);
			else
				obj.writefln("f %s %s %s", t.vertices[0]+1, t.vertices[1]+1, t.vertices[2]+1);
		}

	}
}

