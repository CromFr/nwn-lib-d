# nwn-lib-d
Multi-platform D library & tooling for handling Neverwinter Nights 1 & 2 resource files

[![Build Status](https://travis-ci.org/CromFr/nwn-lib-d.svg?branch=master)](https://travis-ci.org/CromFr/nwn-lib-d)
[![codecov](https://codecov.io/gh/CromFr/nwn-lib-d/branch/master/graph/badge.svg)](https://codecov.io/gh/CromFr/nwn-lib-d)

[![GitHub license](https://img.shields.io/badge/license-GPL%203.0-blue.svg)](https://raw.githubusercontent.com/CromFr/nwn-lib-d/master/LICENSE)

---

# Features

### Command-line tools

__[Download nwn-lib-d tools](https://cromfr.github.io/nwn-lib-d/)__

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

- `nwn-tlk`
  + Serialize TLK files to readable text.

    | Format | Parsing | Serialization | Comment |
    |:------:|:-------:|:-------------:|---------|
    |`tlk`| :white_check_mark:| :white_check_mark:|NWN TLK binary format |
    |`text`|:x:| :white_check_mark:|Human-readable|

- `nwn-erf`
  + Create, extract or view ERF files (hak, erf, mod) in a reproducible manner (same content => same checksum).
  + Pros
    * By default sets the ERF buildDate field to a 0 value, to create reproducible erf files.
  + Cons
    * No support for NWN1 ERF
    * Not very memory efficient (all files are loaded to memory before the erf file is written)

- `nwn-bdb`
  + View/search Bioware/foxpro database content (dbf + ctx + fpt) using regular expressions.

- `nwn-trn`
  + TRN/TRX experimental tool:
    * `trrn-export`: Export the terrain mesh, textures and grass
    * `trrn-import`: Import a terrain mesh, textures and grass into an existing TRN/TRX file
    * `watr-import`: Export water mesh
    * `watr-import`: Import a water mesh into an existing TRN/TRX file
    * `aswm-strip`: Reduce walkmesh data size by removing non-walkable triangle & related data. Can reduce LZMA-compressed files to 50% of their non-stripped size (depending on the amount of unused triangles of course).
    * `aswm-export-fancy`: Export custom walkmesh data into a colored wavefront obj
    * `aswm-export`: Export walkable walkmesh into a wavefront obj
    * `aswm-import`: Import a wavefront obj as the walkmesh of an existing TRX file
    * `bake`: Bake an area (placeables and walkmesh cutters not supported)

- `nwn-srv`
  + Interact with NWN2 server:
    * Measure latency (ping)
    * Query server info and status



### Library

__[API reference](https://cromfr.github.io/nwn-lib-d/docs)__

- GFF
    + Read / Write / Modify
- TLK
    + Read only
- 2DA
    + Read only
    + May refuse to parse official 2da when incorrect


# Tips & tricks

### Generate git diff from GFF & TLK files

1. Configure Git to use the tools
  - Using git command line:
  ```sh
  git config --global diff.gff.textconv "$PATH_TO_NWNLIBD_TOOLS/nwn-gff -i \$1"
  git config --global diff.tlk.textconv "$PATH_TO_NWNLIBD_TOOLS/nwn-tlk -i \$1"
  ```
  - __Or__ by editing .gitconfig:
  ```sh
  [diff "gff"]
    textconv = 'C:\\Program Files\\nwn-lib-d\\nwn-gff' -i $1
  [diff "tlk"]
    textconv = 'C:\\Program Files\\nwn-lib-d\\nwn-tlk' -i $1
  ```

2. Configure your git repository to use GFF / TLK diff by creating `.gitattributes` file:
```
#Areas
*.[aA][rR][eE] diff=gff
*.[gG][iI][cC] diff=gff
*.[gG][iI][tT] diff=gff

#Dialogs
*.[dD][lL][gG] diff=gff

#Module
*.[fF][aA][cC] diff=gff
*.[iI][fF][oO] diff=gff
*.[jJ][rR][lL] diff=gff

#Blueprints
*.[uU][lL][tT] diff=gff
*.[uU][pP][eE] diff=gff
*.[uU][tT][cC] diff=gff
*.[uU][tT][dD] diff=gff
*.[uU][tT][eE] diff=gff
*.[uU][tT][iI] diff=gff
*.[uU][tT][mM] diff=gff
*.[uU][tT][pP] diff=gff
*.[uU][tT][rR] diff=gff
*.[uU][tT][tT] diff=gff
*.[uU][tT][wW] diff=gff

#Others
*.[pP][fF][bB] diff=gff
*.[tT][lL][kK] diff=tlk
```




# Build

### Requirements
- dmd (D language compiler)
- dub (D build system)

### Build
```sh
# Build library
dub build

# Build nwn-gff tools
dub build :nwn-gff

# Eventually you can append --build=release
dub build :nwn-gff --build=release
```
