#!/bin/bash
set -e

# dub fetch -q scod
if [ ! -d scod ]; then
	git clone https://github.com/CromFr/scod.git scod
	dub add-local scod
fi

# Gen doc
DFLAGS='-c -o- -Df__dummy.html -Xfdocs.json' dub build
dub run -q scod -- filter --min-protection=Protected --only-documented docs.json
dub run -q scod -- generate-html --navigation-type=ModuleTree docs.json docs

# Install static files
pkg_path=$(dub list | sed -n 's|.*scod.*: ||p')
rsync -ru "$pkg_path"public/ docs/