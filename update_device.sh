#!/usr/bin/bash

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
    virtpart=$(lsblk -o path,mountpoint | grep "$vhdmount" | awk '{print $1}')
    virtdisk=$(echo $virtpart | sed 's/p[0-9]\+$//')
    vtscheme=$(sudo sfdisk -l $virtdisk | grep "Disklabel type:" | awk '{print $3}')
    physpart=$(lsblk -o path,mountpoint | grep "$imgmount" | awk '{print $1}')
    physdisk=$(echo $physpart | sed 's/[0-9]\+$//')
    pyscheme=$(sudo sfdisk -l $physdisk | grep "Disklabel type:" | awk '{print $3}')
else    
    part=$(lsblk -o path,mountpoint | grep "$mntpoint" | awk '{print $1}')
    disk=$(echo $part | sed 's/[0-9]\+$//')
    scheme=$(sudo sfdisk -l $disk | grep "Disklabel type:" | awk '{print $3}')
fi

if  [[ "$virtual" == "true" ]]; then
    if   [[ "$vtscheme" == "gpt" ]]; then
         vtdiskguid=$(sudo sfdisk -l $virtdisk | grep "Disk identifier:" | awk '{print $3}')
         vtpartguid=$(sudo sfdisk -o Device,UUID -l $virtdisk | grep $virtpart | awk '{print $2}')
         vtdiskbytes=$(printf "%s" $(guid_bytes $vtdiskguid) | sed 's/.\{2\}/&,/g;s/,$//')
         vtpartbytes=$(printf "%s" $(guid_bytes $vtpartguid) | sed 's/.\{2\}/&,/g;s/,$//')
         vtschemebyte="00"
    elif [[ "$vtscheme" == "dos" ]]; then
         vtdisksig=$(sudo sfdisk -l $virtdisk | grep "Disk identifier:" | awk '{print $3}')
         sectors=$(sudo sfdisk -o device,start -l $virtdisk | grep $virtpart | awk '{print $2}')
         sectsize=$(sudo blockdev --getss $virtdisk)
         vtpartoffset=$(($sectors * $sectsize))
         vtdiskbytes=$(printf "%s" $(endian $(printf "%032x" "$vtdisksig")) | sed 's/.\{2\}/&,/g;s/,$//')
         vtpartbytes=$(printf "%s" $(endian $(printf "%032x" "$vtpartoffset")) | sed 's/.\{2\}/&,/g;s/,$//')
         vtschemebyte="01"
    fi
    if   [[ "$pyscheme" == "gpt" ]]; then
         pydiskguid=$(sudo sfdisk -l $physdisk | grep "Disk identifier:" | awk '{print $3}')
         pypartguid=$(sudo sfdisk -o Device,UUID -l $physdisk | grep $physpart | awk '{print $2}')
         pydiskbytes=$(printf "%s" $(guid_bytes $pydiskguid) | sed 's/.\{2\}/&,/g;s/,$//')
         pypartbytes=$(printf "%s" $(guid_bytes $pypartguid) | sed 's/.\{2\}/&,/g;s/,$//')
         pyschemebyte="00"
    elif [[ "$pyscheme" == "dos" ]]; then
         pydisksig=$(sudo sfdisk -l $physdisk | grep "Disk identifier:" | awk '{print $3}')
         sectors=$(sudo sfdisk -o device,start -l $physdisk | grep $physpart | awk '{print $2}')
         sectsize=$(sudo blockdev --getss $physdisk)
         pypartoffset=$(($sectors * $sectsize))
         pydiskbytes=$(printf "%s" $(endian $(printf "%032x" "$pydisksig")) | sed 's/.\{2\}/&,/g;s/,$//')
         pypartbytes=$(printf "%s" $(endian $(printf "%032x" "$pypartoffset")) | sed 's/.\{2\}/&,/g;s/,$//')
         pyschemebyte="01"
    fi
    imgstrbytes=$(printf '%s' "$imgstring" | hexdump -ve '/1 "%02x\0\0"' | sed 's/.\{2\}/&,/g;s/,$//')
    imgstrlen=$((${#imgstring} * 2 + 2))
    devlength=$(($datalen + $imgstrlen))
    offbyte1=$(printf '%x' $(($devlength - 15)))
    offbyte2=$(printf '%x' $(($devlength - 71)))
    offbyte3=$(printf '%x' $(($devlength - 91)))
    
    printf "hex:3:00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,06,00,00,00,00,00,00,00,$offbyte1,00,00,00,00,00,00,00,$vtpartbytes,06,00,00,00,$vtschemebyte,00,00,00,$vtdiskbytes,00,00,00,00,00,00,00,00,$offbyte2,00,00,00,00,00,00,00,05,00,00,00,01,00,00,00,$offbyte3,00,00,00,05,00,00,00,06,00,00,00,00,00,00,00,48,00,00,00,00,00,00,00,$pypartbytes,00,00,00,00,$pyschemebyte,00,00,00,$pydiskbytes,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,$imgstrbytes,00,00\n"
else
    if   [[ "$scheme" == "gpt" ]]; then
         diskguid=$(sudo sfdisk -l $disk | grep "Disk identifier:" | awk '{print $3}')
         partguid=$(sudo sfdisk -o Device,UUID -l $disk | grep $part | awk '{print $2}')
         diskbytes=$(printf "%s" $(guid_bytes $diskguid) | sed 's/.\{2\}/&,/g;s/,$//')
         partbytes=$(printf "%s" $(guid_bytes $partguid) | sed 's/.\{2\}/&,/g;s/,$//')
         schemebyte="00"
    elif [[ "$scheme" == "dos" ]]; then
         disksig=$(sudo sfdisk -l $disk | grep "Disk identifier:" | awk '{print $3}')
         sectors=$(sudo sfdisk -o device,start -l $disk | grep $part | awk '{print $2}')
         sectsize=$(sudo blockdev --getss $disk)
         partoffset=$(($sectors * $sectsize))
         diskbytes=$(printf "%s" $(endian $(printf "%032x" "$disksig")) | sed 's/.\{2\}/&,/g;s/,$//')
         partbytes=$(printf "%s" $(endian $(printf "%032x" "$partoffset")) | sed 's/.\{2\}/&,/g;s/,$//')
         schemebyte="01"
    fi
    printf "hex:3:00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,06,00,00,00,00,00,00,00,48,00,00,00,00,00,00,00,$partbytes,00,00,00,00,$schemebyte,00,00,00,$diskbytes,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00\n"
fi
