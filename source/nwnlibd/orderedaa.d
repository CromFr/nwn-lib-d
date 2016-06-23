/// Ordered Associative Array
module nwnlibd.orderedaa;

import std.typecons;
debug import std.stdio: writeln;


/// Ordered Associative Array
struct OrderedAA(KEY, VALUE){
	alias THIS = OrderedAA!(KEY, VALUE);
	alias DataContainer = Tuple!(string, "key", string, "value");

	///
	this(in THIS copy){
		data = copy.data.dup;
		map = cast(typeof(map))(copy.map.dup);
	}

	///
	@property THIS dup() const{
		return THIS(this);
	}

	///
	bool opEquals(const THIS rhs) const{
		if(length != rhs.length)
			return false;

		foreach(idx, ref kv ; data){
			if(kv.key!=rhs.data[idx].key || kv.value!=rhs.data[idx].value)
				return false;
		}
		return true;
	}

	///
	@property bool empty() const{
		return data.length==0;
	}
	///
	@property size_t length() const{
		return data.length;
	}

	///
	void rehash(){
		map.rehash;
	}

	void remove(KEY key)
	{
		immutable idx = map[key];
		if(idx+1<length)
			data = data[0..idx]~data[idx+1..$];
		else
			data = data[0..idx];
		map.remove(key);
	}

	///
	void clear(){
		data.length = 0;
		map.clear;
	}

	///
	void opIndexAssign(VALUE value, KEY key){
		if(auto idx = key in map){
			data[*idx].value = value;
		}
		else{
			map[key] = data.length;
			data ~= DataContainer(key, value);
		}
	}
	///
	ref inout(VALUE) opIndex(KEY key) inout{
		immutable idx = map[key];
		return data[idx].value;
	}

	///
	inout(VALUE)* opBinaryRight(string op)(KEY key) inout if(op == "in"){
		return &((key in map).value);
	}

	///
	int opApply(scope int delegate(KEY, VALUE) del){
		foreach(ref kv ; data){
			return del(kv.key, kv.value);
		}
		return 0;
	}

	///
	auto ref byKeyValue() const{
	    return data;
	}



private:
	DataContainer[] data;
	size_t[KEY] map;



}

unittest{
	OrderedAA!(string, string) orderedAA;
	orderedAA["Hello"] = "World";
	orderedAA["Foo"] = "Bar";
	orderedAA["Yolo"] = "Yay";

	size_t i = 0;
	foreach(k, v ; orderedAA){
		switch(i++){
			case 0: assert(k=="Hello"); assert(v=="World"); break;
			case 1: assert(k=="Foo");   assert(v=="Bar");   break;
			case 2: assert(k=="Yolo");  assert(v=="Yay");   break;
			default: assert(0);
		}
	}

	auto orderedAA2 = orderedAA.dup;
	assert(orderedAA2 == orderedAA);

	orderedAA2["Foo"] = "42";
	assert(orderedAA["Foo"] == "Bar");
	assert(orderedAA2 != orderedAA);

	orderedAA2.remove("Foo");
	orderedAA2["Heya"] = "It's me Imoen";
	foreach(idx, kv ; orderedAA2.byKeyValue){
		switch(idx){
			case 0: assert(kv.key=="Hello"); assert(kv.value=="World"); break;
			case 1: assert(kv.key=="Yolo");  assert(kv.value=="Yay");   break;
			case 2: assert(kv.key=="Heya");  assert(kv.value=="It's me Imoen");break;
			default: assert(0);
		}
	}
	orderedAA2.remove("Heya");
	foreach(idx, kv ; orderedAA2.byKeyValue){
		switch(idx){
			case 0: assert(kv.key=="Hello"); assert(kv.value=="World"); break;
			case 1: assert(kv.key=="Yolo");  assert(kv.value=="Yay");   break;
			default: assert(0);
		}
	}



}