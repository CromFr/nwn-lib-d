/// DirectDraw Surfaces (DDS files)
module nwn.dds;

import std.stdint;
import std.exception;
import std.algorithm;
import std.conv;
import std.traits;
import std.string: format;
import std.range: chunks;
debug import std.stdio;

import nwnlibd.parseutils;
import nwnlibd.bitmap;

/// DDS file parsing
struct Dds {

	///
	this(in ubyte[] data){
		auto cr = ChunkReader(data);

		enforce(cr.read!(char[4]) == "DDS ", "Data is not a DDS image");
		header = cr.read!Header;

		enum requiredFlags = Header.Flags.DDSD_WIDTH | Header.Flags.DDSD_HEIGHT | Header.Flags.DDSD_PIXELFORMAT;
		enforce((header.flags & requiredFlags) == requiredFlags,
			"Unsupported DDS flags: " ~ header.flags.flagsToString!(Header.Flags));

		if(header.caps2 & Header.Caps2Flags.DDSCAPS2_CUBEMAP)
			enforce(false, "Unsupported DDS cubemap");
		if (header.caps2 & Header.Caps2Flags.DDSCAPS2_VOLUME && header.depth > 0)
			enforce(false, "Unsupported DDS volume map");


		if (header.ddpf.flags & (Header.DDPF.Flags.DDPF_RGB | Header.DDPF.Flags.DDPF_LUMINANCE)){
			enforce(header.ddpf.rgb_bit_count % 8 == 0, "header.ddpf.rgb_bit_count must a multiple of 8");

			blockSize = 1;
			bpp = header.ddpf.rgb_bit_count > 0 ? header.ddpf.rgb_bit_count : 24;
		}
		else if (header.ddpf.flags & Header.DDPF.Flags.DDPF_FOURCC){
			// FourCC compression: http://www.buckarooshangar.com/flightgear/tut_dds.html
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
			enforce(false, "Unsupported DDS pixel format flags");
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
		enforce((header.ddpf.flags & header.ddpf.Flags.DDPF_FOURCC) == 0, "Not implemented for compressed DDS");

		assert(T.sizeof == bpp / 8,
			format!"Pixel destination structure (%s, size=%d bits) does not match bit per pixel (%d)"(T.stringof, T.sizeof * 8, bpp)
		);
		assert(mipmap < mipmaps.length, "Mip map out of bounds");

		//immutable w = header.mip_map_count / (2 ^^ mipmap);
		//immutable h = header.mip_map_count / (2 ^^ mipmap);
		immutable rowLength = ((header.width * (bpp / 8) + blockSize - 1) / blockSize) * blockSize;

		return *cast(T*)&mipmaps[mipmap][rowLength * y + x * bpp / 8];
	}

	///
	auto getPixelGrid(T = ubyte[4])(uint mipmap = 0){
		import std.range: chunks;
		assert((header.ddpf.flags & header.ddpf.Flags.DDPF_FOURCC) == 0, "Not implemented for compressed DDS");

		assert(T.sizeof == bpp / 8,
			format!"Pixel destination structure (%s, size=%d bits) does not match bit per pixel (%d)"(T.stringof, T.sizeof * 8, bpp)
		);
		assert(mipmap < mipmaps.length, "Mip map out of bounds");

		immutable rowLength = ((header.width * (bpp / 8) + blockSize - 1) / blockSize) * blockSize;

		return (cast(T[])(mipmaps[mipmap])).chunks(rowLength);
	}

	/// Behavior:
	/// 1-byte color => grayscale
	Bitmap!Pixel toBitmap(Pixel = ubyte[4])(uint mipmap = 0){
		import std.range: chunks;
		assert((header.ddpf.flags & header.ddpf.Flags.DDPF_FOURCC) == 0, "Not implemented for compressed DDS");
		assert(Pixel.sizeof >= bpp / 8, "Pixel destination structure cannot b");
		assert(mipmap < mipmaps.length, "Mip map out of bounds");

		immutable rowLength = ((header.width * (bpp / 8) + blockSize - 1) / blockSize) * blockSize;

		auto ret = Bitmap!Pixel(header.width, header.height);

		//auto data = (cast(Pixel[])(mipmaps[mipmap])).chunks(rowLength);
		foreach(y ; 0 .. header.height){
			const rowStart = rowLength * y;
			foreach(x ; 0 .. header.width){
				uint sourceSize = bpp / 8;
				auto pixData = mipmaps[mipmap][rowStart + sourceSize * x .. rowStart + sourceSize * (x + 1)];
				switch(sourceSize){
					case 1:
						// Grayscale
						static if     (Pixel.sizeof == 1) ret[x, y] = *cast(Pixel*)[pixData[0]].ptr;
						else static if(Pixel.sizeof == 2) ret[x, y] = *cast(Pixel*)[pixData[0], 0xff].ptr;
						else static if(Pixel.sizeof == 3) ret[x, y] = *cast(Pixel*)[pixData[0], pixData[0], pixData[0]].ptr;
						else static if(Pixel.sizeof == 4) ret[x, y] = *cast(Pixel*)[pixData[0], pixData[0], pixData[0], 0xff].ptr;
						else enforce(0, format!"Unsupported %d-bytes color to %d-bytes bitmap"(bpp, Pixel.sizeof));
						break;
					case 2:
						// Grayscale + alpha
						static if     (Pixel.sizeof == 1) ret[x, y] = *cast(Pixel*)[pixData[0]].ptr;
						else static if(Pixel.sizeof == 2) ret[x, y] = *cast(Pixel*)[pixData[0], pixData[1]].ptr;
						else static if(Pixel.sizeof == 3) ret[x, y] = *cast(Pixel*)[pixData[0], pixData[0], pixData[0]].ptr;
						else static if(Pixel.sizeof == 4) ret[x, y] = *cast(Pixel*)[pixData[0], pixData[0], pixData[0], pixData[1]].ptr;
						else enforce(0, format!"Unsupported %d-bytes color to %d-bytes bitmap"(bpp, Pixel.sizeof));
						break;
					case 3:
						// BGR
						static if     (Pixel.sizeof == 1) ret[x, y] = *cast(Pixel*)[((pixData[0] + pixData[1] + pixData[2]) / 3).to!ubyte].ptr;
						else static if(Pixel.sizeof == 2) ret[x, y] = *cast(Pixel*)[((pixData[0] + pixData[1] + pixData[2]) / 3).to!ubyte, 0xff].ptr;
						else static if(Pixel.sizeof == 3) ret[x, y] = *cast(Pixel*)[pixData[2], pixData[1], pixData[0]].ptr;
						else static if(Pixel.sizeof == 4) ret[x, y] = *cast(Pixel*)[pixData[2], pixData[1], pixData[0], 0xff].ptr;
						else enforce(0, format!"Unsupported %d-bytes color to %d-bytes bitmap"(bpp, Pixel.sizeof));
						break;
					case 4:
						// BGRA
						static if     (Pixel.sizeof == 1) ret[x, y] = *cast(Pixel*)[(pixData[0] + pixData[1] + pixData[2]) / 3].ptr;
						else static if(Pixel.sizeof == 2) ret[x, y] = *cast(Pixel*)[(pixData[0] + pixData[1] + pixData[2]) / 3, pixData[3]].ptr;
						else static if(Pixel.sizeof == 3) ret[x, y] = *cast(Pixel*)[pixData[2], pixData[1], pixData[0]].ptr;
						else static if(Pixel.sizeof == 4) ret[x, y] = *cast(Pixel*)[pixData[2], pixData[1], pixData[0], pixData[3]].ptr;
						else enforce(0, format!"Unsupported %d-bytes color to %d-bytes bitmap"(bpp, Pixel.sizeof));
						break;
					default: enforce(0, format!"Unsupported DDS %d-bytes color"(bpp));
				}
			}
		}

		return ret;
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
		uint32_t[11] _reserved1;/// Unused
		/// DirectDraw Pixel Format
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
			char[4] four_cc;/// Four-character codes for specifying compressed or custom formats. Possible values include: DXT1, DXT2, DXT3, DXT4, or DXT5.
			uint32_t rgb_bit_count;/// Number of bits in an RGB (possibly including alpha) format. Valid when dwFlags includes DDPF_RGB, DDPF_LUMINANCE, or DDPF_YUV.
			uint32_t r_bit_mask;/// Red (or lumiannce or Y) mask for reading color data. For instance, given the A8R8G8B8 format, the red mask would be 0x00ff0000.
			uint32_t g_bit_mask;/// Green (or U) mask for reading color data. For instance, given the A8R8G8B8 format, the green mask would be 0x0000ff00.
			uint32_t b_bit_mask;/// Blue (or V) mask for reading color data. For instance, given the A8R8G8B8 format, the blue mask would be 0x000000ff.
			uint32_t a_bit_mask;/// Alpha mask for reading alpha data. dwFlags must include DDPF_ALPHAPIXELS or DDPF_ALPHA. For instance, given the A8R8G8B8 format, the alpha mask would be 0xff000000.

			string toString() const {
				return format!"Dds.DDPF(flags=%s four_cc=%s rgb_bit_count=%d rgba_mask=%08x;%08x;%08x;%08x)"(
					flags.flagsToString!Flags, four_cc, rgb_bit_count, r_bit_mask, g_bit_mask, b_bit_mask, a_bit_mask
				);
			}
		}
		DDPF ddpf;/// See `DDPF`
		/// caps values
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
		uint32_t[3] _reserved2;/// Unused

		string toString() const {
			return format!"Dds.Header(flags=%s size=%dx%d linear_size=%d depth=%d mip_map_count=%d caps=%s caps2=%s DDPF=%s)"(
				flags.flagsToString!Flags, width, height, linear_size, depth, mip_map_count, caps.flagsToString!CapsFlags, caps2.flagsToString!Caps2Flags, ddpf
			);
		}
	}
}



