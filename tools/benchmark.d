import std.stdio;
import std.datetime.stopwatch;


void main(){

	{
		import nwn.gff;
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
		stderr.writeln("nwn.gff.Gff Parsing: ", min.total!"usecs" / 1000.0, "ms");

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
		stderr.writeln("nwn.gff.Gff Serialization: ", min.total!"usecs" / 1000.0, "ms");
	}
	{
		import nwn.fastgff;
		StopWatch sw;
		Duration min = Duration.max;
		foreach(i ; 0 .. 100){
			sw.reset();
			sw.start();
			new FastGff(cast(immutable ubyte[])import("krogar.bic"));
			sw.stop();
			if(sw.peek() < min)
				min = sw.peek();
		}
		stderr.writeln("nwn.fastgff.FastGff Parsing: ", min.total!"usecs" / 1000.0, "ms");
	}

}