/// DirectDraw Surfaces (DDS files)
module nwn.dds;

import std.stdint;
import std.exception;
import std.algorithm;
import std.conv;
debug import std.stdio: writeln;

import nwnlibd.parseutils;

///
struct Dds {

	///
	this(in ubyte[] data){
		auto cr = ChunkReader(data);

		enforce(cr.read!(char[4]) == "DDS ", "Data is not a DDS image");
		header = cr.read!Header;


		if(header.ddpf.flags & header.ddpf.Flags.DDPF_FOURCC){
			assert(header.ddpf.rgb_bit_count == 0, "Bad header.ddpf.rgb_bit_count value");
			switch(header.ddpf.four_cc) with(header.ddpf.FourCC){
				case DXT1:
					blockSize = 8;
					break;
				case DXT3:
					blockSize = 16;
					break;
				case DXT5:
					blockSize = 16;
					break;
				case NONE, NONE2:
					break;
				default: assert(0, "FourCC '"~(cast(ubyte[])header.ddpf.four_cc).to!string~" not supported");
			}
			bpp = 32;
		}
		else{
			assert(header.ddpf.rgb_bit_count % 8 == 0, "header.ddpf.rgb_bit_count must a multiple of 8");
			blockSize = 1;
			bpp = header.ddpf.rgb_bit_count;
		}


		auto w = header.width;
		auto h = header.height;

		mipmaps.length = header.mip_map_count == 0 ? 1 : header.mip_map_count;
		foreach(ref image ; mipmaps){

			const len = header.ddpf.rgb_bit_count > 0 ?
				(w * h * header.ddpf.rgb_bit_count / 8)
				: (max(4, w) / 4 * max(4, h) / 4 * blockSize);

			image = cr.readArray(len).dup;

			w /= 2;
			h /= 2;
		}

		assert(cr.bytesLeft == 0, "Remaining "~cr.bytesLeft.to!string~" bytes at the end of DDS data");
	}
	///
	Header header;

	private uint bpp, blockSize;
	///
	ubyte[][] mipmaps;

	/// Get a specifix pixel casted into a struct T. Size of T must match bytes per pixel.
	ref T getPixel(T = ubyte[4])(in size_t x, in size_t y, uint mipmap = 0){
		assert((header.ddpf.flags & header.ddpf.Flags.DDPF_FOURCC) == 0, "Not implemented for compressed DDS");

		assert(T.sizeof == bpp / 8, "Pixel destination structure does not match bit per pixel");
		assert(mipmap < mipmaps.length, "Mip map out of bounds");

		//immutable w = header.mip_map_count / (2 ^^ mipmap);
		//immutable h = header.mip_map_count / (2 ^^ mipmap);
		immutable rowLength = ((header.width * (bpp / 8) + blockSize - 1) / blockSize) * blockSize;

		return *cast(T*)&mipmaps[mipmap][rowLength * y + x * bpp / 8];
	}

	/// Converts the DDS into a BMP file
	ubyte[] toBitmap(){
		assert((header.ddpf.flags & header.ddpf.Flags.DDPF_FOURCC) == 0, "Not implemented for compressed DDS");

		import std.outbuffer;
		auto buf = new OutBuffer();

		//header
		buf.write(cast(char[2])"BM");
		buf.write(cast(uint32_t)0);//will be filled later
		buf.write(cast(uint16_t)0);
		buf.write(cast(uint16_t)0);
		buf.write(cast(uint32_t)(54));
		assert(buf.offset == 14);

		//DIB header
		buf.write(cast(uint32_t)40);
		buf.write(cast(int32_t)header.width);
		buf.write(cast(int32_t)header.height);//height
		buf.write(cast(uint16_t)1);
		buf.write(cast(uint16_t)bpp);//bits per pixel
		buf.write(cast(uint32_t)0);
		buf.write(cast(uint32_t)0);//size of the pixel array, 0 = auto
		buf.write(cast(uint32_t)500);//dpi
		buf.write(cast(uint32_t)500);//dpi
		buf.write(cast(uint32_t)(0));//colors in color palette
		buf.write(cast(uint32_t)0);
		assert(buf.offset == 54);



		ubyte[] padding;
		padding.length = ((header.width * bpp/8 + 3) / 4) * 4 - header.width * bpp/8;
		padding[] = 0;

		foreach_reverse(y ; 0 .. header.height){
			foreach(x ; 0 .. header.width){
				buf.write(getPixel(x, y));
			}
			buf.write(padding);
		}

		// re-write file size
		const oldOffset = buf.offset;
		buf.offset = 2;
		buf.write(cast(uint32_t)oldOffset);
		buf.offset = oldOffset;



		return buf.toBytes();
	}

