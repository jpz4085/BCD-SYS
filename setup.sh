#!/usr/bin/env bash

platform=$(uname)
appimage="false"
bindir="/usr/local/bin"
resdir="/usr/local/share/BCD-SYS"

if [[ "$platform" != "Linux" && "$platform" != "Darwin" ]]; then
   echo "Unsupported platform detected."
   exit 1
fi

show_help () {
   echo "Usage: $(basename $0) [--appdir <path>] {install | uninstall}"
   echo
   echo "      --appdir	Path to folder for install or uninstall instead"
   echo "              	of '/usr/local' when building an AppImage package."
   echo
   exit 1
}

if [[ $# -eq 0 ]]; then show_help; fi

shopt -s nocasematch
while (( "$#" )); do
	case "$1" in
	     "install" )
	        option="$1"
	        respath="$resdir"
	        shift
	        ;;
	     --appdir )
	        shift
	        appdir="$1"
	        if   [[ "$platform" == "Darwin" ]]; then
	             bindir="$appdir/Contents/Resources/bin"
	             libdir="$appdir/Contents/Resources/lib"
	             resdir="$appdir/Contents/Resources/share/BCD-SYS"
	        elif [[ "$platform" == "Linux" ]]; then
	             bindir="$appdir/usr/bin"
	             libdir="$appdir/usr/lib"
	             resdir="$appdir/usr/share/BCD-SYS"
	        fi
	        appimage="true"
	        shift
	        ;;
	     "uninstall" )
	        option="$1"
	        shift
	        ;;
	     * )
	        show_help
	        ;;
	esac
done
shopt -u nocasematch

if [[ "$appimage" == "true" && ! -d "$appdir" ]]; then
   echo "Invalid directory path specified. Please try again."
   exit 1
fi

if [[ $EUID -ne 0 && "$appimage" == "false" ]]; then
   echo "This script must be run as root." >&2
   exit 1
fi

if   [[ "$option" == "install" ]]; then
     echo "Installing scripts and resources..."
     mkdir -p $bindir
     mkdir -p $resdir
     mkdir $resdir/Resources
     install $platform/bcd-sys.sh $bindir/bcd-sys
     install $platform/recovery.sh $resdir
     install $platform/update_device.sh $resdir
     install $platform/wbmfwvar.sh $resdir
     install $platform/winload.sh $resdir
     if [[ "$appimage" == "false" ]]; then
        install Resources/attach-vhdx.sh $bindir/attach-vhdx
        install Resources/detach-vhdx.sh $bindir/detach-vhdx
     fi
     cp Resources/*.txt $resdir/Resources
     cp -r Templates $resdir
     echo "Update script and template paths..."
     if [[ "$appimage" == "true" ]]; then
        if   [[ "$platform" == "Darwin" ]]; then
             apptype="appbundle"
             perl -i -pe"s|$apptype=\"false\"|$apptype=\"true\"|" $resdir/recovery.sh
             perl -i -pe"s|$apptype=\"false\"|$apptype=\"true\"|" $resdir/winload.sh
        elif [[ "$platform" == "Linux" ]]; then
             apptype="appimage"
        fi
        perl -i -pe"s|$apptype=\"false\"|$apptype=\"true\"|" $bindir/bcd-sys
        respath='\$\(dirname \"\$\(realpath \"\$\{0\}\"\)\"\)/../share/BCD-SYS'
     fi
     perl -i -pe"s|resdir=\".\"|resdir=\"$respath\"|" $bindir/bcd-sys
     perl -i -pe"s|tmpdir=\".\"|tmpdir=\"/tmp\"|" $bindir/bcd-sys
     if [[ "$appimage" == "true" ]]; then
        respath='\$\(dirname \"\$\(realpath \"\$\{0\}\"\)\"\)'
     fi
     perl -i -pe"s|resdir=\".\"|resdir=\"$respath\"|" $resdir/recovery.sh
     perl -i -pe"s|resdir=\".\"|resdir=\"$respath\"|" $resdir/winload.sh
     if [[ "$appimage" == "true" ]]; then mkdir -p "$libdir"; fi
     echo "Finished."
elif [[ "$option" == "uninstall" ]]; then
     echo "Removing scripts and resources..."
     rm $bindir/bcd-sys
     if [[ "$appimage" == "false" ]]; then
        rm $bindir/attach-vhdx
        rm $bindir/detach-vhdx
     fi
     rm -r $resdir
     echo "Finished."
else
     echo "Invalid option entered. Please try again."
     exit 1
fi
