module nwnlibd.geometry;

import std.math;
import std.traits;
import std.typecons;
import gfm.math.vector;

pure:

double signedArea(in vec2f a, in vec2f b, in vec2f c){
	return ((b.x * a.y - a.x * b.y)
		+ (c.x * b.y - b.x * c.y)
		+ (a.x * c.y - c.x * a.y)) / 2.0;
}

double distance(in vec2f[2] line, in vec2f point){
	return 2.0 * fabs(signedArea(line[0], line[1], point)) / line[0].distanceTo(line[1]);
}
unittest{
	assert(isClose(distance([vec2f(0.0, 0.0), vec2f(10.0, 0.0)], vec2f(3.0, 5.0)), 5.0));
	assert(isClose(distance([vec2f(1.0, 12.0), vec2f(2.0, 19.0)], vec2f(3.0, 5.0)), 2.9698484817));
}

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
	assert(getAltitudeOnPlane(t, vec2f([0,0])).isClose(0));
	assert(getAltitudeOnPlane(t, vec2f([0,-1])).isClose(-1));
	assert(getAltitudeOnPlane(t, vec2f([5,3])).isClose(3));
}

auto getLineIntersection(T)(in Vector!(T, 2)[2] lineA, in Vector!(T, 2)[2] lineB) if(isFloatingPoint!T)
{
	alias Ret = Tuple!(bool,"intersect", Vector!(T, 2),"position");
	static T[3] lineCalc(in Vector!(T, 2)[2] line){
		return [
			(line[0][1] - line[1][1]),
			(line[1][0] - line[0][0]),
			-(line[0][0]*line[1][1] - line[1][0]*line[0][1]),
		];
	}

	immutable l1 = lineCalc(lineA);
	immutable l2 = lineCalc(lineB);

    immutable d  = l1[0] * l2[1] - l1[1] * l2[0];
    immutable dx = l1[2] * l2[1] - l1[1] * l2[2];
    immutable dy = l1[0] * l2[2] - l1[2] * l2[0];
    if(d != 0){
    	return Ret(true, Vector!(T, 2)(dx / d, dy / d));
    }
    return Ret(false, Vector!(T, 2)());
}
unittest{
	auto intersect = getLineIntersection([vec2f(0, 0), vec2f(1, 1)], [vec2f(1, 0), vec2f(1, 1)]);
	assert(intersect.intersect);
	assert(intersect.position.x.isClose(1));
	assert(intersect.position.y.isClose(1));

	intersect = getLineIntersection([vec2d(123.1, 42.8), vec2d(100, 171.667)], [vec2d(99.9197, 173.126), vec2d(99.9765, 172.353)]);
	assert(intersect.intersect);
	assert(intersect.position.x.isClose(100.0456008911));
	assert(intersect.position.y.isClose(171.4126129150));


	intersect = getLineIntersection([vec2d(99.9757, 172.41), vec2d(100, 171.667)], [vec2d(99.9197, 173.126), vec2d(99.9765, 172.353)]);
	assert(intersect.intersect);
	assert(intersect.position.x.isClose(99.9784164429));
	assert(intersect.position.y.isClose(172.3269042969));

	intersect = getLineIntersection([vec2d(0.75, 0.13), vec2d(0.46, 0.21)], [vec2d(0.94, 0.82), vec2d(0.48, 0.57)]);
	assert(intersect.intersect);
	assert(intersect.position.x.isClose(0.0338883810));
	assert(intersect.position.y.isClose(0.3275480270));

	intersect = getLineIntersection([vec2d(0, 0), vec2d(1, 1)], [vec2d(5, 0), vec2d(6, 1)]);
	assert(!intersect.intersect);
}

auto getSegmentIntersection(T)(in Vector!(T, 2)[2] segA, in Vector!(T, 2)[2] segB){
	auto intersect = getLineIntersection(segA, segB);
	if(isTriangleClockwise((segA[] ~ segB[0])[0 .. 3]) != isTriangleClockwise((segA[] ~ segB[1])[0 .. 3])
	&& isTriangleClockwise((segB[] ~ segA[0])[0 .. 3]) != isTriangleClockwise((segB[] ~ segA[1])[0 .. 3])){
		// intersection
		return intersect;
	}
	return typeof(intersect)(false, Vector!(T, 2)());
}

/// Returns true if the polygon is complex (self intersecting)
/// Simple bruteforce method, O(n²) complexity
bool isPolygonComplex(in vec2f[] polygon){
	assert(polygon.length > 2);
    foreach(i ; 0 .. polygon.length / 2 + 1){
    	foreach(j ; 0 .. polygon.length){
    		if(j == i || (j+1) % polygon.length == i || (j + polygon.length - 1) % polygon.length == i)
    			continue;
    		if(getSegmentIntersection(
    			[polygon[i], polygon[(i + 1) % polygon.length]],
    			[polygon[j], polygon[(j + 1) % polygon.length]],
    		).intersect){
    			return true;
    		}
    	}
    }
    return false;
}
unittest{
	assert(!isPolygonComplex([
		vec2f([125.701, 175.164]),
		vec2f([127.324, 175.198]),
		vec2f([127.107, 170.852]),
		vec2f([126.358, 170.737]),
	]));
	assert(!isPolygonComplex([
		vec2f([88.8613, 233.356]),
		vec2f([89.0199, 234.805]),
		vec2f([88.173, 234.874]),
		vec2f([87.8595, 234.935]),
		vec2f([87.9355, 236.449]),
		vec2f([88.4193, 237.144]),
		vec2f([87.9985, 237.693]),
		vec2f([86.7631, 238.032]),
		vec2f([85.3175, 237.102]),
		vec2f([85.0783, 235.127]),
		vec2f([86.216, 233.077]),
		vec2f([86.8881, 233.572]),
		vec2f([86.6886, 234.077]),
		vec2f([87.1182, 234.339]),
		vec2f([87.7617, 234.406]),
		vec2f([87.7927, 233.435]),
	]));
	assert(isPolygonComplex([
		vec2f([125.701, 175.164]),
		vec2f([127.107, 170.852]),
		vec2f([127.324, 175.198]),
		vec2f([126.358, 170.737]),
	]));
}


