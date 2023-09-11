#!/usr/bin/bash

gen_uuid () {
python3 -c 'import uuid; print(uuid.uuid4())'
}

guid_list () {
if  [[ "$2" == "true" ]]; then
    printf '%s\0\0' "$1" | hexdump -ve '/1 "%02x\0\0"'
else
    newguidlist=$(printf '%s\0' "$1" | hexdump -ve '/1 "%02x\0\0"')
    newguidlist+="$3"
    echo "$newguidlist"
fi
}

sourcepath="$1"
destpath="$2"
firmware="$3"
setfwmod="$4"
createbcd="$5"
prewbmdef="$6"
prodname="$7"
locale="$8"
resdir="."
winresguid=$(gen_uuid)
winldrguid=$(gen_uuid)
softhivepath="$sourcepath/Windows/System32/config/SOFTWARE"
namescript="cd Microsoft\Windows NT\CurrentVersion\nlsval ProductName\nunload\n"
ordscript="cd Objects\\{9dea862c-5cdd-4e70-acc1-f32b344d4795}\\\Elements\\\24000001\nlsval\nunload\n"
locscript="cd Objects\\{9dea862c-5cdd-4e70-acc1-f32b344d4795}\\\Elements\\\12000005\nlsval Element\nunload\n"
winproduct=$(printf "$namescript" | hivexsh "$softhivepath" | cut -d' ' -f 1,2)

if   [[ "$firmware" == "uefi" ]]; then
     mainbcdpath="$destpath/EFI/Microsoft/Boot/BCD"
elif [[ "$firmware" == "bios" ]]; then
     mainbcdpath="$destpath/Boot/BCD"
fi

if   [[ "$firmware" == "uefi" ]]; then
     ext="efi"
     mempath="\EFI\Microsoft\Boot\memtest.efi"
elif [[ "$firmware" == "bios" ]]; then
     ext="exe"
     mempath="\Boot\memtest.exe"
fi

if [[ "$createbcd" == "false" ]]; then
   wbmdsporder=$(printf "$ordscript" | sudo hivexsh "$mainbcdpath" | sed 's/.*://;s/,//g')
   wbmlocale=$(printf "$locscript" | sudo hivexsh "$mainbcdpath")
fi

### Windows Resume Loader Entry ###
printf "cd \Objects\n"
printf "add {%s}\n" "$winresguid"
printf "cd {%s}\n" "$winresguid"
printf "add Description\n"
printf "cd Description\n"
printf "setval 1\n"
printf "Type\n"
printf "dword:0x10200004\n"
printf "cd ..\n"
printf "add Elements\n"
printf "cd Elements\n"
printf "add 11000001\n"
printf "cd 11000001\n"
printf "setval 1\n"
printf "Element\n"
$resdir/update_device.sh "$sourcepath"
printf "cd ..\n"
printf "add 12000002\n"
printf "cd 12000002\n"
printf "setval 1\n"
printf "Element\n"
printf "string:\Windows\system32\winresume.%s\n" "$ext"
printf "cd ..\n"
printf "add 12000004\n"
printf "cd 12000004\n"
printf "setval 1\n"
printf "Element\n"
printf "string:Windows Resume Application\n"
printf "cd ..\n"
printf "add 12000005\n"
printf "cd 12000005\n"
printf "setval 1\n"
printf "Element\n"
printf "string:%s\n" "$locale"
printf "cd ..\n"
printf "add 14000006\n"
printf "cd 14000006\n"
printf "setval 1\n"
printf "Element\n"
printf "hex:7:7b,00,31,00,61,00,66,00,61,00,39,00,63,00,34,00,39,00,2d,00,31,00,36,00,61,00,62,00,2d,00,34,00,61,00,35,00,63,00,2d,00,39,00,30,00,31,00,62,00,2d,00,32,00,31,00,32,00,38,00,30,00,32,00,64,00,61,00,39,00,34,00,36,00,30,00,7d,00,00,00,00,00\n"
printf "cd ..\n"
if [[ "$firmware" == "uefi" ]]; then
   printf "add 16000060\n"
   printf "cd 16000060\n"
   printf "setval 1\n"
   printf "Element\n"
   printf "hex:3:01\n"
   printf "cd ..\n"
