# attach-vhdx.sh - connect virtual disk to an available nbd device
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