vec2f toVec2f(in vec3f vector){
	return vec2f(vector.v[0..2]);
}
vec3f toVec3f(in vec2f vector){
	return vec3f(vector.v[0..$] ~ 0.0);
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
		assert(newChain.length >= 2);
		debug scope(exit){
			import std.algorithm: map;
			import std.conv;
			bool[T] values;
			foreach(ref chain ; chains){
				foreach(value ; chain){
					assert(value !in values, "Duplicated value in chains in " ~ chains.map!(a => a[]).to!string);
					values[value] = true;
				}
			}
		}

		static struct ChainPos{ size_t index = size_t.max; bool isInFront; }
		ChainPos[2] chainPos;
		foreach(i, ref chain ; chains){
			foreach(chainExtremity ; 0 .. 2){{
				immutable newChainValue = newChain[chainExtremity == 0 ? 0 : $-1];
				if(chain.front == newChainValue || chain.back == newChainValue){
					chainPos[chainExtremity] = ChainPos(i, chain.front == newChainValue);
				}
			}}
		}

		if(chainPos[0].index == size_t.max && chainPos[1].index == size_t.max){
			// unknown vertices, append both to a new chain
			chains ~= Chain(newChain.dup);
		}
		else if(chainPos[0].index != size_t.max && chainPos[1].index != size_t.max){
			// Both vertices are known, link both chains together
			assert(chainPos[0].index != chainPos[1].index);

			immutable targetChainIdx = chainPos[0].index;
			immutable rmChainIdx = chainPos[1].index;

			auto middleVertices = newChain[1 .. $-1];

			// Append to chains[chainPos[0].index]
			if(chainPos[0].isInFront){
				if(chainPos[1].isInFront)
					chains[chainPos[0].index].insertFront(
						(middleVertices ~ chains[chainPos[1].index].array).reverse
					);
				else
					chains[chainPos[0].index].insertFront(
						(chains[chainPos[1].index] ~ middleVertices)[]
					);
			}
			else{
				if(chainPos[1].isInFront)
					chains[chainPos[0].index].insertBack(
						(middleVertices ~ chains[chainPos[1].index].array)[]
					);
				else
					chains[chainPos[0].index].insertBack(
						(chains[chainPos[1].index].array ~ middleVertices).reverse
					);
			}

			// Remove chains[chainPos[1].index]
			chains = chains.remove(chainPos[1].index);
		}
		else{
			// only one newChain is known, extend existing chain
			foreach(chainExtremity ; 0 .. 2){
				if(chainPos[chainExtremity].index != size_t.max){
					immutable chainIndex = chainPos[chainExtremity].index;
					if(chainPos[chainExtremity].isInFront)
						chains[chainIndex].insertFront(
							chains[chainIndex].front == newChain[$-1] ? newChain.dup[0 .. $-1] : newChain.dup.reverse[0 .. $-1]
						);
					else
						chains[chainIndex].insertBack(
							chains[chainIndex].back == newChain[0] ? newChain.dup[1 .. $] : newChain.dup.reverse[1 .. $]
						);
					return;
				}
			}
			assert(0);
		}
	}

	string toString() {
		import std.conv: to;
		import std.algorithm: map;
		return chains.map!(a => a[]).to!string;
	}
}
unittest{
	import std.algorithm;
	import std.exception;

	Chains!int chains;
	// extending one chain
	chains.extend([0, 1]);
	chains.extend([1, 2, 3]);

	chains.extend([12, 11]);
	chains.extend([13, 12]);
	chains.extend([13, 14]);
	chains.extend([11, 10]);

	// merging two existing chains together
	chains.extend([20, 21]);
	chains.extend([22, 23]);
	chains.extend([22, 21]);

	chains.extend([31, 30]);
	chains.extend([33, 32]);
	chains.extend([32, 31]);

	chains.extend([40, 41]);
	chains.extend([43, 42]);
	chains.extend([42, 41]);

	chains.extend([50, 51]);
	chains.extend([53, 54]);
	chains.extend([51, 52, 53]);

	// Error out on duplicated insert
	chains.extend([60, 61]);
	assertThrown!Error(chains.extend([60, 61]));

	//chains.extend([60, 61, 62, 63]);
	//assertThrown!Error(chains.extend([62, 63]));

	assert(chains.countUntil!(a => a[].equal([0, 1, 2, 3])) >= 0);
	assert(chains.countUntil!(a => a[].equal([14, 13, 12, 11, 10])) >= 0);
	assert(chains.countUntil!(a => a[].equal([20, 21, 22, 23])) >= 0);
	assert(chains.countUntil!(a => a[].equal([33, 32, 31, 30])) >= 0);
	assert(chains.countUntil!(a => a[].equal([43, 42, 41, 40])) >= 0);
	assert(chains.countUntil!(a => a[].equal([50, 51, 52, 53, 54])) >= 0);
	assert(chains.countUntil!(a => a[].equal([60, 61])) >= 0);
	assert(chains.length == 7);
}