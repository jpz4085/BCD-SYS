#!/usr/bin/bash

firmware=$(test -d /sys/firmware/efi && echo uefi || echo bios)
setfwmod="false"
createbcd="true"
prewbmdef="false"
locale="en-us"
clean="false"
resdir="."
tmpdir="."

usage () {
echo "Usage: $(basename $0) <source> [options] <system>"
echo
echo "Configure the boot environment for a Windows installation."
echo
echo "Options:"
echo
echo "<source>	 Mount point of the Windows partition"
echo "-f, --firmware	 Specify the firmware type as UEFI or BIOS"
echo "-s, --syspath	 Mount point of the system partition (Optional)"
echo "-d, --wbmdefault Preserve the existing default entry in {bootmgr}"
echo "                 this will be ignored when creating a new BCD store"
echo "-n, --prodname	 Specify the display name for the new OS entry"
echo "              	 otherwise use the product name from the registry"
echo "-l, --locale	 Specify the locale parameter (Default is en-us)"
echo "-c, --clean	 Remove existing BCD stores and create new entries"
echo "-h, --help	 Display this help message"
echo
echo "This script will copy the boot files, if missing or outdated, from"
echo "the Windows installation located at <source> to a system partition"
echo "on either the same drive or the first drive (/dev/sda) whichever"
echo "exists. Alternatively a volume mounted at <system> can be specified"
echo "using the --syspath option. Any duplicate objects will be deleted"
echo "from an existing BCD when creating new entries. The system template"
echo "at Windows/System32/config/BCD-Template is currently ignored."
echo
echo "The default firmware type is the same type running under Linux. UEFI"
echo "is currently the only firmware option until BIOS support is finished."
echo "The Windows Boot Manager will be added to the UEFI firmware boot menu"
echo "except when using the --syspath option which must rely on the default"
echo "path at /EFI/BOOT/BOOTX64.efi"
exit
}

remove_duplicates () {
bcdpath="$2/EFI/Microsoft/Boot/BCD"
newdevstr=$($resdir/update_device.sh "$1" | sed 's/.*://;')
newdevstr=${newdevstr,,}
ordscript="cd Objects\\{9dea862c-5cdd-4e70-acc1-f32b344d4795}\\\Elements\\\24000001\n"
rldrscript="cd Objects\\{9dea862c-5cdd-4e70-acc1-f32b344d4795}\\\Elements\\\23000006\n"

readarray -t objects <<< $(printf "cd Objects\nls\nq\n" | hivexsh "$bcdpath")

for key in "${!objects[@]}"
do
	curdevstr=$(printf "cd Objects\\${objects[$key]}\\\Elements\\\11000001\nlsval\nq" | hivexsh "$bcdpath" 2> /dev/null | sed 's/.*://;')
	if [[ "$curdevstr" == "$newdevstr" ]]; then
	   echo "Remove entry at ${objects[$key]}"
	   printf "cd Objects\\${objects[$key]}\ndel\ncommit\nunload\n" | sudo hivexsh -w "$bcdpath"
	   wbmdsporder=$(printf "$ordscript""lsval\nunload\n" | hivexsh "$bcdpath" | sed 's/.*://;s/,//g')
	   guidstr=$(printf '%s\0' "${objects[$key]}" | hexdump -ve '/1 "%02x\0\0"')
	   if [[ "$wbmdsporder" == *"$guidstr"* ]]; then
	      echo "Remove ${objects[$key]} from WBM display order."
	      newdsporder=$(printf "%s" "$wbmdsporder" | sed "s/$guidstr//")
	      printf "$ordscript""setval 1\nElement\nhex:7:%s\ncommit\nunload\n" "$newdsporder" | sudo hivexsh -w "$bcdpath"
	   fi
	   wbmresldr=$(printf "$rldrscript""lsval\nunload\n" | hivexsh "$bcdpath" | sed 's/.*=//;s/"//g')
	   if [[ "$wbmresldr" == "${objects[$key]}" ]]; then
	      echo "Remove ${objects[$key]} from WBM resume object."
	      printf "$rldrscript""setval 0\ncommit\nunload\n" | sudo hivexsh -w "$bcdpath"
	   fi	   
	fi
done
}

build_stores () {
echo "Build main and recovery BCD stores..."
$resdir/winload.sh "$1" "$2" "$3" "$4" "$5" "$6" "$7" > $tmpdir/winload.txt && $resdir/recovery.sh "$2" "$4" "$7" > $tmpdir/recovery.txt
cp $resdir/Templates/BCD-NEW $tmpdir/BCD-Windows && cp $resdir/Templates/BCD-NEW $tmpdir/BCD-Recovery
hivexregedit --merge --prefix BCD00000001 $tmpdir/BCD-Windows $resdir/Templates/winload.reg
hivexregedit --merge --prefix BCD00000001 $tmpdir/BCD-Recovery $resdir/Templates/recovery.reg
hivexsh -w $tmpdir/BCD-Windows -f $tmpdir/winload.txt && hivexsh -w $tmpdir/BCD-Recovery -f $tmpdir/recovery.txt
echo "Copy the BCD hives to the ESP folders..."
sudo cp $tmpdir/BCD-Windows "$2"/EFI/Microsoft/Boot/BCD
sudo cp $tmpdir/BCD-Recovery "$2"/EFI/Microsoft/Recovery/BCD
}

