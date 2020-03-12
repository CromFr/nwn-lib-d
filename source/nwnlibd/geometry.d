module nwnlibd.geometry;

import std.math;
import std.typecons;
import gfm.math.vector;


			import std.stdio;
			import std.algorithm;
			import std.array;

//pure:

double signedArea(in vec2f a, in vec2f b, in vec2f c){
	return ((b.x * a.y - a.x * b.y)
		+ (c.x * b.y - b.x * c.y)
		+ (a.x * c.y - c.x * a.y)) / 2.0;
}

double distance(in vec2f[2] line, in vec2f point){
	return 2.0 * fabs(signedArea(line[0], line[1], point)) / line[0].distanceTo(line[1]);
}
unittest{
	assert(approxEqual(distance([vec2f(0.0, 0.0), vec2f(10.0, 0.0)], vec2f(3.0, 5.0)), 5.0));
	assert(approxEqual(distance([vec2f(1.0, 12.0), vec2f(2.0, 19.0)], vec2f(3.0, 5.0)), 2.9698485));
}

//bool isPointInTriangle(in vec2f p, in vec2f[3] tri) {
//    immutable A = 1/2 * (-tri[1].y * tri[2].x + tri[0].y * (-tri[1].x + tri[2].x) + tri[0].x * (tri[1].y - tri[2].y) + tri[1].x * tri[2].y);
//    immutable sign = A < 0 ? -1 : 1;
//    immutable s = (tri[0].y * tri[2].x - tri[0].x * tri[2].y + (tri[2].y - tri[0].y) * p.x + (tri[0].x - tri[2].x) * p.y) * sign;
//    immutable t = (tri[0].x * tri[1].y - tri[0].y * tri[1].x + (tri[0].y - tri[1].y) * p.x + (tri[1].x - tri[0].x) * p.y) * sign;

//    return s > 0 && t > 0 && (s + t) < 2 * A * sign;
//}
//unittest{
//	assert(isPointInTriangle(
//		vec2f(vertices[v][0..2]),
//		potentialTriangle[0..3],
//	));
//}

bool isTriangleClockwise(in vec2f[3] tri){
	return signedArea(tri[0], tri[1], tri[2]) > 0;
}
unittest{
	assert(isTriangleClockwise([vec2f(0.0, 0.0), vec2f(0.0, 1.0), vec2f(1.0, 0.0)]));
	assert(!isTriangleClockwise([vec2f(0.0, 0.0), vec2f(1.0, 0.0), vec2f(0.0, 1.0)]));
}

bool isPointLeftOfLine(in vec2f point, in vec2f[2] line){
	return isTriangleClockwise([line[0], line[1], point]);
}


// source: https://wrf.ecse.rpi.edu//Research/Short_Notes/pnpoly.html
bool isPointInsidePolygon(in vec2f point, in vec2f[] polygon){
	size_t i, j;
	bool c = false;
	for(i = 0, j = polygon.length - 1 ; i < polygon.length; j = i++) {
		if((polygon[i].y > point.y) != (polygon[j].y > point.y)
		&& (point.x < (polygon[j].x - polygon[i].x) * (point.y - polygon[i].y) / (polygon[j].y - polygon[i].y) + polygon[i].x))
			c = !c;
	}
	return c;
}

float getAltitudeOnPlane(in vec3f[3] triangle, in vec2f point){
	auto normal = (triangle[1] - triangle[0])
		.cross(triangle[2] - triangle[0])
		.normalized;
	return getAltitudeOnPlane(normal, triangle[0], point);
}
float getAltitudeOnPlane(in vec3f normal, in vec3f pointOnPlane, in vec2f point){
	return (normal.x * (pointOnPlane.x - point.x) + normal.y * (pointOnPlane.y - point.y))
		/ (normal.z)
		+ pointOnPlane.z;
}
unittest{
	vec3f[3] t = [vec3f([0,0,0]), vec3f([1,0,0]), vec3f([0,1,1])];
	assert(getAltitudeOnPlane(t, vec2f([0,0])).approxEqual(0));
	assert(getAltitudeOnPlane(t, vec2f([0,-1])).approxEqual(-1));
	assert(getAltitudeOnPlane(t, vec2f([5,3])).approxEqual(3));
}


