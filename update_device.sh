#!/usr/bin/bash

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

mntpoint="$1"
part=$(lsblk -o path,mountpoint | grep "$mntpoint" | awk '{print $1}')
disk=$(echo $part | sed 's/[0-9]\+$//')
scheme=$(sudo sfdisk -l $disk | grep "Disklabel type:" | awk '{print $3}')

if [[ "$scheme" == "gpt" ]]; then
   diskguid=$(sudo sfdisk -l $disk | grep "Disk identifier:" | awk '{print $3}')
   partguid=$(sudo sfdisk -o Device,UUID -l $disk | grep $part | awk '{print $2}')
   diskbytes=$(printf "%s" $(guid_bytes $diskguid) | sed 's/.\{2\}/&,/g;s/,$//')
   partbytes=$(printf "%s" $(guid_bytes $partguid) | sed 's/.\{2\}/&,/g;s/,$//')

   printf "hex:3:00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,06,00,00,00,00,00,00,00,48,00,00,00,00,00,00,00,$partbytes,00,00,00,00,00,00,00,00,$diskbytes,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00\n"
fi

if [[ "$scheme" == "dos" ]]; then
   disksig=$(sudo sfdisk -l $disk | grep "Disk identifier:" | awk '{print $3}')
   sectors=$(sudo sfdisk -o device,start -l $disk | grep $part | awk '{print $2}')
   sectsize=$(sudo blockdev --getss $disk)
   partoffset=$(($sectors * $sectsize))
   sigbytes=$(printf "%s" $(endian $(printf "%032x" "$disksig")) | sed 's/.\{2\}/&,/g;s/,$//')
   partbytes=$(printf "%s" $(endian $(printf "%032x" "$partoffset")) | sed 's/.\{2\}/&,/g;s/,$//')
   
   printf "hex:3:00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,06,00,00,00,00,00,00,00,48,00,00,00,00,00,00,00,$partbytes,00,00,00,00,01,00,00,00,$sigbytes,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00\n"
fi