update_winload () {
remove_duplicates "$1" "$2"
echo "Update current BCD stores with new entries..."
$resdir/winload.sh "$1" "$2" "$3" "$4" "$5" "$6" "$7" > $tmpdir/winload.txt && $resdir/recovery.sh "$2" "$4" "$7" > $tmpdir/recovery.txt
sudo hivexsh -w "$2/EFI/Microsoft/Boot/BCD" -f $tmpdir/winload.txt && sudo hivexsh -w "$2/EFI/Microsoft/Recovery/BCD" -f $tmpdir/recovery.txt
}

copy_bootmgr () {
echo "Copy the EFI boot files to the ESP..."
sudo mkdir -p "$2"/EFI/Microsoft/Recovery
sudo cp -r "$1"/Windows/Boot/EFI "$2"/EFI/Microsoft/Boot
sudo cp -r "$1"/Windows/Boot/Fonts "$2"/EFI/Microsoft/Boot
sudo cp -r "$1"/Windows/Boot/Resources "$2"/EFI/Microsoft/Boot
}

if [[ -z $(command -v hivexsh) ]]; then missing+=" hivex"; fi
if [[ -z $(command -v hivexregedit) ]]; then missing+=" hivexregedit"; fi
if [[ -z $(command -v peres) ]]; then missing+=" pev/peres"; fi
if [[ ! -z "$missing" ]]; then
   echo "The following packages are required:""$missing"
   exit 1
fi

if [[ $# -eq 0 ]]; then usage; fi

shopt -s nocasematch
while (( "$#" )); do
	case "$1" in
	    -f | --firmware )
	       shift
	       firmware="$1"
	       firmware=${firmware,,}
	       shift
	       ;;
	    -s | --syspath )
	       shift
	       syspath=$(echo "$1"| sed 's/\/\+$//')
	       setfwmod="true"
	       shift
	       ;;
	    -d | --wbmdefault )
	       prewbmdef="true"
	       shift
	       ;;
	    -n | --prodname )
	       shift
	       prodname="$1"
	       shift
	       ;;
	    -l | --locale )
	       shift
	       locale="$1"
	       locale=${locale,,}
	       shift
	       ;;
	    -c | --clean )
	       clean="true"
	       shift
	       ;;
	    -h | --help )
	       usage
	       ;;
	    * )
	       winpath=$(echo "$1"| sed 's/\/\+$//')
	       shift
	       ;;
	esac
done
shopt -u nocasematch

if  [[ -d "$winpath/Windows/Boot" ]]; then
    windisk=$(lsblk -o path,mountpoint | grep "$winpath" | awk '{print $1}' | sed 's/[0-9]\+$//')
else
    echo "Invalid source path please try again."
    exit 1
fi

