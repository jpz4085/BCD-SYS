#!/usr/bin/env bash

# attach-vhdx.sh - connect virtual disk to an nbd or block device
# 
# Copyright (C) 2024 Joseph P. Zeller
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

verbose="false"
mntopts="-imagekey diskimage-class=CRawDiskImage"

usage () {
if   [[ $(uname) == "Linux" ]]; then
     echo "Usage: $(basename $0) <path>"
     echo "Connect VHDX image file to NBD device."
elif [[ $(uname) == "Darwin" ]]; then
     echo "Usage: $(basename $0) [options] <path>"
     echo
     echo "Attach and mount VHDX image file at <path>"
     echo "-m	Don't automatically mount partitions."
     echo "-v	Display header offset information."
     echo
     echo "Notes: Only fixed size images are supported."
fi
exit
}

endian () {
v=$1
i=${#v}

while [ $i -gt 0 ]
do
    i=$[$i-2]
    echo -n ${v:$i:2}
done
echo
}

#Script startes here.
if [[ $# -eq 0 ]]; then usage; fi

shopt -s nocasematch
while (( "$#" )); do
	case "$1" in
             -v )
              verbose="true"
              shift
              ;;
             -m )
              mntopts+=" -nomount"
              shift
              ;;
             * )
              image="$1"
              shift
              ;;
        esac
done
shopt -u nocasematch

if   [[ ! -f "$image" || "$image" != *".vhdx"* ]]; then
     echo "Invalid file: $image"
     exit 1
elif [[ $(uname) == "Linux" ]]; then
     errormsg=$(modinfo nbd 2>&1>/dev/null)
     if [[ -z $(command -v qemu-nbd) ]]; then missing+=" qemu-utils"; fi
     if [[ "$errormsg" == "modinfo: ERROR: Module nbd not found." ]]; then missing+=" nbd-client"; fi
     if [[ ! -z "$missing" ]]; then
        echo "The following packages are required:""$missing"
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
elif [[ $(uname) == "Darwin" ]]; then
     #Get file offset of first payload block and metadata region in bytes then step through the metadata
     #enteries to get the logical sector size (LSS) and virtual disk size (VDS). Divide the offset of the
     #first payload block by the LSS to get offset in sectors then pass to hdiutil using the section option.
     #Byte offsets of headers and length of entries and data fields taken from the VHDX v2 Specification:
     #https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-vhdx/83e061f8-f6e2-4de1-91bd-5d518a43d477

     offsetbat=$(endian $(xxd -ps -s 196640 -l 8 "$image"))
     offsetmeta=$(endian $(xxd -ps -s 196672 -l 8 "$image"))
     metaentries=$(endian $(xxd -ps -s "$((0x$offsetmeta + 0xA))" -l 2 "$image"))
     blockzero=$(endian $(xxd -ps -s "0x$offsetbat" -l 8 "$image" | sed 's/^\([0-9]\)[0-7]/\10/'))
     offmetavdisk=$(xxd -c 32 -s "$((0x$offsetmeta + 0x20))" -l "$((0x20 * 0x$metaentries))" "$image" | grep '2442 a52f 1bcd 7648 b211 5dbe d83b f4b8' | awk '{print $1}' | sed 's/://')
     offmetalsect=$(xxd -c 32 -s "$((0x$offsetmeta + 0x20))" -l "$((0x20 * 0x$metaentries))" "$image" | grep '1dbf 4181 6fa9 0947 ba47 f233 a8fa ab5f' | awk '{print $1}' | sed 's/://')
     offvdisksz=$(endian $(xxd -ps -s "$((0x$offmetavdisk + 0x10))" -l 4 "$image"))
     offlsectsz=$(endian $(xxd -ps -s "$((0x$offmetalsect + 0x10))" -l 4 "$image"))
     vdisksize=$(endian $(xxd -ps -s "$((0x$offvdisksz + 0x$offsetmeta))" -l 8 "$image"))
     lsectsize=$(endian $(xxd -ps -s "$((0x$offlsectsz + 0x$offsetmeta))" -l 4 "$image"))
     offsetimage=$((0x$blockzero / 0x$lsectsize))
     filesize=$(stat -f %z "$image")

     #Values of offsets and media sizes from header information displayed in verbose.
     if [[ $verbose == "true" ]]; then
        echo "Header Data Offsets"
        echo "Block Allocation Table: 0x$offsetbat"
        echo "Metadata Section:       0x$offsetmeta"
        echo "Payload Block Zero:     0x$blockzero"
        echo "Metadata Entries:       0x$metaentries"
        echo "Metadata LSS Entry:     0x$offmetalsect"
        echo "Metadata LSS Item:      0x$offlsectsz"
        echo "Metadata VDS Entry:     0x$offmetavdisk"
        echo "Metadata VDS Item:      0x$offvdisksz"
        echo "Logical Sector Size:    0x$lsectsize"
        echo "Virtual Disk Size:      0x$vdisksize"
        echo
        echo "Sector offset of image: $offsetimage"
        echo
     fi

     if [[ $filesize -lt 0x$vdisksize ]]; then
        echo "Virtual disk size is greater than the image file."
        echo "Dynamically expanding VHDX files are not supported."
        exit 1
     fi

     hdiutil attach $mntopts -section $offsetimage "$image"
else
     echo "Unsupported platform detected."
     exit 1
fi
