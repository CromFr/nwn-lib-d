module nwntrx;

import std.stdio;
import std.stdint;
import std.conv: to;
import std.file: writeFile=write;
import std.traits;
import std.typecons: Tuple, Nullable;
version(unittest) import std.exception: assertThrown, assertNotThrown;

import nwn.trn;


version(unittest){}
else{
	int main(string[] args){return _main(args);}
}
int _main(string[] args)
{
	auto trn = new Trn(args[1]);

	foreach(ref packet ; trn.packets){
		if(packet.type == TrnPacketType.NWN2_ASWM){
			with(packet.as!(TrnPacketType.NWN2_ASWM)){
				foreach(ref triangle ; triangles){
					triangle.flags |= 0b0000_0000_0000_0001;
					if(triangle.microtileId==triangle.microtileId.max)
						triangle.microtileId = 0;
				}


				//build list of triangles with sorted vertex indices as key
				alias TriList = uint32_t[];
				struct Seg{uint32_t[2] vertices; alias vertices this;}
				TriList[Seg] junctions_rebuilt;
				foreach(i, ref triangle ; triangles){
					import std.algorithm: sort;
					auto v = triangle.vertices[].dup.sort();

					void addTri(in Seg s, uint32_t t){
						if(auto j = s in junctions_rebuilt) *j ~= i;
						else junctions_rebuilt[s] = [i];
					}

					addTri(Seg([v[0],v[1]]), i);
					addTri(Seg([v[1],v[2]]), i);
					addTri(Seg([v[0],v[2]]), i);
				}

				foreach(i, ref junction ; junctions){
					if(junction.triangles[0]==uint32_t.max || junction.triangles[1]==uint32_t.max){
						import std.algorithm: sort;
						import std.array: array;
						auto v = junction.vertices[].dup.sort().array();
						//writeln("inspecting junction id ",v);
						if(auto tlist = Seg([v[0],v[1]]) in junctions_rebuilt){
							//writeln("tlist.length=",tlist.length);
							if(tlist.length == 2){
								writeln("Restored junction id ",i);
								stdout.flush();
								junction.triangles[] = (*tlist)[];
							}
							else if(tlist.length>2){
								stderr.writeln("Warning: there are ",tlist.length," triangles on the segment ",vertices[v[0]]," -> ",vertices[v[1]]);
							}
							//else
							//	assert(tlist.length==1);
						}
					}
				}
			}
		}
	}

	args[1].writeFile(trn.serialize);

	return 0;
}