fi
printf "add 17000077\n"
printf "cd 17000077\n"
printf "setval 1\n"
printf "Element\n"
printf "hex:3:75,00,00,15,00,00,00,00\n"
printf "cd ..\n"
printf "add 21000001\n"
printf "cd 21000001\n"
printf "setval 1\n"
printf "Element\n"
$resdir/update_device.sh "$sourcepath"
printf "cd ..\n"
printf "add 22000002\n"
printf "cd 22000002\n"
printf "setval 1\n"
printf "Element\n"
printf "string:\hiberfil.sys\n"
printf "cd ..\n"
printf "add 25000008\n"
printf "cd 25000008\n"
printf "setval 1\n"
printf "Element\n"
printf "hex:3:01,00,00,00,00,00,00,00\n"
if [[ "$firmware" == "bios" ]]; then
   printf "cd ..\n"
   printf "add 26000006\n"
   printf "cd 26000006\n"
   printf "setval 1\n"
   printf "Element\n"
   printf "hex:3:00\n"
fi

### Windows Boot Loader Entry ###
printf "cd ..\..\..\n"
printf "add {%s}\n" "$winldrguid"
printf "cd {%s}\n" "$winldrguid"
printf "add Description\n"
printf "cd Description\n"
printf "setval 1\n"
printf "Type\n"
printf "dword:0x10200003\n"
printf "cd ..\n"
printf "add Elements\n"
printf "cd Elements\n"
printf "add 11000001\n"
printf "cd 11000001\n"
printf "setval 1\n"
printf "Element\n"
$resdir/update_device.sh "$sourcepath"
printf "cd ..\n"
printf "add 12000002\n"
printf "cd 12000002\n"
printf "setval 1\n"
printf "Element\n"
printf "string:\Windows\system32\winload.%s\n" "$ext"
printf "cd ..\n"
printf "add 12000004\n"
printf "cd 12000004\n"
printf "setval 1\n"
printf "Element\n"
if  [[ -z "$prodname" ]]; then
    printf "string:%s\n" "$winproduct"
else
    printf "string:%s\n" "$prodname"
fi
printf "cd ..\n"
printf "add 12000005\n"
printf "cd 12000005\n"
printf "setval 1\n"
printf "Element\n"
printf "string:%s\n" "$locale"
printf "cd ..\n"
printf "add 14000006\n"
printf "cd 14000006\n"
printf "setval 1\n"
printf "Element\n"
printf "hex:7:7b,00,36,00,65,00,66,00,62,00,35,00,32,00,62,00,66,00,2d,00,31,00,37,00,36,00,36,00,2d,00,34,00,31,00,64,00,62,00,2d,00,61,00,36,00,62,00,33,00,2d,00,30,00,65,00,65,00,35,00,65,00,66,00,66,00,37,00,32,00,62,00,64,00,37,00,7d,00,00,00,00,00\n"
printf "cd ..\n"
if [[ "$firmware" == "uefi" ]]; then
   printf "add 16000060\n"
   printf "cd 16000060\n"
   printf "setval 1\n"
   printf "Element\n"
   printf "hex:3:01\n"
   printf "cd ..\n"
