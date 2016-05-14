# nwn-lib-d
Multi-platform D library & tooling for handling Neverwinter Nights 1 & 2 resource files

[![Build Status](https://travis-ci.org/CromFr/nwn-lib-d.svg?branch=master)](https://travis-ci.org/CromFr/nwn-lib-d)
[![codecov](https://codecov.io/gh/CromFr/nwn-lib-d/branch/master/graph/badge.svg)](https://codecov.io/gh/CromFr/nwn-lib-d)

[![GitHub license](https://img.shields.io/badge/license-GPL%203.0-blue.svg)](https://raw.githubusercontent.com/CromFr/nwn-lib-d/master/LICENSE)

---

# Features

- GFF file format (ifo, are, bic, uti, ...)
    + Parsing from:
        * GFF
    + Serialization to:
        * GFF
        * _pretty_ (human readable)


# Install

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

# Tools usage

```sh
./nwn-gff --help

```

### Examples
```sh
# Print gff file in console
./nwn-gff -i mycharacter.bic

# Write mycharacter.bic to mycharacter.bic.txt in pretty format
./nwn-gff -i mycharacter.bic:gff -o mycharacter.bic.txt:pretty

# Read gff from stdin, write to stdout in pretty format
./nwn-gff -i -:gff -o -:pretty
```