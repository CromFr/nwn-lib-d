module tools.common.colors;

enum colfg : string{
	def =          "\x1b[39m",
	black =        "\x1b[30m",
	lightblack =   "\x1b[90m",
	red =          "\x1b[31m",
	lightred =     "\x1b[91m",
	green =        "\x1b[32m",
	lightgreen =   "\x1b[92m",
	yellow =       "\x1b[33m",
	lightyellow =  "\x1b[93m",
	blue =         "\x1b[34m",
	lightblue =    "\x1b[94m",
	magenta =      "\x1b[35m",
	lightmagenta = "\x1b[95m",
	cyan =         "\x1b[36m",
	lightcyan =    "\x1b[96m",
	white =        "\x1b[37m",
	lightwhite =   "\x1b[97m"
}
enum colbg : string{
	def =          "\x1b[49m",
	black =        "\x1b[40m",
	lightblack =   "\x1b[100m",
	red =          "\x1b[41m",
	lightred =     "\x1b[101m",
	green =        "\x1b[42m",
	lightgreen =   "\x1b[102m",
	yellow =       "\x1b[43m",
	lightyellow =  "\x1b[103m",
	blue =         "\x1b[44m",
	lightblue =    "\x1b[104m",
	magenta =      "\x1b[45m",
	lightmagenta = "\x1b[105m",
	cyan =         "\x1b[46m",
	lightcyan =    "\x1b[106m",
	white =        "\x1b[47m",
	lightwhite =   "\x1b[107m"
}

enum colvar : string{
	none =      "\x1b[0m",
	bold =      "\x1b[1m",
	faded =     "\x1b[2m",
	italic =    "\x1b[3m",
	ulined =    "\x1b[4m",
	striked =   "\x1b[9m",
	inverted =  "\x1b[7m",
	nobold =    "\x1b[21m",
	nofaded =   "\x1b[22m",
	noitalic =  "\x1b[23m",
	noulined =  "\x1b[24m",
	nostriked = "\x1b[29m",
	end =       "\x1b[m"
}