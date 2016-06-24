/// Ordered Associative Array
module nwnlibd.orderedaa;

import std.typecons;
debug import std.stdio: writeln;


/// Ordered Associative Array
struct OrderedAA(KEY, VALUE){
	private alias THIS = OrderedAA!(KEY, VALUE);
	private alias DataContainer = Tuple!(KEY, "key", VALUE, "value");

	///
	@property THIS dup() const{
		THIS ret;
		ret.data.length = data.length;
		foreach(i, ref d ; ret.data)
			d = data[i];

		foreach(ref k, ref v ; map)
			ret.map[k] = v;

		return ret;
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

	///
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
			if(auto res = del(kv.key, kv.value))
				return res;
		}
		return 0;
	}

	///
	auto ref byKeyValue() const{
	    return data;
	}


	/// This function should not be used by sane people.
	///
	/// Workaround for storing multiple values for a same key like in half-broken nwn2 gff files.
	/// Only the newest value will be accessible using its key.
	/// The older value will only be accessible using byKeyValue or iterating with foreach.
	void dirtyAppendKeyValue(KEY key, VALUE value){
		map[key] = data.length;
		data ~= DataContainer(key, value);
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