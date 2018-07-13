///
module nwnlibd.wavefrontobj;

import std.typecons;
import std.string;
import std.algorithm;
import std.format;
import std.conv;
import std.array;
import std.exception;

import gfm.math.vector;

///
class WavefrontObj {
	///
	static struct WFVertex{
		///
		vec4f position;
		///
		Nullable!vec3f color;
	}
	///
	WFVertex[] vertices;
	///
	vec3f[] normals;
	///
	vec2f[] textCoords;

	///
	static struct WFFace {
		///
		size_t[] vertices;
		///
		Nullable!(size_t[]) textCoords;
		///
		Nullable!(size_t[]) normals;
	}
	///
	static struct WFLine {
		///
		size_t[] points;
	}
	///
	static struct WFGroup {
		///
		WFFace[] faces;
		///
		WFLine[] lines;
	}
	///
	static struct WFObject {
		///
		WFGroup[string] groups;
		///
		alias groups this;
	}
	///
	WFObject[string] objects;

	///
	this(){}

	///
	this(in string data){
		import std.uni : isWhite;

		string object, group;
		foreach(ref line ; data.lineSplitter.map!strip.filter!(a => a[0] != '#')){
			auto ws = line.countUntil!isWhite;
			string type = line[0 .. ws];
			line = line[ws .. $].strip;

			switch(type){
				case "o":
					object = line;
					group = null;
					objects[object] = WFObject();
					break;
				case "g":
					group = line;
					objects[object][group] = WFGroup();
					break;
				case "v":
					auto values = line
						.split!isWhite
						.filter!(a => a.length > 0)
						.array;

					WFVertex vtx;
					if(values.length >= 3)
						vtx.position.v[0 .. 3] = values[0 .. 3].map!(a => a.to!float).array;

					if(values.length >= 4)
						vtx.position.v[3] = values[3].to!float;
					else
						vtx.position[3] = 1.0;

					if(values.length >= 7)
						vtx.color = vec3f(values[4 .. 7].map!(a => a.to!float).array);

					vertices ~= vtx;
					break;
				case "vt":
					textCoords ~= vec2f(line
						.split!isWhite
						.filter!(a => a.length > 0)
						.map!(a => a.to!float)
						.array[0 .. 2]);
					break;
				case "vn":
					normals ~= vec3f(line
						.split!isWhite
						.filter!(a => a.length > 0)
						.map!(a => a.to!float)
						.array[0 .. 3]);
					break;
				case "f":
					if(group !in objects[object])
						objects[object][group] = WFGroup();

					auto indices = line
						.split!isWhite
						.filter!(a => a.length > 0)
						.map!(a => a.split("/"))
						.array;

					WFFace face;
					face.vertices = indices.map!(a => a[0].to!size_t).array;
					if(indices[0].length >= 2 && indices[0][1].length > 0)
						face.textCoords = indices.map!(a => a[1].to!size_t).array;
					if(indices[0].length >= 3 && indices[0][2].length > 0)
						face.normals = indices.map!(a => a[2].to!size_t).array;

					objects[object][group].faces ~= face;
					break;

				case "l":
					if(group !in objects[object])
						objects[object][group] = WFGroup();

					objects[object][group].lines ~= WFLine(
						line
							.split!isWhite
							.filter!(a => a.length > 0)
							.map!(a => a.to!size_t)
							.array
					);
					break;

				default: break;
			}
		}
	}
	///
	string serialize() const {
		string objData;

		foreach(ref v ; vertices){
			if(v.color.isNull)
				objData ~= format("v %(%f %)\n", v.position);
			else
				objData ~= format("v %(%f %) 1.0 %(%f %)\n", v.position, v.color);
		}

		foreach(ref vt ; textCoords)
			objData ~= format("vt %(%f %)\n", vt);

		foreach(ref vn ; normals)
			objData ~= format("vn %(%f %)\n", vn);

		foreach(ref objName ; objects.keys().sort()){
			foreach(ref groupName ; objects[objName].groups.keys().sort()){

				foreach(ref t ; objects[objName].groups[groupName].faces){
					import std.range : repeat;
					objData ~= format!"f %(%d/%) %(%d/%) %(%d/%)\n"(
						[t.vertices[0], t.textCoords[0], t.normals[0]],
						[t.vertices[1], t.textCoords[1], t.normals[1]],
						[t.vertices[2], t.textCoords[2], t.normals[2]],
					);
				}
			}
		}

		return objData;
	}

	void validate() const {
		foreach(vi, ref v ; vertices){
			if(!v.color.isNull){
				foreach(ci, c ; v.color.v)
					enforce(0 <= c && c <= 1.0,
						format!"vertices[%d].color[%d]: value %f is invalid"(vi, ci, c));
			}
		}

		foreach(oname, ref o ; objects){
			foreach(gname, ref g ; o.groups){
				foreach(fi, ref f ; g.faces){
					foreach(vi, ref v ; f.vertices)
						enforce(0 < v && v <= vertices.length,
							format!"objects[%s][%s].faces[%d].vertices[%d] %d is out of bounds"(oname, gname, fi, vi, v));
					if(!f.textCoords.isNull)
						foreach(vi, ref v ; f.textCoords)
							enforce(0 < v && v <= textCoords.length,
								format!"objects[%s][%s].faces[%d].textCoords[%d] %d is out of bounds"(oname, gname, fi, vi, v));
					if(!f.normals.isNull)
						foreach(vi, ref v ; f.normals)
							enforce(0 < v && v <= normals.length,
								format!"objects[%s][%s].faces[%d].normals[%d] %d is out of bounds"(oname, gname, fi, vi, v));
				}
			}
		}
	}
}