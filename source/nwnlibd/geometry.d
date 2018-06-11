module nwnlibd.geometry;

import std.conv;

alias Vec2 = Vec!2;
alias Vec3 = Vec!3;

struct Vec(size_t dim, T = float){

	T[dim] pos;

	this(VT...)(VT pos) if(pos.length == dim){
		foreach(i, p ; pos){
			static assert(is(typeof(p): T), "Cannot convert argument "~i.to!string~" of type "~typeof(p).stringof~" to "~T.stringof);
			this.pos[i] = p;
		}
	}

	static if(dim > 0){
		@property void x(T x){pos[0] = x;}
		@property T x() const {return pos[0];}
	}
	static if(dim > 1){
		@property void y(T y){pos[1] = y;}
		@property T y() const {return pos[1];}
	}
	static if(dim > 2){
		@property void z(T z){pos[2] = z;}
		@property T z() const {return pos[2];}
	}


	Vect3D!T opBinary(string op, O)(in O other){
	  static if(__traits(isArithmetic, O))
	    return Vect3D!T(
	      mixin("x"~op~"other"),
	      mixin("y"~op~"other"),
	      mixin("z"~op~"other"));
	 else static if(is(O : typeof(this)))
	    return Vect3D!T(
	      mixin("x"~op~"other.x"),
	      mixin("y"~op~"other.y"),
	      mixin("z"~op~"other.z"));
	}
}

alias AABB2 = AABB!2;
alias AABB3 = AABB!3;

struct AABB(size_t dim, T = float){
	this(Vec!(dim,T) start, Vec!(dim,T) end){
		foreach(i ; 0 .. dim)
			assert(start.pos[i] < end.pos[i], "Bad AABB start/end vectors");
		this.start = start;
		this.end = end;
	}

	Vec!(dim,T) start, end;

	bool contains(in T[dim] point) const {
		foreach(i ; 0 .. dim){
			if(point[i] < start.pos[i] || point[i] >= end.pos[i])
				return false;
		}
		return true;
	}
	bool contains(in Vec!dim point) const {
		return contains(point.pos);
	}
}