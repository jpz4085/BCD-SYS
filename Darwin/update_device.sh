#!/usr/bin/env bash

# update_device.sh - format physical and virtual disk signatures/offsets
#                    used by device entries such as 11000001 and 21000001
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

guid_bytes () {
guidstr="$1"
IFS='-'

   read -a strarr <<< "$guidstr"

   guidbytes=$(endian ${strarr[0]})
   guidbytes+=$(endian ${strarr[1]})
   guidbytes+=$(endian ${strarr[2]})
   guidbytes+=${strarr[3]}
   guidbytes+=${strarr[4]}
   
   echo $guidbytes
}

blksize () {
sectsz=$(diskutil info $1 | grep "Device Block Size:" | awk '{print $4}')
echo $sectsz
}

if  [[ $# -eq 3 ]]; then
    virtual="true"
    datalen=175
    vhdmount="$1"
    imgmount="$2"
    imgstring="$3"
else
    virtual="false"
    mntpoint="$1"
fi

if  [[ "$virtual" == "true" ]]; then
    virtpart=$(diskutil info "$(basename "$vhdmount")" | grep "Device Node:" | awk '{print $3}')
    virtdisk=$(printf $virtpart | sed 's/s[0-9]*$//')
    vtscheme=$(diskutil info $virtdisk | grep "Content (IOContent):" | awk '{print $3}')
    physpart=$(diskutil info "$(basename "$imgmount")" | grep "Device Node:" | awk '{print $3}')
    physdisk=$(printf $physpart | sed 's/s[0-9]*$//')
    pyscheme=$(diskutil info $physdisk | grep "Content (IOContent):" | awk '{print $3}')
else
    part=$(diskutil info "$(basename "$mntpoint")" | grep "Device Node:" | awk '{print $3}')
    disk=$(printf $part | sed 's/s[0-9]*$//')
    scheme=$(diskutil info $disk | grep "Content (IOContent):" | awk '{print $3}')
    if [[ "$scheme" == "GUID_partition_scheme" ]]; then
       if [[ ! -z $(sudo fdisk "$disk" | grep -E '2:|3:|4:' | grep -v unused) ]]; then
          scheme="FDisk_partition_scheme" #Use fdisk option for GPT disk with hybrid MBR.
       fi
    fi
fi

if  [[ "$virtual" == "true" ]]; then
    if   [[ "$vtscheme" == "GUID_partition_scheme" ]]; then
         vtsectsz=$(blksize $virtdisk)
         vtdiskbytes=$(sudo xxd -u -p -s $(($vtsectsz + 56)) -l 16 $virtdisk | sed 's/.\{2\}/&,/g;s/,$//')
         vtpartguid=$(diskutil info $virtpart | grep "Partition UUID:" | awk '{print $5}')
         vtpartbytes=$(printf "%s" $(guid_bytes $vtpartguid) | sed 's/.\{2\}/&,/g;s/,$//')
         vtschemebyte="00"
    elif [[ "$vtscheme" == "FDisk_partition_scheme" ]]; then
         vtdisksig=$(sudo xxd -u -p -s 440 -l 4 $virtdisk)
         vtpartoffset=$(diskutil info $virtpart | grep "Partition Offset:" | awk '{print $3}')
         if [[ -z $vtpartoffset ]]; then
            hidsect=$(sudo fdisk $virtdisk | tail -n +6 | awk -v partnum=${virtpart##*s} 'FNR == partnum {print $11}')
            sectsize=$(blksize $virtdisk)
            vtpartoffset=$(($sectsize * $hidsect))
         fi
         vtdiskbytes=$(printf "%s" $(printf "%x%024x" "0x$vtdisksig") | sed 's/.\{2\}/&,/g;s/,$//')
         vtpartbytes=$(printf "%s" $(endian $(printf "%032x" "$vtpartoffset")) | sed 's/.\{2\}/&,/g;s/,$//')
         vtschemebyte="01"
    fi
    if   [[ "$pyscheme" == "GUID_partition_scheme" ]]; then
         pysectsz=$(blksize $physdisk)
         pydiskbytes=$(sudo xxd -u -p -s $(($pysectsz + 56)) -l 16 $physdisk | sed 's/.\{2\}/&,/g;s/,$//')
         pypartguid=$(diskutil info $physpart | grep "Partition UUID:" | awk '{print $5}')
         pypartbytes=$(printf "%s" $(guid_bytes $pypartguid) | sed 's/.\{2\}/&,/g;s/,$//')
         pyschemebyte="00"
    elif [[ "$pyscheme" == "FDisk_partition_scheme" ]]; then
         pydisksig=$(sudo xxd -u -p -s 440 -l 4 $physdisk)
         pypartoffset=$(diskutil info $physpart | grep "Partition Offset:" | awk '{print $3}')
         if [[ -z $pypartoffset ]]; then
            hidsect=$(sudo fdisk $physdisk | tail -n +6 | awk -v partnum=${physpart##*s} 'FNR == partnum {print $11}')
            sectsize=$(blksize $physdisk)
            pypartoffset=$(($sectsize * $hidsect))
         fi
         pydiskbytes=$(printf "%s" $(printf "%x%024x" "0x$pydisksig") | sed 's/.\{2\}/&,/g;s/,$//')
         pypartbytes=$(printf "%s" $(endian $(printf "%032x" "$pypartoffset")) | sed 's/.\{2\}/&,/g;s/,$//')
         pyschemebyte="01"
    fi
    imgstrbytes=$(printf '%s' "$imgstring" | hexdump -ve '/1 "%02x\0\0"' | sed 's/.\{2\}/&,/g;s/,$//')
    imgstrlen=$((${#imgstring} * 2 + 2))
    devlength=$(($datalen + $imgstrlen))
    offbyte1=$(printf '%x' $(($devlength - 15))) #Length from end to byte 0x0F.
    offbyte2=$(printf '%x' $(($devlength - 71))) #Length from end to byte 0x47.
    offbyte3=$(printf '%x' $(($devlength - 91))) #Length from end to byte 0x5B.
    
    printf "hex:3:00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,06,00,00,00,00,00,00,00,$offbyte1,00,00,00,00,00,00,00,$vtpartbytes,06,00,00,00,$vtschemebyte,00,00,00,$vtdiskbytes,00,00,00,00,00,00,00,00,$offbyte2,00,00,00,00,00,00,00,05,00,00,00,01,00,00,00,$offbyte3,00,00,00,05,00,00,00,06,00,00,00,00,00,00,00,48,00,00,00,00,00,00,00,$pypartbytes,00,00,00,00,$pyschemebyte,00,00,00,$pydiskbytes,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,$imgstrbytes,00,00\n"
else
    if   [[ "$scheme" == "GUID_partition_scheme" ]]; then
         sectsize=$(blksize $disk)
         diskbytes=$(sudo xxd -u -p -s $(($sectsize + 56)) -l 16 $disk | sed 's/.\{2\}/&,/g;s/,$//')
         partguid=$(diskutil info $part | grep "Partition UUID:" | awk '{print $5}')
         partbytes=$(printf "%s" $(guid_bytes $partguid) | sed 's/.\{2\}/&,/g;s/,$//')
         schemebyte="00"
    elif [[ "$scheme" == "FDisk_partition_scheme" ]]; then
         disksig=$(sudo xxd -u -p -s 440 -l 4 $disk)
         partoffset=$(diskutil info $part | grep "Partition Offset:" | awk '{print $3}')
         if [[ -z $partoffset ]]; then
            hidsect=$(sudo fdisk $disk | tail -n +6 | awk -v partnum=${part##*s} 'FNR == partnum {print $11}')
            sectsize=$(blksize $disk)
            partoffset=$(($sectsize * $hidsect))
         fi
         diskbytes=$(printf "%s" $(printf "%x%024x" "0x$disksig") | sed 's/.\{2\}/&,/g;s/,$//')
         partbytes=$(printf "%s" $(endian $(printf "%032x" "$partoffset")) | sed 's/.\{2\}/&,/g;s/,$//')
         schemebyte="01"
    fi
    printf "hex:3:00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,06,00,00,00,00,00,00,00,48,00,00,00,00,00,00,00,$partbytes,00,00,00,00,$schemebyte,00,00,00,$diskbytes,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00\n"
fi
