#!/bin/bash
set -ev

# dub fetch -q scod
if [ ! -d scod ]; then
	git clone https://github.com/MartinNowak/scod.git scod
	
	cd scod
	sed -i 's/"vibe-d":\s"0\.7\.30"/"vibe-d": "0.7.31"/' dub.selections.json
	echo 'versions "VibeNoSSL"' >> dub.sdl
	
	dub build
	cd ..
fi

# Gen doc
DFLAGS='-c -o- -Df__dummy.html -Xfdocs.json' dub build
scod/scod -- filter --min-protection=Protected --only-documented docs.json
scod/scod -- generate-html --navigation-type=ModuleTree docs.json docs

# Install static files
#pkg_path=$(dub list | sed -n 's|.*scod.*: ||p')
pkg_path=
rsync -ru scod/public/ docs/
