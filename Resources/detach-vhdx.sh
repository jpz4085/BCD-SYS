#!/usr/bin/bash

rmnbdmod="false"

usage () {
echo "Usage: $(basename $0) [options] <device>"
echo
echo "<device>    	Block device to disconnect."
echo "-u, --unload	Unload the NBD kernel module."
exit
}

if [[ $# -eq 0 ]]; then usage; fi

shopt -s nocasematch
while (( "$#" )); do
	case "$1" in
	    -u | --unload )
	       rmnbdmod="true"
	       shift
	       ;;
	    * )
	      nbdpath="$1"
	      shift
	      ;;
	esac
done
shopt -u nocasematch

if  [[ ! -e "$nbdpath" ]]; then
    echo "Invalid device path: $nbdpath"
    exit 1
else
    echo "Detach virtual disk (sudo required)..."
    sudo qemu-nbd -d "$nbdpath"
    if [[ "$rmnbdmod" == "true" ]]; then
       echo "Unload nbd kernel module..."
       sleep 1 && sudo rmmod nbd
    fi
fi
