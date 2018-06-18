#!/bin/bash

set -e
export WINEPREFIX=$HOME/.wine-dmd
export WINEARCH=win64
export WINEDEBUG=-all

if [[ "$1" == "before_install" ]]; then
	sudo dpkg --add-architecture i386

	wget -nc https://dl.winehq.org/wine-builds/Release.key
	sudo apt-key add Release.key
	sudo apt-add-repository https://dl.winehq.org/wine-builds/ubuntu/
	sudo apt-get update

	sudo apt-get install --install-recommends -y winehq-stable p7zip
	wineboot

	INSTALL_DIR=$WINEPREFIX/drive_c/dmd

	DMD_VERSION=`dmd --version | grep -P -o "2\.\d{3}\.\d"`

	wget http://downloads.dlang.org/releases/2.x/${DMD_VERSION}/dmd.${DMD_VERSION}.windows.7z -O /tmp/dmd.7z
	7zr x -o$INSTALL_DIR /tmp/dmd.7z


	DUB_VERSION=`dub --version | grep -P -o "\d+\.\d+\.\d+"`

	wget http://code.dlang.org/files/dub-${DUB_VERSION}-windows-x86.zip -O /tmp/dub.zip
	unzip -o /tmp/dub.zip -d $INSTALL_DIR/dmd2/windows/bin/

	echo 'Windows Registry Editor Version 5.00
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment]
"PATH"="c:\\\\windows;c:\\\\windows\\\\system;c:\\\\dmd\\\\dmd2\\\\windows\\\\bin"' | wine regedit -

elif [[ "$1" == "exec" ]]; then
	wine ${@:2}
else
	echo "Unknown command $1"
	exit 1
fi