if   [[ "$firmware" == "uefi" ]]; then
     if  [[ -z "$syspath" ]]; then
         echo "Checking block devices for ESP (sudo required)..."
         efipart=$(sudo sfdisk -o device,type -l "$windisk" | grep "EFI System" | awk '{print $1}')
         efidisk="$windisk"
         if [[ -z "$efipart" ]]; then
            efipart=$(sudo sfdisk -o device,type -l /dev/sda | grep "EFI System" | awk '{print $1}')
            efidisk="/dev/sda"
         fi
         if [[ -z "$efipart" ]]; then
            echo "Unable to locate ESP on $windisk or /dev/sda."
            echo "Use the --syspath option to specify a volume."
            exit 1
         fi
         syspath=$(lsblk -o path,mountpoint | grep "$efipart" | awk '{print $2}')
         if [[ -z "${syspath// }" ]]; then
            echo "Mounting ESP on $efipart"
            sudo mkdir -p /mnt/EFI && sudo mount $efipart /mnt/EFI
            syspath="/mnt/EFI"
         fi
     elif [[ ! -z "$syspath" && -d "$syspath" ]]; then
          efipart=$(lsblk -o path,mountpoint | grep "$syspath" | awk '{print $1}')
          efidisk=$(printf "$efipart" | sed 's/[0-9]\+$//')
     else
          echo "Invalid ESP path please try again."
          exit 1
     fi
     defbootpath="$syspath/EFI/BOOT/BOOTX64.efi"
     syswbmpath="$syspath/EFI/Microsoft/Boot/bootmgfw.efi"
     localwbmpath="$winpath/Windows/Boot/EFI/bootmgfw.efi"
     if [[ -f "$defbootpath" ]]; then
        defbootver=$(peres -v "$defbootpath" | grep 'Product Version:' | awk '{print $3}')
     fi
     if [[ -f "$syswbmpath" && -f "$localwbmpath" ]]; then
        syswbmver=$(peres -v "$syswbmpath" | grep 'Product Version:' | awk '{print $3}')
        localwbmver=$(peres -v "$localwbmpath" | grep 'Product Version:' | awk '{print $3}')
     fi
     if   [[ ! -f "$localwbmpath" ]]; then
          echo "Unable to find the EFI boot files at $winpath"
          exit 1
     elif [[ ! -f "$syswbmpath" ]]; then
          copy_bootmgr "$winpath" "$syspath"
          build_stores "$winpath" "$syspath" "$setfwmod" "$createbcd" "$prewbmdef" "$prodname" "$locale"
          wbmoptnum=$(efibootmgr | grep "Windows Boot Manager" | awk '{print $1}' | sed 's/Boot0*//;s/\*//')
          if [[ ! -z "$wbmoptnum" && "$setfwmod" == "false" ]]; then
             echo "Remove the current Windows Boot Manager option..."
             sudo efibootmgr -b "$wbmoptnum" -B > /dev/null
          fi
          if [[ "$setfwmod" == "false" ]]; then
             echo "Add the Windows Boot Manager to the firmware..."
             efinum=$(printf "$efipart" | sed 's/.*[a-z]//')
             wbmpath="\\EFI\\Microsoft\\Boot\\bootmgfw.efi"
             sudo efibootmgr -c -d "$efidisk" -p "$efinum" -l "$wbmpath" -L "Windows Boot Manager" -@ $resdir/Templates/wbmoptdata.bin > /dev/null
          fi
     elif [[ -f "$syswbmpath" && "$clean" == "true" ]]; then
          echo "Remove current main and recovery BCD stores..."
          sudo rm -f "$syspath"/EFI/Microsoft/Boot/BCD
          sudo rm -f "$syspath"/EFI/Microsoft/Recovery/BCD
          if [[ "$syswbmver" != "$localwbmver" && $(printf "$syswbmver\n$localwbmver\n" | sort -rV | head -1) == "$localwbmver" ]]; then
             if [[ -f "$defbootpath" && "$defbootver" == "$syswbmver" ]]; then
                sudo rm "$defbootpath"
             fi
             sudo rm -rf "$syspath/EFI/Microsoft" && copy_bootmgr "$winpath" "$syspath"
          fi
          build_stores "$winpath" "$syspath" "$setfwmod" "$createbcd" "$prewbmdef" "$prodname" "$locale"
     else
          createbcd="false"
          if [[ "$syswbmver" != "$localwbmver" && $(printf "$syswbmver\n$localwbmver\n" | sort -rV | head -1) == "$localwbmver" ]]; then
             if [[ -f "$defbootpath" && "$defbootver" == "$syswbmver" ]]; then
                sudo rm "$defbootpath"
             fi
             echo "Backup current BCD files before update..."
             sudo mv "$syspath/EFI/Microsoft/Boot/BCD" "$syspath/EFI/BCD-BOOT"
             sudo mv "$syspath/EFI/Microsoft/Recovery/BCD" "$syspath/EFI/BCD-RECOVERY"
             sudo rm -rf "$syspath/EFI/Microsoft" && copy_bootmgr "$winpath" "$syspath"
             echo "Restore current BCD files after update..."
             sudo mv "$syspath/EFI/BCD-BOOT" "$syspath/EFI/Microsoft/Boot/BCD"
             sudo mv "$syspath/EFI/BCD-RECOVERY" "$syspath/EFI/Microsoft/Recovery/BCD"
          fi
          update_winload "$winpath" "$syspath" "$setfwmod" "$createbcd" "$prewbmdef" "$prodname" "$locale"
     fi
     if [[ ! -f "$defbootpath" ]]; then
        echo "Copy bootmgfw.efi to default boot path..."
        sudo mkdir -p "$syspath"/EFI/BOOT
        sudo cp "$localwbmpath" "$defbootpath"
     fi
     if [[ "$syspath" == "/mnt/EFI" ]]; then
        echo "Removing temporary ESP mount point..."
        sudo umount "$syspath" && sudo rm -rf "$syspath"
     fi
elif [[ "$firmware" == "bios" ]]; then
     echo "Legacy booting not yet supported."
     exit 1
elif [[ "$firmware" != "uefi" && "$firmware" != "bios" ]]; then
     echo "Unknown firmware: Only UEFI or BIOS."
     exit 1
fi

echo "Clean up temporary files..."
rm -f $tmpdir/winload.txt $tmpdir/recovery.txt $tmpdir/BCD-Windows $tmpdir/BCD-Recovery
echo "Finished!"
