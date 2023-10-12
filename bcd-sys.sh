#!/usr/bin/bash

firmware=$(test -d /sys/firmware/efi && echo uefi || echo bios)
setfwmod="false"
createbcd="true"
prewbmdef="false"
setwbmlast="false"
locale="en-us"
clean="false"
virtual="false"
unloadnbd="false"
verbose="false"
resdir="."
tmpdir="."

RED='\033[1;31m'
BGTYELLOW='\033[1;93m'
NC='\033[0m' # No Color

usage () {
echo "Usage: $(basename $0) <source> [options] <system>"
echo
echo "<source>	  Path to Windows volume or VHDX file."
echo "<system>	  Mount point of the system partition."
echo
echo "-h, --help        Display full usage information."
exit 1
}

help () {
echo "Usage: $(basename $0) <source> [options] <system>"
echo
echo "Configure the boot environment for a Windows installation."
echo
echo "Options:"
echo
echo "<source>      	 Mount point of the Windows partition or path to"
echo "              	 a virtual disk (VHDX) file containing a Windows"
echo "              	 image. A list of partitions on the virtual disk"
echo "              	 will be displayed to assist making a selection."
echo "-f, --firmware	 Specify the firmware type as UEFI, BIOS or BOTH."
echo "-s, --syspath	 Mount point of the system partition. (Optional)"
echo "-d, --wbmdefault Preserve the existing default entry in {bootmgr}"
echo "                 this will be ignored when creating a new BCD store."
echo "-n, --prodname	 Specify the display name for the new OS entry"
echo "              	 otherwise use the product name from the registry."
echo "-l, --locale	 Specify the locale parameter. (Default is en-us)"
echo "-e, --addtoend   Add the Windows Boot Manager to the end of the"
echo "                 UEFI boot order otherwise it will be added first"
echo "                 when missing or creating new BCD stores. The WBM"
echo "                 position will be preserved by default when updating"
echo "                 existing BCD hives if already present."
echo "-v, --verbose    Display progress for all steps in the configuration"
echo "                 process and show loader/resume GUIDs of new entry."
echo "-c, --clean	 Remove existing BCD stores and create new entries."
echo "-h, --help	 Display this help message."
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
echo "is supported on GPT and MBR disks while BIOS or BOTH requires legacy"
echo "bootable MBR partitions with boot sectors created using a tool like"
echo "ms-sys. The Windows Boot Manager will be added to the UEFI firmware"
echo "boot menu except when using the --syspath option which must rely on"
echo "the default path at /EFI/BOOT/BOOTX64.efi"
exit
}

remove_duplicates () {
if   [[ "$3" == "uefi" ]]; then
     bcdpath="$2/EFI/Microsoft/Boot/BCD"
elif [[ "$3" == "bios" ]]; then
     bcdpath="$2/Boot/BCD"
fi
if   [[ "$virtual" == "true" ]]; then
     newdevstr=$($resdir/update_device.sh "$4" "$1" "$5" | sed 's/.*://;')
elif [[ "$virtual" == "false" ]]; then
     newdevstr=$($resdir/update_device.sh "$1" | sed 's/.*://;')
fi
newdevstr=${newdevstr,,}
ordscript="cd Objects\\{9dea862c-5cdd-4e70-acc1-f32b344d4795}\\\Elements\\\24000001\n"
rldrscript="cd Objects\\{9dea862c-5cdd-4e70-acc1-f32b344d4795}\\\Elements\\\23000006\n"

readarray -t objects <<< $(printf "cd Objects\nls\nq\n" | sudo hivexsh "$bcdpath")

for key in "${!objects[@]}"
do
	curdevstr=$(printf "cd Objects\\${objects[$key]}\\\Elements\\\11000001\nlsval\nq" | sudo hivexsh "$bcdpath" 2> /dev/null | sed 's/.*://;')
	if [[ "$curdevstr" == "$newdevstr" ]]; then
	   if [[ "$verbose" == "true" ]]; then echo "Remove entry at ${objects[$key]}"; fi
	   printf "cd Objects\\${objects[$key]}\ndel\ncommit\nunload\n" | sudo hivexsh -w "$bcdpath"
	   wbmdsporder=$(printf "$ordscript""lsval\nunload\n" | sudo hivexsh "$bcdpath" | sed 's/.*://;s/,//g')
	   guidstr=$(printf '%s\0' "${objects[$key]}" | hexdump -ve '/1 "%02x\0\0"')
	   if [[ "$wbmdsporder" == *"$guidstr"* ]]; then
	      if [[ "$verbose" == "true" ]]; then echo "Remove ${objects[$key]} from WBM display order."; fi
	      newdsporder=$(printf "%s" "$wbmdsporder" | sed "s/$guidstr//")
	      printf "$ordscript""setval 1\nElement\nhex:7:%s\ncommit\nunload\n" "$newdsporder" | sudo hivexsh -w "$bcdpath"
	   fi
	   wbmresldr=$(printf "$rldrscript""lsval\nunload\n" | sudo hivexsh "$bcdpath" | sed 's/.*=//;s/"//g')
	   if [[ "$wbmresldr" == "${objects[$key]}" ]]; then
	      if [[ "$verbose" == "true" ]]; then echo "Remove ${objects[$key]} from WBM resume object."; fi
	      printf "$rldrscript""setval 0\ncommit\nunload\n" | sudo hivexsh -w "$bcdpath"
	   fi	   
	fi
done
}

