module nwnlibd.geometry;

import std.math;
import gfm.math.vector;

pure:

float signedArea(vec2f a, vec2f b, vec2f c){
	return ((b.x * a.y - a.x * b.y)
		+ (c.x * b.y - b.x * c.y)
		+ (a.x * c.y - c.x * a.y)) / 2.0;
}

float distance(vec2f[2] line, vec2f point){
	return 2.0 * fabs(signedArea(line[0], line[1], point)) / line[0].distanceTo(line[1]);
}

bool isPointInTriangle(vec2f p, vec2f[3] tri) {
    auto A = 1/2 * (-tri[1].y * tri[2].x + tri[0].y * (-tri[1].x + tri[2].x) + tri[0].x * (tri[1].y - tri[2].y) + tri[1].x * tri[2].y);
    auto sign = A < 0 ? -1 : 1;
    auto s = (tri[0].y * tri[2].x - tri[0].x * tri[2].y + (tri[2].y - tri[0].y) * p.x + (tri[0].x - tri[2].x) * p.y) * sign;
    auto t = (tri[0].x * tri[1].y - tri[0].y * tri[1].x + (tri[0].y - tri[1].y) * p.x + (tri[1].x - tri[0].x) * p.y) * sign;

    return s > 0 && t > 0 && (s + t) < 2 * A * sign;
}

bool isTriangleClockwise(vec2f[3] tri){
	return signedArea(tri[0], tri[1], tri[2]) > 0;
}
unittest{
	assert(isTriangleClockwise([vec2f(0.0, 0.0), vec2f(0.0, 1.0), vec2f(1.0, 0.0)]));
	assert(!isTriangleClockwise([vec2f(0.0, 0.0), vec2f(1.0, 0.0), vec2f(0.0, 1.0)]));
}

bool isPointLeftOfLine(vec2f point, vec2f[2] line){
	return isTriangleClockwise([line[0], line[1], point]);
}

