import std.stdio;
import std.datetime.stopwatch;

import nwn.gff;

void main(){

	StopWatch sw;
	Duration min = Duration.max;
	foreach(i ; 0 .. 100){
		sw.reset();
		sw.start();
		new Gff(cast(immutable ubyte[])import("krogar.bic"));
		sw.stop();
		if(sw.peek() < min)
			min = sw.peek();
	}
	stderr.writeln("GFF Parsing: ", min.total!"usecs" / 1000.0, "ms");

	auto gff = new Gff(cast(immutable ubyte[])import("krogar.bic"));
	min = Duration.max;
	sw.reset();
	foreach(i ; 0 .. 100){
		sw.reset();
		sw.start();
		gff.serialize();
		sw.stop();
		if(sw.peek() < min)
			min = sw.peek();
	}
	sw.stop();
	stderr.writeln("GFF Serialization: ", min.total!"usecs" / 1000.0, "ms");

}