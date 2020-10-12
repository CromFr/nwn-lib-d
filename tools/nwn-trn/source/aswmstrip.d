import std.stdio;
import std.conv: to;
import std.string;
import std.stdint;
import std.algorithm;
import std.array;

import nwn.trn;

void stripASWM(ref TrnNWN2WalkmeshPayload aswm, bool silent){


	auto initVertices = aswm.vertices.length;
	auto initEdges = aswm.edges.length;
	auto initTriangles = aswm.triangles.length;



	uint32_t[] vertTransTable, edgeTransTable, triTransTable;//table[oldIndex] = newIndex
	vertTransTable.length = aswm.vertices.length;
	edgeTransTable.length = aswm.edges.length;
	triTransTable.length = aswm.triangles.length;
	uint32_t newIndex;

	bool[] usedVertices, usedEdges;
	usedVertices.length = aswm.vertices.length;
	usedEdges.length = aswm.edges.length;
	usedVertices[] = false;
	usedEdges[] = false;

	// Reduce triangle list & flag used vertices & edges
	newIndex = 0;
	foreach(i, ref triangle ; aswm.triangles){
		if(triangle.island != uint16_t.max){

			// Flag used / unused vertices & edges
			foreach(vert ; triangle.vertices){
				usedVertices[vert] = true;
			}
			foreach(edge ; triangle.linked_edges){
				if(edge != uint32_t.max)
					usedEdges[edge] = true;
			}

			// Reduce triangle list in place
			aswm.triangles[newIndex] = triangle;
			triTransTable[i] = newIndex++;
		}
		else
			triTransTable[i] = uint32_t.max;
	}
	aswm.triangles.length = newIndex;


	// Reduce vertices list
	newIndex = 0;
	foreach(i, used ; usedVertices){
		if(used){
			aswm.vertices[newIndex] = aswm.vertices[i];
			vertTransTable[i] = newIndex++;
		}
		else
			vertTransTable[i] = uint32_t.max;
	}
	aswm.vertices.length = newIndex;

	// Reduce edges list
	newIndex = 0;
	foreach(i, used ; usedEdges){
		if(used){
			aswm.edges[newIndex] = aswm.edges[i];
			edgeTransTable[i] = newIndex++;
		}
		else
			edgeTransTable[i] = uint32_t.max;
	}
	aswm.edges.length = newIndex;

	// Adjust indices in mesh data
	aswm.translateIndices(triTransTable, edgeTransTable, vertTransTable);


	// Adjust indices inside tiles pathtable
	uint32_t currentOffset = 0;
	foreach(i, ref tile ; aswm.tiles){

		struct Tri {
			uint32_t id;
			ubyte node;
		}
		Tri[] newLtn;
		foreach(j, ltn ; tile.path_table.local_to_node){
			// Ignore non unused/unwalkable triangles
			if(ltn == 0xff)
				continue;

			const newTriIndex = triTransTable[j + tile.header.triangles_offset];

			// Ignore removed triangles
			if(newTriIndex == uint32_t.max)
				continue;

			newLtn ~= Tri(newTriIndex, ltn);
		}

		foreach(ref ntl ; tile.path_table.node_to_local){
			assert(triTransTable[ntl + tile.header.triangles_offset] != uint32_t.max, "todo");
			ntl = triTransTable[ntl + tile.header.triangles_offset];
		}

		// Find new offset
		tile.header.triangles_offset = newLtn.length == 0? currentOffset : min(
			newLtn.minElement!"a.id".id,
			tile.path_table.node_to_local.minElement);

		// Adjust node_to_local indices with new offset
		tile.path_table.node_to_local[] -= tile.header.triangles_offset;

		// Adjust newLtn indices with new offset
		foreach(ref ltn ; newLtn)
			ltn.id -= tile.header.triangles_offset;

		// Resize & erase ltn data
		tile.path_table.local_to_node.length = newLtn.length == 0? 0 : newLtn.maxElement!"a.id".id + 1;
		tile.path_table.local_to_node[] = 0xff;

		// Set ltn data
		foreach(ltn ; newLtn){
			tile.path_table.local_to_node[ltn.id] = ltn.node;
		}


		tile.header.triangles_count = tile.path_table.local_to_node.length.to!uint32_t;

		currentOffset = tile.header.triangles_offset + tile.header.triangles_count;

		// Re-count linked vertices / edges
		tile.header.vertices_count = tile.path_table.node_to_local
			.map!(a => a != a.max? aswm.triangles[a].vertices[] : [])
			.join.sort.uniq.array.length.to!uint32_t;
		tile.header.edges_count = tile.path_table.node_to_local
			.map!(a => a != a.max?  aswm.triangles[a].linked_edges[] : [])
			.join.sort.uniq.array.length.to!uint32_t;
	}
	// Adjust indices in islands
	foreach(ref island ; aswm.islands){
		foreach(ref t ; island.exit_triangles){
			t = triTransTable[t];
			assert(t != uint32_t.max && t < aswm.triangles.length, "Invalid triangle index");
		}
	}

	if(!silent){
		writeln("Vertices: ", initVertices, " => ", aswm.vertices.length, " (stripped ", 100 - aswm.vertices.length * 100.0 / initVertices, "%)");
		writeln("Edges: ", initEdges, " => ", aswm.edges.length, " (stripped ", 100 - aswm.edges.length * 100.0 / initEdges, "%)");
		writeln("Triangles: ", initTriangles, " => ", aswm.triangles.length, " (stripped ", 100 - aswm.triangles.length * 100.0 / initTriangles, "%)");
	}
}