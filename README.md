# nwn-lib-d
Multi-platform D library & tooling for handling Neverwinter Nights 1 & 2 resource files

[![Build Status](https://travis-ci.org/CromFr/nwn-lib-d.svg?branch=master)](https://travis-ci.org/CromFr/nwn-lib-d)
[![codecov](https://codecov.io/gh/CromFr/nwn-lib-d/branch/master/graph/badge.svg)](https://codecov.io/gh/CromFr/nwn-lib-d)

[![GitHub license](https://img.shields.io/badge/license-GPL%203.0-blue.svg)](https://raw.githubusercontent.com/CromFr/nwn-lib-d/master/LICENSE)

---

# Features

### Command-line tools

[Download nwn-lib-d tools](https://cromfr.github.io/nwn-lib-d/)

- `nwn-gff`
  + Read / write GFF files (ifo, are, bic, uti, ...)
  
    | Format | Parsing | Serialization | Comment |
    |:------:|:-------:|:-------------:|---------|
    |`gff`| :white_check_mark:| :white_check_mark:|NWN binary. Generated binary file match exactly official NWN2 files (needs to be tested with NWN1)|
    |`json`| :white_check_mark:| :white_check_mark:|Json, compatible with [Niv nwn-lib](https://github.com/niv/nwn-lib)|
    |`json_minified`|:white_check_mark:|:white_check_mark:|Same as `json` but minified|
    |`pretty`|:x:| :white_check_mark:|Human-readable|

  + Pros
    * Fast
    * GFF nodes keeps original ordering
    * Basic GFF modifications
  + Cons
    * Limited serialization targets

- `nwn-erf`
  + Create / Extract / View ERF files (erf, hak, mod, ...)
  + Pros
    * Allows to set the ERF buildDate field, to create reproducible erf files.
  + Cons
    * No support for NWN1 ERF
    * Not very memory efficient

### Library

__[API reference](https://cromfr.github.io/nwn-lib-d/docs)__

- GFF
    + Read / Write / Modify
- TLK
    + Read only
- 2DA
    + Read only
    + May refuse to parse official 2da when incorrect


# Build

### Requirements
- dmd (D language compiler)
- dub (D build system)

### Build
```sh
# Build library
dub build

# Build tools
dub build :nwn-gff

# Eventually you can append --build=release
dub build :nwn-gff --build=release
```

# Command-line usage

```sh
./nwn-gff --help

```

### Examples
```sh
# Print gff file in console
./nwn-gff -i mycharacter.bic

# Write mycharacter.bic to mycharacter.bic.txt in pretty format
./nwn-gff -i mycharacter.bic -o mycharacter.bic.txt

# Read gff from stdin, write to stdout in pretty format
./nwn-gff -j gff -k pretty
```