unittest{
	enum names = [
		"dds_test_rgba.dds",
		"dds_test_grayscale.dds",
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
					assert(dds.getPixel(0, j)[].equal([0,0,255,255]), name);
					assert(dds.getPixel(1, j)[].equal([0,255,0,255]), name);
					assert(dds.getPixel(2, j)[].equal([255,0,0,255]), name);
					assert(dds.getPixel(3, j)[].equal([255,255,255,255]), name);
					assert(dds.getPixel(4, j)[].equal([255,255,255,0]), name);
					assert(dds.getPixel(5, j)[].equal([0,0,0,255]), name);
				}

				auto bitmap = dds.toBitmap!(ubyte[4])();
				foreach(y ; 0 .. dds.header.height){
					foreach(x ; 0 .. dds.header.width){
						auto p = dds.getPixel(x, y);

						// BGRA => RGBA
						assert(p[0] == bitmap[x, y][2], name);
						assert(p[1] == bitmap[x, y][1], name);
						assert(p[2] == bitmap[x, y][0], name);
						assert(p[3] == bitmap[x, y][3], name);
					}
				}
			}
			else static if(i == 1){
				assert(dds.getPixel!ubyte(16, 16) == 0, name);
				assert(dds.getPixel!ubyte(30, 30) == 255, name);
				assert(dds.getPixel!ubyte(69, 80) == 0, name);
				assert(dds.getPixel!ubyte(108, 100) == 255, name);

				auto bitmap = dds.toBitmap!(ubyte[1])();
				foreach(y ; 0 .. dds.header.height){
					foreach(x ; 0 .. dds.header.width){
						assert(dds.getPixel!ubyte(x, y) == bitmap[x, y][0], name);
					}
				}
			}

		}
	}
}