#!/usr/bin/bash

image="$1"
errormsg=$(modinfo nbd 2>&1>/dev/null)
if [[ -z $(command -v qemu-nbd) ]]; then missing+=" qemu-utils"; fi
if [[ "$errormsg" == "modinfo: ERROR: Module nbd not found." ]]; then missing+=" nbd-client"; fi
if [[ ! -z "$missing" ]]; then
   echo "The following packages are required:""$missing"
   exit 1
fi

if   [[ $# -eq 0 ]]; then
     echo "Usage: $(basename $0) <path>"
     echo "Connect to VHDX image file at <path>"
     exit
elif [[ ! -f "$image" || "$image" != *".vhdx"* ]]; then
     echo "Invalid file: $image"
     exit 1
fi

echo "Attach virtual disk to nbd device (sudo required)..."
if ! lsmod | grep -wq nbd; then
   sudo modprobe nbd max_part=10
fi

for x in /sys/class/block/nbd*; do
    S=$(cat $x/size)
    if [[ "$S" == "0" && ! -f "$x/pid" ]]; then
       nbdev="/dev/$(basename $x)"
       sudo qemu-nbd -c "$nbdev" "$image"
       echo "Connected $(basename "$image") to $nbdev"
       break
    fi
done
