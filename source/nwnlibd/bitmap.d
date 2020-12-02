/// DirectDraw Surfaces (DDS files)
module nwnlibd.bitmap;

import std.stdint;
import std.exception;
import std.algorithm;
import std.conv;
import std.traits;
import std.string: format;
import std.range: chunks;
debug import std.stdio;

import nwnlibd.parseutils;

alias BitmapGrayscale = Bitmap!(ubyte[1]);
alias BitmapGrayscaleA = Bitmap!(ubyte[2]);
alias BitmapRGB = Bitmap!(ubyte[3]);
alias BitmapRGBA = Bitmap!(ubyte[4]);

/// 2D bitmap. Each pixel is coded with a fixed number of bytes.
///
/// Pixel sizes:
///   ubyte[1] => grayscale
///   ubyte[2] => grayscale + alpha
///   ubyte[3] => RGB
///   ubyte[4] => RGBA
struct Bitmap(Pixel = ubyte[4]) {
	static assert(isStaticArray!Pixel || isIntegral!Pixel, "Bitmap can only contain a static array or a single integers");

	this(size_t width, size_t height){
		this.width = width;
		this.height = height;
		pixels.length = width * height;
	}

	/// Access a given pixel with Bitmap[x, y]
	ref inout(Pixel) opIndex(in size_t x, in size_t y) inout {
		return pixels[y * width + x];
	}

	///// Rotate the image by increments of 90° counter clockwise
	//void rotate(int rot) {
	//	rot = ((abs(rot / 4) + 1) * 4 + rot) % 4;

	//	auto newPixels = new Pixel[pixels.length];

	//	final switch(rot){
	//		case 0:
	//			return;
	//		case 1:
	//			foreach(y ; 0 .. height)
	//				foreach(x ; 0 .. width)
	//					newPixels[y * width + x] = this[]


	//	}

	//}

	/// Serialize to a BMP file. Alpha data is lost.
	ubyte[] toBMP(){
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
		buf.write(cast(int32_t)width);
		buf.write(cast(int32_t)height);//height
		buf.write(cast(uint16_t)1);
		buf.write(cast(uint16_t)24);//bits per pixel
		buf.write(cast(uint32_t)0);
		buf.write(cast(uint32_t)0);//size of the pixel array, 0 = auto
		buf.write(cast(uint32_t)500);//dpi
		buf.write(cast(uint32_t)500);//dpi
		buf.write(cast(uint32_t)(0));//colors in color palette
		buf.write(cast(uint32_t)0);
		assert(buf.offset == 54);

		ubyte[] padding;
		padding.length = ((width * 3 + 3) / 4) * 4 - width * 3;
		padding[] = 0;

		foreach_reverse(y ; 0 .. height){
			foreach(x ; 0 .. width){
				static if(isStaticArray!Pixel){
					static if     (Pixel.sizeof == 1 || Pixel.sizeof == 2)
						buf.write([this[x, y][0], this[x, y][0], this[x, y][0]]);
					else static if(Pixel.sizeof >= 3)
						buf.write(this[x, y][0 .. 3]);
				}
				else
					buf.write(this[x, y]);
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

	/// Serialize to a PNG file
	ubyte[] toPNG(){
		import std.zlib: compress, crc32;
		import std.outbuffer: OutBuffer;
		import std.bitmanip;
		//import std.digest.crc: crc32Of;

		auto buf = new OutBuffer();

		void writeChunk(T...)(char[4] type, T data){
			template ChunkLen(T...){
				uint32_t ChunkLen(T data){
					uint32_t len = 0;
					static foreach(d ; data){
						static if(isDynamicArray!(typeof(d)))
							len += ForeachType!(typeof(d)).sizeof * d.length;
						else
							len += d.sizeof;
					}
					return len;
				}
			}
			buf.write(ChunkLen(data).nativeToBigEndian);
			const crcStart = buf.offset;
			buf.write(type);
			static foreach(d ; data)
				buf.write(d);
			buf.write(crc32(0, buf.toBytes()[crcStart .. buf.offset]).nativeToBigEndian);
		}

		buf.write("\x89PNG\r\n\x1A\n");

		static if(isStaticArray!Pixel)
			ubyte depth = ForeachType!Pixel.sizeof * 8;
		else
			ubyte depth = 8;
		ubyte colorType;
		switch(Pixel.sizeof){
			case 1: colorType = 0b0000; break; // Grayscale
			case 2: colorType = 0b0100; break; // Grayscale + A
			case 3: colorType = 0b0010; break; // RGB
			case 4: colorType = 0b0110; break; // RGBA
			default: assert(0, format!"Cannot convert %d-bits colors to PNG"(Pixel.sizeof * 8));
		}


		writeChunk("IHDR",
			width.to!uint32_t.nativeToBigEndian,
			height.to!uint32_t.nativeToBigEndian,
			depth,// depth
			cast(ubyte)colorType,// color type
			cast(ubyte)0,// compression
			cast(ubyte)0,// filter
			cast(ubyte)0,// interlace
		);


		auto uncompIdat = new OutBuffer();
		foreach(y ; 0 .. height){
			uncompIdat.write(cast(ubyte)0);
			uncompIdat.write(cast(ubyte[])(pixels[y * width .. (y + 1) * width]));
		}

		writeChunk("IDAT",
			uncompIdat.toBytes().compress(0)
		);


		writeChunk("IEND");

		return buf.toBytes();
	}


	size_t width, height;
	Pixel[] pixels;
}

unittest{
	import std.file;
	auto bmp = BitmapRGBA(8, 8);

	ubyte[4] GetColor(size_t i){
		switch(i % 8){
			case 0: return [255, 0,   0,   255];
			case 1: return [255, 255, 0,   255];
			case 2: return [0,   255, 0,   255];
			case 3: return [0,   255, 255, 255];
			case 4: return [0,   0,   255, 255];
			case 5: return [255, 0,   255, 255];
			case 6: return [0,   0,   0,   255];
			case 7: return [255, 255, 255, 255];
			default: assert(0);
		}
	}

	foreach(i ; 0 .. 8){
		bmp[i, i] = GetColor(i);
		bmp[i, 0] = GetColor(i);
	}

	std.file.write("test.png", bmp.toPNG());
}