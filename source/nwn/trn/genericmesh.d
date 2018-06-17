module nwn.trn.genericmesh;

import std.stdint;
import std.conv: to;
import std.algorithm;
import std.math;
import std.exception: enforce;
import std.array: array;

import nwnlibd.geometry;
import gfm.math.vector;


struct GenericASWMMesh {
	vec3f[] vertices;

	static struct Triangle{
		uint32_t[3] vertices; /// Vertex indices composing the triangle
		uint16_t flags; /// See `Flags`
		enum Flags {
			walkable  = 0x01, /// if the triangle can be walked on. Note the triangle needs path tables to be really walkable
			dirt      = 0x08, /// Floor type (for sound effects)
			grass     = 0x10, /// ditto
			stone     = 0x20, /// ditto
			wood      = 0x40, /// ditto
			carpet    = 0x80, /// ditto
			metal     = 0x100, /// ditto
			swamp     = 0x200, /// ditto
			mud       = 0x400, /// ditto
			leaves    = 0x800, /// ditto
			water     = 0x1000, /// ditto
			puddles   = 0x2000, /// ditto
		}
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
			triangles[newTIdx] = Triangle(oldTri.vertices, oldTri.flags);

			foreach(ref v ; triangles[newTIdx].vertices[].randomShuffle)
				v = vertTransTable[v];
		}
	}


	auto findTrianglesIntersecting(vec2f[2] line) const {
		struct TriCut{
			uint32_t triangle;
			ubyte[] cutEdges;
		}
		TriCut[] ret;


		auto lineVec = vec2f(line[1] - line[0]).normalized;

		auto lineVecPer = vec2f(lineVec[1], -lineVec[0]);
		auto lineDist = line[0].dot(lineVecPer);

		foreach(uint32_t i, ref t ; triangles){

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
				|| (edgeCw[j][0] != cw && edgeCw[j][1] == cw))
					triCut.cutEdges ~= edge;
			}

			if(triCut.cutEdges.length == 0)
				continue;


			ret ~= triCut;
		}
		return ret;

	}
}