	///
	static align(1) struct Header{
		static assert(this.sizeof == 124);
		align(1):

		/// Size of the header struct. Always 124
		uint32_t size;
		///
		enum Flags{
			DDSD_CAPS        = 0x1,/// Required in every .dds file.
			DDSD_HEIGHT      = 0x2,/// Required in every .dds file.
			DDSD_WIDTH       = 0x4,/// Required in every .dds file.
			DDSD_PITCH       = 0x8,/// Required when pitch is provided for an uncompressed texture.
			DDSD_PIXELFORMAT = 0x1000,/// Required in every .dds file.
			DDSD_MIPMAPCOUNT = 0x20000,/// Required in a mipmapped texture.
			DDSD_LINEARSIZE  = 0x80000,/// Required when pitch is provided for a compressed texture.
			DDSD_DEPTH       = 0x800000,/// Required in a depth texture.
		}
		uint32_t flags;/// See `Flags`
		uint32_t height;/// Height in pixels
		uint32_t width;/// Width in pixels
		uint32_t linear_size;/// The pitch or number of bytes per scan line in an uncompressed texture; the total number of bytes in the top level texture for a compressed texture.
		uint32_t depth;/// Depth of a volume texture (in pixels), otherwise unused.
		uint32_t mip_map_count;/// Number of mipmap levels, otherwise unused.
		uint32_t[11] reserved1;/// Unused
		///
		static struct DDPF {
			static assert(this.sizeof == 32);
			align(1):
			uint32_t size;/// Structure size; set to 32 (bytes).
			///
			enum Flags{
				DDPF_ALPHAPIXELS = 0x1,/// Texture contains alpha data; dwRGBAlphaBitMask contains valid data.
				DDPF_ALPHA       = 0x2,/// Used in some older DDS files for alpha channel only uncompressed data (dwRGBBitCount contains the alpha channel bitcount; dwABitMask contains valid data)
				DDPF_FOURCC      = 0x4,/// Texture contains compressed RGB data; dwFourCC contains valid data.
				DDPF_RGB         = 0x40,/// Texture contains uncompressed RGB data; dwRGBBitCount and the RGB masks (dwRBitMask, dwGBitMask, dwBBitMask) contain valid data.
				DDPF_YUV         = 0x200,/// Used in some older DDS files for YUV uncompressed data (dwRGBBitCount contains the YUV bit count; dwRBitMask contains the Y mask, dwGBitMask contains the U mask, dwBBitMask contains the V mask)
				DDPF_LUMINANCE   = 0x20000,/// Used in some older DDS files for single channel color uncompressed data (dwRGBBitCount contains the luminance channel bit count; dwRBitMask contains the channel mask). Can be combined with DDPF_ALPHAPIXELS for a two channel DDS file.
			}
			uint32_t flags;/// See Flags
			///
			enum FourCC: char[4]{
				DXT1 = "DXT1",
				DXT2 = "DXT2",
				DXT3 = "DXT3",
				DXT4 = "DXT4",
				DXT5 = "DXT5",
				DX10 = "DX10",
				NONE = "\0\0\0\0",
				NONE2 = "t\0\0\0",
			}
			FourCC four_cc;/// Four-character codes for specifying compressed or custom formats. Possible values include: DXT1, DXT2, DXT3, DXT4, or DXT5.
			uint32_t rgb_bit_count;/// Number of bits in an RGB (possibly including alpha) format. Valid when dwFlags includes DDPF_RGB, DDPF_LUMINANCE, or DDPF_YUV.
			uint32_t r_bit_mask;/// Red (or lumiannce or Y) mask for reading color data. For instance, given the A8R8G8B8 format, the red mask would be 0x00ff0000.
			uint32_t g_bit_mask;/// Green (or U) mask for reading color data. For instance, given the A8R8G8B8 format, the green mask would be 0x0000ff00.
			uint32_t b_bit_mask;/// Blue (or V) mask for reading color data. For instance, given the A8R8G8B8 format, the blue mask would be 0x000000ff.
			uint32_t a_bit_mask;/// Alpha mask for reading alpha data. dwFlags must include DDPF_ALPHAPIXELS or DDPF_ALPHA. For instance, given the A8R8G8B8 format, the alpha mask would be 0xff000000.
		}
		DDPF ddpf;/// See `DDPF`
		/// caps vaulues
		enum CapsFlags{
			DDSCAPS_COMPLEX = 0x8,/// Optional; must be used on any file that contains more than one surface (a mipmap, a cubic environment map, or mipmapped volume texture).
			DDSCAPS_MIPMAP  = 0x400000,/// Optional; should be used for a mipmap.
			DDSCAPS_TEXTURE = 0x1000,/// Required
		}
		uint32_t caps;/// See CapsFlags
		/// caps2 values
		enum Caps2Flags{
			DDSCAPS2_CUBEMAP           = 0x200,/// Required for a cube map.
			DDSCAPS2_CUBEMAP_POSITIVEX = 0x400,/// Required when these surfaces are stored in a cube map.
			DDSCAPS2_CUBEMAP_NEGATIVEX = 0x800,/// Required when these surfaces are stored in a cube map.
			DDSCAPS2_CUBEMAP_POSITIVEY = 0x1000,/// Required when these surfaces are stored in a cube map.
			DDSCAPS2_CUBEMAP_NEGATIVEY = 0x2000,/// Required when these surfaces are stored in a cube map.
			DDSCAPS2_CUBEMAP_POSITIVEZ = 0x4000,/// Required when these surfaces are stored in a cube map.
			DDSCAPS2_CUBEMAP_NEGATIVEZ = 0x8000,/// Required when these surfaces are stored in a cube map.
			DDSCAPS2_VOLUME            = 0x200000,/// Required for a volume texture.
		}
		uint32_t caps2;/// See Caps2Flags
		uint32_t caps3;/// Unused
		uint32_t caps4;/// Unused
		uint32_t reserved2;/// Unused
	}
}



version(None) unittest{
	enum names = [
		"dds_test_rgba.dds",
		"dds_test_rgba_dxt5.dds",
		"PLC_MC_Auril.dds",
		"PLC_MC_Auril_n.dds"
	];
	static foreach(i, name ; names){
		{
			auto dds = new Dds(cast(ubyte[])import(name));
			static if(i == 0){
				// BGRA
				foreach(j ; 0 .. 3){
					assert(dds.getPixel(0, j)[].equal([0,0,255,255]));
					assert(dds.getPixel(1, j)[].equal([0,255,0,255]));
					assert(dds.getPixel(2, j)[].equal([255,0,0,255]));
					assert(dds.getPixel(3, j)[].equal([255,255,255,255]));
					assert(dds.getPixel(4, j)[].equal([255,255,255,0]));
					assert(dds.getPixel(5, j)[].equal([0,0,0,255]));
				}
				dds.toBitmap();
			}

		}
	}
}