auto getLineIntersection(in vec2f[2] lineA, in vec2f[2] lineB)
{
	alias Ret = Tuple!(bool,"intersect", vec2f,"position");
    immutable s1_x = lineA[1].x - lineA[0].x;
    immutable s1_y = lineA[1].y - lineA[0].y;
    immutable s2_x = lineB[1].x - lineB[0].x;
    immutable s2_y = lineB[1].y - lineB[0].y;

    immutable s = (-s1_y * (lineA[0].x - lineB[0].x) + s1_x * (lineA[0].y - lineB[0].y)) / (-s2_x * s1_y + s1_x * s2_y);
    immutable t = ( s2_x * (lineA[0].y - lineB[0].y) - s2_y * (lineA[0].x - lineB[0].x)) / (-s2_x * s1_y + s1_x * s2_y);

    if (s >= 0 && s <= 1 && t >= 0 && t <= 1)
    {
        // Collision detected
        return Ret(true, vec2f(lineA[0].x + (t * s1_x), lineA[0].y + (t * s1_y)));
    }
    return Ret(false, vec2f());
}


vec2f toVec2f(in vec3f vector){
	return vec2f(vector.v[0..2]);
}

/// Useful for assembling a multi-vertex line from 2-point segments
struct Chains(T){
	import std.container.dlist: DList;
	import std.array: array;
	import std.algorithm: reverse, remove;

	alias Chain = DList!T;
	Chain[] chains;
	alias chains this;


	void extend(in T[] newChain){
		//stderr.writeln("extend ", chains.map!(a => a.array).array);
		assert(newChain.length >= 2);

		static struct ChainPos{ size_t index = size_t.max; bool isInFront; }
		ChainPos[2] chainPos;
		stderr.writefln("Extend with %s", newChain);
		foreach(i, ref chain ; chains){
			stderr.writefln("  Chain %s = %s", i, chain[]);
			static foreach(chainExtremity ; 0 .. 2){{
				immutable newChainVertex = newChain[chainExtremity == 0 ? 0 : $-1];
				if(chain.front == newChainVertex || chain.back == newChainVertex){
					chainPos[chainExtremity] = ChainPos(i, chain.front == newChainVertex);
				}
			}}
		}
		stderr.writeln("chainPos=", chainPos);
		if(chainPos[0].index == size_t.max && chainPos[1].index == size_t.max){
			// unknown vertices, append both to a new chain
			chains ~= Chain(newChain.dup);
			//stderr.writefln("Add unknown chain: %s", newChain);
			//stderr.writeln("  ==> res ", chains.map!(a => a.array).array);
		}
		else if(chainPos[0].index != size_t.max && chainPos[1].index != size_t.max){
			// Both vertices are known, link both chains together
			assert(chainPos[0].index != chainPos[1].index);

			stderr.writefln("chains: %s", chains.map!(a => a.array).array);
			stderr.writefln("Stitch chains: %d with %s", chainPos[0].index, chainPos[1].index);

			// Append to chains[chainPos[0].index]
			if(chainPos[0].isInFront)
				chains[chainPos[0].index].insertFront(
					(chainPos[1].isInFront? Chain(chains[chainPos[1].index][].reverse) : chains[chainPos[1].index])[]
				);
			else
				chains[chainPos[0].index].insertBack(
					(chainPos[1].isInFront? chains[chainPos[1].index] : Chain(chains[chainPos[1].index][].reverse))[]
				);

			// Remove chains[chainPos[1].index]
			chains.remove(chainPos[1].index);
			//stderr.writeln("  ==> res ", chains.map!(a => a.array).array);
		}
		else{
			// only one newChain is known, extend existing chain

			static foreach(chainExtremity ; 0 .. 2){
				if(chainPos[chainExtremity].index != size_t.max){
					stderr.writefln("Append %s to %s", newChain, chains[chainPos[chainExtremity].index][].array);
					immutable chainIndex = chainPos[chainExtremity].index;
					if(chainPos[chainExtremity].isInFront)
						chains[chainIndex].insertFront(
							chains[chainIndex].front == newChain[$-1] ? newChain.dup[0 .. $-1] : newChain.dup.reverse[0 .. $-1]
						);
					else
						chains[chainIndex].insertBack(
							chains[chainIndex].back == newChain[0] ? newChain.dup[1 .. $] : newChain.dup.reverse[1 .. $]
						);
					//stderr.writeln("  ==> res ", chains.map!(a => a.array).array);
					return;
				}
			}
			assert(0);
		}
	}
}
unittest{
	import std.algorithm;
	Chains!int chains;
	chains.extend([0, 1]);
	chains.extend([1, 2, 3]);

	chains.extend([11, 10]);
	chains.extend([12, 11]);
	chains.extend([12, 13]);
	chains.extend([10, 9]);

	chains.extend([20, 21]);
	chains.extend([22, 23]);
	chains.extend([22, 21]);

	assert(chains.countUntil!(a => a[].equal([0, 1, 2, 3])) >= 0);
	assert(chains.countUntil!(a => a[].equal([13, 12, 11, 10, 9])) >= 0);
	assert(chains.countUntil!(a => a[].equal([20, 21, 22, 23])) >= 0);
}