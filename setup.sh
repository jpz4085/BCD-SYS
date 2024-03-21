#!/usr/bin/env bash

platform=$(uname)
bindir="/usr/local/bin"
resdir="/usr/local/share/BCD-SYS"

if [[ $# -eq 0 ]]; then
   echo "Usage: $(basename $0) install|uninstall"
   exit 1
fi

if [[ "$platform" != "Linux" && "$platform" != "Darwin" ]]; then
   echo "Unsupported platform detected."
   exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." >&2
   exit 1
fi

if   [[ "$1" == "install" ]]; then
     echo "Installing scripts and resources..."
     mkdir -p $bindir
     mkdir -p $resdir
     mkdir $resdir/Resources 
     install $platform/bcd-sys.sh $bindir/bcd-sys
     install $platform/recovery.sh $resdir
     install $platform/update_device.sh $resdir
     install $platform/wbmfwvar.sh $resdir
     install $platform/winload.sh $resdir
     install Resources/attach-vhdx.sh $bindir/attach-vhdx
     install Resources/detach-vhdx.sh $bindir/detach-vhdx
     cp Resources/*.txt $resdir/Resources
     cp -r Templates $resdir
     echo "Update script and template paths..."
     perl -i -pe"s|resdir=\".\"|resdir=\"$resdir\"|" $bindir/bcd-sys
     perl -i -pe"s|tmpdir=\".\"|tmpdir=\"/tmp\"|" $bindir/bcd-sys
     perl -i -pe"s|resdir=\".\"|resdir=\"$resdir\"|" $resdir/recovery.sh
     perl -i -pe"s|resdir=\".\"|resdir=\"$resdir\"|" $resdir/winload.sh
     echo "Finished."
elif [[ "$1" == "uninstall" ]]; then
     echo "Removing scripts and resources..."
     rm $bindir/bcd-sys
     rm $bindir/attach-vhdx
     rm $bindir/detach-vhdx
     rm -r $resdir
     echo "Finished."
else
     echo "Invalid option entered. Please try again."
fi
