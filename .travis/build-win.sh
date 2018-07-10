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
	wget https://downloads.dlang.org/releases/2.x/${DMD_VERSION}/dmd.${DMD_VERSION}.windows.7z -O /tmp/dmd.7z
	7zr x -o$INSTALL_DIR /tmp/dmd.7z

	echo 'Windows Registry Editor Version 5.00
[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment]
"PATH"="c:\\\\windows;c:\\\\windows\\\\system;c:\\\\dmd\\\\dmd2\\\\windows\\\\bin"' | wine regedit -
fi