#!/usr/bin/bash

# bcd-sys.sh - main script
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

firmware=$(test -d /sys/firmware/efi && echo uefi || echo bios)
mntopts="rw,nosuid,nodev,relatime,uid=$(id -u),gid=$(id -g),iocharset=utf8,windows_names"
setfwmod="false"
createbcd="true"
prewbmdef="false"
setwbmlast="false"
locale="en-us"
clean="false"
virtual="false"
rmsysmnt="false"
unloadnbd="false"
verbose="false"
resdir="."
tmpdir="."

RED='\033[1;31m'
BGTYELLOW='\033[1;93m'
NC='\033[0m' # No Color

# Show basic usage.
usage () {
echo "Usage: $(basename $0) <source> [options] <system>"
echo
echo "<source>	  Path to Windows volume or VHDX file."
echo "<system>	  Mount point of the system partition."
echo
echo "-h, --help        Display full usage information."
exit 1
}

# Show full help.
help () {
echo "Usage: $(basename $0) <source> [options] <system>"
echo
cat $resdir/Resources/help-page.txt
echo
exit
}

# Remove existing boot loader and resume entries for matching device (11000001).
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

# Build main and recovery stores using blank BCD-NEW file and reg templates.
build_stores () {
if [[ "$verbose" == "true" ]]; then echo "Build the main BCD store..."; fi
$resdir/winload.sh "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" > $tmpdir/winload.txt
cp $resdir/Templates/BCD-NEW $tmpdir/BCD-Windows
hivexregedit --merge --prefix BCD00000001 $tmpdir/BCD-Windows $resdir/Templates/winload.reg
hivexsh -w $tmpdir/BCD-Windows -f $tmpdir/winload.txt
if [[ ! $? -eq 0 ]]; then
   echo -e "${RED}Failed to create main BCD store.${NC}"
   return 1
fi
if   [[ "$3" == "uefi" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Build the recovery BCD store..."; fi
     $resdir/recovery.sh "$2" "$5" "$8" > $tmpdir/recovery.txt
     cp $resdir/Templates/BCD-NEW $tmpdir/BCD-Recovery
     hivexregedit --merge --prefix BCD00000001 $tmpdir/BCD-Recovery $resdir/Templates/recovery.reg
     hivexsh -w $tmpdir/BCD-Recovery -f $tmpdir/recovery.txt
     if [[ ! $? -eq 0 ]]; then
        echo -e "${RED}Failed to create recovery BCD store.${NC}"
        return 1
     fi
     if [[ "$verbose" == "true" ]]; then echo "Copy the BCD hives to the ESP folders..."; fi
     sudo cp $tmpdir/BCD-Windows "$2"/EFI/Microsoft/Boot/BCD
     if [[ ! $? -eq 0 ]]; then
        echo -e "${RED}Failed to copy main hive to the ESP.${NC}"
        return 1
     fi
     sudo cp $tmpdir/BCD-Recovery "$2"/EFI/Microsoft/Recovery/BCD
     if [[ ! $? -eq 0 ]]; then
        echo -e "${RED}Failed to copy recovery hive to the ESP.${NC}"
        return 1
     fi
elif [[ "$3" == "bios" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Copy the main BCD hive to the boot folder..."; fi
     sudo cp $tmpdir/BCD-Windows "$2"/Boot/BCD
     if [[ ! $? -eq 0 ]]; then
        echo -e "${RED}Failed to copy main hive to the system partition.${NC}"
        return 1
     fi
fi
return 0
}

# Build new Windows entry and update existing BCD stores.
update_winload () {
remove_duplicates "$1" "$2" "$3" "${11}" "${12}"
if [[ "$verbose" == "true" ]]; then echo "Update main BCD hive with new entries..."; fi
$resdir/winload.sh "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" > $tmpdir/winload.txt
if   [[ "$3" == "uefi" ]]; then
     sudo hivexsh -w "$2/EFI/Microsoft/Boot/BCD" -f $tmpdir/winload.txt
     if [[ ! $? -eq 0 ]]; then
        echo -e "${RED}Failed to update main BCD store.${NC}"
        return 1
     fi
     if [[ "$verbose" == "true" ]]; then echo "Update recovery BCD hive with new entries..."; fi
     $resdir/recovery.sh "$2" "$5" "$8" > $tmpdir/recovery.txt
     sudo hivexsh -w "$2/EFI/Microsoft/Recovery/BCD" -f $tmpdir/recovery.txt
     if [[ ! $? -eq 0 ]]; then
        echo -e "${RED}Failed to update recovery BCD store.${NC}"
        return 1
     fi
elif [[ "$3" == "bios" ]]; then
     sudo hivexsh -w "$2/Boot/BCD" -f $tmpdir/winload.txt
     if [[ ! $? -eq 0 ]]; then
        echo -e "${RED}Failed to update main BCD store.${NC}"
        return 1
     fi
fi
return 0
}

# Copy the WBM files for the specified firmware and set the file attributes the same as bcdboot.
copy_bootmgr () {
if   [[ "$3" == "uefi" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Copy the EFI boot files to the ESP..."; fi
     sudo mkdir -p "$2"/EFI/Microsoft/Recovery
     sudo cp -r "$1"/Windows/Boot/EFI "$2"/EFI/Microsoft/Boot
     sudo cp -r "$1"/Windows/Boot/Fonts "$2"/EFI/Microsoft/Boot
     if sudo test -d "$1"/Windows/Boot/Resources; then
        sudo cp -r "$1"/Windows/Boot/Resources "$2"/EFI/Microsoft/Boot
     fi
elif [[ "$3" == "bios" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Copy the BIOS boot files to the system partition..."; fi
     sudo cp -r "$1"/Windows/Boot/PCAT "$2"/Boot
     sudo cp -r "$1"/Windows/Boot/Fonts "$2"/Boot
     if sudo test -d "$1"/Windows/Boot/Resources; then
        sudo cp -r "$1"/Windows/Boot/Resources "$2"/Boot
     fi
     sudo mv "$2"/Boot/bootmgr "$2"
     if sudo test -f "$1"/Windows/Boot/PCAT/bootnxt; then
        sudo mv "$2"/Boot/bootnxt "$2"/BOOTNXT
     fi
     if [[ "$4" == "ntfs" ]]; then
        if [[ "$verbose" == "true" ]]; then echo "Set extended NTFS attributes (Hidden/System/Read Only)..."; fi
        sudo setfattr -h -v 0x00000027 -n system.ntfs_attrib_be "$2"/bootmgr
        if sudo test -f "$1"/Windows/Boot/PCAT/bootnxt; then
           sudo setfattr -h -v 0x00040026 -n system.ntfs_attrib_be "$2"/BOOTNXT
        fi
        sudo setfattr -h -v 0x10000006 -n system.ntfs_attrib_be "$2"/Boot
     fi
     if [[ "$4" == "vfat" ]]; then
        if [[ "$verbose" == "true" ]]; then echo "Set filesystem attributes (Hidden/System/Read Only)..."; fi
        sudo fatattr +shr "$2"/bootmgr
        if sudo test -f "$1"/Windows/Boot/PCAT/bootnxt; then
           sudo fatattr +sh "$2"/BOOTNXT
        fi
        sudo fatattr +sh "$2"/Boot
     fi
fi
}

# Used when no syspath is specified in the arguments.
# Look for a system partition on the Windows disk, the first block device, or the root device.
# Check for compatibility between the partition scheme and firmware mode.
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
        rootdisk=$(findmnt -n -o SOURCE / | sed 's/[0-9]\+$//;s/p\+$//')
        if [[ "$rootdisk" != "$windisk" && "$rootdisk" != "/dev/sda" ]]; then
           efipart=$(sudo sfdisk -o device,type -l "$rootdisk" | grep "EFI" | awk '{print $1}')
           efidisk="$rootdisk"
        fi
     fi
     if [[ -z "$efipart" ]]; then
        echo -e "${RED}Unable to locate an EFI System Partition.${NC}"
        echo "Use the --syspath option to specify a volume."
        if [[ "$virtual" == "true" ]]; then umount_vpart; fi
        exit 1
     fi
     efifstype=$(lsblk -o path,fstype | grep "$efipart" | awk '{print $2}' | uniq)
     syspath=$(lsblk -o path,mountpoint | grep "$efipart" | awk -v n=2 '{ for (i=n; i<=NF; i++) printf "%s%s", $i, (i<NF ? OFS : ORS)}' | uniq)
     if [[ -z "${syspath// }" ]]; then
        rmsysmnt="true"
        syspath="/mnt/EFI"
        sudo mkdir -p $syspath
        if [[ "$verbose" == "true" ]]; then echo "Mounting ESP on $efipart"; fi
        if  [[ "$efifstype" == "ntfs" ]]; then
            sudo mount -t ntfs3 -o"$mntopts" $efipart $syspath
        else
            sudo mount $efipart $syspath
        fi
     fi
elif [[ "$firmware" == "bios" || "$firmware" == "both" ]]; then
     if [[ "$virtual" == "false" || "$verbose" == "true" ]]; then
        echo "Checking block devices for active partition (sudo required)..."
     fi
     syspart=$(sudo sfdisk -o device,boot -l "$windisk" 2>/dev/null | grep -E '/dev/.*\*' | awk '{print $1}')
     errormsg=$(sudo sfdisk -o device,boot -l "$windisk" 2>&1>/dev/null)
     if [[ "$errormsg" == "sfdisk: gpt unknown column: boot" ]]; then
        if [[ "$virtual" == "true" ]]; then umount_vpart; fi
        echo -e "${BGTYELLOW}Windows disk $windisk is using GPT partition scheme.${NC}"
        echo -e "${RED}This configuration is not compatible with Windows in BIOS mode.${NC}"
        exit 1
     fi
     if [[ -z "$syspart" ]]; then
        syspart=$(sudo sfdisk -o device,boot -l /dev/sda 2>/dev/null | grep -E '/dev/.*\*' | awk '{print $1}')
        errormsg=$(sudo sfdisk -o device,boot -l /dev/sda 2>&1>/dev/null)
        if [[ "$errormsg" == "sfdisk: gpt unknown column: boot" ]]; then
           echo -e "${BGTYELLOW}First block device (sda) is using GPT partition scheme.${NC}"
        fi
     fi
     if [[ -z "$syspart" ]]; then
        rootdisk=$(findmnt -n -o SOURCE / | sed 's/[0-9]\+$//;s/p\+$//')
        if [[ "$rootdisk" != "$windisk" && "$rootdisk" != "/dev/sda" ]]; then
           syspart=$(sudo sfdisk -o device,boot -l "$rootdisk" 2>/dev/null | grep -E '/dev/.*\*' | awk '{print $1}')
           errormsg=$(sudo sfdisk -o device,boot -l "$rootdisk" 2>&1>/dev/null)
           if [[ "$errormsg" == "sfdisk: gpt unknown column: boot" ]]; then
              echo -e "${BGTYELLOW}Root device $rootdisk is using GPT partition scheme.${NC}"
           fi
        fi
     fi
     if [[ -z "$syspart" ]]; then
        echo -e "${RED}Unable to locate an active partition.${NC}"
        echo "Use the --syspath option to specify a volume."
        if [[ "$virtual" == "true" ]]; then umount_vpart; fi
        exit 1
     fi
     sysfstype=$(lsblk -o path,fstype | grep "$syspart" | awk '{print $2}' | uniq)
     syspath=$(lsblk -o path,mountpoint | grep "$syspart" | awk -v n=2 '{ for (i=n; i<=NF; i++) printf "%s%s", $i, (i<NF ? OFS : ORS)}' | uniq)
     if [[ -z "${syspath// }" ]]; then
        rmsysmnt="true"
        syspath="/mnt/winsys"
        sudo mkdir -p $syspath
        if [[ "$verbose" == "true" ]]; then echo "Mounting active partition on $syspart"; fi
        if  [[ "$sysfstype" == "ntfs" ]]; then
            sudo mount -t ntfs3 -o"$mntopts" $syspart $syspath
        else
            sudo mount $syspart $syspath
        fi
     fi
     if [[ "$firmware" == "both" ]]; then
        efipart="$syspart"
        efifstype="$sysfstype"
        efidisk=$(printf "$efipart" | sed 's/[0-9]\+$//;s/p\+$//')
     fi
fi
}

# Used when a syspath is provided in the arguments.
# Find the block device (and active partition if BIOS/BOTH) for the specified mount point.
# Check for compatibility between the partition scheme and firmware mode.
get_device () {
firmware="$1"
syspath="$2"

if   [[ "$firmware" == "uefi" ]]; then
     if [[ "$virtual" == "false" || "$verbose" == "true" ]]; then
        echo "Get block device for mount point (sudo required later)..."
     fi
     efipart=$(lsblk -o path,mountpoint | grep "$syspath" | awk '{print $1}' | uniq)
     efifstype=$(lsblk -o path,fstype | grep "$efipart" | awk '{print $2}' | uniq)
elif [[ "$firmware" == "bios" || "$firmware" == "both" ]]; then
     syspart=$(lsblk -o path,mountpoint | grep "$syspath" | awk '{print $1}' | uniq)
     sysdisk=$(printf "$syspart" | sed 's/[0-9]\+$//;s/p\+$//')
     if [[ "$virtual" == "false" || "$verbose" == "true" ]]; then
        echo "Checking block device for active partition (sudo required)..."
     fi
     errormsg=$(sudo sfdisk -o device,boot -l "$windisk" 2>&1>/dev/null)
     if [[ "$errormsg" == "sfdisk: gpt unknown column: boot" ]]; then
        if [[ "$virtual" == "true" ]]; then umount_vpart; fi
        echo -e "${BGTYELLOW}Windows disk $windisk is using GPT partition scheme.${NC}"
        echo -e "${RED}This configuration is not compatible with Windows in BIOS mode.${NC}"
        exit 1
     fi
     actpart=$(sudo sfdisk -o device,boot -l "$sysdisk" 2>/dev/null | grep -E '/dev/.*\*' | awk '{print $1}')
     errormsg=$(sudo sfdisk -o device,boot -l "$sysdisk" 2>&1>/dev/null)
     if [[ "$errormsg" == "sfdisk: gpt unknown column: boot" ]]; then
        if [[ "$virtual" == "true" ]]; then umount_vpart; fi
        echo -e "${BGTYELLOW}System disk $sysdisk is using GPT partition scheme.${NC}"
        echo -e "${RED}This configuration is not compatible with Windows in BIOS mode.${NC}"
        exit 1
     fi
     if   [[ -z "$actpart" ]]; then
          echo -e "${RED}No active partition on $sysdisk.${NC}"
          if [[ "$virtual" == "true" ]]; then umount_vpart; fi
          exit 1
     elif [[ "$syspart" != "$actpart" ]]; then
          echo -e "${RED}The volume $syspath on $syspart is not the active partition.${NC}"
          if [[ "$virtual" == "true" ]]; then umount_vpart; fi
          exit 1
     fi
     sysfstype=$(lsblk -o path,fstype | grep "$syspart" | awk '{print $2}' | uniq)
     if [[ "$firmware" == "both" ]]; then
        efipart="$syspart"
        efifstype="$sysfstype"
     fi
fi
}

# Load the NBD module if needed then find a free block device to use.
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

# Display partitions on virtual disk and mount the specified volume.
mount_vpart () {
vrtpath="/mnt/virtwin"
echo "Partition table on: $imgpath"
echo
lsblk "$vrtdisk" -o path,pttype,fstype,parttypename,label,mountpoint | sed '2d' | uniq
echo
read -p "Enter device containing the Windows volume [nbd#p#]:" vtwinpart
while [[ "$vtwinpart" != *"nbd"* || ! -e "/dev/$vtwinpart" ]]; do
      echo -e "${BGTYELLOW}Invalid partition specified. Please try again.${NC}"
      read -p "Enter device containing the Windows volume [nbd#p#]:" vtwinpart
done
sudo mkdir -p "$vrtpath" && sudo mount -t ntfs3 -o"$mntopts" /dev/$vtwinpart "$vrtpath"
}

# Unmount volume and detach virtual disk then unload NBD module if no longer needed.
umount_vpart () {
if [[ "$verbose" == "true" ]]; then echo "Removing temporary VHDX mount point..."; fi
sudo umount "$vrtpath" && sudo rm -rf "$vrtpath"
if [[ "$verbose" == "true" ]]; then echo "Detach virtual disk from block device..."; fi
sudo qemu-nbd -d "$vrtdisk" > /dev/null
if [[ "$unloadnbd" == "true" ]]; then
   sleep 1 && sudo rmmod nbd
fi
}

# Unmount the EFI or Windows System Partition mounted automatically by get_syspath.
umount_system () {
if   [[ "$syspath" == "/mnt/EFI" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Removing temporary ESP mount point..."; fi
elif [[ "$syspath" == "/mnt/winsys" ]]; then
     if [[ "$verbose" == "true" ]]; then echo "Removing temporary system mount point..."; fi
fi
sudo umount "$syspath" && sudo rm -rf "$syspath"
}

# Check for the WBM in the current firmware boot options.
get_wbmoption () {
wbmoptnum=$(efibootmgr | grep "Windows Boot Manager" | awk '{print $1}' | sed 's/Boot//;s/\*//')
}

# Update the WBM firmware option and device data in the BCD entry.
create_wbmfwvar () {
if [[ "$verbose" == "true" ]]; then echo "Update main BCD with current WBM firware variable..."; fi
$resdir/wbmfwvar.sh $1 > $tmpdir/wbmfwvar.txt
sudo hivexsh -w "$2/EFI/Microsoft/Boot/BCD" -f $tmpdir/wbmfwvar.txt
}

# Remove hivexsh scripts and BCD files created during the build process.
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

# Script starts here.
if [[ $(uname) != "Linux" ]]; then echo "Unsupported platform detected."; exit 1; fi

if [[ $# -eq 0 ]]; then
usage
fi

# Check for required packages that are missing.
if [[ -z $(command -v hivexsh) ]]; then missing+=" hivex"; fi
if [[ -z $(command -v hivexregedit) ]]; then missing+=" hivexregedit"; fi
if [[ -z $(command -v setfattr) ]]; then missing+=" attr/setfattr"; fi
if [[ -z $(command -v fatattr) ]]; then missing+=" fatattr"; fi
if [[ -z $(command -v peres) ]]; then missing+=" pev/peres"; fi
if [[ -z $(command -v xxd) ]]; then missing+=" xxd"; fi
requirements_message

# Create symlinks to Resources and Templates folder if needed.
if [[ "$resdir" == "." ]]; then
   if [[ ! -d "$resdir/Resources" && ! -d "$resdir/Templates" ]]; then
      ln -s ../Resources && ln -s ../Templates
   fi
fi

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

# Check if source is a virtual disk file.
if [[ "$winpath" == *".vhdx"* && -f "$winpath" ]];then
   virtual="true"
   imgpath="$winpath"
   attach_vdisk
   sleep 1 && mount_vpart
fi

# Check source for path to the WBM files then get the block device.
# Get the mount point, file path and block device that contains the virtual disk file.
if   [[ -d "$winpath/Windows/Boot" ]]; then
     windisk=$(lsblk -o path,mountpoint | grep "$winpath" | awk '{print $1}' | sed 's/[0-9]\+$//;s/p\+$//' | uniq)
elif [[ "$virtual" == "true" && -d "$vrtpath/Windows/Boot" ]]; then
     if [[ "$winpath" == *"/mnt"* ]]; then winpath=$(echo "$winpath" | cut -d/ -f1-3); fi
     if [[ "$winpath" == *"/media"* ]]; then winpath=$(echo "$winpath" | cut -d/ -f1-4); fi
     windisk=$(lsblk -o path,mountpoint | grep "$winpath" | awk '{print $1}' | sed 's/[0-9]\+$//;s/p\+$//' | uniq)
     if [[ "$imgpath" == *"/mnt"* ]]; then imgstring=$(echo "$imgpath" | cut -d/ -f4- | sed 's/^/\\/;s/\//\\/g'); fi
     if [[ "$imgpath" == *"/media"* ]]; then imgstring=$(echo "$imgpath" | cut -d/ -f5- | sed 's/^/\\/;s/\//\\/g'); fi
else
    echo -e "${RED}Invalid source path please try again.${NC}"
    if  [[ "$virtual" == "true" ]]; then umount_vpart; fi
    exit 1
fi

# Perform the actions appropriate for the specified firmware type.
# Compare the WBM product versions of the source and system volumes.
# Copy the boot files if missing or older than the source version.
# Create new BCD stores or update existing ones with new entries.
# Create a WBM firmware entry in the first or last position when needed.
# Unmount the virtual disk and remove the temporary hive scripts/files.
if  [[ "$firmware" != "uefi" && "$firmware" != "bios" && "$firmware" != "both" ]]; then
    echo -e "${RED}Unsupport firmware: Only UEFI, BIOS or BOTH.${NC}"
    if  [[ "$virtual" == "true" ]]; then umount_vpart; fi
    exit 1
else
    if [[ -f $tmpdir/winload.txt || -f $tmpdir/recovery.txt || -f $tmpdir/wbmfwvar.txt || \
          -f $tmpdir/BCD-Windows || -f $tmpdir/BCD-Recovery ]]; then
       cleanup
    fi
    if [[ "$firmware" == "uefi" || "$firmware" == "both" ]]; then
       if  [[ -z "$syspath" ]]; then
           get_syspath "$firmware" "$windisk"
       elif [[ ! -z "$syspath" && -d "$syspath" ]]; then
            get_device "$firmware" "$syspath"
       else
            echo -e "${RED}Invalid ESP path please try again.${NC}"
            if  [[ "$virtual" == "true" ]]; then umount_vpart; fi
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
       if [[ "$efifstype" != "vfat" ]]; then
          echo "Partition at $efipart is $efifstype format."
          if  [[ "$efifstype" == "ntfs" ]]; then
              echo -e "${BGTYELLOW}Disk may not be UEFI bootable on all systems.${NC}"
          else
              echo -e "${RED}ESP must be FAT or NTFS format.${NC}"
              if [[ "$virtual" == "true" ]]; then umount_vpart; fi
              if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
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
            if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
            exit 1
       elif ! sudo test -f "$syswbmpath"; then
            if  [[ "$virtual" == "true" ]]; then
                copy_bootmgr "$vrtpath" "$syspath" "$fwmode"
            else
                copy_bootmgr "$winpath" "$syspath" "$fwmode"
            fi
            build_stores "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" \
                         "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
            if [[ ! $? -eq 0 ]]; then
               if [[ "$virtual" == "true" ]]; then umount_vpart; fi
               if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
               exit 1
            fi
            if [[ "$setfwmod" == "false" && "$efibootvars" == "true" ]]; then
               if [[ ! -z "$wbmoptnum" ]]; then
                  if [[ "$verbose" == "true" ]]; then echo "Remove the current Windows Boot Manager option..."; fi
                  sudo efibootmgr -b "$wbmoptnum" -B > /dev/null
               fi
               if [[ "$verbose" == "true" ]]; then echo "Add the Windows Boot Manager to the firmware..."; fi
               sudo efibootmgr -c -d "$efidisk" -p "$efinum" -l "$wbmefipath" -L "Windows Boot Manager" \
                               -@ $resdir/Templates/wbmoptdata.bin > /dev/null
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
            build_stores "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" \
                         "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
            if [[ ! $? -eq 0 ]]; then
               if [[ "$virtual" == "true" ]]; then umount_vpart; fi
               if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
               exit 1
            fi
            if [[ "$setfwmod" == "false" && "$efibootvars" == "true" ]]; then
               if [[ -z "$wbmoptnum" ]]; then
                  if [[ "$verbose" == "true" ]]; then echo "Add the Windows Boot Manager to the firmware..."; fi
                  sudo efibootmgr -c -d "$efidisk" -p "$efinum" -l "$wbmefipath" -L "Windows Boot Manager" \
                                  -@ $resdir/Templates/wbmoptdata.bin > /dev/null
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
            update_winload "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" \
                           "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
            if [[ ! $? -eq 0 ]]; then
               if [[ "$virtual" == "true" ]]; then umount_vpart; fi
               if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
               exit 1
            fi
            if [[ "$setfwmod" == "false" && "$efibootvars" == "true" && -z "$wbmoptnum" ]]; then
               if [[ "$verbose" == "true" ]]; then echo "Add the Windows Boot Manager to the firmware..."; fi
               sudo efibootmgr -c -d "$efidisk" -p "$efinum" -l "$wbmefipath" -L "Windows Boot Manager" \
                               -@ $resdir/Templates/wbmoptdata.bin > /dev/null
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
       if [[ "$rmsysmnt" == "true" && "$firmware" == "uefi" ]]; then umount_system; fi
       if [[ "$virtual" == "true" && "$firmware" == "uefi" ]]; then umount_vpart; fi
       cleanup
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
            if  [[ "$virtual" == "true" ]]; then umount_vpart; fi
            exit 1
       fi
       fwmode="bios"
       sysbtmgr="false"
       sysuwfpath="$syspath/Boot/bootuwf.dll"
       sysvhdpath="$syspath/Boot/bootvhd.dll"
       sysmempath="$syspath/Boot/memtest.exe"
       if  [[ "$virtual" == "true" ]]; then
           localuwfpath="$vrtpath/Windows/Boot/PCAT/bootuwf.dll"
           localvhdpath="$vrtpath/Windows/Boot/PCAT/bootvhd.dll"
           localmempath="$vrtpath/Windows/Boot/PCAT/memtest.exe"
           localmgrpath="$vrtpath/Windows/Boot/PCAT/bootmgr"
       else
           localuwfpath="$winpath/Windows/Boot/PCAT/bootuwf.dll"
           localvhdpath="$winpath/Windows/Boot/PCAT/bootvhd.dll"
           localmempath="$winpath/Windows/Boot/PCAT/memtest.exe"
           localmgrpath="$winpath/Windows/Boot/PCAT/bootmgr"
       fi
       if [[ "$sysfstype" != "vfat" && "$sysfstype" != "ntfs" ]]; then
          echo "Active partition $syspart is $sysfstype format."
          echo -e "${RED}System partition must be FAT or NTFS format.${NC}"
          if [[ "$virtual" == "true" ]]; then umount_vpart; fi
          if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
          exit 1
       fi
       if   [[ -f "$localmgrpath" && -f "$localuwfpath" && -f "$localvhdpath" ]]; then
            localuwfver=$(peres -v "$localuwfpath" | grep 'Product Version:' | awk '{print $3}')
            localvhdver=$(peres -v "$localvhdpath" | grep 'Product Version:' | awk '{print $3}')
       elif [[ -f "$localmgrpath" && -f "$localmempath" ]]; then
            localmemver=$(peres -v "$localmempath" | grep 'Product Version:' | awk '{print $3}')
            localuwfver="NULL"
            localvhdver="NULL"
       else
           if  [[ "$virtual" == "true" ]]; then
               echo -e "${RED}Unable to find the BIOS boot files at $vrtpath${NC}"
               umount_vpart
           else
               echo -e "${RED}Unable to find the BIOS boot files at $winpath${NC}"
           fi
           if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi           
           exit 1
       fi
       if   sudo test -f "$syspath/bootmgr" && sudo test -f "$sysuwfpath" && sudo test -f "$sysvhdpath"; then
            sysuwfver=$(sudo peres -v "$sysuwfpath" | grep 'Product Version:' | awk '{print $3}')
            sysvhdver=$(sudo peres -v "$sysvhdpath" | grep 'Product Version:' | awk '{print $3}')
            sysbtmgr="true"
       elif sudo test -f "$syspath/bootmgr" && sudo test -f "$sysmempath"; then
            sysmemver=$(peres -v "$sysmempath" | grep 'Product Version:' | awk '{print $3}')
            sysuwfver="NULL"
            sysvhdver="NULL"
            sysbtmgr="true"
       fi
       if ! sudo test -f "$sysuwfpath" && ! sudo test -f "$sysvhdpath"; then
          if  [[ "$virtual" == "true" ]]; then
              copy_bootmgr "$vrtpath" "$syspath" "$fwmode" "$sysfstype"
          else
              copy_bootmgr "$winpath" "$syspath" "$fwmode" "$sysfstype"
          fi
          build_stores "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" \
                       "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
          if [[ ! $? -eq 0 ]]; then
             if [[ "$virtual" == "true" ]]; then umount_vpart; fi
             if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
             exit 1
          fi
       elif [[ "$sysbtmgr" == "true" && "$clean" == "true" ]]; then
            if [[ "$verbose" == "true" ]]; then echo "Remove current BCD store..."; fi
            sudo rm -f "$syspath"/Boot/BCD
            if   [[ "$sysuwfver" != "NULL" && "$sysvhdver" != "NULL" && "$localuwfver" != "NULL" && "$localvhdver" != "NULL" ]]; then
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
            else
                 if [[ "$sysmemver" != "$localmemver" ]]; then
                    if [[ $(printf "$sysmemver\n$localmemver\n" | sort -rV | head -1) == "$localmemver" ]]; then
                       sudo rm -rf "$syspath/Boot" && rm -f "$syspath/bootmgr $syspath/bootnxt"
                       if  [[ "$virtual" == "true" ]]; then
                           copy_bootmgr "$vrtpath" "$syspath" "$fwmode" "$sysfstype"
                       else
                           copy_bootmgr "$winpath" "$syspath" "$fwmode" "$sysfstype"
                       fi
                    fi
                 fi
            fi
            build_stores "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" \
                         "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
            if [[ ! $? -eq 0 ]]; then
               if [[ "$virtual" == "true" ]]; then umount_vpart; fi
               if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
               exit 1
            fi
       else
            createbcd="false"
            if   [[ "$sysuwfver" != "NULL" && "$sysvhdver" != "NULL" && "$localuwfver" != "NULL" && "$localvhdver" != "NULL" ]]; then
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
            else
                 if [[ "$sysmemver" != "$localmemver" ]]; then
                    if [[ $(printf "$sysmemver\n$localmemver\n" | sort -rV | head -1) == "$localmemver" ]]; then
                       if [[ "$verbose" == "true" ]]; then echo "Backup current BCD store before update..."; fi
                       sudo mv "$syspath/Boot/BCD" "$syspath"
                       sudo rm -rf "$syspath/Boot" && rm -f "$syspath/bootmgr $syspath/bootnxt"
                       if  [[ "$virtual" == "true" ]]; then
                           copy_bootmgr "$vrtpath" "$syspath" "$fwmode" "$sysfstype"
                       else
                           copy_bootmgr "$winpath" "$syspath" "$fwmode" "$sysfstype"
                       fi
                       if [[ "$verbose" == "true" ]]; then echo "Restore current BCD store after update..."; fi
                       sudo mv "$syspath/BCD" "$syspath/Boot"
                    fi
                 fi
            fi
            update_winload "$winpath" "$syspath" "$fwmode" "$setfwmod" "$createbcd" "$prewbmdef" \
                           "$prodname" "$locale" "$verbose" "$virtual" "$vrtpath" "$imgstring"
            if [[ ! $? -eq 0 ]]; then
               if [[ "$virtual" == "true" ]]; then umount_vpart; fi
               if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
               exit 1
            fi
       fi
       if [[ "$rmsysmnt" == "true" ]]; then umount_system; fi
       if [[ "$virtual" == "true" ]]; then umount_vpart; fi
       cleanup
       echo "Finished configuring BIOS boot files."
    fi
exit 0
fi
