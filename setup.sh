#!/usr/bin/bash

bindir="/usr/local/bin"
resdir="/usr/local/share/BCD-SYS"

if   [[ "$1" == "install" ]]; then
     echo "Install scripts and resources..."
     mkdir -p $bindir && mkdir -p $resdir
     install -m 755 bcd-sys.sh $bindir/bcd-sys
     install -m 755 recovery.sh $resdir
     install -m 755 update_device.sh $resdir
     install -m 755 winload.sh $resdir
     cp -r Templates $resdir
     echo "Update script and template paths..."
     sed -i "s|resdir=\".\"|resdir=\"$resdir\"|" $bindir/bcd-sys
     sed -i "s|tmpdir=\".\"|tmpdir=\"/tmp\"|" $bindir/bcd-sys
     sed -i "s|resdir=\".\"|resdir=\"$resdir\"|" $resdir/recovery.sh
     sed -i "s|resdir=\".\"|resdir=\"$resdir\"|" $resdir/winload.sh
     echo "Finished!"
elif [[ "$1" == "uninstall" ]]; then
     echo "Removing scripts and resources..."
     rm $bindir/bcd-sys && rm -r $resdir
     echo "Finished!"
else
     echo "Usage: $(basename $0) install|uninstall"
fi
