#!/usr/bin/bash

# wbmfwvar.sh - read and format the WBM firmware variable data required
#               by the BCD entry when adding the WBM to the UEFI options.
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

wbmdevice=$(xxd -p "/sys/firmware/efi/efivars/Boot$1-8be4df61-93ca-11d2-aa0d-00e098032b8c" | tr -d '\n' | sed 's/7fff0400.*/7fff0400/;s/.*04012a/04012a/;s/.\{2\}/&,/g;s/,$//')
wbmoptdata=$(xxd -p "/sys/firmware/efi/efivars/Boot$1-8be4df61-93ca-11d2-aa0d-00e098032b8c" | tr -d '\n' | sed 's/.*57494e444f5753/57494e444f5753/;s/.\{2\}/&,/g;s/,$//')
wbmoptbytes=$(printf "%s" $(endian $(printf "%08x" "0x$1")) | sed 's/.\{2\}/&,/g;s/,$//')

printf "cd Objects\\{9dea862c-5cdd-4e70-acc1-f32b344d4795}\\Description\n"
printf "setval 2\n"
printf "Type\n"
printf "dword:0x10100002\n"
printf "FirmwareVariable\n"
printf "hex:3:01,00,00,00,50,01,00,00,$wbmoptbytes,05,00,00,00,a4,00,00,00,d0,00,00,00,88,00,00,00,$wbmoptdata,57,00,69,00,6e,00,64,00,6f,00,77,00,73,00,20,00,42,00,6f,00,6f,00,74,00,20,00,4d,00,61,00,6e,00,61,00,67,00,65,00,72,00,00,00,00,00,01,00,00,00,80,00,00,00,04,00,00,00,$wbmdevice\n"
printf "commit\n"
printf "unload\n"