fi
printf "add 17000077\n"
printf "cd 17000077\n"
printf "setval 1\n"
printf "Element\n"
printf "hex:3:75,00,00,15,00,00,00,00\n"
printf "cd ..\n"
printf "add 21000001\n"
printf "cd 21000001\n"
printf "setval 1\n"
printf "Element\n"
$resdir/update_device.sh "$sourcepath"
printf "cd ..\n"
printf "add 22000002\n"
printf "cd 22000002\n"
printf "setval 1\n"
printf "Element\n"
printf "string:\Windows\n"
printf "cd ..\n"
printf "add 23000003\n"
printf "cd 23000003\n"
printf "setval 1\n"
printf "Element\n"
printf "string:{%s}\n" "$winresguid"
printf "cd ..\n"
printf "add 25000020\n"
printf "cd 25000020\n"
printf "setval 1\n"
printf "Element\n"
printf "hex:3:00,00,00,00,00,00,00,00\n"
printf "cd ..\n"
printf "add 250000c2\n"
printf "cd 250000c2\n"
printf "setval 1\n"
printf "Element\n"
printf "hex:3:01,00,00,00,00,00,00,00\n"

### Windows Boot Manager Entry ###
printf "cd ..\..\..\n"
printf "cd {9dea862c-5cdd-4e70-acc1-f32b344d4795}\n"
printf "cd Elements\n"
if [[ "$createbcd" == "true" ]]; then
   printf "cd 11000001\n"
   printf "setval 1\n"
   printf "Element\n"
   $resdir/update_device.sh "$destpath"
   printf "cd ..\n"
fi
if [[ "$createbcd" == "true" && "$firmware" == "uefi" ]]; then
   printf "add 12000002\n"
   printf "cd 12000002\n"
   printf "setval 1\n"
   printf "Element\n"
   printf "string:\\\EFI\\Microsoft\\Boot\\\bootmgfw.efi\n"
   printf "cd ..\n"
fi
if [[ "$createbcd" == "true" || "$wbmlocale" != "$locale" ]]; then
   printf "cd 12000005\n"
   printf "setval 1\n"
   printf "Element\n"
   printf "string:%s\n" "$locale"
   printf "cd ..\n"
fi
if [[ "$createbcd" == "true" || "$prewbmdef" == "false" ]]; then
   printf "cd 23000003\n"
   printf "setval 1\n"
   printf "Element\n"
   printf "string:{%s}\n" "$winldrguid"
   printf "cd ..\n"
fi
printf "cd 23000006\n"
printf "setval 1\n"
printf "Element\n"
printf "string:{%s}\n" "$winresguid"
printf "cd ..\n"
printf "cd 24000001\n"
printf "setval 1\n"
printf "Element\n"
if  [[ "$createbcd" == "true" ]]; then
    printf "hex:7:%s\n" $(guid_list "{$winldrguid}" "$createbcd")
else
    printf "hex:7:%s\n" $(guid_list "{$winldrguid}" "$createbcd" "$wbmdsporder")
fi

### Windows Memory Tester Entry ###
printf "cd ..\..\..\n"
printf "cd {b2721d73-1db4-4c62-bf78-c548a880142d}\n"
printf "cd Elements\n"
if [[ "$createbcd" == "true" ]]; then
   printf "cd 11000001\n"
   printf "setval 1\n"
   printf "Element\n"
   $resdir/update_device.sh "$destpath"
   printf "cd ..\n"
fi
if [[ "$createbcd" == "true" ]]; then
   printf "cd 12000002\n"
   printf "setval 1\n"
   printf "Element\n"
   printf "string:%s\n" "$mempath"
   printf "cd ..\n"
fi
if [[ "$createbcd" == "true" || "$wbmlocale" != "$locale" ]]; then
   printf "cd 12000005\n"
   printf "setval 1\n"
   printf "Element\n"
   printf "string:%s\n" "$locale"
fi

### System and KeyName Entries ###
if [[ "$createbcd" == "true" ]]; then
   printf "cd \\ \n"
   printf "cd Description\n"
   if [[ "$setfwmod" == "true" ]]; then num=3; else num=2; fi
   printf "setval $num\n"
   printf "KeyName\n"
   printf "string:BCD00000000\n"
   if [[ "$setfwmod" == "true" ]]; then
      printf "FirmwareModified\n"
      printf "dword:1\n"
   fi
   printf "System\n"
   printf "dword:1\n"
fi
printf "commit\n"
printf "unload\n"