build_stores () {
if [[ "$verbose" == "true" ]]; then echo "Build the main BCD store..."; fi
$resdir/winload.sh "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" > $tmpdir/winload.txt
cp $resdir/Templates/BCD-NEW $tmpdir/BCD-Windows
hivexregedit --merge --prefix BCD00000001 $tmpdir/BCD-Windows $resdir/Templates/winload.reg
hivexsh -w $tmpdir/BCD-Windows -f $tmpdir/winload.txt
if   [[ "$3" == "uefi" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Build the recovery BCD store..."; fi
     $resdir/recovery.sh "$2" "$5" "$8" > $tmpdir/recovery.txt
     cp $resdir/Templates/BCD-NEW $tmpdir/BCD-Recovery
     hivexregedit --merge --prefix BCD00000001 $tmpdir/BCD-Recovery $resdir/Templates/recovery.reg
     hivexsh -w $tmpdir/BCD-Recovery -f $tmpdir/recovery.txt
     if [[ "$verbose" == "true" ]]; then echo "Copy the BCD hives to the ESP folders..."; fi
     sudo cp $tmpdir/BCD-Windows "$2"/EFI/Microsoft/Boot/BCD
     sudo cp $tmpdir/BCD-Recovery "$2"/EFI/Microsoft/Recovery/BCD
elif [[ "$3" == "bios" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Copy the main BCD hive to the boot folder..."; fi
     sudo cp $tmpdir/BCD-Windows "$2"/Boot/BCD
fi
}

update_winload () {
remove_duplicates "$1" "$2" "$3" "${11}" "${12}"
if [[ "$verbose" == "true" ]]; then echo "Update main BCD hive with new entries..."; fi
$resdir/winload.sh "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" > $tmpdir/winload.txt
if   [[ "$3" == "uefi" ]]; then
     sudo hivexsh -w "$2/EFI/Microsoft/Boot/BCD" -f $tmpdir/winload.txt
     if [[ "$verbose" == "true" ]]; then echo "Update recovery BCD hive with new entries..."; fi
     $resdir/recovery.sh "$2" "$5" "$8" > $tmpdir/recovery.txt
     sudo hivexsh -w "$2/EFI/Microsoft/Recovery/BCD" -f $tmpdir/recovery.txt
elif [[ "$3" == "bios" ]]; then
     sudo hivexsh -w "$2/Boot/BCD" -f $tmpdir/winload.txt
fi
}

copy_bootmgr () {
if   [[ "$3" == "uefi" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Copy the EFI boot files to the ESP..."; fi
     sudo mkdir -p "$2"/EFI/Microsoft/Recovery
     sudo cp -r "$1"/Windows/Boot/EFI "$2"/EFI/Microsoft/Boot
     sudo cp -r "$1"/Windows/Boot/Fonts "$2"/EFI/Microsoft/Boot
     sudo cp -r "$1"/Windows/Boot/Resources "$2"/EFI/Microsoft/Boot
elif [[ "$3" == "bios" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Copy the BIOS boot files to the system partition..."; fi
     sudo cp -r "$1"/Windows/Boot/PCAT "$2"/Boot
     sudo cp -r "$1"/Windows/Boot/Fonts "$2"/Boot
     sudo cp -r "$1"/Windows/Boot/Resources "$2"/Boot
     sudo mv "$2"/Boot/bootmgr "$2" && sudo mv "$2"/Boot/bootnxt "$2"/BOOTNXT
     if [[ "$4" == "ntfs" ]]; then
        if [[ "$verbose" == "true" ]]; then echo "Set extended NTFS attributes (Hidden/System/Read Only)..."; fi
        sudo setfattr -h -v 0x00000027 -n system.ntfs_attrib_be "$2"/bootmgr
        sudo setfattr -h -v 0x00040026 -n system.ntfs_attrib_be "$2"/BOOTNXT
        sudo setfattr -h -v 0x10000006 -n system.ntfs_attrib_be "$2"/Boot
     fi
     if [[ "$4" == "vfat" ]]; then
        if [[ "$verbose" == "true" ]]; then echo "Set filesystem attributes (Hidden/System/Read Only)..."; fi
        sudo fatattr +shr "$2"/bootmgr
        sudo fatattr +sh "$2"/BOOTNXT
        sudo fatattr +sh "$2"/Boot
     fi
fi
}

get_syspath () {
firmware="$1"
windisk="$2"

if   [[ "$firmware" == "uefi" ]]; then
     if [[ "$virtual" == "false" || "$verbose" == "true" ]]; then
        echo "Checking block devices for ESP (sudo required)..."
     fi
     efipart=$(sudo sfdisk -o device,type -l "$windisk" | grep "EFI" | awk '{print $1}')
     efidisk="$windisk"
     if [[ -z "$efipart" ]]; then
        efipart=$(sudo sfdisk -o device,type -l /dev/sda | grep "EFI" | awk '{print $1}')
        efidisk="/dev/sda"
     fi
     if [[ -z "$efipart" ]]; then
        echo -e "${RED}Unable to locate ESP on $windisk or /dev/sda.${NC}"
        echo "Use the --syspath option to specify a volume."
        exit 1
     fi
     syspath=$(lsblk -o path,mountpoint | grep "$efipart" | awk '{print $2}')
     if [[ -z "${syspath// }" ]]; then
        if [[ "$verbose" == "true" ]]; then echo "Mounting ESP on $efipart"; fi
        sudo mkdir -p /mnt/EFI && sudo mount $efipart /mnt/EFI
        syspath="/mnt/EFI"
     fi
elif [[ "$firmware" == "bios" || "$firmware" == "both" ]]; then
     if [[ "$virtual" == "false" || "$verbose" == "true" ]]; then
        echo "Checking block devices for active partition (sudo required)..."
     fi
     syspart=$(sudo sfdisk -o device,boot -l "$windisk" 2>/dev/null | grep -E '/dev/.*\*' | awk '{print $1}')
     errormsg=$(sudo sfdisk -o device,boot -l "$windisk" 2>&1>/dev/null)
     if [[ "$errormsg" == "sfdisk: gpt unknown column: boot" ]]; then
        echo -e "${BGTYELLOW}Windows disk $windisk is using GPT partition scheme.${NC}"
     fi
     if [[ -z "$syspart" ]]; then
        syspart=$(sudo sfdisk -o device,boot -l /dev/sda 2>/dev/null | grep -E '/dev/.*\*' | awk '{print $1}')
        errormsg=$(sudo sfdisk -o device,boot -l /dev/sda 2>&1>/dev/null)
        if [[ "$errormsg" == "sfdisk: gpt unknown column: boot" ]]; then
           echo -e "${BGTYELLOW}First block device (sda) is using GPT partition scheme.${NC}"
        fi
     fi
     if [[ -z "$syspart" ]]; then
        echo -e "${RED}No active partition on $windisk or /dev/sda.${NC}"
        echo "Use the --syspath option to specify a volume."
        exit 1
     fi
     if [[ "$firmware" == "both" ]]; then
        efipart="$syspart"
        efidisk=$(printf "$syspart" | sed 's/[0-9]\+$//')
     fi
     syspath=$(lsblk -o path,mountpoint | grep "$syspart" | awk '{print $2}')
     if [[ -z "${syspath// }" ]]; then
        if [[ "$verbose" == "true" ]]; then echo "Mounting active partition on $syspart"; fi
        sudo mkdir -p /mnt/winsys && sudo mount $syspart /mnt/winsys
        syspath="/mnt/winsys"
     fi
fi
}

get_device () {
firmware="$1"
syspath="$2"

if   [[ "$firmware" == "uefi" ]]; then
     if [[ "$virtual" == "false" || "$verbose" == "true" ]]; then
        echo "Get block device for mount point (sudo required later)..."
     fi
     efipart=$(lsblk -o path,mountpoint | grep "$syspath" | awk '{print $1}')
elif [[ "$firmware" == "bios" || "$firmware" == "both" ]]; then
     syspart=$(lsblk -o path,mountpoint | grep "$syspath" | awk '{print $1}')
     sysdisk=$(printf "$syspart" | sed 's/[0-9]\+$//')
     if [[ "$firmware" == "both" ]]; then efipart="$syspart"; fi
     if [[ "$virtual" == "false" || "$verbose" == "true" ]]; then
        echo "Checking block device for active partition (sudo required)..."
     fi
     actpart=$(sudo sfdisk -o device,boot -l "$sysdisk" | grep -E '/dev/.*\*' | awk '{print $1}')
     if   [[ -z "$actpart" ]]; then
          echo -e "${RED}No active partition on $sysdisk.${NC}"
          exit 1
     elif [[ "$syspart" != "$actpart" ]]; then
          echo -e "${RED}The volume $syspath on $syspart is not the active partition.${NC}"
          exit 1
     fi
fi
}

attach_vdisk () {
errormsg=$(modinfo nbd 2>&1>/dev/null)
if [[ -z $(command -v qemu-nbd) ]]; then missing+=" qemu-utils"; fi
if [[ "$errormsg" == "modinfo: ERROR: Module nbd not found." ]]; then missing+=" nbd-client"; fi
requirements_message
echo "Attach virtual disk to network block device (sudo required)..."
if ! lsmod | grep -wq nbd; then
   sudo modprobe nbd max_part=10
   unloadnbd="true"
fi
for x in /sys/class/block/nbd*; do
    S=$(cat $x/size)
    if [[ "$S" == "0" && ! -f "$x/pid" ]]; then
       vrtdisk="/dev/$(basename $x)"
       break
    fi
done
sudo qemu-nbd -c "$vrtdisk" "$imgpath"
}

mount_vpart () {
vrtpath="/mnt/virtwin"
mntopts="rw,nosuid,nodev,relatime,uid=$(id -u),gid=$(id -g),iocharset=utf8,windows_names"
echo "Partition table on: $imgpath"
echo
lsblk "$vrtdisk" -o path,pttype,fstype,parttypename,label,mountpoint | sed '2d'
echo
read -p "Enter device containing the Windows volume (ex. nbd0p1):" vtwinpart
while [[ "$vtwinpart" != *"nbd"* || ! -e "/dev/$vtwinpart" ]]; do
      echo -e "${BGTYELLOW}Invalid partition specified. Please try again.${NC}"
      read -p "Enter device containing the Windows volume (ex. nbd0p1):" vtwinpart
done
sudo mkdir -p "$vrtpath" && sudo mount -t ntfs3 -o"$mntopts" /dev/$vtwinpart "$vrtpath"
}

umount_vpart () {
if [[ "$verbose" == "true" ]]; then echo "Removing temporary VHDX mount point..."; fi
sudo umount "$vrtpath" && sudo rm -rf "$vrtpath"
if [[ "$verbose" == "true" ]]; then echo "Detach virtual disk from block device..."; fi
sudo qemu-nbd -d "$vrtdisk" > /dev/null
if [[ "$unloadnbd" == "true" ]]; then
   sleep 1 && sudo rmmod nbd
fi
}

get_wbmoption () {
wbmoptnum=$(efibootmgr | grep "Windows Boot Manager" | awk '{print $1}' | sed 's/Boot//;s/\*//')
}

create_wbmfwvar () {
if [[ "$verbose" == "true" ]]; then echo "Update main BCD with current WBM firware variable..."; fi
$resdir/wbmfwvar.sh $1 > $tmpdir/wbmfwvar.txt
sudo hivexsh -w "$2/EFI/Microsoft/Boot/BCD" -f $tmpdir/wbmfwvar.txt
}

cleanup () {
if [[ "$verbose" == "true" ]]; then echo "Clean up temporary files..."; fi
rm -f $tmpdir/winload.txt $tmpdir/recovery.txt $tmpdir/wbmfwvar.txt $tmpdir/BCD-Windows $tmpdir/BCD-Recovery
}

requirements_message () {
if [[ ! -z "$missing" ]]; then
   echo "The following packages are required:""$missing"
   exit 1
fi
}

if [[ $(uname) != "Linux" ]]; then echo "Unsupported platform detected."; exit 1; fi

if [[ $# -eq 0 ]]; then
usage
fi

if [[ -z $(command -v hivexsh) ]]; then missing+=" hivex"; fi
if [[ -z $(command -v hivexregedit) ]]; then missing+=" hivexregedit"; fi
if [[ -z $(command -v setfattr) ]]; then missing+=" attr/setfattr"; fi
if [[ -z $(command -v fatattr) ]]; then missing+=" fatattr"; fi
if [[ -z $(command -v peres) ]]; then missing+=" pev/peres"; fi
if [[ -z $(command -v xxd) ]]; then missing+=" xxd"; fi
requirements_message

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
	    -e | --addtoend )
	       setwbmlast="true"
	       shift
	       ;;
	    -v | --verbose )
	       verbose="true"
	       shift
	       ;;
	    -c | --clean )
	       clean="true"
	       shift
	       ;;
	    -h | --help )
	       help
	       ;;
	    * )
	       winpath=$(echo "$1"| sed 's/\/\+$//')
	       shift
	       ;;
	esac
done
shopt -u nocasematch

if [[ "$winpath" == *".vhdx"* && -f "$winpath" ]];then
   virtual="true"
   imgpath="$winpath"
   attach_vdisk
   sleep 1 && mount_vpart
fi

if   [[ -d "$winpath/Windows/Boot" ]]; then
     windisk=$(lsblk -o path,mountpoint | grep "$winpath" | awk '{print $1}' | sed 's/[0-9]\+$//')
elif [[ "$virtual" == "true" && -d "$vrtpath/Windows/Boot" ]]; then
     if [[ "$winpath" == *"/mnt"* ]]; then winpath=$(echo "$winpath" | cut -d/ -f1-3); fi
     if [[ "$winpath" == *"/media"* ]]; then winpath=$(echo "$winpath" | cut -d/ -f1-4); fi
     windisk=$(lsblk -o path,mountpoint | grep "$winpath" | awk '{print $1}' | sed 's/[0-9]\+$//')
     if [[ "$imgpath" == *"/mnt"* ]]; then imgstring=$(echo "$imgpath" | cut -d/ -f4- | sed 's/^/\\/;s/\//\\/g'); fi
     if [[ "$imgpath" == *"/media"* ]]; then imgstring=$(echo "$imgpath" | cut -d/ -f5- | sed 's/^/\\/;s/\//\\/g'); fi
else
    echo -e "${RED}Invalid source path please try again.${NC}"
    exit 1
fi

if  [[ "$firmware" != "uefi" && "$firmware" != "bios" && "$firmware" != "both" ]]; then
    echo -e "${RED}Unsupport firmware: Only UEFI, BIOS or BOTH.${NC}"
    exit 1
else
    if [[ "$firmware" == "uefi" || "$firmware" == "both" ]]; then
       if  [[ -z "$syspath" ]]; then
           get_syspath "$firmware" "$windisk"
       elif [[ ! -z "$syspath" && -d "$syspath" ]]; then
            get_device "$firmware" "$syspath"
       else
            echo -e "${RED}Invalid ESP path please try again.${NC}"
            exit 1
       fi
       fwmode="uefi"
       efibootvars="false"
       defbootpath="$syspath/EFI/BOOT/BOOTX64.efi"
       syswbmpath="$syspath/EFI/Microsoft/Boot/bootmgfw.efi"
       if  [[ "$virtual" == "true" ]]; then
           localwbmpath="$vrtpath/Windows/Boot/EFI/bootmgfw.efi"
       else
           localwbmpath="$winpath/Windows/Boot/EFI/bootmgfw.efi"
       fi
       efifstype=$(lsblk -o path,fstype | grep "$efipart" | awk '{print $2}')
       if [[ "$efifstype" != "vfat" ]]; then
          echo "Partition at $efipart is $efifstype format."
          if  [[ "$efifstype" == "ntfs" ]]; then
              echo -e "${BGTYELLOW}Disk may not be UEFI bootable on all systems.${NC}"
          else
              echo -e "${RED}ESP must be FAT or NTFS format.${NC}"
              exit 1
          fi
       fi
       if sudo test -f "$defbootpath"; then
          defbootver=$(sudo peres -v "$defbootpath" 2> /dev/null | grep 'Product Version:' | awk '{print $3}')
       fi
       if sudo test -f "$syswbmpath" && test -f "$localwbmpath"; then
          syswbmver=$(sudo peres -v "$syswbmpath" | grep 'Product Version:' | awk '{print $3}')
          localwbmver=$(peres -v "$localwbmpath" | grep 'Product Version:' | awk '{print $3}')
       fi
       if [[ ! -z $(command -v efibootmgr) ]]; then
          get_wbmoption && efibootvars="true"
          efinum=$(printf "$efipart" | sed 's/.*[a-z]//')
          wbmefipath="\\EFI\\Microsoft\\Boot\\bootmgfw.efi"
       fi
       if   [[ ! -f "$localwbmpath" ]]; then
            if  [[ "$virtual" == "true" ]]; then
                echo -e "${RED}Unable to find the EFI boot files at $vrtpath${NC}"
                umount_vpart
            else
                echo -e "${RED}Unable to find the EFI boot files at $winpath${NC}"
            fi
            if [[ "$syspath" == "/mnt/EFI" || "$syspath" == "/mnt/winsys" ]]; then
               if  [[ "$firmware" == "uefi" ]]; then
                   if [[ "$verbose" == "true" ]]; then echo "Removing temporary ESP mount point..."; fi
               else
                   if [[ "$verbose" == "true" ]]; then echo "Removing temporary system mount point..."; fi
               fi
               sudo umount "$syspath" && sudo rm -rf "$syspath"
            fi
            exit 1
       elif ! sudo test -f "$syswbmpath"; then
            if  [[ "$virtual" == "true" ]]; then
                copy_bootmgr "$vrtpath" "$syspath" "$fwmode"
            else
                copy_bootmgr "$winpath" "$syspath" "$fwmode"
            fi
            build_stores "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
            if [[ "$setfwmod" == "false" && "$efibootvars" == "true" ]]; then
               if [[ ! -z "$wbmoptnum" ]]; then
                  if [[ "$verbose" == "true" ]]; then echo "Remove the current Windows Boot Manager option..."; fi
                  sudo efibootmgr -b "$wbmoptnum" -B > /dev/null
               fi
               if [[ "$verbose" == "true" ]]; then echo "Add the Windows Boot Manager to the firmware..."; fi
               sudo efibootmgr -c -d "$efidisk" -p "$efinum" -l "$wbmefipath" -L "Windows Boot Manager" -@ $resdir/Templates/wbmoptdata.bin > /dev/null
               get_wbmoption && create_wbmfwvar "$wbmoptnum" "$syspath"
               if [[ "$setwbmlast" == "true" ]]; then
                  bootorder=$(efibootmgr | grep BootOrder: | awk '{print $2}' | sed "s/$wbmoptnum,//")
                  bootorder+=",$wbmoptnum"
                  sudo efibootmgr -o "$bootorder" > /dev/null
               fi
            fi
       elif sudo test -f "$syswbmpath" && [[ "$clean" == "true" ]]; then
            if [[ "$verbose" == "true" ]]; then echo "Remove current main and recovery BCD stores..."; fi
            sudo rm -f "$syspath"/EFI/Microsoft/Boot/BCD
            sudo rm -f "$syspath"/EFI/Microsoft/Recovery/BCD
            if [[ "$syswbmver" != "$localwbmver" && $(printf "$syswbmver\n$localwbmver\n" | sort -rV | head -1) == "$localwbmver" ]]; then
               if sudo test -f "$defbootpath" && [[ "$defbootver" == "$syswbmver" ]]; then
                  sudo rm "$defbootpath"
               fi
               sudo rm -rf "$syspath/EFI/Microsoft"
               if  [[ "$virtual" == "true" ]]; then
                   copy_bootmgr "$vrtpath" "$syspath" "$fwmode"
               else
                   copy_bootmgr "$winpath" "$syspath" "$fwmode"
               fi
            fi
            build_stores "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
            if [[ "$setfwmod" == "false" && "$efibootvars" == "true" ]]; then
               if [[ -z "$wbmoptnum" ]]; then
                  if [[ "$verbose" == "true" ]]; then echo "Add the Windows Boot Manager to the firmware..."; fi
                  sudo efibootmgr -c -d "$efidisk" -p "$efinum" -l "$wbmefipath" -L "Windows Boot Manager" -@ $resdir/Templates/wbmoptdata.bin > /dev/null
                  get_wbmoption
                  if [[ "$setwbmlast" == "true" ]]; then
                     bootorder=$(efibootmgr | grep BootOrder: | awk '{print $2}' | sed "s/$wbmoptnum,//")
                     bootorder+=",$wbmoptnum"
                     sudo efibootmgr -o "$bootorder" > /dev/null
                  fi
               fi
               create_wbmfwvar "$wbmoptnum" "$syspath"
            fi
       else
            createbcd="false"
            if [[ "$syswbmver" != "$localwbmver" && $(printf "$syswbmver\n$localwbmver\n" | sort -rV | head -1) == "$localwbmver" ]]; then
               if sudo test -f "$defbootpath" && [[ "$defbootver" == "$syswbmver" ]]; then sudo rm "$defbootpath"; fi
               if [[ "$verbose" == "true" ]]; then echo "Backup current BCD files before update..."; fi
               sudo mv "$syspath/EFI/Microsoft/Boot/BCD" "$syspath/EFI/BCD-BOOT"
               sudo mv "$syspath/EFI/Microsoft/Recovery/BCD" "$syspath/EFI/BCD-RECOVERY"
               sudo rm -rf "$syspath/EFI/Microsoft"
               if  [[ "$virtual" == "true" ]]; then
                   copy_bootmgr "$vrtpath" "$syspath" "$fwmode"
               else
                   copy_bootmgr "$winpath" "$syspath" "$fwmode"
               fi
               if [[ "$verbose" == "true" ]]; then echo "Restore current BCD files after update..."; fi
               sudo mv "$syspath/EFI/BCD-BOOT" "$syspath/EFI/Microsoft/Boot/BCD"
               sudo mv "$syspath/EFI/BCD-RECOVERY" "$syspath/EFI/Microsoft/Recovery/BCD"
            fi
            update_winload "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
            if [[ "$setfwmod" == "false" && "$efibootvars" == "true" && -z "$wbmoptnum" ]]; then
               if [[ "$verbose" == "true" ]]; then echo "Add the Windows Boot Manager to the firmware..."; fi
               sudo efibootmgr -c -d "$efidisk" -p "$efinum" -l "$wbmefipath" -L "Windows Boot Manager" -@ $resdir/Templates/wbmoptdata.bin > /dev/null
               get_wbmoption && create_wbmfwvar "$wbmoptnum" "$syspath"
               if [[ "$setwbmlast" == "true" ]]; then
                  bootorder=$(efibootmgr | grep BootOrder: | awk '{print $2}' | sed "s/$wbmoptnum,//")
                  bootorder+=",$wbmoptnum"
                  sudo efibootmgr -o "$bootorder" > /dev/null
               fi
            fi
       fi
       if ! sudo test -f "$defbootpath"; then
          if [[ "$verbose" == "true" ]]; then echo "Copy bootmgfw.efi to default boot path..."; fi
          sudo mkdir -p "$syspath"/EFI/BOOT
          sudo cp "$localwbmpath" "$defbootpath"
       fi
       if [[ "$syspath" == "/mnt/EFI" ]]; then
          if [[ "$verbose" == "true" ]]; then echo "Removing temporary ESP mount point..."; fi
          sudo umount "$syspath" && sudo rm -rf "$syspath"
       fi
       cleanup
       if [[ "$virtual" == "true" && "$firmware" == "uefi" ]]; then umount_vpart; fi
       echo "Finished configuring UEFI boot files."
    fi
    if [[ "$firmware" == "bios" || "$firmware" == "both" ]]; then
       if   [[ -z "$syspath" ]]; then
            get_syspath "$firmware" "$windisk"
       elif [[ ! -z "$syspath" && -d "$syspath" ]]; then
            if [[ "$firmware" == "bios" ]]; then
               get_device "$firmware" "$syspath"
            fi
       else
            echo -e "${RED}Invalid system path please try again.${NC}"
            exit 1
       fi
       fwmode="bios"
       sysbtmgr="false"
       sysuwfpath="$syspath/Boot/bootuwf.dll"
       sysvhdpath="$syspath/Boot/bootvhd.dll"
       if  [[ "$virtual" == "true" ]]; then
           localuwfpath="$vrtpath/Windows/Boot/PCAT/bootuwf.dll"
           localvhdpath="$vrtpath/Windows/Boot/PCAT/bootvhd.dll"
       else
           localuwfpath="$winpath/Windows/Boot/PCAT/bootuwf.dll"
           localvhdpath="$winpath/Windows/Boot/PCAT/bootvhd.dll"
       fi
       sysfstype=$(lsblk -o path,fstype | grep "$syspart" | awk '{print $2}')
       if [[ "$sysfstype" != "vfat" && "$sysfstype" != "ntfs" ]]; then
          echo "Active partition $syspart is $sysfstype format."
          echo -e "${RED}System partition must be FAT or NTFS format.${NC}"
          exit 1
       fi
       if  [[ -f "$localuwfpath" && -f "$localvhdpath" ]]; then
           localuwfver=$(peres -v "$localuwfpath" | grep 'Product Version:' | awk '{print $3}')
           localvhdver=$(peres -v "$localvhdpath" | grep 'Product Version:' | awk '{print $3}')
       else
           if  [[ "$virtual" == "true" ]]; then
               echo -e "${RED}Unable to find the BIOS boot files at $vrtpath${NC}"
               umount_vpart
           else
               echo -e "${RED}Unable to find the BIOS boot files at $winpath${NC}"
           fi
           if [[ "$syspath" == "/mnt/winsys" ]]; then
              if [[ "$verbose" == "true" ]]; then echo "Removing temporary system mount point..."; fi
              sudo umount "$syspath" && sudo rm -rf "$syspath"
           fi
           
           exit 1
       fi
       if sudo test -f "$sysuwfpath" && sudo test -f "$sysvhdpath"; then
          sysuwfver=$(sudo peres -v "$sysuwfpath" | grep 'Product Version:' | awk '{print $3}')
          sysvhdver=$(sudo peres -v "$sysvhdpath" | grep 'Product Version:' | awk '{print $3}')
          sysbtmgr="true"
       fi
       if ! sudo test -f "$sysuwfpath" && ! sudo test -f "$sysvhdpath"; then
          if  [[ "$virtual" == "true" ]]; then
              copy_bootmgr "$vrtpath" "$syspath" "$fwmode" "$sysfstype"
          else
              copy_bootmgr "$winpath" "$syspath" "$fwmode" "$sysfstype"
          fi
          build_stores "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
       elif [[ "$sysbtmgr" == "true" && "$clean" == "true" ]]; then
            if [[ "$verbose" == "true" ]]; then echo "Remove current BCD store..."; fi
            sudo rm -f "$syspath"/Boot/BCD
            if [[ "$sysuwfver" != "$localuwfver" || "$sysvhdver" != "$localvhdver" ]]; then
               if [[ $(printf "$sysuwfver\n$localuwfver\n" | sort -rV | head -1) == "$localuwfver" ||
                     $(printf "$sysvhdver\n$localvhdver\n" | sort -rV | head -1) == "$localvhdver" ]]; then
                  sudo rm -rf "$syspath/Boot" && sudo rm -f "$syspath/bootmgr $syspath/bootnxt"
                  if  [[ "$virtual" == "true" ]]; then
                      copy_bootmgr "$vrtpath" "$syspath" "$fwmode" "$sysfstype"
                  else
                      copy_bootmgr "$winpath" "$syspath" "$fwmode" "$sysfstype"
                  fi
               fi
            fi
            build_stores "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
       else
            createbcd="false"
            if [[ "$sysuwfver" != "$localuwfver" || "$sysvhdver" != "$localvhdver" ]]; then
               if [[ $(printf "$sysuwfver\n$localuwfver\n" | sort -rV | head -1) == "$localuwfver" ||
                     $(printf "$sysvhdver\n$localvhdver\n" | sort -rV | head -1) == "$localvhdver" ]]; then
                  if [[ "$verbose" == "true" ]]; then echo "Backup current BCD store before update..."; fi
                  sudo mv "$syspath/Boot/BCD" "$syspath"
                  sudo rm -rf "$syspath/Boot" && sudo rm -f "$syspath/bootmgr $syspath/bootnxt"
                  if  [[ "$virtual" == "true" ]]; then
                      copy_bootmgr "$vrtpath" "$syspath" "$fwmode" "$sysfstype"
                  else
                      copy_bootmgr "$winpath" "$syspath" "$fwmode" "$sysfstype"
                  fi
                  if [[ "$verbose" == "true" ]]; then echo "Restore current BCD store after update..."; fi
                  sudo mv "$syspath/BCD" "$syspath/Boot"
               fi
            fi
            update_winload "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
       fi
       if [[ "$syspath" == "/mnt/winsys" ]]; then
          if [[ "$verbose" == "true" ]]; then echo "Removing temporary system mount point..."; fi
          sudo umount "$syspath" && sudo rm -rf "$syspath"
       fi
       cleanup
       if [[ "$virtual" == "true" ]]; then umount_vpart; fi
       echo "Finished configuring BIOS boot files."
    fi
fi
