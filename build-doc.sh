#!/bin/bash
set -e

dub fetch scod

# Gen doc
DFLAGS='-c -o- -Df__dummy.html -Xfdocs.json' dub build
dub run scod -- filter --min-protection=Protected --only-documented docs.json
dub run scod -- generate-html --navigation-type=ModuleTree docs.json docs

# Install static files
pkg_path=$(dub list | sed -n 's|.*scod.*: ||p')
rsync -ru "$pkg_path"public/ docs/