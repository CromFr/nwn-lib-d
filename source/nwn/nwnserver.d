/// Query the nwn2 server
module nwn.nwnserver;

import nwnlibd.parseutils;

import std.stdio;
import std.datetime;
import std.socket;
import std.exception: enforce;
import std.typecons: tuple;
import std.conv;
import std.bitmanip: littleEndianToNative;

///
class NWNServer{
	///
	this(in string host, in ushort port = 5121){
		sock = new UdpSocket();
		sock.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, dur!"seconds"(5));
		target = new InternetAddress(host, port);
		sock.connect(target);
	}
	~this(){
		sock.close();
	}

	/// Send ping request to the server and measure latency in msecs
	double ping(){
		import std.datetime.stopwatch: StopWatch, to, TickDuration;
		StopWatch sw;
		sw.start();
		queryBNLM(0, 0);
		return (cast(TickDuration)sw.peek()).to!("msecs", double);
	}

	/// Query server name info
	auto queryBNES(){
		sock.send("BNES" ~ localPort ~ '\0');

		ubyte[] buff;
		buff.length = 128;
		buff.length = sock.receive(buff);

		enforce(buff.length >= 5 && buff[0..5] == "BNERU", "Wrong answer received");
		auto cr = ChunkReader(buff[5 .. $]);

		struct BNERU {
			uint16_t port;
			ubyte __padding;
			string serverName;
		}
		return BNERU(
			cr.read!(ubyte[2]).littleEndianToNative!(uint16_t, 2),
			cr.read!ubyte,
			cr.readArray!char(cr.read!ubyte).to!string,
		);
	}

	/// Query server game / module info
	auto queryBNDS(){
		sock.send("BNDS" ~ localPort);

		ubyte[] buff;
		buff.length = 2^^14;
		buff.length = sock.receive(buff);
		enforce(buff.length >=4 && buff[0..4] == "BNDR", "Wrong answer received");
		auto cr = ChunkReader(buff[4 .. $]);

		struct BNDR {
			uint16_t port;
			string serverDesc;
			string moduleDesc;
			string gameVersion;
			enum GameType: uint16_t {
				Action = 0,
				Story = 1,
				Story_lite = 2,
				Role_Play = 3,
				Team = 4,
				Melee = 5,
				Arena = 6,
				Social = 7,
				Alternative = 8,
				PW_Action = 9,
				PW_Story = 10,
				Solo = 11,
				Tech_Support  = 12,
			}
			GameType gameType;
			string webUrl;
			string filesUrl;
		}
		return BNDR(
			cr.read!(ubyte[2]).littleEndianToNative!(uint16_t, 2),
			cr.readArray!char(cr.read!(ubyte[4]).littleEndianToNative!(uint32_t, 4)).to!string,
			cr.readArray!char(cr.read!(ubyte[4]).littleEndianToNative!(uint32_t, 4)).to!string,
			cr.readArray!char(cr.read!(ubyte[4]).littleEndianToNative!(uint32_t, 4)).to!string,
			cr.read!(BNDR.GameType),
			cr.readArray!char(cr.read!(ubyte[4]).littleEndianToNative!(uint32_t, 4)).to!string,
			cr.readArray!char(cr.read!(ubyte[4]).littleEndianToNative!(uint32_t, 4)).to!string,
		);
	}

	/// Query server config
	auto queryBNXI(){
		sock.send("BNXI" ~ localPort);

		ubyte[] buff;
		buff.length = 256;
		buff.length = sock.receive(buff);

		enforce(buff.length >= 4 && buff[0..4] == "BNXR", "Wrong answer received");
		auto cr = ChunkReader(buff[4 .. $]);

		struct BNXR {
			uint16_t port;
			ubyte bnxiVersion;
			bool hasPassword;
			ubyte minLevel;
			ubyte maxLevel;
			ubyte currentPlayers;
			ubyte maxPlayers;
			enum VaultType: ubyte {
				server = 0,
				local = 1,
			}
			VaultType vaultType;
			enum PvpType: ubyte {
				none = 0,
				party = 1,
				full = 2,
			}
			PvpType pvp;
			bool playerPause;
			bool oneParty;
			bool enforceLegalChars;
			bool itemLvlRestriction;
			bool xp;
			string modName;
			string gameVersion;
		}

		return BNXR(
			cr.read!(ubyte[2]).littleEndianToNative!(uint16_t, 2),
			cr.read!ubyte,
			cr.read!bool,
			cr.read!ubyte,
			cr.read!ubyte,
			cr.read!ubyte,
			cr.read!ubyte,
			cr.read!(BNXR.VaultType),
			cr.read!(BNXR.PvpType),
			cr.read!bool,
			cr.read!bool,
			cr.read!bool,
			cr.read!bool,
			cr.read!bool,
			cr.readArray!char(cr.read!ubyte).to!string,
			cr.readArray!char(cr.read!ubyte).to!string,
		);
	}

	///
	auto queryBNLM(ubyte messageNo = 0, ubyte sessionID = 0){
		sock.send("BNLM" ~ localPort ~ messageNo ~ sessionID ~ hexString!"00 00 00");

		ubyte[] buff;
		buff.length = 128;
		buff.length = sock.receive(buff);

		enforce(buff.length >= 4 && buff[0..4] == "BNLR", "Wrong answer received");
		auto cr = ChunkReader(buff[4 .. $]);

		struct BNLR {
			uint16_t port;
			ubyte messageNo;
			ubyte sessionID;
			ubyte[3] unknown;
		}
		return cr.readPackedStruct!BNLR;
	}


private:
	Address target;
	UdpSocket sock;

	char[2] localPort(){
		short port = (cast(InternetAddress)sock.localAddress).port;
		return (cast(char*)&port)[0..2];
	}
}


unittest{
	auto gs = new NWNServer("lcda-nwn2.fr", 5121);

	gs.ping();
	assert(gs.queryBNDS().webUrl == "https://lcda-nwn2.fr");
	assert(gs.queryBNES().serverName == "FR]La Colere d'Aurile");
	assert(gs.queryBNXI().modName == "Lcda");
}