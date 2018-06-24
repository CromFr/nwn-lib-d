module nwnlibd.geometry;

import std.math;
import std.typecons;
import gfm.math.vector;

pure:

float signedArea(in vec2f a, in vec2f b, in vec2f c){
	return ((b.x * a.y - a.x * b.y)
		+ (c.x * b.y - b.x * c.y)
		+ (a.x * c.y - c.x * a.y)) / 2.0;
}

float distance(in vec2f[2] line, in vec2f point){
	//auto lineVec = (line[1] - line[0]).normalized;
	//auto hyp = point - line[0];
	//auto proj = line[0] + lineVec * lineVec.dot(hyp);
	//return proj.distanceTo(point);

	return 2.0 * fabs(signedArea(line[0], line[1], point)) / line[0].distanceTo(line[1]);
}
unittest{
	assert(fabs(distance([vec2f(0.0, 0.0), vec2f(10.0, 0.0)], vec2f(3.0, 5.0)) - 5.0) < float.epsilon);
	assert(fabs(distance([vec2f(1.0, 12.0), vec2f(2.0, 19.0)], vec2f(3.0, 5.0)) - 2.9698485) < float.epsilon);
}

bool isPointInTriangle(in vec2f p, in vec2f[3] tri) {
    immutable A = 1/2 * (-tri[1].y * tri[2].x + tri[0].y * (-tri[1].x + tri[2].x) + tri[0].x * (tri[1].y - tri[2].y) + tri[1].x * tri[2].y);
    immutable sign = A < 0 ? -1 : 1;
    immutable s = (tri[0].y * tri[2].x - tri[0].x * tri[2].y + (tri[2].y - tri[0].y) * p.x + (tri[0].x - tri[2].x) * p.y) * sign;
    immutable t = (tri[0].x * tri[1].y - tri[0].y * tri[1].x + (tri[0].y - tri[1].y) * p.x + (tri[1].x - tri[0].x) * p.y) * sign;

    return s > 0 && t > 0 && (s + t) < 2 * A * sign;
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