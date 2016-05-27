#!/bin/bash

dub fetch scod

# Gen doc
dub run scod -- filter --min-protection=Protected --only-documented docs.json
dub run scod -- generate-html --navigation-type=ModuleTree docs.json docs

# Install static files
pkg_path=$(dub list | sed -n 's|.*scod.*: ||p')
rsync -ru "$pkg_path"public/ docs/